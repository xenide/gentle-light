import AppKit

private let skyLightHandle: UnsafeMutableRawPointer? = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
    RTLD_LAZY
)

// SkyLight exports many CGS functions under both prefixes; try the native SLS
// name first and fall back to the legacy CGS alias.
private func skyLightSymbol<T>(_ suffix: String, as type: T.Type) -> T? {
    guard let skyLightHandle else { return nil }
    for prefix in ["SLS", "CGS"] {
        if let sym = dlsym(skyLightHandle, prefix + suffix) {
            return unsafeBitCast(sym, to: T.self)
        }
    }
    return nil
}

// During Mission Control and space-slide transitions the window server orders the
// Dock's full-screen transition canvas above every ordinary window regardless of
// window level (macOS 26.5: Dock window at level 20 composites above shielding+1),
// so overlay dimming drops out for the length of the animation. The fix is to move
// overlay windows out of the managed-space system entirely, into a private
// "floating" space whose absolute level beats the transition compositing. Same
// SkyLight technique the notch-HUD apps use (Parrot / SkyLightWindow lineage).
@MainActor
enum OverlaySpace {
    // These functions return no usable value (reading a result register yields
    // noise, observed on macOS 26.5) — declare them void like the Parrot-lineage
    // headers do. Verify effects via SLSCopySpacesForWindows(selector 15) instead.
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias SpacesOpFn = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceAddRemoveFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias SpaceDestroyFn = @convention(c) (Int32, UInt64) -> Void

    private static let mainConnection: MainConnectionFn? =
        skyLightSymbol("MainConnectionID", as: MainConnectionFn.self)
    private static let spaceCreate: SpaceCreateFn? =
        skyLightSymbol("SpaceCreate", as: SpaceCreateFn.self)
    private static let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevelFn? =
        skyLightSymbol("SpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevelFn.self)
    private static let showSpaces: SpacesOpFn? =
        skyLightSymbol("ShowSpaces", as: SpacesOpFn.self)
    private static let hideSpaces: SpacesOpFn? =
        skyLightSymbol("HideSpaces", as: SpacesOpFn.self)
    private static let spaceAddWindowsAndRemoveFromSpaces: SpaceAddRemoveFn? =
        skyLightSymbol("SpaceAddWindowsAndRemoveFromSpaces", as: SpaceAddRemoveFn.self)
    private static let spaceDestroy: SpaceDestroyFn? =
        skyLightSymbol("SpaceDestroy", as: SpaceDestroyFn.self)

    // Absolute space levels (SkyLightWindow lineage): 0 user spaces,
    // 100 Setup Assistant, 200 SecurityAgent, 300 screen lock, 400 Notification
    // Center at screen lock, 500 boot progress, 600 VoiceOver. 400 beats Mission
    // Control transition compositing without sitting above accessibility UI.
    private static let absoluteLevel: Int32 = 400

    private static var spaceID: UInt64?

    // Windows leave the space by being deallocated; there is no put-back —
    // an overlay outside the floating space would flash bright in transitions.
    static func add(_ window: NSWindow) {
        guard let sid = ensureSpace(),
              let spaceAddWindowsAndRemoveFromSpaces, let mainConnection else { return }
        spaceAddWindowsAndRemoveFromSpaces(
            mainConnection(), sid, [window.windowNumber] as CFArray, 7
        )
    }

    static func destroy() {
        guard let sid = spaceID, let hideSpaces, let spaceDestroy, let mainConnection else { return }
        let cid = mainConnection()
        hideSpaces(cid, [sid] as CFArray)
        spaceDestroy(cid, sid)
        spaceID = nil
    }

    private static func ensureSpace() -> UInt64? {
        if let spaceID { return spaceID }
        guard let mainConnection, let spaceCreate, let spaceSetAbsoluteLevel,
              let showSpaces else {
            NSLog("OverlaySpace: SkyLight space symbols unavailable; overlays stay in managed spaces")
            return nil
        }
        let cid = mainConnection()
        // Second argument must be 1; other values make Finder draw desktop icons
        // into the space (Parrot lineage, attested by the notch-HUD apps).
        let sid = spaceCreate(cid, 1, nil)
        guard sid != 0 else {
            NSLog("OverlaySpace: SLSSpaceCreate failed; overlays stay in managed spaces")
            return nil
        }
        spaceSetAbsoluteLevel(cid, sid, absoluteLevel)
        showSpaces(cid, [sid] as CFArray)
        NSLog("OverlaySpace: created floating space \(sid)")
        spaceID = sid
        return sid
    }
}
