#!/bin/bash
set -euo pipefail

echo "=== Gỡ cài đặt UpackX (UpackX Clean Uninstaller) ==="

DEST_APP="/Applications/UpackX.app"
SERVICES_DIR="${HOME}/Library/Services"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

# 1. Stop any running UpackX instances
echo "Dừng các tiến trình UpackX..."
killall UpackX 2>/dev/null || true

# 2. Unregister LaunchServices
if [ -d "${DEST_APP}" ]; then
    echo "Hủy đăng ký LaunchServices cho ${DEST_APP}..."
    "${LSREGISTER}" -u "${DEST_APP}" 2>/dev/null || true
    echo "Xóa ${DEST_APP}..."
    rm -rf "${DEST_APP}"
fi

# Also unregister build folder if present
BUILD_APP="$(pwd)/build/UpackX.app"
if [ -d "${BUILD_APP}" ]; then
    "${LSREGISTER}" -u "${BUILD_APP}" 2>/dev/null || true
fi

# 3. Remove CLI symlinks
if [ -L "/usr/local/bin/upackx" ]; then
    echo "Xóa symlink /usr/local/bin/upackx..."
    rm -f "/usr/local/bin/upackx"
fi

if [ -L "${HOME}/.local/bin/upackx" ]; then
    echo "Xóa symlink ${HOME}/.local/bin/upackx..."
    rm -f "${HOME}/.local/bin/upackx"
fi

# 4. Remove all legacy Automator workflows (v1.0 & v1.1)
echo "Dọn sạch các workflow UpackX trong ~/Library/Services..."
rm -rf "${SERVICES_DIR}/UpackX - Giải nén nhanh.workflow"
rm -rf "${SERVICES_DIR}/UpackX - Giải nén….workflow"
rm -rf "${SERVICES_DIR}"/UpackX*.workflow

# 5. Clean pbs preferences for UpackX
echo "Dọn dẹp mục đăng ký Services trong pbs..."
python3 -c '
import subprocess
keys = [
    "com.upackx.extractor - Giải nén nhanh với UpackX - quickExtractService",
    "com.upackx.extractor - Giải nén nhanh với UpackX - quickExtractService",
    "com.upackx.extractor - Giải nén… với UpackX - extractToService",
    "com.upackx.extractor - Giải nén… với UpackX - extractToService"
]
for k in keys:
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Delete :NSServicesStatus:\"{k}\"", f"{subprocess.os.path.expanduser(\"~\")}/Library/Preferences/pbs.plist"], capture_output=True)
' 2>/dev/null || true

# 6. Flush Pasteboard Server & LaunchServices
if [ -x "${PBS}" ]; then
    "${PBS}" -flush 2>/dev/null || true
    "${PBS}" -update 2>/dev/null || true
fi

# Restart Finder to clear cache
killall Finder 2>/dev/null || true

echo "=== Đã gỡ cài đặt UpackX hoàn tất và sạch sẽ! ==="
