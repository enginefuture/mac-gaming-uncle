import AppKit
import CoreGraphics
import IndieCore

@MainActor
enum GameDisplaySnapshot {
    static func policy(retinaEnabled: Bool) -> SteamDisplayPolicy {
        let screens = NSScreen.screens.map { screen -> String in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let mode = CGDisplayCopyDisplayMode(id)
            let f = screen.frame
            return "\(id):\(f.origin.x),\(f.origin.y):\(f.width)x\(f.height):\(screen.backingScaleFactor):\(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0):\(mode?.refreshRate ?? 0)"
        }
        return SteamDisplayPolicy(retinaEnabled: retinaEnabled,
                                  topology: "v1:primary=\(CGMainDisplayID());" + screens.sorted().joined(separator: ";"))
    }
}
