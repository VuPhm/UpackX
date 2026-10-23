## UpackX v1.3.1 — Data Integrity & Release Hardening (macOS Intel x86_64)

**UpackX v1.3.1** is a critical security and data integrity patch for UpackX, focusing on bulletproof I/O error handling, strict compression verification, atomic commit with safe rollback, and full release checksum alignment.

---

### Highlights in v1.3.1

1. **Strict Compression Data Integrity (`ZipCompressor`):**
   - **Zero Silent File Omission:** Failure during `archive_entry_new`, `archive_write_header`, or `open()` immediately aborts the operation and reports an explicit failure. Never reports success on partial archives.
   - **POSIX `read()` & `EINTR` Loop:** Explicitly distinguishes EOF (`0`) from read errors (`-1`) and transparently handles interrupted system calls (`EINTR`).
   - **Entry Byte-Count Verification:** Enforces that actual written bytes match declared file sizes. Detects if a source file was truncated or modified during compression.
   - **Libarchive API Verification:** Checks all return codes for `archive_write_set_options`, `archive_write_close`, and `archive_write_free`. If archive closing fails, the broken file is purged and never committed.
   - **Safe Directory Traversal:** Stops immediately upon encountering permission denied or unreadable subdirectories, returning error diagnostics rather than omitting child items.
   - **Symlink & Special File Security:** Preserves symlink paths (`AE_IFLNK`) without following symlink filenames via `realpath`. Safely and immediately rejects sockets, FIFOs, and device nodes without process blocking.

2. **Atomic Commit & Data Rollback (`commitArchive`):**
   - Existing destination archives are **never deleted** prior to having a fully verified replacement.
   - Uses native filesystem atomic exchange (`replaceItemAt`) where supported.
   - Automatic staged backup (`.upackx_backup_<uuid>.tmp`) and immediate rollback restores original destination files if replacement or move fails.
   - Protects users against data loss on non-atomic file systems, network shares, and Google Drive File Provider paths.

3. **Release Assets & Checksums Audit:**
   - Audited GitHub Release v1.3.0 assets and verified matching SHA-256 digests across all downloaded packages and `SHA256SUMS.txt`.
   - Corrected documentation in `release_notes_v1.3.0.md` to match genuine release digests.

4. **Expanded Automated Verification Suite (50 Tests):**
   - Expanded test suite from 39 to 50 automated tests.
   - Added Tests 30–39 covering unreadable source files, unreadable directory children, fault injection (disk full, write failure, close failure, commit failure), file truncation detection, symlink round-trip preservation, FIFO rejection, Google Drive mount path overwrite, and 50-file exhaustive SHA-256 manifest validation.

---

### Verification & Checksums

| Package | Format | Description |
|---|---|---|
| **`UpackX-v1.3.1-macOS-Intel.dmg`** | Apple Disk Image | Recommended drag-and-drop installer into `/Applications`. |
| **`UpackX-v1.3.1-macOS-Intel.pkg`** | Apple Installer | Guided installer package for macOS. |
| **`UpackX-v1.3.1-macOS-Intel.zip`** | Portable ZIP | Standalone `.app` bundle preserving metadata via `ditto`. |
| **`SHA256SUMS.txt`** | Text | Authoritative SHA-256 verification hashes for all release packages. |

---

### Installation & First Launch

1. Download **`UpackX-v1.3.1-macOS-Intel.dmg`** or **`UpackX-v1.3.1-macOS-Intel.pkg`**.
2. Install UpackX into your `/Applications` directory.
3. **First Launch (Gatekeeper):**
   - Right-click on `UpackX.app` in `/Applications` and select **Open**, then click **Open** in the prompt.
4. Launching the application registers and activates all 4 native Finder Quick Actions in your user session.
