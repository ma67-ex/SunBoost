#!/bin/bash
# Builds SunBoost.app (menu bar app + window). Needs Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
APP=SunBoost.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Sources/Shared/Booster.swift Sources/App/SunBoostApp.swift -o "$APP/Contents/MacOS/SunBoost"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SunBoost</string>
<key>CFBundleIdentifier</key><string>com.ma67.sunboost</string>
<key>CFBundleName</key><string>SunBoost</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1
echo "Built $APP"
