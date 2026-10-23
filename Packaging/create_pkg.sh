#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.2.0}"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"
DIST_DIR="${PROJECT_DIR}/dist"
OUTPUT_PKG="${DIST_DIR}/UpackX-v${VERSION}-macOS-Intel.pkg"

echo "=== Packaging UpackX Apple Installer PKG (v${VERSION}) ==="

if [ ! -d "${BUILD_APP}" ]; then
    echo "Error: ${BUILD_APP} does not exist. Run 'make build' first."
    exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${OUTPUT_PKG}"

TMP_DIR="/tmp/upackx_pkg_staging_$$"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "1. Building component package (pkgbuild)..."
pkgbuild --component "${BUILD_APP}" \
         --install-location "/Applications" \
         --scripts "${PROJECT_DIR}/Packaging/scripts" \
         --identifier "com.upackx.extractor" \
         --version "${VERSION}" \
         "${TMP_DIR}/UpackX-component.pkg"

echo "2. Building native distribution package (productbuild)..."
productbuild --distribution "${PROJECT_DIR}/Packaging/Distribution.xml" \
             --package-path "${TMP_DIR}" \
             --resources "${PROJECT_DIR}/Packaging/html" \
             "${OUTPUT_PKG}"

echo "3. Verifying PKG integrity..."
if pkgutil --payload-files "${OUTPUT_PKG}" | grep -q "UpackX.app/Contents/MacOS/UpackX"; then
    echo "✔ PKG payload verified: UpackX.app binary present in package."
else
    echo "✘ Error: PKG payload verification failed."
    exit 1
fi

echo "=== PKG Created Successfully: ${OUTPUT_PKG} ==="
ls -lh "${OUTPUT_PKG}"
