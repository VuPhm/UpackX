# Changelog

All notable changes to **UpackX** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.3.0] - 2026-10-24

### Added
- **Core ZIP Compression Engine (`ZipCompressor`):**
  - High-performance, streaming native ZIP compression powered by `libarchive`.
  - Supports single file, single directory (preserving root folder structure, e.g. `Photos/` -> `Photos.zip`), and multiple items into unified `Archive.zip`.
  - Source files and directories are strictly untouched and never modified or deleted.
  - Streaming architecture with 64 KB chunk buffers maintaining constant low memory footprint (< 13 MB observed RSS).
  - Configurable compression levels: Fast (level 1), Normal (level 6), and Maximum (level 9).
  - Robust cancellation handling with automatic removal of staging temporary files (`.upackx_compress_<uuid>.tmp`).
- **Finder Integration Expansion (4 Distinct Native NSServices):**
  - **Nén nhanh với UpackX (`quickCompressService`):** One-click in-place ZIP compression with safe auto-renaming on conflict (no silent overwrite, no modal disruption).
  - **Nén… với UpackX (`compressToService`):** Native AppKit modal window (`CompressToWindowController`) allowing custom archive name, destination folder picker, compression level selection, source size preview, and Cancel/Compress actions.
  - Exactly 4 canonical UpackX actions in Finder's context menu (2 extract, 2 compress) with zero legacy Automator workflow duplicates.
- **Safety & Integrity Protections:**
  - Self-inclusion defense: output archive and temporary staging files are automatically excluded if placed inside the directory being compressed.
  - Collision safety: existing files are never overwritten silently; automatic incrementing (`Archive (1).zip`) or interactive prompts prevent data loss.
  - POSIX `realpath` path canonicalization resolving macOS `/tmp` (`/private/tmp`) symlink prefixes.
- **Dual Functionality MainWindow:**
  - Updated `MainWindowController` supporting drag-and-drop of both archives (to extract) and regular files/folders (to compress).
  - Direct action buttons for "Chọn file giải nén..." and "Chọn file/thư mục nén...".
- **Comprehensive Test Suite (39 Passing Tests):**
  - Added Tests 23–29 covering single/multi-item round-trips, Vietnamese Unicode paths, deep hierarchies, large data streaming benchmarks, self-inclusion defense, collision safety, compression levels, and Finder NSService dispatch.

## [1.2.1] - 2026-10-24

### Fixed & Hardened
- **7-Zip Password Security:** Migrated password input from command-line arguments to standard input pipe (`stdin`), eliminating exposure to process listing tools (`ps aux`).
- **Interactive Conflict Handling in 7zz:** Added staging directory and interactive conflict prompting for 7Z/RAR extractions. The `.ask` policy now legitimately prompts the user instead of automatically falling back to rename.
- **Path Resolution on Symlinked Mounts:** Resolved canonical symlink mismatches on macOS `/tmp` (`/private/tmp`) ensuring correct relative path extraction.
- **CI/CD Pipeline Upgrade:** Migrated GitHub Actions runners from deprecated `macos-13` to supported `macos-15-intel` runners.
- **Regression Tests:** Added automated tests for 7Z conflict handling, stdin password protection, and corrupted archive detection (28 passing tests).

## [1.2.0] - 2026-10-24

### Added
- **Native macOS Packaging:**
  - Standard Apple Disk Image (`UpackX-v1.2.0-macOS-Intel.dmg`) with drag-and-drop Applications shortcut.
  - Apple Installer Package (`UpackX-v1.2.0-macOS-Intel.pkg`) built with `pkgbuild` and `productbuild` featuring Welcome, License, and Conclusion steps.
  - Portable bundle ZIP archive preserving extended attributes via `ditto`.
  - Automatic `SHA256SUMS.txt` generation and verification.
- **Pre-Flight Release Automation:**
  - Automated `make package` and `make release-check` workflows.
  - GitHub Actions CI/CD workflows for macOS Intel (`macos-13`).
- **Minimal Native AppIcon:**
  - Custom minimal archive box icon with cyan electrical accents (`#38BDF8`) and graphite body.
  - 10-resolution macOS iconset (`AppIcon.icns`) and vector master (`AppIcon.svg`).
- **Multi-Part Volume Extraction:**
  - Automatic group detection for multi-part archives (`.part1.rar`, `.7z.001`, `.z01`, `.r00`).
  - Automatic identification and dispatch from non-first volume selection.
  - Safe rejection of incomplete archive sets when volumes are missing.
- **Safe Directory Merging:**
  - Destination directories are preserved during extraction without destructive directory replacement.
- **Google Drive for Desktop Support:**
  - Compatible with mounted Google Drive directories, atomic rename fallbacks, and `SF_DATALESS` placeholder detection.

### Changed
- **Finder Integration Architecture:**
  - Fully migrated to single, canonical **Native Cocoa NSServices** (`quickExtractService` and `extractToService`).
  - Completely eliminated the previous duplicate 4 context menu items.
  - Added user-session auto-registration on first launch from `/Applications`.
- **Memory Streaming Engine:**
  - Stream buffer optimization keeping memory consumption between 12.5 MB and 27.2 MB RSS regardless of archive size (tested up to 500 MB).

---

## [1.0.0] - 2026-10-23

### Added
- Initial release of UpackX core extractor engine.
- Swift + AppKit native interface.
- Support for ZIP, TAR.GZ, 7Z, RAR, BZ2, XZ formats.
- Safe collision handling with interactive conflict dialogs.
- Zip-Slip path traversal defense.
- Password-protected archive support.
