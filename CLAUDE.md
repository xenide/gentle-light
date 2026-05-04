# PWM-free brightness for macOS

A menu-bar utility that mitigates LED-backlight PWM flicker by pinning the hardware backlight to 100%, disabling ambient-light compensation, and dimming / warming the screen via the GPU's gamma table.

## Why

Most LED backlights dim by strobing on/off at a duty cycle proportional to the brightness setting. Lower brightness → longer "off" intervals → flicker that a sizable minority of users perceive as eye strain, headache, or nausea. The fix: keep the hardware backlight at 100% (no PWM), and reduce *perceived* brightness in software via the video card's gamma ramp. NotebookCheck and BetterDisplay both document this approach.

## Build & run

```sh
swift build
.build/debug/gentle-light
```

Quit via the popover's Quit button, or `kill <pid>` (default `SIGTERM`). `kill -9` skips cleanup — gamma stays warped until next clean launch + quit.

## Architecture

Swift Package executable. AppKit + SwiftUI hybrid. Runs as `.accessory` activation policy (no Dock icon).

| File | Responsibility |
|---|---|
| `Sources/GentleLight/App.swift` | `@main` AppDelegate, status item, popover host, signal handlers |
| `Sources/GentleLight/DisplayController.swift` | Singleton `ObservableObject`. Per-display gamma via `CGSetDisplayTransferByFormula`, overlay management, HW backlight pin + ambient-light disable, hot-plug via `CGDisplayRegisterReconfigurationCallback` |
| `Sources/GentleLight/GammaCurve.swift` | Tanner Helland Kelvin → RGB scalar approximation (1000–10000 K) |
| `Sources/GentleLight/HardwareBrightness.swift` | `dlopen` wrappers around private `DisplayServices` symbols: `Set/GetBrightness` and `Has/Enable/IsEnabled AmbientLightCompensation` |
| `Sources/GentleLight/DimOverlayWindow.swift` | Click-through full-screen `NSWindow` at `CGShieldingWindowLevel + 1` for sub-gamma-floor dim |
| `Sources/GentleLight/SettingsView.swift` | SwiftUI popover: kelvin / gamma / overlay sliders + HW pin toggle |

## What's done

- Color temperature 1000–10000 K via gamma formula
- Software brightness via gamma scaling (PWM-free; primary control)
- Overlay dim for going below the gamma floor without banding
- Hardware backlight pin to 100% with 1 Hz drift correction (snapshots and restores on toggle-off / quit)
- Auto-brightness disable while pinned (DisplayServices ambient-light compensation), restored on unpin
- Multi-display via `CGGetOnlineDisplayList` (covers mirrored / AirPlay / Sidecar / sleeping externals)
- Hot-plug + display-reconfiguration handling

## What's next

In roughly priority order:

1. Persist settings across launches (UserDefaults)
2. Unified brightness slider that splits gamma (top of range) and overlay (bottom) automatically — see "gamma vs overlay" below
3. Global hotkeys for brightness ± / kelvin ±
4. Sunrise/sunset schedule for auto-warming
5. Per-display independent settings
6. Disable temporal dithering (the *other* macOS eye-strain trigger; needs IOMobileFramebuffer registers — see BetterDisplay)
7. Package as a proper `.app` bundle with `Info.plist`, code signing, launch-at-login (see `README.md`)

## Non-obvious notes

- **Gamma vs overlay**: both are PWM-free. Gamma is preferred until ~30–50% perceived brightness — below that it causes color banding (256 levels squeezed into ~75). Overlay covers the rest. Tradeoff: the macOS cursor renders *above* the overlay and stays bright on a dim screen.
- **HW pin uses a private framework** (`DisplayServices`). Stable since 10.15 and used by Lunar / MonitorControl / BetterDisplay. Cannot ship via App Store; fine for personal use.
- **Signal cleanup is partial**: `SIGINT` / `SIGTERM` handlers only restore gamma — not HW backlight or ambient-light state — because `DisplayServices` calls aren't async-signal-safe. If brightness gets stuck at 100%, F1 fixes it instantly.
- **Dithering is separate**: this app does not address temporal dithering, which a subset of PWM-sensitive users also react to. BetterDisplay is the reference tool there.

## References

- [NotebookCheck: Why PWM is a headache](https://www.notebookcheck.net/Why-Pulse-Width-Modulation-PWM-is-such-a-headache.270240.0.html)
- [BetterDisplay eye-care wiki](https://github.com/waydabber/BetterDisplay/wiki/Eye-care:-prevent-PWM-and-or-temporal-dithering)
