#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Breathe.app"
DMGSTAGE="build/dmg"
DMG="build/Breathe.dmg"

echo "==> Cleaning"
rm -rf "$APP" "$DMGSTAGE" "$DMG" build/Breathe.iconset build/icon.png build/AppIcon.icns

echo "==> Compiling app"
swiftc -O -parse-as-library -o build/Breathe App.swift Core.swift Sound.swift \
    -framework SwiftUI -framework AppKit -framework AVFoundation

echo "==> Rendering icon"
swiftc -O -o build/makeicon makeicon.swift -framework AppKit
build/makeicon build/icon.png

echo "==> Building iconset"
mkdir -p build/Breathe.iconset
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s build/icon.png --out "build/Breathe.iconset/icon_${s}x${s}.png" >/dev/null
done
# retina variants
cp build/Breathe.iconset/icon_32x32.png   build/Breathe.iconset/icon_16x16@2x.png
cp build/Breathe.iconset/icon_64x64.png   build/Breathe.iconset/icon_32x32@2x.png
cp build/Breathe.iconset/icon_256x256.png build/Breathe.iconset/icon_128x128@2x.png
cp build/Breathe.iconset/icon_512x512.png build/Breathe.iconset/icon_256x256@2x.png
cp build/Breathe.iconset/icon_1024x1024.png build/Breathe.iconset/icon_512x512@2x.png
rm build/Breathe.iconset/icon_64x64.png build/Breathe.iconset/icon_1024x1024.png
iconutil -c icns build/Breathe.iconset -o build/AppIcon.icns

echo "==> Assembling .app bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Breathe "$APP/Contents/MacOS/Breathe"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/Breathe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Breathe</string>
    <key>CFBundleDisplayName</key><string>Breathe</string>
    <key>CFBundleIdentifier</key><string>com.breathe.app</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Breathe</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (codesign skipped)"

echo "==> Creating DMG"
mkdir -p "$DMGSTAGE"
cp -R "$APP" "$DMGSTAGE/"
ln -s /Applications "$DMGSTAGE/Applications"
hdiutil create -volname "Breathe" -srcfolder "$DMGSTAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Done"
echo "App:  $(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
echo "DMG:  $(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
du -h "$DMG" | cut -f1
