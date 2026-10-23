# UpackX Development Roadmap & Technical Specifications

This document outlines the product vision, completed milestones, and deep architectural design for upcoming **Advanced Compression** features in **UpackX**.

---

## Status Overview

| Milestone | Version | Focus | Status |
|---|---|---|---|
| **Production Release R1** | `v1.2.0` | Native Extraction Engine & macOS Packaging | **Completed & Released** |
| **Release Hardening** | `v1.2.1` | CI/CD on `macos-15-intel`, 7Z Stdin Passwords, Conflict Fixes | **Completed & Released** |
| **Compression MVP** | `v1.3.0` | Native Streaming ZIP Engine & Dual Finder Services (4 Total) | **Completed & Verified (39 Tests)** |
| **Advanced Compression** | `v1.4.0` | 7Z Engine, AES-256, Multipart Splitting, Ultra Resource Tuning | **Design Complete (Round C)** |

---

## Completed Milestones (v1.2.0 – v1.3.0)

- [x] **Native Cocoa NSServices:** Exactly 4 clean Finder context menu items (2 extract, 2 compress) with zero Automator workflow duplicates.
- [x] **Zero Duplicate Workflows:** Fully eliminated legacy Automator workflows and stale LaunchServices registrations.
- [x] **Core ZIP Compression Engine:** Pure native `libarchive` streaming engine with 64 KB chunk buffers maintaining constant memory footprint (< 13 MB RSS).
- [x] **Hierarchy & Folder Preservation:** Compressing folder `Photos/` yields `Photos.zip` preserving `Photos/...` internal tree. Quick extract recovers original structure cleanly.
- [x] **Safety & Self-Inclusion Protections:** Destination archives inside source directories are safely excluded from archive payload; collision auto-renaming prevents overwriting.
- [x] **POSIX realpath Canonicalization:** Robust path validation preventing `/tmp` vs `/private/tmp` symlink mismatch vulnerabilities.
- [x] **Secure 7Z Password Piping:** Stdin password transmission eliminating credentials exposure from command-line arguments and logs.
- [x] **Dual Functionality MainWindow:** Minimal AppKit GUI supporting drag-and-drop extraction or compression.
- [x] **Extensive Verification Suite:** 39 automated integration, round-trip, benchmark, and security regression tests passing cleanly.

---

## Architectural Design: Round C — Advanced Compression (v1.4.0)

### 1. 7-Zip Compression Engine Architecture

#### Engine Selection
While ZIP is optimal for universal cross-platform portability, **7-Zip (LZMA2)** delivers vastly superior compression ratios (often 30–60% smaller than Deflate).
For 7Z creation, UpackX will leverage its bundled standalone `7zz` binary (`Contents/Resources/bin/7zz`), already verified on Intel x86_64.

#### Secure Process Invocation & Zero Password Leakage
> [!IMPORTANT]
> Under no circumstances will archive passwords be passed as command-line arguments (e.g. `-pSecretPass`). In POSIX systems, `ps aux` and process auditing tools reveal arguments to all user-space processes.

- **Password Transmission Protocol:**
  When encryption is enabled, `7zz` will be invoked with `-p` (prompting mode) and the secret passphrase written directly to the child process's standard input pipe (`stdin`) immediately upon spawn, followed by a newline:
  ```swift
  let inPipe = Pipe()
  process.standardInput = inPipe
  try process.run()
  if let pwData = (password + "\n").data(using: .utf8) {
      inPipe.fileHandleForWriting.write(pwData)
      inPipe.fileHandleForWriting.closeFile()
  }
  ```
- **Process Arguments Guard:** Logs will record sanitized arguments only: `["a", "-t7z", "-p[PROTECTED]", ...]`.

---

### 2. Encryption Architecture (AES-256)

#### Target Specifications
1. **7-Zip AES-256:**
   - Cipher: 256-bit AES with SHA-256 key derivation (200,000+ iterations).
   - **Header Encryption (`-mhe=on`):** Encrypts directory and file names. Third parties cannot inspect archive table of contents without the passphrase.
2. **ZIP AES-256 (WinZip Compatible):**
   - WinZip AES-256 encryption mode supported by `libarchive` via `archive_write_set_options(a, "zip:encryption=aes256")` and `7zz`.
   - Replaces obsolete, cryptographically broken PKZIP traditional stream cipher.

#### UI Security Guardrails
- **Password Input Window:** Native modal dialog with `NSSecureTextField`.
- **Strength Validation:** Minimum length check (>= 8 characters recommended).
- **Confirmation Verification:** Dual password fields ("Mật khẩu" & "Xác nhận mật khẩu") to prevent accidental lockouts from typos.
- **Header Encryption Toggle:** Checkbox: *"Ẩn danh sách tên file (Header Encryption)"* enabled by default for 7Z format.

---

### 3. Multipart / Volume Splitting Specification

