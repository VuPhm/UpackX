#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.2.0}"
DIST_DIR="${PROJECT_DIR}/dist"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"

echo "=========================================================="
echo "    UpackX Production Release Pre-Flight & QA Verification"
echo "    Target Version: v${VERSION}"
echo "=========================================================="

PASSED=0
FAILED=0

check_pass() {
    echo -e "  \033[32m✔ PASS:\033[0m $1"
    PASSED=$((PASSED + 1))
}

check_fail() {
    echo -e "  \033[31m✘ FAIL:\033[0m $1 - $2"
    FAILED=$((FAILED + 1))
}

# 1. Binary Architecture Check
echo ""
echo "[Check 1] Binary Architecture & Deployment Target..."
MAIN_BIN="${BUILD_APP}/Contents/MacOS/UpackX"
if [ -f "${MAIN_BIN}" ]; then
    ARCH_INFO=$(file "${MAIN_BIN}")
    if [[ "${ARCH_INFO}" == *"x86_64"* ]]; then
        check_pass "Main executable architecture is Intel x86_64 (${ARCH_INFO})"
    else
        check_fail "Main executable" "Architecture is not x86_64: ${ARCH_INFO}"
    fi
else
    check_fail "Main executable" "Missing at ${MAIN_BIN}"
fi

# 2. Bundled 7zz Helper Check
echo ""
echo "[Check 2] Standalone Helper (7zz) Architecture..."
HELPER_BIN="${BUILD_APP}/Contents/Resources/bin/7zz"
if [ -f "${HELPER_BIN}" ]; then
    HELPER_ARCH=$(file "${HELPER_BIN}")
    if [[ "${HELPER_ARCH}" == *"x86_64"* ]]; then
        check_pass "Bundled 7zz helper architecture is x86_64"
    else
        check_fail "Bundled 7zz" "Architecture unexpected: ${HELPER_ARCH}"
    fi
else
    check_fail "Bundled 7zz" "Helper missing in Resources/bin"
fi

# 3. Info.plist & Version Metadata
echo ""
echo "[Check 3] Info.plist Metadata Integrity..."
PLIST_PATH="${BUILD_APP}/Contents/Info.plist"
PLIST_VER=$(defaults read "${PLIST_PATH}" CFBundleShortVersionString 2>/dev/null || echo "")
PLIST_ID=$(defaults read "${PLIST_PATH}" CFBundleIdentifier 2>/dev/null || echo "")
PLIST_MIN=$(defaults read "${PLIST_PATH}" LSMinimumSystemVersion 2>/dev/null || echo "")

if [ "${PLIST_VER}" = "${VERSION}" ]; then
    check_pass "Info.plist CFBundleShortVersionString matches '${VERSION}'"
else
    check_fail "Info.plist Version" "Expected '${VERSION}', found '${PLIST_VER}'"
fi

if [ "${PLIST_ID}" = "com.upackx.extractor" ]; then
    check_pass "Bundle Identifier is com.upackx.extractor"
else
    check_fail "Bundle Identifier" "Expected 'com.upackx.extractor', found '${PLIST_ID}'"
fi

if [ "${PLIST_MIN}" = "14.0" ]; then
    check_pass "LSMinimumSystemVersion set to macOS 14.0"
else
    check_fail "System Version" "Expected '14.0', found '${PLIST_MIN}'"
fi

# 4. Code Signature Check
echo ""
echo "[Check 4] Code Signature Status..."
if codesign --verify "${BUILD_APP}" >/dev/null 2>&1; then
    check_pass "Application bundle code signature is valid on disk"
else
    check_fail "Code Signature" "Bundle verification failed"
fi

# 5. Distribution Artifacts Existence
echo ""
echo "[Check 5] Distribution Artifacts in dist/..."
DMG_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Intel.dmg"
PKG_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Intel.pkg"
ZIP_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Intel.zip"
SUMS_FILE="${DIST_DIR}/SHA256SUMS.txt"

for f in "${DMG_FILE}" "${PKG_FILE}" "${ZIP_FILE}" "${SUMS_FILE}"; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        check_pass "Artifact present: $(basename "$f") ($(ls -lh "$f" | awk '{print $5}'))"
    else
        check_fail "Artifact missing" "$(basename "$f") is missing or empty"
    fi
done

# 6. Checksum Verification
echo ""
echo "[Check 6] SHA-256 Checksums Verification..."
if (cd "${DIST_DIR}" && shasum -c SHA256SUMS.txt >/dev/null 2>&1); then
    check_pass "All distribution artifacts pass SHA256 checksum verification"
else
    check_fail "Checksum Verification" "SHA256SUMS.txt mismatch"
fi

# 7. DMG Mountability & Structure
echo ""
echo "[Check 7] DMG Mountability & Layout..."
MOUNT_VOL="/Volumes/UpackX"
if [ -d "${MOUNT_VOL}" ]; then
    hdiutil detach "${MOUNT_VOL}" -force 2>/dev/null || true
fi

hdiutil attach -nobrowse -readonly "${DMG_FILE}" >/dev/null
if [ -d "${MOUNT_VOL}/UpackX.app" ] && [ -L "${MOUNT_VOL}/Applications" ]; then
    check_pass "DMG mounts cleanly: contains UpackX.app and Applications symlink"
else
    check_fail "DMG Mount" "Contents in mounted DMG missing or corrupt"
fi
hdiutil detach "${MOUNT_VOL}" -force >/dev/null 2>&1 || true

# 8. PKG Payload Structure
echo ""
echo "[Check 8] PKG Payload Verification..."
if pkgutil --payload-files "${PKG_FILE}" | grep -q "UpackX.app/Contents/MacOS/UpackX"; then
    check_pass "PKG payload contains complete UpackX.app structure"
else
    check_fail "PKG Payload" "UpackX executable not found in payload"
fi

# 9. ZIP Archive Integrity
echo ""
echo "[Check 9] ZIP Archive Integrity..."
if unzip -tq "${ZIP_FILE}" >/dev/null 2>&1; then
    check_pass "Portable ZIP passes unzip integrity check without corruption"
else
    check_fail "ZIP Integrity" "unzip reported errors"
fi

# 10. Summary
echo ""
echo "=========================================================="
echo "    Pre-Flight QA Results: ${PASSED} Passed, ${FAILED} Failed"
echo "=========================================================="

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
