#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.2.1}"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"
DIST_DIR="${PROJECT_DIR}/dist"
OUTPUT_DMG="${DIST_DIR}/UpackX-v${VERSION}-macOS-Intel.dmg"

echo "=== Packaging UpackX DMG (v${VERSION}) ==="

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
if [ -d "${MOUNT_POINT}/UpackX.app" ] && [ -L "${MOUNT_POINT}/Applications" ]; then
    echo "✔ DMG structure verified: UpackX.app and Applications link present."
else
    echo "✘ Error: Mounted DMG contents invalid."
    hdiutil detach "${MOUNT_POINT}" -force 2>/dev/null || true
    exit 1
fi
hdiutil detach "${MOUNT_POINT}" -force >/dev/null

echo "=== DMG Created Successfully: ${OUTPUT_DMG} ==="
ls -lh "${OUTPUT_DMG}"
