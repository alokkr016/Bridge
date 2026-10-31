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

# 4. Sign with a Developer ID. Ad-hoc signing has no Team ID, so the updater
#    would accept any equally unsigned replacement.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application identity in the keychain. Refusing an ad-hoc release."
  exit 1
fi
echo "Signing with: $IDENTITY"
APP="Build/DerivedData/Build/Products/Release/Bridge.app"
ENTITLEMENTS=$(mktemp)
if codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null && grep -q "<plist" "$ENTITLEMENTS"; then
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
rm -f "$ENTITLEMENTS"
codesign --verify --strict --verbose=2 "$APP"

# 5. Package as DMG
echo "[3/4] Packaging Bridge.app into DMG..."
rm -rf Build/dmg
mkdir -p Build/dmg
cp -R "$APP" Build/dmg/
ln -s /Applications Build/dmg/Applications

rm -f Bridge-Installer.dmg
hdiutil create -volname "Bridge Installer" -srcfolder Build/dmg -ov -format UDZO Bridge-Installer.dmg
rm -rf Build/dmg

echo "[4/4] Codesigning the DMG..."
codesign --force --timestamp --sign "$IDENTITY" Bridge-Installer.dmg

echo "=== Build Completed Successfully! ==="
echo "Application DMG packaged at: Bridge-Installer.dmg"
