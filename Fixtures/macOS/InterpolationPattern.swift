import AppKit

@MainActor final class PatternView: NSView {
    var phase: CGFloat = 0
    var clicks = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor.darkGray.setFill(); bounds.fill()
        NSColor.orange.setFill()
        NSRect(x: phase, y: 180, width: 100, height: 220).fill()
        let text = "Synthetic interpolation target · clicks: \(clicks)"
        text.draw(at: NSPoint(x: 30, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.white])
    }
    override func mouseDown(with event: NSEvent) { clicks += 1; needsDisplay = true; print("clicks=\(clicks)") }
}

@main struct InterpolationPattern {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 1280, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "MGU interpolation test pattern"
        let view = PatternView(frame: window.contentView!.bounds)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        app.activate()
        let timer = Timer(timeInterval: 1.0/30, repeats: true) { _ in
            Task { @MainActor in view.phase = (view.phase + 12).truncatingRemainder(dividingBy: 1180); view.needsDisplay = true }
        }
        RunLoop.main.add(timer, forMode: .common)
        app.run()
    }
}
