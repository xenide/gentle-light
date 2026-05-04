import Foundation

struct RGBScalar {
    let red: Float
    let green: Float
    let blue: Float
}

enum GammaCurve {
    static let neutralKelvin: Int = 6500
    static let minKelvin: Int = 1000
    static let maxKelvin: Int = 10000

    static func scalar(forKelvin kelvin: Int) -> RGBScalar {
        let clamped = max(minKelvin, min(maxKelvin, kelvin))
        let t = Double(clamped) / 100.0

        let r: Double
        if t <= 66 {
            r = 255
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
        }

        let g: Double
        if t <= 66 {
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }

        let b: Double
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }

        return RGBScalar(
            red: Float(clamp01(r / 255)),
            green: Float(clamp01(g / 255)),
            blue: Float(clamp01(b / 255))
        )
    }

    private static func clamp01(_ x: Double) -> Double {
        max(0, min(1, x))
    }
}
