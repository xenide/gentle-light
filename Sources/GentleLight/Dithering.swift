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
    private static let serviceClass = "IOMobileFramebufferAP"

    static var isAvailable: Bool {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator
        ) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        return IOIteratorNext(iterator) != IO_OBJECT_NULL
    }

    static func setDithering(disabled: Bool) {
        setProperties(["enableDither": boolean(!disabled)])
    }

    static func setUniformity2D(disabled: Bool) {
        setProperties(["uniformity2D": boolean(!disabled)], target: .embedded)
    }

    private static func setProperties(_ props: [String: CFTypeRef], target: DisplayTarget = .all) {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator
        ) == KERN_SUCCESS, iterator != IO_OBJECT_NULL else {
            NSLog("Dithering: no services matching \(serviceClass)")
            return
        }
        defer { IOObjectRelease(iterator) }

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

            // IORegistryEntrySetCFProperties only applies the first key, so set each one alone.
            for (key, value) in props {
                if let current = property(key, service), CFEqual(value, current) { continue }
                let ret = IORegistryEntrySetCFProperty(service, key as CFString, value)
                if ret != KERN_SUCCESS {
                    let location = isExternal ? "external" : "embedded"
                    NSLog("Dithering: set \(key) on \(location) failed: \(String(cString: mach_error_string(ret)))")
                }
            }
        }
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
