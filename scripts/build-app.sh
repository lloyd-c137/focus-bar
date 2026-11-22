#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=".FocusBarBuild/Focus Bar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FocusBar "$APP/Contents/MacOS/FocusBar"
RESOURCE_DIR=".build/release/FocusBar_FocusBar.resources"
if [[ -d "$RESOURCE_DIR" ]]; then cp -R "$RESOURCE_DIR"/. "$APP/Contents/Resources/"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FocusBar</string>
<key>CFBundleIdentifier</key><string>com.lloydc137.focusbar</string>
<key>CFBundleName</key><string>Focus Bar</string>
<key>CFBundleDisplayName</key><string>Focus Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
