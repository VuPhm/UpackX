## UpackX v1.3.0 — Compression MVP (macOS Intel x86_64)

**UpackX v1.3.0** introduces the **Native Compression Engine**, transforming UpackX into a complete, dual-capability archive extractor and compressor built specifically for Intel Macs running macOS 14.0 Sonoma or newer.

---

### Highlights in v1.3.0

1. **Native Streaming ZIP Compression Engine (`ZipCompressor`):**
   - High-performance compression powered natively by `libarchive`.
   - Streaming architecture with 64 KB chunk buffers maintaining constant low memory footprint (**< 13 MB RSS** observed during 60 MB+ compression).
   - Preserves exact folder hierarchy: compressing folder `Photos/` creates `Photos.zip` containing `Photos/...` root structure. Extracting it with UpackX restores original layout with zero unnecessary folder nesting.
   - Supports individual files, single directories, and multiple items into unified archives.
   - Non-destructive: source files and folders are strictly untouched.
   - Configurable compression levels: **Fast** (level 1), **Normal** (level 6), and **Maximum** (level 9).

2. **4 Dedicated Native Finder Quick Actions (Zero Duplicate Workflows):**
   - **Giải nén nhanh với UpackX:** Direct extraction in place.
   - **Giải nén… với UpackX:** Customizable extraction destination and conflict strategies.
   - **Nén nhanh với UpackX:** One-click in-place ZIP creation with automatic non-conflicting renaming on collision (never overwrites silently).
   - **Nén… với UpackX:** AppKit modal window (`CompressToWindowController`) to choose custom archive name, destination directory, compression level, and source size display.

3. **Safety & Collision Protections:**
   - **Self-Inclusion Defense:** Output archives and temporary staging files created inside a source folder are safely excluded from the zip payload.
   - **Collision Prevention:** Existing files are never silently overwritten; non-conflicting names (e.g. `Archive (1).zip`) are automatically generated.
   - **POSIX realpath Canonicalization:** Robust path validation preventing `/tmp` vs `/private/tmp` symlink prefix mismatches.
   - **Atomic Staging:** Compresses to temporary hidden file `.upackx_compress_<uuid>.tmp`; cancellation cleanly cleans up all staging data.

4. **Dual Functionality MainWindow:**
   - Enhanced `MainWindowController` accepts both archives (for extraction) and files/folders (for compression) via drag-and-drop.
   - Clean, minimal AppKit interface preserving the product identity and minimal application icon.

5. **Extensive Verification Suite (39 Tests):**
   - 39 automated tests covering extraction, compression round-trips, Vietnamese Unicode characters, deep nested paths, large data streaming, self-inclusion defense, collision safety, compression levels, and Finder NSService integration.

6. **Advanced Compression Roadmap (Round C):**
   - Detailed architectural design in `ROADMAP.md` covering 7Z compression, AES-256 header encryption, multi-volume splitting, benchmark profiles, and Ultra compression memory guardrails.

---

### Verification & Checksums

| Package | Format | Description |
|---|---|---|
| **`UpackX-v1.3.0-macOS-Intel.dmg`** | Apple Disk Image | Recommended drag-and-drop installer into `/Applications`. |
| **`UpackX-v1.3.0-macOS-Intel.pkg`** | Apple Installer | Guided installer package for macOS. |
| **`UpackX-v1.3.0-macOS-Intel.zip`** | Portable ZIP | Standalone `.app` bundle preserving metadata via `ditto`. |
| **`SHA256SUMS.txt`** | Text | SHA-256 verification hashes for all distribution artifacts. |

#### SHA-256 Checksums
```text
8c21995060b4b37bcb8d505bcf451d85a76189fed1050e9aae1c449262611363  UpackX-v1.3.0-macOS-Intel.dmg
09011caa47007e5ea83a0b5663bf4c150a82df814729739efcdbaa571c7c0c25  UpackX-v1.3.0-macOS-Intel.pkg
1608ce64293cc3fea5e40338a7f7502890ca3a043a4d9d846ba8f7a12291f416  UpackX-v1.3.0-macOS-Intel.zip
1bbbec3edf50023e54ed046f004d8fe1a388e78f8929307a7584e77ebf0f2aec  SHA256SUMS.txt
```

---

### Installation & First Launch

1. Download **`UpackX-v1.3.0-macOS-Intel.dmg`** or **`UpackX-v1.3.0-macOS-Intel.pkg`**.
2. Install UpackX into your `/Applications` directory.
3. **First Launch (Gatekeeper):**
   - Right-click on `UpackX.app` in `/Applications` and select **Open**, then click **Open** in the prompt.
4. Launching the application registers and activates all 4 native Finder Quick Actions in your user session.
