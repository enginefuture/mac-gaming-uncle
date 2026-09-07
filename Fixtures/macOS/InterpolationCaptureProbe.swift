import AppKit
import ScreenCaptureKit

@main struct InterpolationCaptureProbe {
    @MainActor static func main() {
        guard #available(macOS 26, *) else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.title == "MGU interpolation test pattern" }) else {
                    print("test pattern absent"); exit(1)
                }
                await GameFrameInterpolation.shared.start(windowID: window.windowID)
                for _ in 0..<12 {
                    try await Task.sleep(for: .seconds(1))
                    print(GameFrameInterpolation.shared.status, GameFrameInterpolation.shared.metrics)
                }
                let success = GameFrameInterpolation.shared.active
                GameFrameInterpolation.shared.stop()
                exit(success ? 0 : 2)
            } catch { print(error); exit(3) }
        }
        app.run()
    }
}
