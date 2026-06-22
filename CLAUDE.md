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
| `Sources/GentleLight/NightShift.swift` | objc-runtime wrapper around private `CoreBrightness` `CBBlueLightClient`: Night Shift strength/enabled get + set |
| `Sources/GentleLight/DimOverlayWindow.swift` | Click-through full-screen `NSWindow` at `CGShieldingWindowLevel + 1` for sub-gamma-floor dim |
| `Sources/GentleLight/Dithering.swift` | Disables GPU/DCP temporal dithering (`enableDither`) + edge `uniformity2D` via `IORegistryEntrySetCFProperty` on `IOMobileFramebufferAP` services (Apple silicon) |
| `Sources/GentleLight/SettingsView.swift` | SwiftUI popover: kelvin / gamma / overlay sliders + HW pin toggle |

## What's done

- Color temperature 1000–10000 K via gamma formula
- Software brightness via gamma scaling (PWM-free; primary control)
- Overlay dim for going below the gamma floor without banding
- Hardware backlight pin to 100% with 1 Hz drift correction (snapshots and restores on toggle-off / quit)
- Auto-brightness disable while pinned (DisplayServices ambient-light compensation), restored on unpin
- Multi-display via `CGGetOnlineDisplayList` (covers mirrored / AirPlay / Sidecar / sleeping externals)
- Hot-plug + display-reconfiguration handling
- Built-in panel fallback for the M5 gamma bug (see below): brightness routes through the black overlay on affected hardware
- Optional "Tint via Night Shift" toggle: warms via `CBBlueLightClient` (reaches the built-in panel and the cursor; ~2700 K floor); while on, gamma carries brightness only so externals aren't double-warmed
- Disable temporal dithering (`enableDither`) + experimental edge `uniformity2D` via IOKit framebuffer writes, re-applied on hot-plug (technique ported from Stillcolor; Apple silicon only)

## What's next

In roughly priority order:

1. Persist settings across launches (UserDefaults)
2. Unified brightness slider that splits gamma (top of range) and overlay (bottom) automatically — see "gamma vs overlay" below
3. Global hotkeys for brightness ± / kelvin ±
4. Sunrise/sunset schedule for auto-warming
5. Per-display independent settings
6. Package as a proper `.app` bundle with `Info.plist`, code signing, launch-at-login (see `README.md`)

## Non-obvious notes

- **M5 gamma bug**: macOS 26 on M5 Pro/Max accepts `CGSetDisplayTransferBy*` writes (returns success, reads back correctly) but never applies them to the built-in panel — Apple bugs FB22273730 / FB22273782, still present in 26.5, breaks BetterDisplay/Lunar/f.lux too. `DisplayController.builtinGammaBroken` gates the fallback (built-in brightness via overlay) by CPU brand + OS major version; re-test after each macOS update and drop the gate when Apple fixes it.
- **Overlay must stay pure black**: alpha compositing is `out = src·α + dst·(1−α)` — it can only add light, so per-channel multiply (tint) is impossible and any non-black overlay color lifts black pixels into a milky haze. Black src = exact uniform multiply.
- **Cursor stays bright under overlay dimming**: macOS composites the cursor above `CGShieldingWindowLevel`; only gamma or hardware dimming affect it. Inherent to overlays — no window-level workaround exists. Night Shift tint does reach the cursor.
- **Gamma vs overlay**: both are PWM-free. Gamma is preferred until ~30–50% perceived brightness — below that it causes color banding (256 levels squeezed into ~75). Overlay covers the rest. Tradeoff: the macOS cursor renders *above* the overlay and stays bright on a dim screen.
- **HW pin uses a private framework** (`DisplayServices`). Stable since 10.15 and used by Lunar / MonitorControl / BetterDisplay. Cannot ship via App Store; fine for personal use.
- **Signal cleanup is partial**: `SIGINT` / `SIGTERM` handlers only restore gamma — not HW backlight or ambient-light state — because `DisplayServices` calls aren't async-signal-safe. If brightness gets stuck at 100%, F1 fixes it instantly.
- **Dithering write resets on reconfiguration**: `enableDither` lives on the IOKit framebuffer and reverts to `Yes` on restart (and per-display on hot-plug), so `DisplayController.reapplyDithering()` re-writes it from the `CGDisplayRegisterReconfigurationCallback`. No restore-on-quit — leaving dithering off is the desired state. Default off (opt-in); toggling off writes `enableDither = Yes` back. Apple silicon only (`IOMobileFramebufferAP`); the toggle is disabled on Intel. TCON/panel-level dithering is out of scope — see Stillcolor's caveats.

## References

- [NotebookCheck: Why PWM is a headache](https://www.notebookcheck.net/Why-Pulse-Width-Modulation-PWM-is-such-a-headache.270240.0.html)
- [BetterDisplay eye-care wiki](https://github.com/waydabber/BetterDisplay/wiki/Eye-care:-prevent-PWM-and-or-temporal-dithering)
