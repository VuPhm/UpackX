#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/UpackX.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
BIN_DIR="${RESOURCES_DIR}/bin"
CACHE_DIR="${PROJECT_DIR}/.cache/7zz"

TARGET_ARCH="${ARCH:-universal}" # "universal", "x86_64", or "arm64"
VERSION=$(defaults read "${PROJECT_DIR}/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.4.0")

echo "=========================================================="
echo "    Building UpackX v${VERSION} for macOS 14.0+"
echo "    Architecture: ${TARGET_ARCH}"
echo "=========================================================="

# Clean build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${BIN_DIR}" "${CACHE_DIR}"

# 1. Prepare Standalone Universal 2 7zz Helper
prepare_7zz() {
    local target_7zz="${CACHE_DIR}/7zz_universal"
    local x64_sha="3af68b124052da7fc2a246c96b0bea6a68bfee389baa788f4cead1a133445586"
    local arm64_sha="b6f17920b4240940461dac8ef4009891881ac44d2a5ead625ede2ec8472185dd"

    # Check if cached universal 7zz already exists and is valid
    if [ -f "${target_7zz}" ] && lipo -info "${target_7zz}" 2>/dev/null | grep -q "x86_64" && lipo -info "${target_7zz}" 2>/dev/null | grep -q "arm64"; then
        echo "Using cached Universal 2 7zz helper..."
        cp "${target_7zz}" "${BIN_DIR}/7zz"
        chmod +x "${BIN_DIR}/7zz"
        return 0
    fi

    echo "Preparing standalone Universal 2 7zz helper..."
    (
        cd "${CACHE_DIR}"
        # Download official standalone 7-zip binaries if needed
        if [ ! -f "7z2606-mac-x64.tar.xz" ]; then
            echo "  Downloading official 7-Zip (x86_64)..."
            curl -sSL -o "7z2606-mac-x64.tar.xz" "https://github.com/ip7z/7zip/releases/download/26.06/7z2606-mac-x64.tar.xz"
        fi
        if [ ! -f "7z2606-mac.tar.xz" ]; then
            echo "  Downloading official 7-Zip (arm64)..."
            curl -sSL -o "7z2606-mac.tar.xz" "https://github.com/ip7z/7zip/releases/download/26.06/7z2606-mac.tar.xz"
        fi

        # Verify SHA-256 digests
        echo "${x64_sha}  7z2606-mac-x64.tar.xz" | shasum -a 256 -c - >/dev/null
        echo "${arm64_sha}  7z2606-mac.tar.xz" | shasum -a 256 -c - >/dev/null

        # Extract binaries
        mkdir -p x64 arm64
        tar -xf "7z2606-mac-x64.tar.xz" -C x64 7zz
        tar -xf "7z2606-mac.tar.xz" -C arm64 7zz

        # Create Universal 2 binary
        lipo -create x64/7zz arm64/7zz -o "${target_7zz}"
        chmod +x "${target_7zz}"
    ) || {
        echo "Warning: Unable to download or create Universal 2 7zz helper."
        # Fallback to local 7zz if available
        for p in "/opt/homebrew/bin/7zz" "/usr/local/bin/7zz" "$(command -v 7zz 2>/dev/null || true)"; do
            if [ -n "$p" ] && [ -f "$p" ]; then
                echo "Falling back to local 7zz binary: $p"
                cp "$p" "${BIN_DIR}/7zz"
                chmod +x "${BIN_DIR}/7zz"
                return 0
            fi
        done
        echo "Error: No 7zz helper available."
        exit 1
    }

    cp "${target_7zz}" "${BIN_DIR}/7zz"
    chmod +x "${BIN_DIR}/7zz"
}

prepare_7zz
echo "✔ Standalone 7zz helper prepared: $(lipo -info "${BIN_DIR}/7zz" | tr '\n' ' ')"

# 2. Compile Swift Sources
echo ""
echo "Compiling Swift sources for target architecture: ${TARGET_ARCH}..."
SWIFT_FILES=()
while IFS= read -r -d '' file; do
    SWIFT_FILES+=("$file")
done < <(find "${PROJECT_DIR}/Sources" -name "*.swift" -print0)

FRAMEWORKS=(
    -larchive
    -framework AppKit
    -framework UniformTypeIdentifiers
    -framework UserNotifications
)

if [ "${TARGET_ARCH}" = "universal" ]; then
    echo "  [1/2] Compiling slice: x86_64 (macOS 14.0+)..."
    swiftc -O \
        -target x86_64-apple-macos14.0 \
        "${FRAMEWORKS[@]}" \
        "${SWIFT_FILES[@]}" \
        -o "${MACOS_DIR}/UpackX_x86_64"

    echo "  [2/2] Compiling slice: arm64 (macOS 14.0+)..."
    swiftc -O \
        -target arm64-apple-macos14.0 \
        "${FRAMEWORKS[@]}" \
        "${SWIFT_FILES[@]}" \
        -o "${MACOS_DIR}/UpackX_arm64"

    echo "  Merging slices into Universal 2 binary..."
    lipo -create "${MACOS_DIR}/UpackX_x86_64" "${MACOS_DIR}/UpackX_arm64" -o "${MACOS_DIR}/UpackX"
    rm -f "${MACOS_DIR}/UpackX_x86_64" "${MACOS_DIR}/UpackX_arm64"
elif [ "${TARGET_ARCH}" = "arm64" ]; then
    echo "  Compiling single slice: arm64..."
    swiftc -O \
        -target arm64-apple-macos14.0 \
        "${FRAMEWORKS[@]}" \
        "${SWIFT_FILES[@]}" \
        -o "${MACOS_DIR}/UpackX"
else
    echo "  Compiling single slice: x86_64..."
    swiftc -O \
        -target x86_64-apple-macos14.0 \
        "${FRAMEWORKS[@]}" \
        "${SWIFT_FILES[@]}" \
        -o "${MACOS_DIR}/UpackX"
fi

# 3. Copy Assets & Metadata
echo ""
echo "Copying icons and application metadata..."

# AppIcon.icns
if [ ! -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    echo "Generating AppIcon.icns..."
    "${PROJECT_DIR}/Scripts/generate_icons.swift"
fi
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

# Document-*.icns
if [ ! -f "${PROJECT_DIR}/Resources/Document-ZIP.icns" ]; then
    echo "Generating Document-*.icns icons..."
    "${PROJECT_DIR}/Scripts/generate_document_icons.swift"
fi
cp "${PROJECT_DIR}/Resources"/Document-*.icns "${RESOURCES_DIR}/"

# Info.plist and PkgInfo
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
echo "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# 4. Ad-Hoc Code Signing
echo ""
echo "Ad-hoc code signing nested helper and application bundle..."
# Sign nested helper first
codesign --force --sign - "${BIN_DIR}/7zz"
# Sign application bundle
codesign --force --deep --sign - "${APP_DIR}"

# Strict verification of code signature
echo "Verifying code signature integrity..."
codesign --verify --deep --strict "${APP_DIR}"
echo "✔ Code signature verified (Ad-hoc signature valid on disk)"

# 5. Create CLI symlink in build dir
ln -sf "UpackX.app/Contents/MacOS/UpackX" "${BUILD_DIR}/upackx"

echo ""
echo "=========================================================="
echo "    Build Complete: ${APP_DIR}"
echo "=========================================================="
lipo -info "${MACOS_DIR}/UpackX"
lipo -info "${BIN_DIR}/7zz"
ls -lh "${MACOS_DIR}/UpackX"
du -sh "${APP_DIR}"
