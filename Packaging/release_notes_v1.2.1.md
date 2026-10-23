## UpackX v1.2.1 — Release Hardening (macOS Intel x86_64)

**UpackX v1.2.1** is a patch release focusing on CI/CD pipeline stability, credential security, and robust archive conflict resolution for Intel Macs running macOS 14.0 Sonoma or newer.

---

### Key Improvements in v1.2.1

1. **GitHub Actions CI/CD Modernization:**
   - Migrated active workflows (`ci.yml` and `release.yml`) from deprecated `macos-13` runner to active Intel runner `macos-15-intel`.
   - Verified automated build, test suite execution, artifact packaging, and pre-flight checks in GitHub Actions.

2. **Security Hardening for 7Z/RAR Extractions:**
   - Eliminated password exposure in process command-line arguments (`ps aux`) and logs.
   - Archive passwords for `7zz` are now securely piped via standard input (`stdin`).

3. **True Interactive Conflict Resolution:**
   - Fixed conflict handling in `SevenZipExtractor.swift`: the `.ask` conflict resolution policy now prompts via interactive delegate rather than silently defaulting to auto-rename.
   - Staged destination extraction prevents accidental overwriting before user confirmation.

4. **Path & Symlink Normalization:**
   - Canonicalized paths with `resolvingSymlinksInPath()` to resolve `/tmp` vs `/private/tmp` prefix mismatches on macOS.

5. **Expanded Test Suite (28 Verification Tests):**
   - Added Test 20: 7Z Conflict Handling & Strategy Verification.
   - Added Test 21: 7Z Stdin Password Security Verification.
   - Added Test 22: Corrupted 7Z Archive Detection & Exit Code Verification.

---

### Verification & Checksums

| Package | Format | Description |
|---|---|---|
| **`UpackX-v1.2.1-macOS-Intel.dmg`** | Apple Disk Image | Recommended drag-and-drop installer into `/Applications`. |
| **`UpackX-v1.2.1-macOS-Intel.pkg`** | Apple Installer | Guided installer package for macOS. |
| **`UpackX-v1.2.1-macOS-Intel.zip`** | Portable ZIP | Standalone `.app` bundle preserving metadata via `ditto`. |
| **`SHA256SUMS.txt`** | Text | SHA-256 verification hashes for all distribution artifacts. |

---

### Installation & First Launch

1. Download **`UpackX-v1.2.1-macOS-Intel.dmg`** or **`UpackX-v1.2.1-macOS-Intel.pkg`**.
2. Install UpackX into your `/Applications` directory.
3. **First Launch (Gatekeeper):**
   - Right-click on `UpackX.app` in `/Applications` and select **Open**, then click **Open** in the prompt.
4. Launching the application registers and activates native Finder Quick Actions.
