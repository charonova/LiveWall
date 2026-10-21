import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum ImportError: LocalizedError {
    case noVideoTrack
    case unsupportedFormat(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The file has no video."
        case .unsupportedFormat(let ext):
            return "macOS can't read .\(ext) files. Install ffmpeg (brew install ffmpeg) to add them."
        case .conversionFailed(let reason):
            return "Conversion failed: \(reason)"
        }
    }
}

/// Turns any video into a file that plays with the least possible work:
/// HEVC (hardware-decoded), no audio track, at most 4K, in a QuickTime container.
/// The same file is also valid as a macOS Aerial for the lock screen.
enum VideoImporter {
    static func makeWallpaper(
        from source: URL,
        id: UUID,
        name: String,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> VideoItem {
        let output = Paths.videos.appendingPathComponent("\(id.uuidString).mov")
        let partial = Paths.videos.appendingPathComponent(".\(id.uuidString).partial.mov")
        try? FileManager.default.removeItem(at: partial)
        defer { try? FileManager.default.removeItem(at: partial) }

        let asset = AVURLAsset(url: source)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            try await convert(asset, track: track, to: partial, progress: progress)
        } else if let ffmpeg = ffmpegPath {
            try await convertWithFFmpeg(ffmpeg, source: source, to: partial, progress: progress)
        } else {
            throw ImportError.unsupportedFormat(source.pathExtension.lowercased())
        }

        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: partial, to: output)

        let info = try await inspect(output)
        let item = VideoItem(
            id: id, name: name, fileName: output.lastPathComponent,
            duration: info.duration, pixelWidth: info.width, pixelHeight: info.height,
            frameRate: info.frameRate, addedAt: Date())
        let thumbnail = try await frame(of: output, maxPixelSize: 480)
        try write(thumbnail, to: item.thumbnailURL, type: .jpeg)
        return item
    }

    /// Grabs a representative frame (about one second in) for previews.
    static func frame(of url: URL, maxPixelSize: CGFloat) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let duration = try await asset.load(.duration).seconds
        let time = CMTime(seconds: min(1, duration / 3), preferredTimescale: 600)
        return try await generator.image(at: time).image
    }

    static func write(_ image: CGImage, to url: URL, type: UTType) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImportError.conversionFailed("couldn't create \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.conversionFailed("couldn't write \(url.lastPathComponent)")
        }
    }

    // MARK: - Conversion

    private static func convert(
        _ asset: AVURLAsset, track: AVAssetTrack, to output: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let (timeRange, transform, naturalSize, formats) = try await track.load(
            .timeRange, .preferredTransform, .naturalSize, .formatDescriptions)
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        let size = naturalSize.applying(transform)
        let longSide = max(abs(size.width), abs(size.height))
        let shortSide = min(abs(size.width), abs(size.height))
        let fitsIn4K = longSide <= 3840 && shortSide <= 2160
        let isHEVC = formats.first.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC } ?? false

        // Already ideal: copy it as-is, no quality loss and no waiting.
        if isHEVC && !hasAudio && fitsIn4K && asset.url.pathExtension.lowercased() == "mov" {
            progress(nil)
            try FileManager.default.copyItem(at: asset.url, to: output)
            return
        }

        // Keep only the video track so the audio is never decoded.
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ImportError.noVideoTrack
        }
        try videoTrack.insertTimeRange(timeRange, of: track, at: .zero)
        videoTrack.preferredTransform = transform

        // HEVC that fits in 4K only needs a new container without the audio: an instant,
        // lossless remux. Everything else is re-encoded to HEVC.
        let preset: String
        if isHEVC && fitsIn4K {
            preset = AVAssetExportPresetPassthrough
        } else {
            preset = fitsIn4K ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHEVC3840x2160
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ImportError.conversionFailed("HEVC encoding isn't available on this Mac")
        }
        session.shouldOptimizeForNetworkUse = false

        if #available(macOS 15, *) {
            let monitor = Task {
                for await state in session.states(updateInterval: 0.2) {
                    // The state arrives once; its Progress object keeps updating, so poll it.
                    guard case .exporting(let exportProgress) = state else { continue }
                    while !Task.isCancelled && !exportProgress.isFinished {
                        progress(exportProgress.fractionCompleted)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
            }
            defer { monitor.cancel() }
            do {
                try await session.export(to: output, as: .mov)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ImportError.conversionFailed(error.localizedDescription)
            }
        } else {
            try await legacyExport(session, to: output, progress: progress)
        }
    }

    @available(macOS, deprecated: 15)
    private static func legacyExport(
        _ session: AVAssetExportSession, to output: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        session.outputURL = output
        session.outputFileType = .mov
        session.exportAsynchronously {}
        while session.status == .waiting || session.status == .exporting {
            progress(Double(session.progress))
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                session.cancelExport()
                throw error
            }
        }
        guard session.status == .completed else {
            throw ImportError.conversionFailed(session.error?.localizedDescription ?? "unknown error")
        }
    }

    static var ffmpegPath: String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// For formats AVFoundation can't read (WebM, MKV, GIF…), using the hardware HEVC encoder.
    private static func convertWithFFmpeg(
        _ ffmpeg: String, source: URL, to output: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        progress(nil)
        let result = try await ProcessRunner.run(ffmpeg, [
            "-nostdin", "-y", "-loglevel", "error",
            "-i", source.path,
            "-map", "0:v:0", "-an", "-sn", "-dn",
            "-vf", "scale='min(3840,iw)':'min(2160,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
            "-c:v", "hevc_videotoolbox", "-q:v", "70", "-tag:v", "hvc1",
            output.path,
        ])
        guard result.status == 0 else {
            throw ImportError.conversionFailed(result.errorOutput.isEmpty ? "ffmpeg exited with \(result.status)" : result.errorOutput)
        }
    }

    private struct Info {
        let duration: Double
        let width: Int
        let height: Int
        let frameRate: Double
    }

    private static func inspect(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ImportError.noVideoTrack
        }
        let (size, transform, frameRate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let duration = try await asset.load(.duration)
        let displaySize = size.applying(transform)
        return Info(
            duration: duration.seconds,
            width: Int(abs(displaySize.width)),
            height: Int(abs(displaySize.height)),
            frameRate: Double(frameRate))
    }
}
