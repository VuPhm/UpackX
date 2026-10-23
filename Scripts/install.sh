#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"
DEST_APP="/Applications/UpackX.app"

if [ ! -d "${BUILD_APP}" ]; then
    echo "App not built yet. Running build first..."
    "${PROJECT_DIR}/Scripts/build.sh"
fi

echo "=== Installing UpackX to /Applications ==="
rm -rf "${DEST_APP}"
cp -R "${BUILD_APP}" "${DEST_APP}"

# Symlink CLI tool to /usr/local/bin if writable, else ~/.local/bin
if [ -w "/usr/local/bin" ]; then
    echo "Creating symlink /usr/local/bin/upackx..."
    ln -sf "${DEST_APP}/Contents/MacOS/UpackX" "/usr/local/bin/upackx"
else
    mkdir -p "${HOME}/.local/bin"
    echo "Creating symlink ${HOME}/.local/bin/upackx..."
    ln -sf "${DEST_APP}/Contents/MacOS/UpackX" "${HOME}/.local/bin/upackx"
fi

echo "=== Installing Finder Quick Actions ==="
"${DEST_APP}/Contents/MacOS/UpackX" --install-services

echo "=== Installation Finished Successfully! ==="
echo "UpackX.app is now in /Applications"
echo "Finder Quick Actions 'Giải nén nhanh với UpackX' and 'Giải nén… với UpackX' are active in ~/Library/Services."
