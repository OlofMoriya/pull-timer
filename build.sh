#!/bin/sh
set -e
cd "$(dirname "$0")"
APP="build/Pull Timer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target arm64-apple-macos13 main.swift -o build/PullTimer-arm64
swiftc -O -target x86_64-apple-macos13 main.swift -o build/PullTimer-x86_64
lipo -create build/PullTimer-arm64 build/PullTimer-x86_64 -output "$APP/Contents/MacOS/PullTimer"
mkdir -p build/AppIcon.iconset "$APP/Contents/Resources"
PULLTIMER_ICONSET=build/AppIcon.iconset "$APP/Contents/MacOS/PullTimer"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
