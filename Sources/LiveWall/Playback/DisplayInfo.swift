import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    /// Stable across reboots and reconnects, unlike `id`; used to remember per-display choices.
    let uuid: String
    let name: String
    let frame: CGRect

    static func current() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            return DisplayInfo(id: id, uuid: uuid(for: id), name: screen.localizedName, frame: screen.frame)
        }
    }

    private static func uuid(for id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return String(id) }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
