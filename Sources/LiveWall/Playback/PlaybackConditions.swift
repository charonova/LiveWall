import AppKit
import IOKit.ps

/// Tracks the system states in which a wallpaper can't be seen or shouldn't spend power.
@MainActor
final class PlaybackConditions {
    var onChange: (() -> Void)?
    var onWake: (() -> Void)?

    private var systemAsleep = false
    private var displaysAsleep = false
    private var sessionInactive = false
    private var screenLocked = false
    private var screenSaverRunning = false
    private var thermalCritical = false
    private var lowPowerMode = false
    private var onBattery = false

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    /// Why playback must pause right now, or nil if it may play.
    func blockReason(pauseOnBattery: Bool, pauseInLowPower: Bool) -> String? {
        if systemAsleep || displaysAsleep { return "Display asleep" }
        if sessionInactive { return "Another user is active" }
        if screenLocked { return "Screen locked" }
        if screenSaverRunning { return "Screen saver running" }
        if thermalCritical { return "Mac is too hot" }
        if pauseInLowPower && lowPowerMode { return "Low Power Mode" }
        if pauseOnBattery && onBattery { return "On battery" }
        return nil
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) {
            $0.systemAsleep = false
            $0.onWake?()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.screenSaverRunning = true }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.screenSaverRunning = false }

        let local = NotificationCenter.default
        observe(local, Notification.Name.NSProcessInfoPowerStateDidChange) {
            $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        observe(local, ProcessInfo.thermalStateDidChangeNotification) {
            $0.thermalCritical = ProcessInfo.processInfo.thermalState == .critical
        }

        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalCritical = ProcessInfo.processInfo.thermalState == .critical
        screenLocked = Self.isScreenLocked()
        startPowerSourceMonitoring()
    }

    func stop() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        _ update: @escaping (PlaybackConditions) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        observers.append((center, token))
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func startPowerSourceMonitoring() {
        updatePowerSource()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let conditions = Unmanaged<PlaybackConditions>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                conditions.updatePowerSource()
                conditions.onChange?()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private func updatePowerSource() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else {
            onBattery = false
            return
        }
        onBattery = (type as String) == kIOPMBatteryPowerKey
    }
}
