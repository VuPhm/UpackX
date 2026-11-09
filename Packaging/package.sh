#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-$(defaults read "${PROJECT_DIR}/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.4.0")}"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"
DIST_DIR="${PROJECT_DIR}/dist"

echo "=========================================================="
echo "    UpackX Production Release Packager"
echo "    Version: v${VERSION} (macOS Universal 2: x86_64 & arm64)"
echo "=========================================================="

# 1. Build application bundle
echo ""
echo "[Step 1/5] Building Release Application Bundle..."
"${PROJECT_DIR}/Scripts/build.sh"

# 2. Prepare output directory
mkdir -p "${DIST_DIR}"

# 3. Create DMG
echo ""
echo "[Step 2/5] Creating Distribution DMG (Primary Installer)..."
"${PROJECT_DIR}/Packaging/create_dmg.sh" "${VERSION}"

# 4. Create PKG
echo ""
echo "[Step 3/5] Creating Apple Installer PKG..."
"${PROJECT_DIR}/Packaging/create_pkg.sh" "${VERSION}"

# 5. Create Portable ZIP using ditto
echo ""
echo "[Step 4/5] Creating Portable ZIP (.app preserve metadata)..."
ZIP_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Universal.zip"
rm -f "${ZIP_FILE}"
ditto -c -k --keepParent "${BUILD_APP}" "${ZIP_FILE}"
echo "✔ Portable ZIP created: ${ZIP_FILE}"
ls -lh "${ZIP_FILE}"

# 6. Generate SHA-256 Checksums
echo ""
echo "[Step 5/5] Generating SHA256SUMS.txt..."
(
    cd "${DIST_DIR}"
    shasum -a 256 \
        "UpackX-v${VERSION}-macOS-Universal.dmg" \
        "UpackX-v${VERSION}-macOS-Universal.pkg" \
        "UpackX-v${VERSION}-macOS-Universal.zip" > SHA256SUMS.txt
)

echo ""
echo "=========================================================="
echo "    Packaging Summary: All Artifacts Ready in dist/"
echo "=========================================================="
ls -lh "${DIST_DIR}"
echo ""
cat "${DIST_DIR}/SHA256SUMS.txt"
echo "=========================================================="
