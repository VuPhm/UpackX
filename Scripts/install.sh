#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_APP="${PROJECT_DIR}/build/UpackX.app"
DEST_APP="/Applications/UpackX.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

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

echo "=== Cleaning Stale LaunchServices Registrations & Registering /Applications/UpackX.app ==="
if [ -x "${LSREGISTER}" ]; then
    # Unregister build directory copy so Finder Services never route to build/
    if [ -d "${BUILD_APP}" ]; then
        "${LSREGISTER}" -u "${BUILD_APP}" 2>/dev/null || true
    fi
    # Unregister any other indexed copies outside /Applications
    while IFS= read -r bundle_path; do
        if [ -n "${bundle_path}" ] && [ "${bundle_path}" != "${DEST_APP}" ]; then
            "${LSREGISTER}" -u "${bundle_path}" 2>/dev/null || true
        fi
    done < <(mdfind "kMDItemCFBundleIdentifier == 'com.upackx.extractor'" 2>/dev/null || true)

    "${LSREGISTER}" -f "${DEST_APP}"
fi
touch "${DEST_APP}"

echo "=== Activating Native Finder NSServices ==="
"${DEST_APP}/Contents/MacOS/UpackX" --install-services

if [ -x "${PBS}" ]; then
    "${PBS}" -flush 2>/dev/null || true
    "${PBS}" -update 2>/dev/null || true
fi

echo "=== Installation Finished Successfully! ==="
echo "UpackX.app is now in /Applications with custom format-colored document icons."
echo "Native Finder Services (2 Nén, 2 Giải nén) are ready for use."
