import AppKit

final class DimOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        hasShadow = false
        alphaValue = 0
        setFrame(screen.frame, display: true)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setMultiply(red: Float, green: Float, blue: Float) {
        let r = max(0, min(1, red))
        let g = max(0, min(1, green))
        let b = max(0, min(1, blue))
        let avg = (r + g + b) / 3
        let alpha = max(0, min(0.9, 1 - avg))
        let dark: Float = 0.35
        backgroundColor = NSColor(
            red: CGFloat(r * dark),
            green: CGFloat(g * dark),
            blue: CGFloat(b * dark),
            alpha: 1
        )
        alphaValue = CGFloat(alpha)
    }

    func reposition(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
