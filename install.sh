#!/bin/zsh
# Builds and installs LectureScribe as /Applications/LectureScribe.app.
# Re-run after any rebuild: ./install.sh
set -e
cd "$(dirname "$0")"
./build.sh

STAGE=$(mktemp -d)
APP="$STAGE/LectureScribe.app"
mkdir -p "$APP/Contents/MacOS"
cp lecturescribe "$APP/Contents/MacOS/lecturescribe"

# App icon: Resources/AppIcon.svg → AppIcon.icns (needs rsvg-convert: brew install librsvg).
mkdir -p "$APP/Contents/Resources"
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size Resources/AppIcon.svg -o "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/AppIcon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>LectureScribe</string>
    <key>CFBundleDisplayName</key>       <string>LectureScribe</string>
    <key>CFBundleIdentifier</key>        <string>com.tcivie.lecturescribe</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleExecutable</key>        <string>lecturescribe</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>27.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>LectureScribe transcribes lectures live, fully on-device.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>LectureScribe names each recording after the calendar event happening now.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>LectureScribe transcribes lectures live, fully on-device.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so macOS keeps granted permissions across rebuilds.
# An ad-hoc signature ties Screen Recording / Microphone grants to one binary hash,
# so every rebuild looked like a new app. Override with SIGN_IDENTITY=…
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}
if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "warning: no signing identity — ad-hoc signature, permissions reset on every rebuild"
  codesign --force --sign - "$APP"
fi

TARGET="/Applications/LectureScribe.app"
rm -rf "$TARGET"
mv "$APP" "$TARGET"
rm -rf "$STAGE"
echo "installed: $TARGET"
