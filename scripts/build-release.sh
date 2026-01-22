#!/bin/bash
#
# Build script for Victor - creates a signed universal binary and DMG
#
# Usage: ./scripts/build-release.sh [--skip-dmg]
#
# Options:
#   --skip-dmg    Skip DMG creation, only build the .app
#
# Output:
#   build/release/Victor.app     - The signed application
#   build/release/Victor.dmg     - The disk image (unless --skip-dmg)
#

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/Victor.xcarchive"
APP_NAME="Victor"
DMG_NAME="Victor"

# Parse arguments
SKIP_DMG=false
for arg in "$@"; do
    case $arg in
        --skip-dmg)
            SKIP_DMG=true
            shift
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v xcodebuild &> /dev/null; then
        log_error "xcodebuild not found. Please install Xcode."
        exit 1
    fi

    if ! command -v hdiutil &> /dev/null; then
        log_error "hdiutil not found. This should be available on macOS."
        exit 1
    fi

    # Check if project exists
    if [ ! -f "$PROJECT_DIR/Victor.xcodeproj/project.pbxproj" ]; then
        log_error "Victor.xcodeproj not found. Run 'xcodegen generate' first."
        exit 1
    fi
}

# Clean previous builds
clean_build() {
    log_info "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# Build universal binary archive
build_archive() {
    log_info "Building universal binary archive..."

    xcodebuild archive \
        -project "$PROJECT_DIR/Victor.xcodeproj" \
        -scheme "Victor" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        SKIP_INSTALL=NO \
        | grep -E "^(Build|Archive|Signing|error:|warning:|\*\*)" || true

    if [ ! -d "$ARCHIVE_PATH" ]; then
        log_error "Archive failed - no archive created"
        exit 1
    fi

    log_info "Archive created at $ARCHIVE_PATH"
}

# Export the app from archive
export_app() {
    log_info "Exporting app from archive..."

    # For ad-hoc distribution, we extract directly from the archive
    # This avoids the complexity of export options requiring specific signing identities
    ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

    if [ ! -d "$ARCHIVE_APP" ]; then
        log_error "App not found in archive at $ARCHIVE_APP"
        exit 1
    fi

    # Copy the app from the archive
    cp -R "$ARCHIVE_APP" "$BUILD_DIR/"

    if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
        log_error "Export failed - no app bundle created"
        exit 1
    fi

    log_info "App exported to $BUILD_DIR/$APP_NAME.app"
}

# Re-sign with ad-hoc signature (removes developer identity requirement for recipients)
adhoc_sign() {
    log_info "Re-signing with ad-hoc signature..."

    # Remove existing signature and re-sign ad-hoc
    codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"

    # Verify signature
    if codesign --verify --verbose "$BUILD_DIR/$APP_NAME.app" 2>&1 | grep -q "valid on disk"; then
        log_info "Ad-hoc signature verified"
    else
        log_warn "Signature verification returned warnings (this is normal for ad-hoc)"
    fi
}

# Create DMG
create_dmg() {
    if [ "$SKIP_DMG" = true ]; then
        log_info "Skipping DMG creation (--skip-dmg flag)"
        return
    fi

    log_info "Creating DMG..."

    DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
    DMG_TEMP="$BUILD_DIR/dmg_temp"

    # Clean up any existing temp directory
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"

    # Copy app to temp directory
    cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_TEMP/"

    # Create symbolic link to Applications folder
    ln -s /Applications "$DMG_TEMP/Applications"

    # Create DMG
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    # Clean up temp directory
    rm -rf "$DMG_TEMP"

    if [ -f "$DMG_PATH" ]; then
        log_info "DMG created at $DMG_PATH"
    else
        log_error "DMG creation failed"
        exit 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    log_info "Build complete!"
    echo "========================================"
    echo ""
    echo "Output files:"
    echo "  App: $BUILD_DIR/$APP_NAME.app"
    if [ "$SKIP_DMG" = false ] && [ -f "$BUILD_DIR/$DMG_NAME.dmg" ]; then
        echo "  DMG: $BUILD_DIR/$DMG_NAME.dmg"

        # Show DMG size
        DMG_SIZE=$(du -h "$BUILD_DIR/$DMG_NAME.dmg" | cut -f1)
        echo "  DMG Size: $DMG_SIZE"
    fi
    echo ""

    # Show architecture info
    log_info "Architecture check:"
    lipo -info "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    echo ""

    log_warn "Note: This is an ad-hoc signed build."
    echo "Users will need to right-click → Open on first launch,"
    echo "or run: xattr -cr '$APP_NAME.app'"
    echo ""
}

# Main
main() {
    cd "$PROJECT_DIR"

    echo "========================================"
    echo "  Victor Release Build"
    echo "========================================"
    echo ""

    check_prerequisites
    clean_build
    build_archive
    export_app
    adhoc_sign
    create_dmg
    print_summary
}

main "$@"
