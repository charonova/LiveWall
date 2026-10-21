import Foundation

enum ProcessRunner {
    struct Result {
        let status: Int32
        let errorOutput: String
    }

    /// Runs a command to completion without blocking the caller.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            // Drain stderr while the process runs so a chatty tool can't fill the pipe and stall.
            let errorPipe = Pipe()
            let collected = ErrorBuffer()
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil  // EOF
                } else {
                    collected.append(chunk)
                }
            }
            process.standardError = errorPipe

            process.terminationHandler = { process in
                errorPipe.fileHandleForReading.readabilityHandler = nil
                collected.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: Result(status: process.terminationStatus, errorOutput: collected.text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class ErrorBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
