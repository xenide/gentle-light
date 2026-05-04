import CoreGraphics
import Foundation

private let displayServicesHandle: UnsafeMutableRawPointer? = dlopen(
    "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
    RTLD_LAZY
)

private func displayServicesSymbol<T>(_ name: String, as type: T.Type) -> T? {
    guard let displayServicesHandle, let sym = dlsym(displayServicesHandle, name) else { return nil }
    return unsafeBitCast(sym, to: T.self)
}

enum HardwareBrightness {
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let setFn: SetFn? = displayServicesSymbol("DisplayServicesSetBrightness", as: SetFn.self)
    private static let getFn: GetFn? = displayServicesSymbol("DisplayServicesGetBrightness", as: GetFn.self)

    static var isAvailable: Bool { setFn != nil && getFn != nil }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    @discardableResult
    static func set(_ display: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let setFn else { return false }
        let clamped = max(0, min(1, value))
        return setFn(display, clamped) == 0
    }
}

enum AmbientLight {
    private typealias HasFn = @convention(c) (CGDirectDisplayID) -> Int32
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    private static let hasFn: HasFn? =
        displayServicesSymbol("DisplayServicesHasAmbientLightCompensation", as: HasFn.self)
    private static let getFn: GetFn? =
        displayServicesSymbol("DisplayServicesAmbientLightCompensationEnabled", as: GetFn.self)
    private static let setFn: SetFn? =
        displayServicesSymbol("DisplayServicesEnableAmbientLightCompensation", as: SetFn.self)

    static func supported(_ display: CGDirectDisplayID) -> Bool {
        guard let hasFn else { return false }
        return hasFn(display) != 0
    }

    static func isEnabled(_ display: CGDirectDisplayID) -> Bool? {
        guard let getFn else { return nil }
        var value: Bool = false
        return getFn(display, &value) == 0 ? value : nil
    }

    @discardableResult
    static func setEnabled(_ display: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        guard let setFn else { return false }
        return setFn(display, enabled) == 0
    }
}
