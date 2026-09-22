import Foundation
import IOKit

enum DisplayTarget {
    case all
    case embedded
    case external
}

// Disables GPU/DCP temporal dithering (FRC) by writing IOKit framebuffer properties,
// mirroring the technique from Stillcolor. Apple-silicon only; resets on restart.
enum Dithering {
    // IOMobileFramebufferAP is the common ancestor of AppleCLCD2 (M1/M2) and
    // IOMobileFramebufferShim (M3+), so one match covers every Apple-silicon panel.
    fileprivate static let serviceClass = "IOMobileFramebufferAP"

    static var isAvailable: Bool {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator
        ) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        return IOIteratorNext(iterator) != IO_OBJECT_NULL
    }

    @discardableResult
    static func setDithering(disabled: Bool, force: Bool = false) -> Bool {
        setProperties(["enableDither": boolean(!disabled)], force: force)
    }

    @discardableResult
    static func setUniformity2D(disabled: Bool, force: Bool = false) -> Bool {
        setProperties(["uniformity2D": boolean(!disabled)], target: .embedded, force: force)
    }

    private static func setProperties(
        _ props: [String: CFTypeRef], target: DisplayTarget = .all, force: Bool = false
    ) -> Bool {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator
        ) == KERN_SUCCESS, iterator != IO_OBJECT_NULL else {
            NSLog("Dithering: no services matching \(serviceClass)")
            return false
        }
        defer { IOObjectRelease(iterator) }

        var matched = false
        var applied = true
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL { break }
            defer { IOObjectRelease(service) }

            let isExternal = boolProperty("external", service) ?? false
            switch target {
            case .embedded where isExternal: continue
            case .external where !isExternal: continue
            default: break
            }

            matched = true
            applied = write(props, to: service, external: isExternal, force: force) && applied
        }
        return matched && applied
    }

    private static func write(
        _ props: [String: CFTypeRef], to service: io_registry_entry_t, external: Bool, force: Bool
    ) -> Bool {
        let location = external ? "external" : "embedded"
        var applied = true
        // IORegistryEntrySetCFProperties only applies the first key, so set each one alone.
        for (key, value) in props {
            if let current = property(key, service), CFEqual(value, current) {
                if !force { continue }
                NSLog("Dithering: forcing \(key) on \(location) although it already reads correct")
            }
            let ret = IORegistryEntrySetCFProperty(service, key as CFString, value)
            if ret != KERN_SUCCESS {
                NSLog("Dithering: set \(key) on \(location) failed: \(String(cString: mach_error_string(ret)))")
                applied = false
                continue
            }
            if let readback = property(key, service), CFEqual(value, readback) { continue }
            NSLog("Dithering: \(key) on \(location) did not stick")
            applied = false
        }
        return applied
    }

    private static func property(_ key: String, _ service: io_registry_entry_t) -> CFTypeRef? {
        IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, key as CFString, kCFAllocatorDefault, IOOptionBits(0)
        )
    }

    private static func boolProperty(_ key: String, _ service: io_registry_entry_t) -> Bool? {
        property(key, service) as? Bool
    }

    private static func boolean(_ value: Bool) -> CFBoolean {
        value ? kCFBooleanTrue : kCFBooleanFalse
    }
}

// Wake from hibernate tears the DCP down and rebuilds it, replacing every framebuffer service
// with a fresh one at default properties. kIOFirstMatchNotification reports each new service
// once its driver has matched, which is the earliest point a re-write can land on the live
// object; CGDisplayRegisterReconfigurationCallback fires too early and on the doomed one.
final class FramebufferWatcher {
    private let port: IONotificationPortRef
    private var iterator: io_iterator_t = IO_OBJECT_NULL
    private let onAppear: () -> Void

    init?(onAppear: @escaping () -> Void) {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            NSLog("Dithering: IONotificationPortCreate failed")
            return nil
        }
        self.port = port
        self.onAppear = onAppear
        IONotificationPortSetDispatchQueue(port, .main)

        let ret = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching(Dithering.serviceClass),
            { context, iterator in
                guard let context else { return }
                Unmanaged<FramebufferWatcher>.fromOpaque(context)
                    .takeUnretainedValue()
                    .drain(iterator, notify: true)
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &iterator
        )
        guard ret == KERN_SUCCESS else {
            NSLog("Dithering: matching notification failed: \(String(cString: mach_error_string(ret)))")
            return nil
        }
        // Draining to empty arms the notification; this first pass reports the services that
        // already exist, which the caller has not asked to be told about.
        drain(iterator, notify: false)
    }

    deinit {
        IOObjectRelease(iterator)
        IONotificationPortDestroy(port)
    }

    private func drain(_ iterator: io_iterator_t, notify: Bool) {
        var appeared = false
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL { break }
            IOObjectRelease(service)
            appeared = true
        }
        if appeared, notify { onAppear() }
    }
}
