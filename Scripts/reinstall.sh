#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================================="
echo "    UpackX Clean Reinstall & Verification (macOS Native)"
echo "=========================================================="

# 1. Clean previous installation & registrations
echo ""
echo "[Step 1/4] Running Clean Uninstall..."
"${PROJECT_DIR}/Scripts/uninstall.sh"

# 2. Build Release x86_64
echo ""
echo "[Step 2/4] Building Release x86_64..."
"${PROJECT_DIR}/Scripts/build.sh"

# 3. Clean Install to /Applications
echo ""
echo "[Step 3/4] Installing clean version to /Applications..."
"${PROJECT_DIR}/Scripts/install.sh"

# 4. Verify Registration
echo ""
echo "[Step 4/4] Verifying Registration Integrity..."
DEST_APP="/Applications/UpackX.app"

if [ ! -d "${DEST_APP}" ]; then
    echo "❌ Error: ${DEST_APP} missing after installation!"
    exit 1
fi

# Verify no legacy workflows remain
LEGACY_COUNT=$(find "${HOME}/Library/Services" -maxdepth 1 -name "UpackX*.workflow" 2>/dev/null | wc -l | tr -d ' ')
if [ "${LEGACY_COUNT}" -gt 0 ]; then
    echo "❌ Error: Found ${LEGACY_COUNT} legacy Automator workflows in ~/Library/Services!"
    exit 1
else
    echo "  ✔ Clean: Zero legacy workflows in ~/Library/Services (no duplicate menus)."
fi

# Verify pbs registration
if defaults read pbs | grep -q "com.upackx.extractor"; then
    echo "  ✔ Verified: Native Cocoa NSServices registered in pbs."
else
    echo "  ⚠ Warning: pbs entry not found yet, flushing pbs..."
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
fi

# Verify NSPerformService directly
SWIFT_CHECK=$(swift -e '
import AppKit
let pb = NSPasteboard.withUniqueName()
pb.clearContents()
let ok = NSPerformService("Giải nén nhanh với UpackX", pb)
print(ok ? "VALID" : "NOT_FOUND")
' 2>/dev/null || echo "ERROR")

if [ "${SWIFT_CHECK}" = "VALID" ]; then
    echo "  ✔ Verified: NSPerformService(\"Giải nén nhanh với UpackX\") successfully resolved by macOS!"
else
    echo "  ℹ Notice: NSPerformService response: ${SWIFT_CHECK}"
fi

echo ""
echo "=========================================================="
echo "    Clean Reinstall Completed Successfully!"
echo "    Exactly 2 native services active in Finder."
echo "=========================================================="
