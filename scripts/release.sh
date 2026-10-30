#!/usr/bin/env bash
# Tests, archives and uploads Northlight to TestFlight with the App Store Connect
# API key. It stops before the upload unless the packaged app carries its privacy
# manifest and its layered icon.
#
# Usage: scripts/release.sh [build_number]
# The build number defaults to a timestamp. The .p8 key stays outside the repo;
# set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID to your App Store Connect API key.
set -euo pipefail

BUILD="${1:-$(date +%Y%m%d%H%M)}"
KEY_PATH="${ASC_KEY_PATH:?set ASC_KEY_PATH to the App Store Connect .p8 key}"
KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID to the App Store Connect key ID}"
ISSUER="${ASC_ISSUER_ID:?set ASC_ISSUER_ID to the App Store Connect issuer ID}"
SIMULATOR="Apple TV 4K (3rd generation)"
[ -f "$KEY_PATH" ] || { echo "ASC key not found at $KEY_PATH" >&2; exit 1; }
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")

cd "$(dirname "$0")/.."
xcodegen generate --spec App/project.yml

echo "▸ Testing"
# No test place keeps Tokyo time, so a read of this Mac's zone fails a test.
TZ=Asia/Tokyo swift test
UDID=$(xcrun simctl list devices available | grep -F "$SIMULATOR (" | head -1 \
  | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)
[ -n "$UDID" ] || { echo "No \"$SIMULATOR\" simulator; add one in Xcode's Devices window" >&2; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
# The settings tests ask for this Apple TV's location and expect Reykjavík.
xcrun simctl location "$UDID" set 64.1466,-21.9426
xcrun simctl privacy "$UDID" grant location com.arkwerx.northlight
xcodebuild test -project App/Northlight.xcodeproj -scheme Northlight -destination "id=$UDID" \
  -test-timeouts-enabled YES -quiet

ARCHIVE="$(mktemp -d)/Northlight.xcarchive"
echo "▸ Archiving build $BUILD to $ARCHIVE"
xcodebuild archive -project App/Northlight.xcodeproj -scheme Northlight -configuration Release \
  -destination "generic/platform=tvOS" -archivePath "$ARCHIVE" "${AUTH[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD" -quiet

APP="$ARCHIVE/Products/Applications/Northlight.app"
[ -f "$APP/PrivacyInfo.xcprivacy" ] || { echo "Northlight.app has no privacy manifest" >&2; exit 1; }
# Read the catalog whole first: grep -q stops early, which would break assetutil's pipe.
ASSETS=$(xcrun assetutil --info "$APP/Assets.car")
grep -q '"AssetType" : "ImageStack"' <<< "$ASSETS" || { echo "Northlight.app has no layered icon" >&2; exit 1; }

echo "▸ Uploading"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$(dirname "$ARCHIVE")/export" \
  -exportOptionsPlist App/ExportOptions.plist "${AUTH[@]}"
echo "▸ Uploaded build $BUILD. TestFlight processing takes a few minutes."
