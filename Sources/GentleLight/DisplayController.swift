import AppKit
import Combine
import CoreGraphics

@MainActor
final class DisplayController: ObservableObject {
    static let shared = DisplayController()

    @Published var kelvin: Int = GammaCurve.neutralKelvin {
        didSet { apply() }
    }

    @Published var gammaBrightness: Double = 1.0 {
        didSet { apply() }
    }

    @Published var overlayDim: Double = 0.0 {
        didSet { applyOverlay() }
    }

    @Published var enabled: Bool = true {
        didSet { enabled ? apply() : restoreSystemGamma() }
    }

    @Published var pinHardwareToMax: Bool = false {
        didSet {
            guard pinHardwareToMax != oldValue else { return }
            pinHardwareToMax ? startBacklightPin() : stopBacklightPin()
        }
    }

    let isHardwarePinAvailable: Bool = HardwareBrightness.isAvailable

    private var overlays: [CGDirectDisplayID: DimOverlayWindow] = [:]
    private var screenObserver: NSObjectProtocol?
    private var originalBacklight: [CGDirectDisplayID: Float] = [:]
    private var originalAmbientLight: [CGDirectDisplayID: Bool] = [:]
    private var pinTimer: Timer?
    private static let pinTarget: Float = 1.0
    private static let pinTolerance: Float = 0.01

    private init() {
        registerDisplayReconfigurationCallback()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildOverlays()
                self?.apply()
            }
        }
        rebuildOverlays()
        apply()
    }

    deinit {
        if let token = screenObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func apply() {
        guard enabled else { return }
        let scalar = GammaCurve.scalar(forKelvin: kelvin)
        let dim = Float(max(0.1, min(1.0, gammaBrightness)))
        for displayID in onlineDisplays() {
            let err = CGSetDisplayTransferByFormula(
                displayID,
                0, scalar.red * dim, 1,
                0, scalar.green * dim, 1,
                0, scalar.blue * dim, 1
            )
            if err != .success {
                NSLog("CGSetDisplayTransferByFormula failed for display \(displayID): \(err.rawValue)")
            }
        }
        applyOverlay()
    }

    func restoreSystemGamma() {
        CGDisplayRestoreColorSyncSettings()
        for overlay in overlays.values {
            overlay.setDim(0)
        }
    }

    func shutdown() {
        if pinHardwareToMax {
            pinHardwareToMax = false
        }
        restoreSystemGamma()
    }

    private func startBacklightPin() {
        guard HardwareBrightness.isAvailable else {
            pinHardwareToMax = false
            return
        }
        for displayID in onlineDisplays() {
            snapshotIfNeeded(displayID)
            HardwareBrightness.set(displayID, Self.pinTarget)
            if AmbientLight.supported(displayID) {
                AmbientLight.setEnabled(displayID, false)
            }
        }
        pinTimer?.invalidate()
        pinTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.assertBacklightPin() }
        }
    }

    private func stopBacklightPin() {
        pinTimer?.invalidate()
        pinTimer = nil
        for (displayID, original) in originalBacklight {
            HardwareBrightness.set(displayID, original)
        }
        for (displayID, wasEnabled) in originalAmbientLight where wasEnabled {
            AmbientLight.setEnabled(displayID, true)
        }
        originalBacklight.removeAll()
        originalAmbientLight.removeAll()
    }

    private func assertBacklightPin() {
        for displayID in onlineDisplays() {
            snapshotIfNeeded(displayID)
            if let current = HardwareBrightness.get(displayID),
               current < Self.pinTarget - Self.pinTolerance {
                HardwareBrightness.set(displayID, Self.pinTarget)
            }
            if AmbientLight.supported(displayID),
               AmbientLight.isEnabled(displayID) == true {
                AmbientLight.setEnabled(displayID, false)
            }
        }
    }

    private func snapshotIfNeeded(_ displayID: CGDirectDisplayID) {
        if originalBacklight[displayID] == nil,
           let current = HardwareBrightness.get(displayID) {
            originalBacklight[displayID] = current
        }
        if originalAmbientLight[displayID] == nil,
           AmbientLight.supported(displayID),
           let enabled = AmbientLight.isEnabled(displayID) {
            originalAmbientLight[displayID] = enabled
        }
    }

    private func applyOverlay() {
        let dim = Float(max(0, min(0.85, overlayDim)))
        for overlay in overlays.values {
            overlay.setDim(dim)
        }
    }

    private func rebuildOverlays() {
        var next: [CGDirectDisplayID: DimOverlayWindow] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            if let existing = overlays[id] {
                existing.reposition(to: screen)
                next[id] = existing
            } else {
                next[id] = DimOverlayWindow(screen: screen)
            }
        }
        for (id, window) in overlays where next[id] == nil {
            window.orderOut(nil)
        }
        overlays = next
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func registerDisplayReconfigurationCallback() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, ctx in
            guard let ctx else { return }
            let me = Unmanaged<DisplayController>.fromOpaque(ctx).takeUnretainedValue()
            let relevant: CGDisplayChangeSummaryFlags = [.addFlag, .removeFlag, .setModeFlag]
            if !flags.intersection(relevant).isEmpty {
                Task { @MainActor in
                    me.rebuildOverlays()
                    me.apply()
                }
            }
        }, context)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
