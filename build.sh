#!/usr/bin/env bash
# Build Rail.app, install to /Applications, optionally launch.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Rail"
BUNDLE_ID="app.rail.menubar"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# ----- Compile the main app binary -----
swiftc -O -target arm64-apple-macos13 \
       -framework Cocoa -framework IOKit \
       -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
       Rail.swift

# ----- Generate cocaine app icon (Rail.icns) -----
ICON_BUILD="$BUILD_DIR/iconwork"
mkdir -p "$ICON_BUILD"

# Compile and run icon generator
swiftc -O -target arm64-apple-macos13 -framework Cocoa \
       -o "$ICON_BUILD/makeicon" MakeIcon.swift

(
  cd "$ICON_BUILD"
  ./makeicon
  mkdir -p Rail.iconset
  sips -z 16   16   source.png --out Rail.iconset/icon_16x16.png        > /dev/null
  sips -z 32   32   source.png --out Rail.iconset/icon_16x16@2x.png     > /dev/null
  sips -z 32   32   source.png --out Rail.iconset/icon_32x32.png        > /dev/null
  sips -z 64   64   source.png --out Rail.iconset/icon_32x32@2x.png     > /dev/null
  sips -z 128  128  source.png --out Rail.iconset/icon_128x128.png      > /dev/null
  sips -z 256  256  source.png --out Rail.iconset/icon_128x128@2x.png   > /dev/null
  sips -z 256  256  source.png --out Rail.iconset/icon_256x256.png      > /dev/null
  sips -z 512  512  source.png --out Rail.iconset/icon_256x256@2x.png   > /dev/null
  sips -z 512  512  source.png --out Rail.iconset/icon_512x512.png      > /dev/null
  cp           source.png       Rail.iconset/icon_512x512@2x.png
  iconutil -c icns Rail.iconset -o Rail.icns
)
cp "$ICON_BUILD/Rail.icns" "$APP_DIR/Contents/Resources/Rail.icns"

# ----- Info.plist -----
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>             <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>      <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>          <string>2</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleIconFile</key>         <string>Rail</string>
  <key>LSMinimumSystemVersion</key>   <string>13.0</string>
  <key>LSUIElement</key>              <true/>
  <key>NSHumanReadableCopyright</key> <string>© 2026 Rail</string>
</dict>
</plist>
EOF

# ----- Install -----
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3
rm -rf "$DEST"
cp -R "$APP_DIR" "$DEST"

# Bust Finder + LaunchServices icon caches so the new icon shows up
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" >/dev/null 2>&1 || true
touch "$DEST"

echo "Installed $DEST"

if [[ "${1:-}" == "--launch" ]]; then
  open "$DEST"
  echo "Launched. Look for the pill icon in your menu bar."
fi
