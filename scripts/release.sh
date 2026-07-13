#!/bin/zsh
# Victor release build: archive -> Developer ID sign -> notarize -> staple -> zip.
# victor-dst (#49). Usage: scripts/release.sh [--dmg]
#   --dmg  additionally build, sign, notarize, and staple a drag-to-install
#          DMG (requires `brew install create-dmg`). The zip is always built -
#          it stays the canonical artifact (and what Sparkle would want later).
# One-time notarization setup: see Docs/RELEASING.md.
set -euo pipefail

MAKE_DMG=0
if [[ "${1:-}" == "--dmg" ]]; then
  MAKE_DMG=1
  if ! command -v create-dmg >/dev/null; then
    echo "error: --dmg needs create-dmg (brew install create-dmg)" >&2
    exit 1
  fi
fi

cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: Karan Juneja (55V96YBUQ4)"
PROFILE="victor-notary"          # xcrun notarytool keychain profile name
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/Victor.xcarchive"
APP="$BUILD_DIR/Victor.app"

VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
ZIP="$BUILD_DIR/Victor-$VERSION.zip"

echo "==> xcodegen"
xcodegen generate

echo "==> Archiving Release (v$VERSION)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project Victor.xcodeproj \
  -scheme Victor \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  | tail -3

cp -R "$ARCHIVE/Products/Applications/Victor.app" "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | head -5 || true

echo "==> Zipping for notarization"
ditto -c -k --keepParent "$APP" "$ZIP"

# Notarization needs a stored credential profile (created once, interactively -
# see Docs/RELEASING.md). Ask notarytool itself: modern notarytool stores
# credentials in the data-protection keychain, which `security
# find-generic-password` can't see (that probe falsely reported "missing"
# on a working setup - 2026-07-13).
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo ""
  echo "!! No notarytool credential profile found in the keychain."
  echo "   Signed (un-notarized) zip is at: $ZIP"
  echo "   One-time setup (needs an app-specific password from account.apple.com):"
  echo "     xcrun notarytool store-credentials $PROFILE \\"
  echo "       --apple-id <your-apple-id> --team-id 55V96YBUQ4"
  echo "   Then re-run this script."
  exit 2
fi

echo "==> Submitting for notarization (waits for Apple)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP"

echo "==> Re-zipping stapled app"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper assessment"
spctl --assess --type execute --verbose=2 "$APP"

if (( MAKE_DMG )); then
  DMG="$BUILD_DIR/Victor-$VERSION.dmg"
  echo "==> Building DMG"
  # Background art is optional until the app-icon redesign (#36) delivers -
  # without scripts/dmg-background.png you get a plain window, which is fine.
  DMG_ARGS=(--volname "Victor" --window-size 660 420 --icon-size 128
            --icon "Victor.app" 165 200 --app-drop-link 495 200)
  [[ -f scripts/dmg-background.png ]] && DMG_ARGS+=(--background scripts/dmg-background.png)
  create-dmg "${DMG_ARGS[@]}" "$DMG" "$APP"

  echo "==> Signing DMG"
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"

  # The app inside is already notarized+stapled; the DMG gets its own
  # notarization + staple so Gatekeeper is satisfied at both layers.
  echo "==> Notarizing DMG (waits for Apple)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

echo ""
echo "Done: $ZIP"
ARTIFACTS="$ZIP"
if (( MAKE_DMG )); then
  echo "      $DMG"
  ARTIFACTS="$ZIP $DMG"
fi
echo "Attach to a GitHub release: gh release create v$VERSION $ARTIFACTS --title \"Victor $VERSION\""
