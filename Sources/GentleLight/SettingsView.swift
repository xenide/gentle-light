import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GentleLight")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $controller.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Color temperature")
                    Spacer()
                    Text("\(controller.kelvin) K")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(controller.kelvin) },
                        set: { controller.kelvin = Int($0) }
                    ),
                    in: Double(GammaCurve.minKelvin)...Double(GammaCurve.maxKelvin),
                    step: 100
                )
                .disabled(!controller.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Brightness (gamma)")
                    Spacer()
                    Text("\(Int(controller.gammaBrightness * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $controller.gammaBrightness, in: 0.10...1.0)
                    .disabled(!controller.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Overlay dim")
                    Spacer()
                    Text("\(Int(controller.overlayDim * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $controller.overlayDim, in: 0...0.85)
                    .disabled(!controller.enabled)
            }

            Divider()

            Toggle(isOn: $controller.pinHardwareToMax) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pin backlight to 100%")
                    Text(controller.isHardwarePinAvailable
                         ? "Eliminates PWM and disables auto-brightness; dim via the sliders above."
                         : "Unavailable on this system.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!controller.isHardwarePinAvailable)

            Divider()

            HStack {
                Button("Reset") {
                    controller.kelvin = GammaCurve.neutralKelvin
                    controller.gammaBrightness = 1.0
                    controller.overlayDim = 0
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
