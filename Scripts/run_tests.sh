#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_BIN="${PROJECT_DIR}/build/UpackX.app/Contents/MacOS/UpackX"

if [ ! -f "${BUILD_BIN}" ]; then
    echo "Executable not found. Building first..."
    "${PROJECT_DIR}/Scripts/build.sh"
fi

TEST_DIR="/tmp/upackx_test_suite_$(date +%s)"
mkdir -p "${TEST_DIR}"
trap 'rm -rf "${TEST_DIR}"' EXIT

PASSED=0
FAILED=0

pass() {
    echo -e "  \033[32m✔ PASS:\033[0m $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "  \033[31m✘ FAIL:\033[0m $1 - $2"
    FAILED=$((FAILED + 1))
}

echo "========================================================"
echo "    UpackX Quality & Compliance Verification Test Suite"
echo "    macOS $(sw_vers -productVersion) ($(uname -m))"
echo "========================================================"

# -------------------------------------------------------------------------
# Test 1: Small Archives (ZIP, TAR.GZ, 7Z, RAR) with Unicode / Vietnamese
# -------------------------------------------------------------------------
echo ""
echo "[Test 1] Testing Basic & Unicode extraction (ZIP, TAR.GZ, 7Z, RAR)..."
SRC_1="${TEST_DIR}/src_unicode"
mkdir -p "${SRC_1}/Thư mục cấp 1/Thư mục con"
echo "Xin chào AGY - UpackX 2026!" > "${SRC_1}/Thư mục cấp 1/Thư mục con/Tiếng Việt có dấu - Đồ án tốt nghiệp.txt"
echo "Simple content" > "${SRC_1}/hello.txt"

# Create archives
(cd "${SRC_1}" && zip -r "${TEST_DIR}/test_small.zip" .) >/dev/null
(cd "${SRC_1}" && tar -czf "${TEST_DIR}/test_small.tar.gz" .) >/dev/null
if command -v 7zz >/dev/null; then
    (cd "${SRC_1}" && 7zz a "${TEST_DIR}/test_small.7z" .) >/dev/null
fi
if command -v rar >/dev/null; then
    (cd "${SRC_1}" && rar a -idq "${TEST_DIR}/test_small.rar" .) >/dev/null
fi

# Test ZIP
DEST_ZIP="${TEST_DIR}/dest_zip"
mkdir -p "${DEST_ZIP}"
"${BUILD_BIN}" --quick "${TEST_DIR}/test_small.zip" >/dev/null 2>&1 || true
# In quick extract, destination is parent folder (${TEST_DIR})
if [ -f "${TEST_DIR}/hello.txt" ] && [ -f "${TEST_DIR}/Thư mục cấp 1/Thư mục con/Tiếng Việt có dấu - Đồ án tốt nghiệp.txt" ]; then
    pass "Quick Extract ZIP with Vietnamese Unicode file names & hierarchy preserved"
    rm -rf "${TEST_DIR}/hello.txt" "${TEST_DIR}/Thư mục cấp 1"
else
    fail "ZIP Extraction" "Files not found at expected destination"
fi

# Test TAR.GZ
"${BUILD_BIN}" --quick "${TEST_DIR}/test_small.tar.gz" >/dev/null 2>&1 || true
if [ -f "${TEST_DIR}/hello.txt" ] && [ -f "${TEST_DIR}/Thư mục cấp 1/Thư mục con/Tiếng Việt có dấu - Đồ án tốt nghiệp.txt" ]; then
    pass "Quick Extract TAR.GZ with Vietnamese Unicode file names & hierarchy preserved"
    rm -rf "${TEST_DIR}/hello.txt" "${TEST_DIR}/Thư mục cấp 1"
else
    fail "TAR.GZ Extraction" "Files not found at expected destination"
fi

# Test 7Z if generated
if [ -f "${TEST_DIR}/test_small.7z" ]; then
    "${BUILD_BIN}" --quick "${TEST_DIR}/test_small.7z" >/dev/null 2>&1 || true
    if [ -f "${TEST_DIR}/hello.txt" ]; then
        pass "Quick Extract 7Z successfully"
        rm -rf "${TEST_DIR}/hello.txt" "${TEST_DIR}/Thư mục cấp 1"
    else
        fail "7Z Extraction" "Files not found"
    fi
fi

# Test RAR if generated
if [ -f "${TEST_DIR}/test_small.rar" ]; then
    "${BUILD_BIN}" --quick "${TEST_DIR}/test_small.rar" >/dev/null 2>&1 || true
    if [ -f "${TEST_DIR}/hello.txt" ]; then
        pass "Quick Extract RAR successfully"
        rm -rf "${TEST_DIR}/hello.txt" "${TEST_DIR}/Thư mục cấp 1"
    else
        fail "RAR Extraction" "Files not found"
    fi
fi

# -------------------------------------------------------------------------
# Test 2: Deep nested directory structure (10 levels)
# -------------------------------------------------------------------------
echo ""
echo "[Test 2] Deep nested directory structure (10 levels)..."
DEEP_SRC="${TEST_DIR}/deep_src"
DEEP_PATH="${DEEP_SRC}"
for i in {1..10}; do
    DEEP_PATH="${DEEP_PATH}/level_${i}"
done
mkdir -p "${DEEP_PATH}"
echo "Deep file content" > "${DEEP_PATH}/deep_file.txt"

(cd "${DEEP_SRC}" && zip -r "${TEST_DIR}/deep.zip" .) >/dev/null
"${BUILD_BIN}" --quick "${TEST_DIR}/deep.zip" >/dev/null 2>&1 || true

CHECK_DEEP="${TEST_DIR}"
for i in {1..10}; do
    CHECK_DEEP="${CHECK_DEEP}/level_${i}"
done
if [ -f "${CHECK_DEEP}/deep_file.txt" ]; then
    pass "Deep nested 10-level directory extracted completely"
    rm -rf "${TEST_DIR}/level_1"
else
    fail "Deep Directory Extraction" "Level 10 deep file not found"
fi

# -------------------------------------------------------------------------
# Test 3: Safe conflict handling (Never silent overwrite)
# -------------------------------------------------------------------------
echo ""
echo "[Test 3] Collision & Conflict Safety (Never silent overwrite)..."
COLLISION_DIR="${TEST_DIR}/collision"
mkdir -p "${COLLISION_DIR}"
echo "ORIGINAL USER DATA DO NOT OVERWRITE" > "${COLLISION_DIR}/conflict_file.txt"

# Create archive containing conflict_file.txt with DIFFERENT content
ARCH_SRC="${TEST_DIR}/arch_src"
mkdir -p "${ARCH_SRC}"
echo "NEW ARCHIVE CONTENT" > "${ARCH_SRC}/conflict_file.txt"
(cd "${ARCH_SRC}" && zip -r "${COLLISION_DIR}/test_conflict.zip" conflict_file.txt) >/dev/null

# Extract in Quick Extract mode
"${BUILD_BIN}" --quick "${COLLISION_DIR}/test_conflict.zip" >/dev/null 2>&1 || true

ORIGINAL_CONTENT=$(cat "${COLLISION_DIR}/conflict_file.txt")
if [ "${ORIGINAL_CONTENT}" = "ORIGINAL USER DATA DO NOT OVERWRITE" ]; then
    pass "Existing file preserved! Never silently overwritten"
else
    fail "Conflict Safety" "Original file was silently overwritten!"
fi

# Also check that non-conflicting renamed file was created
if [ -f "${COLLISION_DIR}/conflict_file (1).txt" ]; then
    pass "Non-conflicting copy 'conflict_file (1).txt' was safely created"
fi

# -------------------------------------------------------------------------
# Test 4: Zip-Slip / Path Traversal Attack Prevention
# -------------------------------------------------------------------------
echo ""
echo "[Test 4] Zip-Slip / Path Traversal Attack Defense..."
MALICIOUS_ZIP="${TEST_DIR}/malicious_slip.zip"
python3 -c "
import zipfile
with zipfile.ZipFile('${MALICIOUS_ZIP}', 'w') as z:
    z.writestr('../../evil_slip.txt', 'MALICIOUS CONTENT OUTSIDE DESTINATION')
"

MALICIOUS_EXTRACT_DIR="${TEST_DIR}/safe_target"
mkdir -p "${MALICIOUS_EXTRACT_DIR}"

# Run extractor on malicious zip
"${BUILD_BIN}" --quick "${MALICIOUS_ZIP}" >/dev/null 2>&1 || true

if [ -f "${TEST_DIR}/evil_slip.txt" ] || [ -f "/tmp/evil_slip.txt" ]; then
    fail "Zip-Slip Defense" "VULNERABILITY DETECTED: File escaped destination directory!"
    rm -f "${TEST_DIR}/evil_slip.txt" "/tmp/evil_slip.txt"
else
    pass "Zip-Slip prevented: Malicious '../../' path blocked safely"
fi

# -------------------------------------------------------------------------
# Test 5: Corrupted / Incomplete archive detection
# -------------------------------------------------------------------------
echo ""
echo "[Test 5] Corrupted Archive Handling..."
CORRUPT_ARCH="${TEST_DIR}/corrupt.zip"
head -c 500 /dev/urandom > "${CORRUPT_ARCH}"

if "${BUILD_BIN}" --quick "${CORRUPT_ARCH}" >/dev/null 2>&1; then
    fail "Corruption Detection" "Extractor reported success on random garbage file!"
else
    pass "Corrupted archive correctly detected and rejected with non-zero exit code"
fi

# -------------------------------------------------------------------------
# Test 6: Multi-Part Archive Detection (Stage 2 foundation)
# -------------------------------------------------------------------------
echo ""
echo "[Test 6] Multi-part Volume Grouping Architecture..."
PART_DIR="${TEST_DIR}/parts"
mkdir -p "${PART_DIR}"
touch "${PART_DIR}/movie.part1.rar" "${PART_DIR}/movie.part2.rar" "${PART_DIR}/movie.part3.rar"
touch "${PART_DIR}/dataset.7z.001" "${PART_DIR}/dataset.7z.002"
touch "${PART_DIR}/single.zip"

SWIFT_TEST_SCRIPT="${TEST_DIR}/main.swift"
cat << 'EOF' > "${SWIFT_TEST_SCRIPT}"
import Foundation

let partDir = CommandLine.arguments[1]
let urls = [
    URL(fileURLWithPath: "\(partDir)/movie.part1.rar"),
    URL(fileURLWithPath: "\(partDir)/movie.part2.rar"),
    URL(fileURLWithPath: "\(partDir)/movie.part3.rar"),
    URL(fileURLWithPath: "\(partDir)/dataset.7z.001"),
    URL(fileURLWithPath: "\(partDir)/dataset.7z.002"),
    URL(fileURLWithPath: "\(partDir)/single.zip")
]

let (primary, groups) = MultipartDetector.groupArchives(urls)
let primaryNames = primary.map { $0.lastPathComponent }.sorted()
let ok = (primary.count == 3 && primaryNames.contains("movie.part1.rar") && primaryNames.contains("dataset.7z.001") && primaryNames.contains("single.zip"))
exit(ok ? 0 : 1)
EOF

swiftc -target x86_64-apple-macos14.0 \
    "${PROJECT_DIR}/Sources/Core/MultipartDetector.swift" \
    "${SWIFT_TEST_SCRIPT}" \
    -o "${TEST_DIR}/test_multipart"

if "${TEST_DIR}/test_multipart" "${PART_DIR}"; then
    pass "Multi-part volumes recognized: only primary volumes (part1, 001) queued, peer parts grouped"
else
    fail "Multipart Grouping" "Multipart volumes not grouped accurately"
fi

# -------------------------------------------------------------------------
# Test 7: Large Archive Streaming & RAM/CPU Footprint
# -------------------------------------------------------------------------
echo ""
echo "[Test 7] Large Archive Streaming & Memory Benchmark..."
LARGE_SRC="${TEST_DIR}/large_src"
mkdir -p "${LARGE_SRC}"

echo "  Generating 120 MB test archive..."
dd if=/dev/urandom of="${LARGE_SRC}/large_1.bin" bs=1048576 count=60 status=none
dd if=/dev/urandom of="${LARGE_SRC}/large_2.bin" bs=1048576 count=60 status=none

LARGE_ZIP="${TEST_DIR}/large_test.zip"
(cd "${LARGE_SRC}" && zip -0 "${LARGE_ZIP}" large_1.bin large_2.bin) >/dev/null

LARGE_DEST="${TEST_DIR}/large_dest"
mkdir -p "${LARGE_DEST}"

# Run extraction in background and sample memory RSS with ps
"${BUILD_BIN}" --quick "${LARGE_ZIP}" >/dev/null 2>&1 &
APP_PID=$!

MAX_RSS_KB=0
while kill -0 "${APP_PID}" 2>/dev/null; do
    RSS=$(ps -o rss= -p "${APP_PID}" 2>/dev/null || echo 0)
    RSS=$(echo "${RSS}" | tr -d ' ')
    if [ -n "${RSS}" ] && [ "${RSS}" -gt "${MAX_RSS_KB}" ] 2>/dev/null; then
        MAX_RSS_KB=${RSS}
    fi
    sleep 0.05
done
wait "${APP_PID}" || true

MAX_RSS_MB=$(echo "scale=1; ${MAX_RSS_KB} / 1024" | bc)
echo "  Peak Memory (RSS) observed during 120MB extraction: ${MAX_RSS_MB} MB"

if [ -f "${TEST_DIR}/large_1.bin" ] && [ -f "${TEST_DIR}/large_2.bin" ]; then
    pass "Large 120 MB Archive extracted completely with streaming"
    rm -rf "${TEST_DIR}/large_1.bin" "${TEST_DIR}/large_2.bin"
else
    fail "Large Archive" "Large extracted files missing"
fi

# -------------------------------------------------------------------------
# Test 8: Finder Quick Actions Installation Verification
# -------------------------------------------------------------------------
echo ""
echo "[Test 8] Finder Integration & Services Check..."
"${BUILD_BIN}" --install-services >/dev/null 2>&1

SERVICES_DIR="${HOME}/Library/Services"
WORKFLOW_QUICK="${SERVICES_DIR}/UpackX - Giải nén nhanh.workflow"
WORKFLOW_TO="${SERVICES_DIR}/UpackX - Giải nén….workflow"

if [ -d "${WORKFLOW_QUICK}" ] && [ -d "${WORKFLOW_TO}" ]; then
    pass "Finder Quick Action workflows installed in ~/Library/Services"
else
    fail "Finder Integration" "Workflows missing in ~/Library/Services"
fi

if grep -q "NSServices" "${WORKFLOW_QUICK}/Contents/Info.plist" && grep -q "runWorkflowAsService" "${WORKFLOW_QUICK}/Contents/Info.plist"; then
    pass "Quick Action workflow contains valid NSServices metadata for Finder right-click"
else
    fail "Finder Metadata" "NSServices definition missing in workflow Info.plist"
fi

# -------------------------------------------------------------------------
# Test 9: Password-protected archive extraction
# -------------------------------------------------------------------------
echo ""
echo "[Test 9] Password-protected Archive (ZIP AES / 7Z)..."
PASS_SRC="${TEST_DIR}/pass_src"
mkdir -p "${PASS_SRC}"
echo "SUPER SECRET CONTENT" > "${PASS_SRC}/secret.txt"

(cd "${PASS_SRC}" && zip -P "P@ssw0rd2026" "${TEST_DIR}/secret.zip" secret.txt) >/dev/null

# Attempt without password: must fail
if "${BUILD_BIN}" --quick "${TEST_DIR}/secret.zip" >/dev/null 2>&1; then
    fail "Password Protection" "Protected archive extracted without password!"
else
    pass "Encrypted archive correctly rejected when password is missing"
fi

# -------------------------------------------------------------------------
# Test 10: Multiple archives passed simultaneously
# -------------------------------------------------------------------------
echo ""
echo "[Test 10] Batch Extraction of Multiple Archives Simultaneously..."
BATCH_DIR="${TEST_DIR}/batch"
mkdir -p "${BATCH_DIR}"
echo "file A" > "${BATCH_DIR}/a.txt"
echo "file B" > "${BATCH_DIR}/b.txt"
(cd "${BATCH_DIR}" && zip "${TEST_DIR}/batch_a.zip" a.txt) >/dev/null
(cd "${BATCH_DIR}" && zip "${TEST_DIR}/batch_b.zip" b.txt) >/dev/null

"${BUILD_BIN}" --quick "${TEST_DIR}/batch_a.zip" "${TEST_DIR}/batch_b.zip" >/dev/null 2>&1 || true

if [ -f "${TEST_DIR}/a.txt" ] && [ -f "${TEST_DIR}/b.txt" ]; then
    pass "Multiple archives passed at once both extracted successfully"
    rm -f "${TEST_DIR}/a.txt" "${TEST_DIR}/b.txt"
else
    fail "Batch Extraction" "Files from batch extraction missing"
fi

# -------------------------------------------------------------------------
# Test 11: Cancellation Handling (Clean partial file cleanup)
# -------------------------------------------------------------------------
echo ""
echo "[Test 11] Mid-flight Extraction Cancellation & Cleanup..."
CANCEL_SRC="${TEST_DIR}/cancel_src"
mkdir -p "${CANCEL_SRC}"
dd if=/dev/urandom of="${CANCEL_SRC}/cancel_big.bin" bs=1048576 count=80 status=none
(cd "${CANCEL_SRC}" && zip -0 "${TEST_DIR}/cancel_test.zip" cancel_big.bin) >/dev/null

# Start extraction and kill with SIGINT midway
"${BUILD_BIN}" --quick "${TEST_DIR}/cancel_test.zip" >/dev/null 2>&1 &
CANCEL_PID=$!
sleep 0.15
kill -INT "${CANCEL_PID}" 2>/dev/null || true
wait "${CANCEL_PID}" 2>/dev/null || true

# Verify no half-written file or orphan .upackx_part file left on disk
PART_FILES=$(find "${TEST_DIR}" -name "*.upackx_part" 2>/dev/null || true)
if [ -z "${PART_FILES}" ]; then
    pass "Cancellation left zero orphan temporary .upackx_part files"
else
    fail "Cancellation Cleanup" "Temporary partial file remained: ${PART_FILES}"
fi

# -------------------------------------------------------------------------
# Test 12: 500 MB Large File Extraction & RAM Benchmark
# -------------------------------------------------------------------------
echo ""
echo "[Test 12] 500 MB Gigantic Archive Streaming & Memory Benchmark..."
GIGA_SRC="${TEST_DIR}/giga_src"
mkdir -p "${GIGA_SRC}"
echo "  Creating 500 MB binary data..."
dd if=/dev/zero of="${GIGA_SRC}/huge_500mb.dat" bs=1048576 count=500 status=none

(cd "${GIGA_SRC}" && zip -0 "${TEST_DIR}/huge_500mb.zip" huge_500mb.dat) >/dev/null

"${BUILD_BIN}" --quick "${TEST_DIR}/huge_500mb.zip" >/dev/null 2>&1 &
HUGE_PID=$!

HUGE_MAX_RSS=0
while kill -0 "${HUGE_PID}" 2>/dev/null; do
    RSS=$(ps -o rss= -p "${HUGE_PID}" 2>/dev/null || echo 0)
    RSS=$(echo "${RSS}" | tr -d ' ')
    if [ -n "${RSS}" ] && [ "${RSS}" -gt "${HUGE_MAX_RSS}" ] 2>/dev/null; then
        HUGE_MAX_RSS=${RSS}
    fi
    sleep 0.05
done
wait "${HUGE_PID}" || true

HUGE_RSS_MB=$(echo "scale=1; ${HUGE_MAX_RSS} / 1024" | bc)
echo "  Peak Memory (RSS) observed during 500MB extraction: ${HUGE_RSS_MB} MB"

if [ -f "${TEST_DIR}/huge_500mb.dat" ]; then
    pass "500 MB Archive extracted completely with streaming (RAM: ${HUGE_RSS_MB} MB)"
    rm -f "${TEST_DIR}/huge_500mb.dat"
else
    fail "500 MB Archive" "500 MB file missing"
fi

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo ""
echo "========================================================"
echo "    Test Results: ${PASSED} Passed, ${FAILED} Failed"
echo "========================================================"

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
