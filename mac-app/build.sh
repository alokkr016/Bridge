#!/bin/bash
set -e

echo "=== Starting Bridge Build ==="

# 1. Clean and Setup build directories
echo "[1/4] Preparing build directories..."
rm -rf Build/DerivedData
mkdir -p Build/DerivedData

# 2. Extract Version
VERSION=$(xcodebuild -project OTPBridge.xcodeproj -scheme OTPBridge -showBuildSettings | grep MARKETING_VERSION | head -n 1 | awk '{print $3}')
if [ -z "$VERSION" ]; then
  VERSION="1.0.2"
fi
echo "Version: $VERSION"

# 3. Compile SwiftUI Application in Release configuration
echo "[2/4] Compiling macOS Application in Release configuration..."
xcodebuild -project OTPBridge.xcodeproj -scheme OTPBridge -configuration Release -derivedDataPath ./Build/DerivedData build

# 4. Package as DMG
echo "[3/4] Packaging Bridge.app into DMG..."
rm -rf Build/dmg
mkdir -p Build/dmg
cp -R Build/DerivedData/Build/Products/Release/Bridge.app Build/dmg/
ln -s /Applications Build/dmg/Applications

rm -f Bridge-Installer.dmg
hdiutil create -volname "Bridge Installer" -srcfolder Build/dmg -ov -format UDZO Bridge-Installer.dmg
rm -rf Build/dmg

echo "[4/4] Codesigning the DMG..."
codesign --force --sign - Bridge-Installer.dmg

echo "=== Build Completed Successfully! ==="
echo "Application DMG packaged at: Bridge-Installer.dmg"
