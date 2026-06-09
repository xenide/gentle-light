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

    // Background must stay pure black: alpha compositing is out = src·α + dst·(1−α),
    // so any non-black src lifts black pixels and reads as a milky haze. Black src
    // makes the overlay an exact uniform multiply. Cap below 1 so the screen can't
    // go fully opaque and unrecoverable.
    func setDim(_ alpha: Float) {
        animator().alphaValue = CGFloat(max(0, min(0.99, alpha)))
    }

    func reposition(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
