import Foundation

// Private CoreBrightness API (CBBlueLightClient) — the engine behind Night Shift.
// macOS 26 on M5 Pro/Max ignores gamma-table writes for the built-in panel
// (FB22273730); Night Shift's tint path still works there and also warms the
// hardware cursor, which no overlay window can reach.
@MainActor
enum NightShift {
    // Night Shift's "More Warm" slider end is roughly this CCT; strength 0 is neutral.
    static let warmestKelvin = 2700

    private typealias SetStrengthFn = @convention(c) (NSObject, Selector, Float, Bool) -> Bool
    private typealias GetStrengthFn = @convention(c) (NSObject, Selector, UnsafeMutablePointer<Float>) -> Bool
    private typealias SetEnabledFn = @convention(c) (NSObject, Selector, Bool) -> Bool
    private typealias GetStatusFn = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool

    private static let client: NSObject? = {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        return cls.init()
    }()

    static var isAvailable: Bool { client != nil }

    static func strength(forKelvin kelvin: Int) -> Float {
        let span = Double(GammaCurve.neutralKelvin - warmestKelvin)
        let warmth = Double(GammaCurve.neutralKelvin - kelvin) / span
        return Float(max(0, min(1, warmth)))
    }

    static func strength() -> Float? {
        guard let (client, fn, sel) = method("getStrength:", as: GetStrengthFn.self) else { return nil }
        var value: Float = 0
        return fn(client, sel, &value) ? value : nil
    }

    static func isEnabled() -> Bool? {
        guard let (client, fn, sel) = method("getBlueLightStatus:", as: GetStatusFn.self) else { return nil }
        // Private Status struct; `enabled` is its second BOOL (byte 1). 64 bytes
        // comfortably covers the struct so the call can't write past the buffer.
        var status = [UInt8](repeating: 0, count: 64)
        let ok = status.withUnsafeMutableBytes { fn(client, sel, $0.baseAddress!) }
        return ok ? status[1] != 0 : nil
    }

    @discardableResult
    static func setStrength(_ strength: Float) -> Bool {
        guard let (client, fn, sel) = method("setStrength:commit:", as: SetStrengthFn.self) else { return false }
        return fn(client, sel, max(0, min(1, strength)), true)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard let (client, fn, sel) = method("setEnabled:", as: SetEnabledFn.self) else { return false }
        return fn(client, sel, enabled)
    }

    private static func method<T>(_ name: String, as type: T.Type) -> (NSObject, T, Selector)? {
        guard let client else { return nil }
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel), let imp = client.method(for: sel) else { return nil }
        return (client, unsafeBitCast(imp, to: T.self), sel)
    }
}
