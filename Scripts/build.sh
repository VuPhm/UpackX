#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/UpackX.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BIN_DIR="${RESOURCES_DIR}/bin"

echo "=== Building UpackX for macOS Intel (x86_64) ==="

# Clean build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${BIN_DIR}"

# Find all Swift source files
SWIFT_FILES=$(find "${PROJECT_DIR}/Sources" -name "*.swift")

echo "Compiling Swift sources..."
swiftc -O \
    -target x86_64-apple-macos14.0 \
    -larchive \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -framework UserNotifications \
    ${SWIFT_FILES} \
    -o "${MACOS_DIR}/UpackX"

# Ensure AppIcon.icns is up to date and copied
if [ ! -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    echo "Generating AppIcon.icns..."
    "${PROJECT_DIR}/Scripts/generate_icons.swift"
fi
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

# Copy Info.plist and PkgInfo
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Bundle 7zz helper if available for standalone distribution
if [ -f "/usr/local/bin/7zz" ]; then
    echo "Bundling standalone 7zz binary into app resources..."
    cp "/usr/local/bin/7zz" "${BIN_DIR}/7zz"
    chmod +x "${BIN_DIR}/7zz"
elif [ -f "/usr/local/Cellar/sevenzip/26.01/bin/7zz" ]; then
    echo "Bundling standalone 7zz binary into app resources..."
    cp "/usr/local/Cellar/sevenzip/26.01/bin/7zz" "${BIN_DIR}/7zz"
    chmod +x "${BIN_DIR}/7zz"
fi

# Ad-hoc code sign the application bundle
echo "Ad-hoc code signing UpackX.app..."
codesign --force --deep --sign - "${APP_DIR}"

# Create CLI symlink in build dir
ln -sf "UpackX.app/Contents/MacOS/UpackX" "${BUILD_DIR}/upackx"

echo "=== Build Complete: ${APP_DIR} ==="
ls -lh "${MACOS_DIR}/UpackX"
du -sh "${APP_DIR}"
