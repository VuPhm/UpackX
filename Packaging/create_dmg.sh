#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-$(defaults read "${PROJECT_DIR}/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.4.0")}"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"
DIST_DIR="${PROJECT_DIR}/dist"
OUTPUT_DMG="${DIST_DIR}/UpackX-v${VERSION}-macOS-Universal.dmg"

echo "=== Packaging UpackX Universal DMG (v${VERSION}) ==="

if [ ! -d "${BUILD_APP}" ]; then
    echo "Error: ${BUILD_APP} does not exist. Run 'make build' first."
    exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${OUTPUT_DMG}"

STAGING_DIR="/tmp/upackx_dmg_staging_$$"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
trap 'rm -rf "${STAGING_DIR}"' EXIT

echo "Copying UpackX.app to staging directory..."
cp -R "${BUILD_APP}" "${STAGING_DIR}/UpackX.app"

echo "Creating Applications shortcut..."
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Copying First-Launch Trust & Installation Guide (HTML)..."
cp "${PROJECT_DIR}/Packaging/html/install_guide.html" "${STAGING_DIR}/Hướng Dẫn Cài Đặt (Install Guide).html"

echo "Building compressed disk image (.dmg)..."
hdiutil create \
    -volname "UpackX" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${OUTPUT_DMG}"

echo "Verifying DMG integrity..."
MOUNT_POINT="/Volumes/UpackX"
# If already mounted from previous run, detach first
if [ -d "${MOUNT_POINT}" ]; then
    hdiutil detach "${MOUNT_POINT}" -force 2>/dev/null || true
fi

hdiutil attach -nobrowse -readonly "${OUTPUT_DMG}" >/dev/null
if [ -d "${MOUNT_POINT}/UpackX.app" ] && [ -L "${MOUNT_POINT}/Applications" ] && [ -f "${MOUNT_POINT}/Hướng Dẫn Cài Đặt (Install Guide).html" ]; then
    echo "✔ DMG structure verified: UpackX.app, Applications link, and Install Guide present."
else
    echo "✘ Error: Mounted DMG contents invalid."
    hdiutil detach "${MOUNT_POINT}" -force 2>/dev/null || true
    exit 1
fi

# Verify codesign inside mounted DMG
if codesign --verify --deep --strict "${MOUNT_POINT}/UpackX.app" >/dev/null 2>&1; then
    echo "✔ Codesign integrity verified on mounted DMG."
else
    echo "✘ Error: Mounted app bundle failed codesign verification."
    hdiutil detach "${MOUNT_POINT}" -force 2>/dev/null || true
    exit 1
fi

hdiutil detach "${MOUNT_POINT}" -force >/dev/null

echo "=== DMG Created Successfully: ${OUTPUT_DMG} ==="
ls -lh "${OUTPUT_DMG}"
