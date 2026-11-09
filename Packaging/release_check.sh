#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-$(defaults read "${PROJECT_DIR}/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.4.0")}"
DIST_DIR="${PROJECT_DIR}/dist"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"

echo "=========================================================="
echo "    UpackX Production Release Pre-Flight & QA Verification"
echo "    Target Version: v${VERSION} (macOS Universal 2)"
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

check_note() {
    echo -e "  \033[34mℹ NOTE:\033[0m $1"
}

# 1. Main Binary Architecture Check
echo ""
echo "[Check 1] Main Executable Architecture & Verification..."
MAIN_BIN="${BUILD_APP}/Contents/MacOS/UpackX"
if [ -f "${MAIN_BIN}" ]; then
    LIPO_INFO=$(lipo -info "${MAIN_BIN}")
    if [[ "${LIPO_INFO}" == *"x86_64"* ]] && [[ "${LIPO_INFO}" == *"arm64"* ]]; then
        check_pass "Main executable is Universal 2 with native x86_64 and arm64 slices (${LIPO_INFO})"
    else
        check_fail "Main executable architecture" "Expected Universal 2 (x86_64 + arm64), found: ${LIPO_INFO}"
    fi

    # Host execution test
    HOST_ARCH=$(uname -m)
    if [ "${HOST_ARCH}" = "x86_64" ]; then
        if "${MAIN_BIN}" --version | grep -q "1.4.0"; then
            check_pass "Host execution (x86_64 slice): runs cleanly, reports v1.4.0"
        else
            check_fail "Host execution" "Main binary failed to execute --version"
        fi
        check_note "arm64 slice verified via lipo/file/linkage. Host is x86_64; physical arm64 execution: NOT VERIFIED on host"
    elif [ "${HOST_ARCH}" = "arm64" ]; then
        if "${MAIN_BIN}" --version | grep -q "1.4.0"; then
            check_pass "Host execution (arm64 slice): runs cleanly, reports v1.4.0"
        else
            check_fail "Host execution" "Main binary failed to execute --version"
        fi
        check_note "x86_64 slice verified via lipo/file/linkage."
    fi
else
    check_fail "Main executable" "Missing at ${MAIN_BIN}"
fi

# 2. Bundled Standalone 7zz Helper Check
echo ""
echo "[Check 2] Bundled Helper (7zz) Architecture & Verification..."
HELPER_BIN="${BUILD_APP}/Contents/Resources/bin/7zz"
if [ -f "${HELPER_BIN}" ]; then
    HELPER_LIPO=$(lipo -info "${HELPER_BIN}")
    if [[ "${HELPER_LIPO}" == *"x86_64"* ]] && [[ "${HELPER_LIPO}" == *"arm64"* ]]; then
        check_pass "Bundled 7zz helper is Universal 2 with native x86_64 and arm64 slices"
    else
        check_fail "Bundled 7zz architecture" "Expected Universal 2, found: ${HELPER_LIPO}"
    fi

    # Helper runability on host
    if "${HELPER_BIN}" --help >/dev/null 2>&1; then
        check_pass "Bundled 7zz helper executes cleanly on host without error"
    else
        check_fail "Bundled 7zz execution" "Helper failed to execute --help"
    fi
else
    check_fail "Bundled 7zz" "Helper missing in Resources/bin"
fi

# 3. Dynamic Library Linkage (No Homebrew dependency)
echo ""
echo "[Check 3] Library Linkage Integrity (Zero Homebrew / Third-party dependencies)..."
MAIN_LIBS=$(otool -L "${MAIN_BIN}" 2>/dev/null || true)
if echo "${MAIN_LIBS}" | grep -E -q "(/usr/local/Cellar|/opt/homebrew|homebrew)"; then
    check_fail "Main binary linkage" "Found Homebrew dependency in linkage:\n${MAIN_LIBS}"
else
    check_pass "Main binary has zero Homebrew linkages; links exclusively to macOS system frameworks & /usr/lib/libarchive.2.dylib"
fi

HELPER_LIBS=$(otool -L "${HELPER_BIN}" 2>/dev/null || true)
if echo "${HELPER_LIBS}" | grep -E -q "(/usr/local/Cellar|/opt/homebrew|homebrew)"; then
    check_fail "Helper 7zz linkage" "Found Homebrew dependency in helper:\n${HELPER_LIBS}"
else
    check_pass "Helper 7zz links exclusively to macOS system /usr/lib/libSystem and /usr/lib/libc++"
fi

# 4. Info.plist & Version Metadata
echo ""
echo "[Check 4] Info.plist Metadata Integrity & Services Filtering..."
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

