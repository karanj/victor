#!/bin/bash
#
# Create a GitHub release with the Victor DMG
#
# Usage: ./scripts/create-release.sh <version>
#
# Example: ./scripts/create-release.sh 0.2
#
# This script will:
#   1. Update version in project.yml
#   2. Regenerate Xcode project
#   3. Build universal binary and DMG
#   4. Create git tag
#   5. Create GitHub release with DMG attached
#

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.2"
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"
DMG_NAME="Victor-$VERSION.dmg"

# Validate version format (basic check)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    log_error "Invalid version format: $VERSION"
    echo "Expected format: X.Y or X.Y.Z (e.g., 0.2 or 1.0.0)"
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) not found. Install with: brew install gh"
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        log_error "Not logged in to GitHub. Run: gh auth login"
        exit 1
    fi

    if ! command -v xcodegen &> /dev/null; then
        log_error "XcodeGen not found. Install with: brew install xcodegen"
        exit 1
    fi

    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        log_warn "You have uncommitted changes:"
        git status --short
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Check if tag already exists
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        log_error "Tag $TAG already exists. Delete it first or use a different version."
        echo "To delete: git tag -d $TAG && git push origin :refs/tags/$TAG"
        exit 1
    fi
}

# Update version in project.yml
update_version() {
    log_step "Updating version to $VERSION..."

    # Update MARKETING_VERSION in project.yml
    sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" "$PROJECT_DIR/project.yml"

    # Increment build number (use timestamp for uniqueness)
    BUILD_NUMBER=$(date +%Y%m%d%H%M)
    sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" "$PROJECT_DIR/project.yml"

    log_info "Version set to $VERSION (build $BUILD_NUMBER)"
}

# Regenerate Xcode project
regenerate_project() {
    log_step "Regenerating Xcode project..."
    cd "$PROJECT_DIR"
    xcodegen generate
}

# Build release
build_release() {
    log_step "Building release..."
    "$PROJECT_DIR/scripts/build-release.sh"

    if [ ! -f "$BUILD_DIR/Victor.dmg" ]; then
        log_error "Build failed - DMG not created"
        exit 1
    fi

    # Rename DMG with version
    mv "$BUILD_DIR/Victor.dmg" "$BUILD_DIR/$DMG_NAME"
    log_info "Created $DMG_NAME"
}

# Create git tag and commit version change
create_tag() {
    log_step "Creating git tag $TAG..."

    cd "$PROJECT_DIR"

    # Commit version change
    git add project.yml
    git commit -m "Release $VERSION" || true  # May fail if no changes

    # Create annotated tag
    git tag -a "$TAG" -m "Victor $VERSION"

    log_info "Created tag $TAG"
}

# Push to GitHub
push_to_github() {
    log_step "Pushing to GitHub..."

    cd "$PROJECT_DIR"

    # Push commits and tags
    git push origin main
    git push origin "$TAG"

    log_info "Pushed to GitHub"
}

# Create GitHub release
create_github_release() {
    log_step "Creating GitHub release..."

    cd "$PROJECT_DIR"

    # Generate release notes
    RELEASE_NOTES="## Victor $VERSION

### Installation

1. Download **$DMG_NAME** below
2. Open the DMG and drag Victor to Applications
3. Right-click Victor → Open (required on first launch)

### Requirements

- macOS 14.0 (Sonoma) or later
- [Hugo](https://gohugo.io/) installed

### Notes

This is an ad-hoc signed build. macOS will show a security warning on first launch.
Right-click the app and select \"Open\" to bypass it.
"

    # Create release with DMG attached
    gh release create "$TAG" \
        --title "Victor $VERSION" \
        --notes "$RELEASE_NOTES" \
        "$BUILD_DIR/$DMG_NAME"

    log_info "GitHub release created"
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    log_info "Release $VERSION complete!"
    echo "========================================"
    echo ""
    echo "Release URL:"
    gh release view "$TAG" --json url --jq '.url'
    echo ""
    echo "Assets:"
    gh release view "$TAG" --json assets --jq '.assets[].name'
    echo ""
}

# Main
main() {
    cd "$PROJECT_DIR"

    echo "========================================"
    echo "  Victor Release: $VERSION"
    echo "========================================"
    echo ""

    check_prerequisites
    update_version
    regenerate_project
    build_release
    create_tag
    push_to_github
    create_github_release
    print_summary
}

main
