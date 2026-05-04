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
        backgroundColor = .black
        alphaValue = 0
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        hasShadow = false
        setFrame(screen.frame, display: true)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setDim(_ dim: Float) {
        animator().alphaValue = CGFloat(max(0, min(0.85, dim)))
    }

    func reposition(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