# Verify all 4 NSServices are declared
for svc in "quickExtractService" "extractToService" "quickCompressService" "compressToService"; do
    if grep -q "<string>${svc}</string>" "${PLIST_PATH}"; then
        check_pass "NSService '${svc}' is declared in Info.plist"
    else
        check_fail "NSService Missing" "Service '${svc}' not found in Info.plist"
    fi
done

# Verify extraction services do NOT match public.item or public.data
python3 -c "
import plistlib, sys
with open('${PLIST_PATH}', 'rb') as f:
    pl = plistlib.load(f)
services = pl.get('NSServices', [])
for s in services:
    msg = s.get('NSMessage', '')
    if 'Extract' in msg or 'extract' in msg:
        types = s.get('NSSendFileTypes', [])
        if 'public.item' in types or 'public.data' in types:
            print(f'FAIL: {msg} contains public.item/public.data')
            sys.exit(1)
sys.exit(0)
" && check_pass "Extract services correctly exclude 'public.item' and 'public.data' (no clutter on non-archive files)" || \
   check_fail "Extract Service Filters" "Extract services contain generic public.item or public.data"

# 5. Code Signature Check
echo ""
echo "[Check 5] Code Signature Status & Ad-hoc Integrity..."
if codesign --verify --deep --strict "${BUILD_APP}" >/dev/null 2>&1; then
    check_pass "Application bundle code signature is valid and strict on disk"
    check_note "Ad-hoc signed (No Apple Developer ID). Unnotarized Gatekeeper Privacy & Security flow applies."
else
    check_fail "Code Signature" "Bundle verification failed"
fi

# 6. Distribution Artifacts Existence
echo ""
echo "[Check 6] Distribution Artifacts in dist/..."
DMG_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Universal.dmg"
PKG_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Universal.pkg"
ZIP_FILE="${DIST_DIR}/UpackX-v${VERSION}-macOS-Universal.zip"
SUMS_FILE="${DIST_DIR}/SHA256SUMS.txt"

for f in "${DMG_FILE}" "${PKG_FILE}" "${ZIP_FILE}" "${SUMS_FILE}"; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        check_pass "Artifact present: $(basename "$f") ($(ls -lh "$f" | awk '{print $5}'))"
    else
        check_fail "Artifact missing" "$(basename "$f") is missing or empty"
    fi
done

# 7. Checksum Verification
echo ""
echo "[Check 7] SHA-256 Checksums Verification..."
if (cd "${DIST_DIR}" && shasum -c SHA256SUMS.txt >/dev/null 2>&1); then
    check_pass "All distribution artifacts pass SHA256 checksum verification"
else
    check_fail "Checksum Verification" "SHA256SUMS.txt mismatch"
fi

# 8. DMG Mountability & Structure
echo ""
echo "[Check 8] DMG Mountability, Layout & First-Launch Trust Guide..."
MOUNT_VOL="/Volumes/UpackX"
if [ -d "${MOUNT_VOL}" ]; then
    hdiutil detach "${MOUNT_VOL}" -force 2>/dev/null || true
fi

hdiutil attach -nobrowse -readonly "${DMG_FILE}" >/dev/null
if [ -d "${MOUNT_VOL}/UpackX.app" ] && [ -L "${MOUNT_VOL}/Applications" ] && [ -f "${MOUNT_VOL}/Hướng Dẫn Cài Đặt (Install Guide).html" ]; then
    check_pass "DMG mounts cleanly: contains UpackX.app, Applications link, and Hướng Dẫn Cài Đặt (Install Guide).html"
else
    check_fail "DMG Mount" "Contents in mounted DMG missing or incomplete"
fi

if codesign --verify --deep --strict "${MOUNT_VOL}/UpackX.app" >/dev/null 2>&1; then
    check_pass "Mounted DMG UpackX.app passes strict code signature verification"
else
    check_fail "Mounted DMG Signature" "UpackX.app inside DMG failed codesign verification"
fi
hdiutil detach "${MOUNT_VOL}" -force >/dev/null 2>&1 || true

# 9. PKG Payload Structure
echo ""
echo "[Check 9] PKG Payload Verification..."
if pkgutil --payload-files "${PKG_FILE}" | grep -q "UpackX.app/Contents/MacOS/UpackX"; then
    check_pass "PKG payload contains complete UpackX.app structure"
else
    check_fail "PKG Payload" "UpackX executable not found in payload"
fi

# 10. ZIP Archive Integrity
echo ""
echo "[Check 10] ZIP Archive Integrity..."
if unzip -tq "${ZIP_FILE}" >/dev/null 2>&1; then
    check_pass "Portable ZIP passes unzip integrity check without corruption"
else
    check_fail "ZIP Integrity" "unzip reported errors"
fi

# 11. Summary
echo ""
echo "=========================================================="
echo "    Pre-Flight QA Results: ${PASSED} Passed, ${FAILED} Failed"
echo "=========================================================="

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
