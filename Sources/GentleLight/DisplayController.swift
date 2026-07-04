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
        didSet { if enabled { applyOverlays() } }
    }

    @Published var enabled: Bool = true {
        didSet { enabled ? apply() : restoreSystemGamma() }
    }

    @Published var nightShiftTint: Bool = false {
        didSet {
            guard nightShiftTint != oldValue else { return }
            nightShiftTint ? startNightShiftTint() : stopNightShiftTint()
            apply()
        }
    }

    @Published var pinHardwareToMax: Bool = false {
        didSet {
            guard pinHardwareToMax != oldValue else { return }
            pinHardwareToMax ? startBacklightPin() : stopBacklightPin()
        }
    }

    @Published var disableDithering: Bool = false {
        didSet {
            guard disableDithering != oldValue else { return }
            Dithering.setDithering(disabled: disableDithering)
        }
    }

    @Published var disableUniformity2D: Bool = false {
        didSet {
            guard disableUniformity2D != oldValue else { return }
            Dithering.setUniformity2D(disabled: disableUniformity2D)
        }
    }

    let isHardwarePinAvailable: Bool = HardwareBrightness.isAvailable
    let isNightShiftAvailable: Bool = NightShift.isAvailable
    let isDitheringAvailable: Bool = Dithering.isAvailable

    private var overlays: [CGDirectDisplayID: DimOverlayWindow] = [:]
    private var screenObserver: NSObjectProtocol?
    private var originalBacklight: [CGDirectDisplayID: Float] = [:]
    private var originalAmbientLight: [CGDirectDisplayID: Bool] = [:]
    private var originalNightShift: (strength: Float, enabled: Bool)?
    private var lastNightShiftStrength: Float?
    private var pinTimer: Timer?
    private static let pinTarget: Float = 1.0
    private static let pinTolerance: Float = 0.01

    // macOS 26 on M5 Pro/Max accepts gamma-table writes but never applies them to the
    // built-in panel (Apple bugs FB22273730 / FB22273782, still present in 26.5).
    // While true, the built-in display's brightness routes through the black overlay
    // instead, so gamma starting to work again can't double-dim it.
    static let builtinGammaBroken: Bool = {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 else { return false }
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let cpu = String(cString: brand)
        return cpu.contains("M5 Pro") || cpu.contains("M5 Max")
    }()

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
        if nightShiftTint {
            applyNightShiftStrength()
        }
        let scalar = nightShiftTint
            ? RGBScalar(red: 1, green: 1, blue: 1)
            : GammaCurve.scalar(forKelvin: kelvin)
        let gamma = Float(max(0.1, min(1.0, gammaBrightness)))
        for displayID in onlineDisplays() {
            let err = CGSetDisplayTransferByFormula(
                displayID,
                0, scalar.red * gamma, 1,
                0, scalar.green * gamma, 1,
                0, scalar.blue * gamma, 1
            )
            if err != .success {
                NSLog("CGSetDisplayTransferByFormula failed for display \(displayID): \(err.rawValue)")
            }
        }
        applyOverlays()
    }

    func restoreSystemGamma() {
        CGDisplayRestoreColorSyncSettings()
        for overlay in overlays.values {
            overlay.setDim(0)
        }
        if let original = originalNightShift {
            NightShift.setStrength(original.strength)
            NightShift.setEnabled(original.enabled)
            lastNightShiftStrength = nil
        }
    }

    func shutdown() {
        if pinHardwareToMax {
            pinHardwareToMax = false
        }
        enabled = false
        if nightShiftTint {
            nightShiftTint = false
        }
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

    private func applyOverlays() {
        let overlay = Float(max(0, min(0.85, overlayDim)))
        let gamma = Float(max(0.1, min(1.0, gammaBrightness)))
        for (displayID, window) in overlays {
            let gammaFallback = Self.builtinGammaBroken && CGDisplayIsBuiltin(displayID) != 0
            let alpha = gammaFallback ? 1 - gamma * (1 - overlay) : overlay
            window.setDim(alpha)
        }
    }

    private func startNightShiftTint() {
        guard NightShift.isAvailable else {
            nightShiftTint = false
            return
        }
        if originalNightShift == nil,
           let strength = NightShift.strength(),
           let isEnabled = NightShift.isEnabled() {
            originalNightShift = (strength, isEnabled)
        }
    }

    private func stopNightShiftTint() {
        guard let original = originalNightShift else { return }
        NightShift.setStrength(original.strength)
        NightShift.setEnabled(original.enabled)
        originalNightShift = nil
        lastNightShiftStrength = nil
    }

    private func applyNightShiftStrength() {
        let strength = NightShift.strength(forKelvin: kelvin)
        guard strength != lastNightShiftStrength else { return }
        lastNightShiftStrength = strength
        NightShift.setStrength(strength)
        NightShift.setEnabled(strength > 0)
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

    private func reapplyDithering() {
        if disableDithering { Dithering.setDithering(disabled: true) }
        if disableUniformity2D { Dithering.setUniformity2D(disabled: true) }
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
                    me.reapplyDithering()
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
