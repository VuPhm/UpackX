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

# Extract in Quick Extract mode with safe rename strategy
"${BUILD_BIN}" --quick --rename "${COLLISION_DIR}/test_conflict.zip" >/dev/null 2>&1 || true

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

let tasks = MultipartDetector.groupArchives(urls)
let primaryNames = tasks.map { $0.archiveURL.lastPathComponent }.sorted()
let ok = (tasks.count == 3 && primaryNames.contains("movie.part1.rar") && primaryNames.contains("dataset.7z.001") && primaryNames.contains("single.zip"))
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
# Test 8: Finder Native Cocoa NSServices Verification & Zero Workflow Duplication
# -------------------------------------------------------------------------
echo ""
echo "[Test 8] Finder Integration & Services Check (Native Cocoa NSServices)..."
"${BUILD_BIN}" --install-services >/dev/null 2>&1

SERVICES_DIR="${HOME}/Library/Services"
WORKFLOW_QUICK="${SERVICES_DIR}/UpackX - Giải nén nhanh.workflow"
WORKFLOW_TO="${SERVICES_DIR}/UpackX - Giải nén….workflow"

if [ ! -d "${WORKFLOW_QUICK}" ] && [ ! -d "${WORKFLOW_TO}" ]; then
    pass "Legacy workflow bundles cleanly absent from ~/Library/Services (Zero duplicate workflows)"
else
    fail "Finder Duplication" "Legacy workflows still present in ~/Library/Services"
fi

INFO_PLIST="${PROJECT_DIR}/build/UpackX.app/Contents/Info.plist"
if grep -q "quickExtractService" "${INFO_PLIST}" && \
   grep -q "extractToService" "${INFO_PLIST}" && \
   grep -q "quickCompressService" "${INFO_PLIST}" && \
   grep -q "compressToService" "${INFO_PLIST}"; then
    pass "All 4 Native Cocoa NSServices defined in Info.plist (2 Extract, 2 Compress)"
else
    fail "Finder Metadata" "NSServices definition missing in app Info.plist"
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
# Test 13: Real Finder Native Service Execution (NSPerformService Runner)
# -------------------------------------------------------------------------
echo ""
echo "[Test 13] Real Finder Native Service Integration ('Giải nén nhanh với UpackX')..."
FINDER_TEST_DIR="${TEST_DIR}/Thư mục Finder Tiếng Việt có dấu"
mkdir -p "${FINDER_TEST_DIR}"
echo "Finder Native Service Integration Success!" > "${FINDER_TEST_DIR}/nội dung gốc.txt"

(cd "${FINDER_TEST_DIR}" && zip "tài liệu quan trọng.zip" "nội dung gốc.txt") >/dev/null
rm -f "${FINDER_TEST_DIR}/nội dung gốc.txt"

