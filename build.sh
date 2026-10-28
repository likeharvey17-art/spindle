#!/bin/zsh
# Builds Spindle.app (release) into ./build. With --install, copies it to /Applications;
# with --dmg, also packs it into dist/Spindle.dmg.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "==> Compiling"
swift build -c release

APP="$DIR/build/Spindle.app"
BIN="$(swift build -c release --show-bin-path)/Vinyl"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Spindle"
cp -R "$DIR/Resources/Panel" "$APP/Contents/Resources/Panel"
cp -R "$DIR/Resources/Scenes" "$APP/Contents/Resources/Scenes"
cp -R "$DIR/Resources/Widgets" "$APP/Contents/Resources/Widgets"

echo "==> Rendering icon"
ICONSET="$DIR/build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
"$BIN" --render-icon "$DIR/build/icon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$DIR/build/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$DIR/build/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Spindle</string>
    <key>CFBundleIdentifier</key><string>com.tryphonbrooks.spindle</string>
    <key>CFBundleName</key><string>Spindle</string>
    <key>CFBundleDisplayName</key><string>Spindle</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Spindle reads only how loud your Mac's audio is, to swing the VU meter needle in its panel. Nothing is recorded or saved.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Spindle reads the current track and album art from Spotify, Music and Swinsian so it can put the record on your desktop.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x Spindle 2>/dev/null || true; pkill -x Vinyl 2>/dev/null || true
  rm -rf /Applications/Spindle.app /Applications/Vinyl.app
  cp -R "$APP" /Applications/Spindle.app
  echo "    /Applications/Spindle.app"
fi

if [[ "${1:-}" == "--dmg" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
  # One stable file name, so the README's "latest" download link never breaks.
  DMG="$DIR/dist/Spindle.dmg"
  STAGE="$DIR/build/dmg"
  echo "==> Packaging $DMG (version $VERSION)"
  rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE" "$DIR/dist"
  cp -R "$APP" "$STAGE/Spindle.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Spindle" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "    $DMG"
fi

echo "==> Done: $APP"
