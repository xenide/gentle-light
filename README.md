# PWM-free brightness for macOS

A menu-bar utility that mitigates LED-backlight PWM flicker by pinning the hardware backlight to 100%, disabling ambient-light compensation, and dimming / warming the screen through the GPU's gamma table. See [`CLAUDE.md`](./CLAUDE.md) for what it does and why.

## Requirements

- macOS 13 (Ventura) or newer
- Swift 5.9+ (Xcode 15 Command Line Tools or full Xcode)

## Build

```sh
# Debug
swift build
.build/debug/gentle-light

# Release
swift build -c release
.build/release/gentle-light
```

Output is a raw Mach-O executable, not an `.app` bundle. The packaging step below wraps it.

## Package as `.app`

A menu-bar app needs a real bundle so `LSUIElement` takes effect (without it, a Dock icon shows up and `NSStatusItem` placement misbehaves). Build the bundle from the release binary:

```sh
swift build -c release

APP="GentleLight.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/gentle-light "$APP/Contents/MacOS/GentleLight"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>           <string>GentleLight</string>
    <key>CFBundleIdentifier</key>           <string>co.alexlau.gentle-light</string>
    <key>CFBundleName</key>                 <string>GentleLight</string>
    <key>CFBundleDisplayName</key>          <string>GentleLight</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>CFBundleShortVersionString</key>   <string>0.1.0</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
</dict>
</plist>
EOF

# Ad-hoc signature so macOS will launch a local build
codesign --force --deep --sign - "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | tail -5

open "$APP"
```

On first launch macOS may show "from an unidentified developer" — right-click → Open to bypass. Once you're set up, drag `GentleLight.app` into `/Applications`.

## Sign for distribution

Ad-hoc signatures only work on the machine that built them. To ship a binary other people can run, sign with a [Developer ID Application certificate](https://developer.apple.com/help/account/create-certificates/create-developer-id-certificates) ($99/yr Apple Developer Program):

```sh
codesign --force --deep --options runtime \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    GentleLight.app
```

This app **cannot ship through the App Store**. It uses the private `DisplayServices` framework (for `DisplayServicesSetBrightness` and `DisplayServicesEnableAmbientLightCompensation`), which App Store review rejects. Same constraint as Lunar, MonitorControl, and BetterDisplay.

## Notarize

Required for Gatekeeper to launch the app silently on any Mac, not just yours.

```sh
# One-time: store credentials in keychain
xcrun notarytool store-credentials gentle-light-notary \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"   # https://appleid.apple.com → app-specific password

# Per release
ditto -c -k --keepParent GentleLight.app GentleLight.zip
xcrun notarytool submit GentleLight.zip --keychain-profile gentle-light-notary --wait
xcrun stapler staple GentleLight.app

# Verify
xcrun stapler validate GentleLight.app
spctl --assess --verbose GentleLight.app
```

## Publish

### GitHub Releases

```sh
ditto -c -k --keepParent GentleLight.app GentleLight-0.1.0.zip
gh release create v0.1.0 GentleLight-0.1.0.zip --notes "First release"
```

### Homebrew cask

After a couple of stable releases you can submit a cask to [homebrew-cask](https://github.com/Homebrew/homebrew-cask):

```ruby
cask "gentle-light" do
  version "0.1.0"
  sha256 "..."
  url "https://github.com/USER/gentle-light/releases/download/v#{version}/GentleLight-#{version}.zip"
  name "GentleLight"
  desc "PWM-free brightness and color temperature"
  homepage "https://github.com/USER/gentle-light"
  app "GentleLight.app"
end
```