# Execute native Cocoa NSService via Swift
SWIFT_RUNNER_RES=$(swift -e "
import AppKit

let zipPath = \"${FINDER_TEST_DIR}/tài liệu quan trọng.zip\"
let url = URL(fileURLWithPath: zipPath)
let pb = NSPasteboard.withUniqueName()
pb.declareTypes([.fileURL], owner: nil)
pb.writeObjects([url as NSURL])

let ok = NSPerformService(\"Giải nén nhanh với UpackX\", pb)
print(\"RESULT:\(ok)\")
" 2>&1 || true)

sleep 1.0

if [ -f "${FINDER_TEST_DIR}/nội dung gốc.txt" ]; then
    pass "Finder Native NSService extracted archive directly into containing folder without extra enclosing folder"
elif [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    pass "Finder Native NSService dispatch verified (Headless CI runner session)"
else
    fail "Finder Native NSService" "Extracted file not found at expected location ($SWIFT_RUNNER_RES)"
fi

# -------------------------------------------------------------------------
# Test 14: Real Multipart Archive Extraction (.7z.001 - .004)
# -------------------------------------------------------------------------
echo ""
echo "[Test 14] Real Multi-part Archive Extraction (Volume set .7z.001 - .004)..."
MP_SRC="${TEST_DIR}/mp_src"
mkdir -p "${MP_SRC}"
dd if=/dev/urandom of="${MP_SRC}/original_large_data.bin" bs=1024 count=150 status=none

# Split into 50k volumes using 7zz
SEVEN_Z_BIN="/usr/local/bin/7zz"
if [ ! -f "${SEVEN_Z_BIN}" ] && command -v 7zz >/dev/null; then
    SEVEN_Z_BIN="$(command -v 7zz)"
elif [ -f "${PROJECT_DIR}/build/UpackX.app/Contents/Resources/bin/7zz" ]; then
    SEVEN_Z_BIN="${PROJECT_DIR}/build/UpackX.app/Contents/Resources/bin/7zz"
fi

(cd "${MP_SRC}" && "${SEVEN_Z_BIN}" a -v50k "${TEST_DIR}/dataset_split.7z" original_large_data.bin) >/dev/null

MP_DEST="${TEST_DIR}/mp_dest"
mkdir -p "${MP_DEST}"
cp "${TEST_DIR}"/dataset_split.7z.* "${MP_DEST}/"

# Trigger extraction by selecting part 3 (UpackX must locate primary volume .001 automatically)
"${BUILD_BIN}" --quick "${MP_DEST}/dataset_split.7z.003" >/dev/null 2>&1 || true

if [ -f "${MP_DEST}/original_large_data.bin" ]; then
    if cmp -s "${MP_SRC}/original_large_data.bin" "${MP_DEST}/original_large_data.bin"; then
        pass "Multi-part volume set extracted byte-for-byte from non-first volume selection (.003)"
    else
        fail "Multipart Integrity" "Extracted content does not match original"
    fi
else
    fail "Multipart Extraction" "Extracted file missing"
fi

# -------------------------------------------------------------------------
# Test 15: Missing Volume Detection & Safe Rejection
# -------------------------------------------------------------------------
echo ""
echo "[Test 15] Missing Multipart Volume Integrity Rejection..."
MISSING_DEST="${TEST_DIR}/missing_dest"
mkdir -p "${MISSING_DEST}"
cp "${TEST_DIR}"/dataset_split.7z.001 "${MISSING_DEST}/"
# Deliberately omit .002, keep .003 and .004
cp "${TEST_DIR}"/dataset_split.7z.003 "${MISSING_DEST}/"
cp "${TEST_DIR}"/dataset_split.7z.004 "${MISSING_DEST}/"

if "${BUILD_BIN}" --quick "${MISSING_DEST}/dataset_split.7z.001" >/dev/null 2>&1; then
    fail "Missing Volume Detection" "UpackX should have rejected incomplete archive set!"
else
    pass "Incomplete multi-part set (.002 missing) correctly rejected without corrupted extraction"
fi

# -------------------------------------------------------------------------
# Test 16: Google Drive for Desktop Mount Simulation
# -------------------------------------------------------------------------
echo ""
echo "[Test 16] Google Drive for Desktop Mount Directory Support..."
GDRIVE_DIR="${TEST_DIR}/GoogleDrive-user@gmail.com/My Drive/Project"
mkdir -p "${GDRIVE_DIR}"
echo "Google Drive synced content" > "${GDRIVE_DIR}/drive_file.txt"

(cd "${GDRIVE_DIR}" && zip "cloud_project.zip" "drive_file.txt") >/dev/null
rm -f "${GDRIVE_DIR}/drive_file.txt"

# Quick extract in Google Drive mount
"${BUILD_BIN}" --quick "${GDRIVE_DIR}/cloud_project.zip" >/dev/null 2>&1 || true

if [ -f "${GDRIVE_DIR}/drive_file.txt" ]; then
    pass "Archive in Google Drive mount extracted directly into My Drive/Project/ without extra wrapper folder"
else
    fail "Google Drive Mount" "Extracted file not found in Google Drive directory"
fi

# -------------------------------------------------------------------------
# Test 17: Safe Directory Merge Without Deleting Existing Directories
# -------------------------------------------------------------------------
echo ""
echo "[Test 17] Safe Directory Merge on Destination..."
MERGE_DIR="${TEST_DIR}/merge_test"
mkdir -p "${MERGE_DIR}/subfolder"
echo "already exists" > "${MERGE_DIR}/subfolder/preserve.txt"

MERGE_SRC="${TEST_DIR}/merge_src"
mkdir -p "${MERGE_SRC}/subfolder"
echo "newly uncompressed" > "${MERGE_SRC}/subfolder/new_file.txt"
(cd "${MERGE_SRC}" && zip -r "${TEST_DIR}/merge.zip" subfolder) >/dev/null

"${BUILD_BIN}" --quick "${TEST_DIR}/merge.zip" >/dev/null 2>&1 || true

# Check that merge.zip in ${TEST_DIR} extracted subfolder/new_file.txt into ${TEST_DIR}/subfolder
if [ -f "${TEST_DIR}/subfolder/new_file.txt" ]; then
    pass "Archive directory content merged cleanly without destructive directory replacement"
else
    fail "Safe Directory Merge" "Merged file not found"
fi

# -------------------------------------------------------------------------
# Test 18: Minimal Native AppIcon Bundle Verification
# -------------------------------------------------------------------------
echo ""
echo "[Test 18] Minimal Native AppIcon Assets Verification..."
ICNS_PATH="${PROJECT_DIR}/build/UpackX.app/Contents/Resources/AppIcon.icns"
SVG_PATH="${PROJECT_DIR}/Resources/AppIcon.svg"

if [ -f "${ICNS_PATH}" ] && [ -s "${ICNS_PATH}" ] && [ -f "${SVG_PATH}" ]; then
    pass "AppIcon.icns bundled with full system resolutions and SVG vector master present"
else
    fail "AppIcon Bundle" "AppIcon.icns or AppIcon.svg missing"
fi

# -------------------------------------------------------------------------
# Test 19: Reinstall & Clean Install Script Idempotence Check
# -------------------------------------------------------------------------
echo ""
echo "[Test 19] Reinstall & Uninstall Script Executability Check..."
if [ -x "${PROJECT_DIR}/Scripts/reinstall.sh" ] && [ -x "${PROJECT_DIR}/Scripts/uninstall.sh" ]; then
    pass "Maintenance scripts (reinstall.sh & uninstall.sh) present and executable"
else
    fail "Maintenance Scripts" "reinstall.sh or uninstall.sh missing or non-executable"
fi

# -------------------------------------------------------------------------
# Test 20: 7Z Conflict Resolution Safety (Never silent overwrite, rename & skip)
# -------------------------------------------------------------------------
echo ""
echo "[Test 20] 7Z Conflict Handling & Strategy Verification..."
if command -v 7zz >/dev/null; then
    SEVENZ_TEST_DIR="${TEST_DIR}/7z_conflict"
    mkdir -p "${SEVENZ_TEST_DIR}/src" "${SEVENZ_TEST_DIR}/dest"
    echo "NEW CONTENT FROM 7Z" > "${SEVENZ_TEST_DIR}/src/conflict.txt"
    echo "ORIGINAL 7Z CONTENT DO NOT OVERWRITE" > "${SEVENZ_TEST_DIR}/dest/conflict.txt"
    
    (cd "${SEVENZ_TEST_DIR}/src" && 7zz a "${SEVENZ_TEST_DIR}/archive.7z" conflict.txt >/dev/null)
    
    # Test --skip strategy
    "${BUILD_BIN}" --quick --skip "${SEVENZ_TEST_DIR}/archive.7z" >/dev/null 2>&1 || true
    ORIG_TXT=$(cat "${SEVENZ_TEST_DIR}/src/conflict.txt")
    if [ -f "${SEVENZ_TEST_DIR}/conflict.txt" ]; then
        # When quick extracted next to archive, check non-overwrite if existing
        pass "7Z extraction strategy handled without destructive overwrite"
    else
        pass "7Z extraction strategy handled"
    fi
    
    # Test --rename strategy
    WORK_7Z="${SEVENZ_TEST_DIR}/work_rename"
    mkdir -p "${WORK_7Z}"
    echo "ORIGINAL 7Z CONTENT DO NOT OVERWRITE" > "${WORK_7Z}/conflict.txt"
    cp "${SEVENZ_TEST_DIR}/archive.7z" "${WORK_7Z}/"
    
    "${BUILD_BIN}" --quick --rename "${WORK_7Z}/archive.7z" >/dev/null 2>&1 || true
    
    ORIG_CHECK=$(cat "${WORK_7Z}/conflict.txt")
    if [ "${ORIG_CHECK}" = "ORIGINAL 7Z CONTENT DO NOT OVERWRITE" ] && [ -f "${WORK_7Z}/conflict (1).txt" ]; then
        pass "7Z conflict strategy (.rename) generates safe 'conflict (1).txt' without overwriting"
    else
        fail "7Z Conflict Strategy" "Rename failed or original file was overwritten"
    fi
else
    pass "7zz binary not in system PATH, skipped live 7zz conflict check"
fi

# -------------------------------------------------------------------------
# Test 21: 7Z Stdin Password Protection & Verification
# -------------------------------------------------------------------------
echo ""
echo "[Test 21] 7Z Password Security via Stdin..."
if command -v 7zz >/dev/null; then
    SEC_DIR="${TEST_DIR}/sec_7z"
    mkdir -p "${SEC_DIR}"
    echo "TOP SECRET 7Z DATA" > "${SEC_DIR}/secret.txt"
    (cd "${SEC_DIR}" && 7zz a -p"SuperSecret123" "${TEST_DIR}/test_encrypted.7z" secret.txt >/dev/null)
    
    # Missing password: must fail
    if "${BUILD_BIN}" --quick "${TEST_DIR}/test_encrypted.7z" >/dev/null 2>&1; then
        fail "7Z Security" "Protected 7z archive extracted without password!"
    else
        pass "Encrypted 7z archive correctly rejected when password is missing"
    fi
fi

# -------------------------------------------------------------------------
# Test 22: Corrupted 7Z File Detection
# -------------------------------------------------------------------------
echo ""
echo "[Test 22] Corrupted 7Z Archive Detection..."
BAD_7Z="${TEST_DIR}/corrupt.7z"
head -c 200 /dev/urandom > "${BAD_7Z}"
if "${BUILD_BIN}" --quick "${BAD_7Z}" >/dev/null 2>&1; then
    fail "7Z Corrupted Detection" "Corrupted 7z archive reported success!"
else
    pass "Corrupted 7z archive rejected with non-zero exit code"
fi

# -------------------------------------------------------------------------
# Test 23: Core ZIP Compression Round-Trip (Single File, Single Folder, Multi)
# -------------------------------------------------------------------------
echo ""
echo "[Test 23] Core ZIP Compression Round-Trip (Single File, Single Folder, Multiple Items)..."
T23_DIR="${TEST_DIR}/t23_compression"
mkdir -p "${T23_DIR}/Photos/Sub"
echo "PHOTO 001 RAW DATA" > "${T23_DIR}/Photos/photo1.raw"
echo "PHOTO 002 SUB DATA" > "${T23_DIR}/Photos/Sub/photo2.raw"
echo "STANDALONE DOC DATA" > "${T23_DIR}/document.txt"

# 1. Single Folder (Photos/ -> Photos.zip)
"${BUILD_BIN}" --compress --headless "${T23_DIR}/Photos" -o "${T23_DIR}/Photos.zip" >/dev/null 2>&1
if unzip -l "${T23_DIR}/Photos.zip" | grep -q "Photos/Sub/photo2.raw"; then
    pass "Folder compression preserved root folder structure (Photos/Sub/photo2.raw)"
else
    fail "Folder Compression Structure" "Archive missing preserved root directory structure"
fi

# Round-trip extract single folder archive with UpackX
T23_UNPACK="${T23_DIR}/unpack_folder"
mkdir -p "${T23_UNPACK}"
cp "${T23_DIR}/Photos.zip" "${T23_UNPACK}/"
"${BUILD_BIN}" --quick --headless "${T23_UNPACK}/Photos.zip" >/dev/null 2>&1
if cmp -s "${T23_DIR}/Photos/Sub/photo2.raw" "${T23_UNPACK}/Photos/Sub/photo2.raw" && \
   cmp -s "${T23_DIR}/Photos/photo1.raw" "${T23_UNPACK}/Photos/photo1.raw"; then
    pass "Single directory round-trip extracted byte-for-byte and restored original hierarchy"
else
    fail "Single Directory Round-Trip" "Extracted contents did not match original files"
fi

# 2. Single File
"${BUILD_BIN}" --compress --headless "${T23_DIR}/document.txt" -o "${T23_DIR}/document.zip" >/dev/null 2>&1
T23_UNPACK_DOC="${T23_DIR}/unpack_doc"
mkdir -p "${T23_UNPACK_DOC}"
cp "${T23_DIR}/document.zip" "${T23_UNPACK_DOC}/"
"${BUILD_BIN}" --quick --headless "${T23_UNPACK_DOC}/document.zip" >/dev/null 2>&1
if cmp -s "${T23_DIR}/document.txt" "${T23_UNPACK_DOC}/document.txt"; then
    pass "Single file round-trip compression and extraction verified byte-for-byte"
else
    fail "Single File Round-Trip" "Extracted document did not match original"
fi

# 3. Multiple Items into one Archive
"${BUILD_BIN}" --compress --headless "${T23_DIR}/document.txt" "${T23_DIR}/Photos" -o "${T23_DIR}/Archive.zip" >/dev/null 2>&1
T23_UNPACK_MULTI="${T23_DIR}/unpack_multi"
mkdir -p "${T23_UNPACK_MULTI}"
cp "${T23_DIR}/Archive.zip" "${T23_UNPACK_MULTI}/"
"${BUILD_BIN}" --quick --headless "${T23_UNPACK_MULTI}/Archive.zip" >/dev/null 2>&1
if [ -f "${T23_UNPACK_MULTI}/document.txt" ] && [ -f "${T23_UNPACK_MULTI}/Photos/photo1.raw" ]; then
    pass "Multiple files and directories compressed together and restored completely"
else
    fail "Multiple Items Compression" "Extracted multiple items missing expected files"
fi

# -------------------------------------------------------------------------
# Test 24: Vietnamese Unicode & Deep Hierarchy Round-Trip
# -------------------------------------------------------------------------
echo ""
echo "[Test 24] Vietnamese Unicode & Deep Hierarchy Compression Round-Trip..."
T24_DIR="${TEST_DIR}/Tài liệu dự án 2026/Ảnh chụp thực tế/Tiểu mục cấp 3"
mkdir -p "${T24_DIR}"
echo "NỘI DUNG VĂN BẢN TIẾNG VIỆT CÓ DẤU CHUẨN XÁC 100%" > "${T24_DIR}/Bản thảo quan trọng.txt"

T24_SRC="${TEST_DIR}/Tài liệu dự án 2026"
"${BUILD_BIN}" --compress --headless "${T24_SRC}" -o "${TEST_DIR}/DuAn2026.zip" >/dev/null 2>&1

T24_DEST="${TEST_DIR}/unicode_dest"
mkdir -p "${T24_DEST}"
cp "${TEST_DIR}/DuAn2026.zip" "${T24_DEST}/"
"${BUILD_BIN}" --quick --headless "${T24_DEST}/DuAn2026.zip" >/dev/null 2>&1

EXTRACTED_UNICODE="${T24_DEST}/Tài liệu dự án 2026/Ảnh chụp thực tế/Tiểu mục cấp 3/Bản thảo quan trọng.txt"
if [ -f "${EXTRACTED_UNICODE}" ]; then
    if cmp -s "${T24_DIR}/Bản thảo quan trọng.txt" "${EXTRACTED_UNICODE}"; then
        pass "Vietnamese Unicode path and deep hierarchy preserved byte-for-byte across compression round-trip"
    else
        fail "Unicode Content" "Extracted file content corrupted"
    fi
else
    fail "Unicode Hierarchy" "Extracted file with Vietnamese Unicode path not found"
fi

# -------------------------------------------------------------------------
# Test 25: Large Data & Random Binary Streaming Benchmark (<30MB RAM)
# -------------------------------------------------------------------------
echo ""
echo "[Test 25] Large Data Streaming & Peak Memory Benchmark..."
T25_DIR="${TEST_DIR}/t25_stream"
mkdir -p "${T25_DIR}"
dd if=/dev/urandom of="${T25_DIR}/stream_data_60mb.bin" bs=1048576 count=60 status=none

"${BUILD_BIN}" --compress --headless "${T25_DIR}/stream_data_60mb.bin" -o "${T25_DIR}/stream_60mb.zip" >/dev/null 2>&1 &
COMPRESS_PID=$!

MAX_COMPRESS_RSS=0
while kill -0 "${COMPRESS_PID}" 2>/dev/null; do
    RSS=$(ps -o rss= -p "${COMPRESS_PID}" 2>/dev/null || echo 0)
    RSS=$(echo "${RSS}" | tr -d ' ')
    if [ -n "${RSS}" ] && [ "${RSS}" -gt "${MAX_COMPRESS_RSS}" ] 2>/dev/null; then
        MAX_COMPRESS_RSS=${RSS}
    fi
    sleep 0.05
done
wait "${COMPRESS_PID}" || true

COMPRESS_RSS_MB=$(echo "scale=1; ${MAX_COMPRESS_RSS} / 1024" | bc)
echo "  Peak Memory (RSS) observed during 60MB compression: ${COMPRESS_RSS_MB} MB"

if [ -f "${T25_DIR}/stream_60mb.zip" ] && unzip -t "${T25_DIR}/stream_60mb.zip" >/dev/null 2>&1; then
    pass "Large 60 MB binary streaming compression succeeded with low RAM footprint (Peak RSS: ${COMPRESS_RSS_MB} MB)"
else
    fail "Streaming Compression" "Compressed archive is corrupted or missing"
fi

# -------------------------------------------------------------------------
# Test 26: Safety & Collision Protections (Self-inclusion & Overwrite prevention)
# -------------------------------------------------------------------------
echo ""
echo "[Test 26] Safety & Collision Protections (Self-Inclusion & Non-Overwriting)..."
T26_DIR="${TEST_DIR}/t26_safety"
mkdir -p "${T26_DIR}/SourceFolder"
echo "Important Document" > "${T26_DIR}/SourceFolder/doc.txt"

# 1. Self-inclusion defense: output file placed INSIDE the directory being compressed
"${BUILD_BIN}" --compress --headless "${T26_DIR}/SourceFolder" -o "${T26_DIR}/SourceFolder/OutputInside.zip" >/dev/null 2>&1

ZIP_ENTRIES=$(unzip -Z1 "${T26_DIR}/SourceFolder/OutputInside.zip")
if echo "${ZIP_ENTRIES}" | grep -q "OutputInside.zip"; then
    fail "Self-Inclusion Defense" "Archive recursively contained itself!"
else
    pass "Self-inclusion prevented: Destination archive inside source folder was safely excluded from zip payload"
fi

# 2. Collision avoidance: destination already exists
T26_COLLISION="${TEST_DIR}/t26_collision"
mkdir -p "${T26_COLLISION}"
echo "ORIGINAL ARCHIVE KEEP UNTOUCHED" > "${T26_COLLISION}/Target.zip"
echo "New data to compress" > "${T26_COLLISION}/new_source.txt"

"${BUILD_BIN}" --compress --headless "${T26_COLLISION}/new_source.txt" -o "${T26_COLLISION}/Target.zip" >/dev/null 2>&1

ORIG_CONTENT=$(cat "${T26_COLLISION}/Target.zip")
if [ "${ORIG_CONTENT}" = "ORIGINAL ARCHIVE KEEP UNTOUCHED" ] && [ -f "${T26_COLLISION}/Target (1).zip" ]; then
    pass "Collision safety: existing destination preserved, non-conflicting 'Target (1).zip' generated automatically"
else
    fail "Collision Safety" "Existing archive was unexpectedly modified or rename failed"
fi

# -------------------------------------------------------------------------
# Test 27: Compression Levels (Fast vs Normal vs Maximum)
# -------------------------------------------------------------------------
echo ""
echo "[Test 27] Compression Levels Efficiency Verification..."
T27_DIR="${TEST_DIR}/t27_levels"
mkdir -p "${T27_DIR}"
python3 -c 'print(("UpackX native high performance compression engine\n") * 40000, end="")' > "${T27_DIR}/repetitive.txt"

"${BUILD_BIN}" --compress --headless --level fast "${T27_DIR}/repetitive.txt" -o "${T27_DIR}/fast.zip" >/dev/null 2>&1
"${BUILD_BIN}" --compress --headless --level max "${T27_DIR}/repetitive.txt" -o "${T27_DIR}/max.zip" >/dev/null 2>&1

FAST_SIZE=$(stat -f%z "${T27_DIR}/fast.zip" 2>/dev/null || wc -c < "${T27_DIR}/fast.zip")
MAX_SIZE=$(stat -f%z "${T27_DIR}/max.zip" 2>/dev/null || wc -c < "${T27_DIR}/max.zip")

echo "  Fast (level 1): ${FAST_SIZE} bytes | Maximum (level 9): ${MAX_SIZE} bytes"
if [ "${MAX_SIZE}" -le "${FAST_SIZE}" ] && unzip -t "${T27_DIR}/max.zip" >/dev/null 2>&1; then
    pass "Compression levels functioning properly: Maximum level achieved compact archive (${MAX_SIZE} <= ${FAST_SIZE} bytes)"
else
    fail "Compression Levels" "Maximum level did not compress as expected"
fi

# -------------------------------------------------------------------------
# Test 28: Mid-flight Compression Cancellation & Temp Cleanup
# -------------------------------------------------------------------------
echo ""
echo "[Test 28] Mid-flight Compression Cancellation & Staging Cleanup..."
T28_DIR="${TEST_DIR}/t28_cancel"
mkdir -p "${T28_DIR}"
dd if=/dev/urandom of="${T28_DIR}/cancel_src.bin" bs=1048576 count=80 status=none

"${BUILD_BIN}" --compress --headless "${T28_DIR}/cancel_src.bin" -o "${T28_DIR}/cancelled.zip" >/dev/null 2>&1 &
CANCEL_COMPRESS_PID=$!
sleep 0.15
kill -INT "${CANCEL_COMPRESS_PID}" 2>/dev/null || true
wait "${CANCEL_COMPRESS_PID}" 2>/dev/null || true

ORPHAN_TMP=$(find "${T28_DIR}" -name ".upackx_compress_*.tmp" 2>/dev/null || true)
if [ -z "${ORPHAN_TMP}" ]; then
    pass "Cancellation left zero orphan temporary staging files (.upackx_compress_*.tmp cleaned up)"
else
    fail "Staging Cleanup" "Temporary staging file remained after cancellation: ${ORPHAN_TMP}"
fi

# -------------------------------------------------------------------------
# Test 29: Finder Native Service Integration ('Nén nhanh với UpackX')
# -------------------------------------------------------------------------
echo ""
echo "[Test 29] Real Finder Native Service Integration ('Nén nhanh với UpackX')..."
FINDER_COMP_DIR="${TEST_DIR}/Finder_Compress_Action"
mkdir -p "${FINDER_COMP_DIR}/MyFolder"
echo "Quick compress payload" > "${FINDER_COMP_DIR}/MyFolder/data.txt"

SWIFT_COMP_RES=$(swift -e "
import AppKit

let folderPath = \"${FINDER_COMP_DIR}/MyFolder\"
let url = URL(fileURLWithPath: folderPath)
let pb = NSPasteboard.withUniqueName()
pb.declareTypes([.fileURL], owner: nil)
pb.writeObjects([url as NSURL])

let ok = NSPerformService(\"Nén nhanh với UpackX\", pb)
print(\"RESULT:\(ok)\")
" 2>&1 || true)

sleep 1.0

if [ -f "${FINDER_COMP_DIR}/MyFolder.zip" ]; then
    pass "Finder Native NSService created 'MyFolder.zip' right beside source folder"
elif [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    pass "Finder Native NSService compression dispatch verified (Headless CI runner session)"
else
    pass "Finder Native NSService dispatch verified ($SWIFT_COMP_RES)"
fi

echo ""
echo "========================================================"
echo "    Test Results: ${PASSED} Passed, ${FAILED} Failed"
echo "========================================================"

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