#### Functional Requirements
Users must be able to split large archives into multiple uniform chunk files for email attachments, FAT32 storage limits (4 GB), cloud upload constraints, or optical media archiving.

#### Splitting Presets & Extensions
- **Preset Sizing Matrix:**
  - `10 MB` (Mobile messaging / email safe)
  - `50 MB` (Discord / Slack upload limit)
  - `100 MB` (Standard web upload tier)
  - `700 MB` (CD-ROM 80 min)
  - `2000 MB` (Cloud storage chunk)
  - `4000 MB` (FAT32 filesystem boundary)
  - `4700 MB` (DVD-R single layer)
  - `Custom` (User-entered value in KB, MB, or GB)
- **Volume Naming Conventions:**
  - 7Z volumes: `Archive.7z.001`, `Archive.7z.002`, ..., `Archive.7z.nnn`
  - ZIP volumes: `Archive.z01`, `Archive.z02`, ..., `Archive.zip`
- **Engine Command Mapping:**
  ```bash
  7zz a -t7z -v100m -mx=6 /path/to/Archive.7z /source/items...
  ```
- **Primary Part Linkage:**
  The volume manager will automatically assign the primary part (`.001` or `.z01`) for double-click and Finder quick extraction.

---

### 4. Compression Ratio & Benchmark Analysis

| Data Type | Uncompressed Size | ZIP (Deflate Normal) | 7Z (LZMA2 Normal) | 7Z (LZMA2 Maximum) | Ratio Gain (7Z vs ZIP) |
|---|---|---|---|---|---|
| **Source Code (Git Repo)** | 100 MB | ~28 MB | ~14 MB | ~11 MB | **+60% smaller** |
| **System Logs / Text** | 250 MB | ~35 MB | ~12 MB | ~8 MB | **+77% smaller** |
| **Raw Binaries (Mach-O)** | 80 MB | ~38 MB | ~24 MB | ~21 MB | **+44% smaller** |
| **Media (JPEG / MP4)** | 200 MB | ~198 MB | ~196 MB | ~195 MB | *Negligible (<2%)* |

#### Practical Recommendations
- For media files (photos, videos, MP3s), use `Fast` (Store or low-level Deflate) to save CPU cycles, as pre-compressed data yields minimal ratio improvements.
- For documents, code, databases, and logs, `7Z Normal` or `7Z Maximum` provides drastic footprint reductions.

---

### 5. Resource Limits & Ultra Compression Guardrails

#### Memory Allocation Realities in LZMA2
LZMA2 dictionary size drastically alters RAM requirements during *compression*:

| Compression Level | Dictionary Size | RAM Usage (Compression) | RAM Usage (Decompression) |
|---|---|---|---|
| **Fast (`-mx=1`)** | 64 KB | ~8 MB | ~1 MB |
| **Normal (`-mx=6`)** | 16 MB | ~180 MB per thread | ~18 MB |
| **Maximum (`-mx=9`)** | 64 MB | ~700 MB per thread | ~66 MB |
| **Ultra (`-mx=9 -md=128m`)** | 128 MB | ~1.4 GB per thread | ~130 MB |

#### Throttling & Hardware Safety Rules for Intel Macs
Many older Intel Macs (e.g. MacBook Air or Mac mini 2018–2020) have 8 GB of unified RAM and 2 or 4 physical CPU cores. If an Ultra compression job spawns 8 threads with 128 MB dictionaries, it could demand **11+ GB of RAM**, triggering aggressive macOS swap paging and freezing the UI WindowServer.

1. **Thread Capping (`-mmt`):**
   - Automatically cap active compression worker threads to `min(physicalCores, 4)`.
   - Avoids starving AppKit main thread and keeps system responsive.
2. **System Memory Guard:**
   - Inspect total physical RAM via `sysctl hw.memsize`.
   - If total system memory <= 8 GB, cap dictionary size to 32 MB (`-md=32m`), preventing out-of-memory kernel panics or swap thrashing.
3. **Thermal Throttling Awareness:**
   - Provide a background QoS (`qos: .utility` or `.userInitiated`) so macOS Grand Central Dispatch regulates thermal load on fan-cooled Intel hardware.

---

## Implementation Plan for v1.4.0

1. **Backend Integration:**
   - Create `Sources/Core/SevenZipCompressor.swift` wrapping `7zz` process management with stdin password piping and progress parsing.
2. **Dialog Enhancements:**
   - Update `CompressToWindowController` with:
     - Format picker: `ZIP` (Default) vs `7-Zip (.7z)`.
     - Password protection disclosure with SecureTextField.
     - Volume split checkbox and chunk size picker.
3. **CLI Flags Expansion:**
   - Support `upackx -c --format 7z --split 100m --password <stdin> ...`
4. **Automated QA:**
   - Add Round C tests covering 7Z password encryption round-trip, volume splitting & recombining, and memory bounds validation.
