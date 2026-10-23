# UpackX Development Roadmap

This document outlines the product vision, completed milestones, and upcoming architectural tracks for **UpackX**.

---

## Current Status: v1.2.0 (Production Release R1) — Extractor Engine

### Completed & Stabilized
- [x] **Native Cocoa NSServices:** Exactly 2 clean right-click Finder menu services (*"Giải nén nhanh với UpackX"* and *"Giải nén… với UpackX"*).
- [x] **Zero Duplicate Workflows:** Fully eliminated legacy Automator workflows and stale LaunchServices registrations.
- [x] **Streaming Memory Engine:** Fixed ~20–27 MB RSS RAM consumption on archives up to 500 MB+.
- [x] **Multi-Part Volume Handling:** Automatic volume set grouping (`.part1.rar`, `.7z.001`, `.z01`), primary part discovery, and missing-part rejection.
- [x] **Safe Directory Merging:** Non-destructive merging of folder contents; safe file collision strategies (Ask, Skip, Auto-rename, Overwrite).
- [x] **Google Drive for Desktop Support:** Cloud Storage mount compatibility, `SF_DATALESS` placeholder awareness, non-atomic rename fallbacks.
- [x] **Minimal App Icon:** Native vector macOS icon stack with 10 system resolutions.
- [x] **Production Distribution Packaging:** Native Apple Disk Image (`.dmg`) with drag-and-drop installer, Apple Installer Package (`.pkg`) with guided wizard, and portable `.zip`.

---

## Planned: Round 2 — Native Compression Engine (Upcoming)

> [!NOTE]
> The upcoming release cycle will introduce the **UpackX Compression Engine**, allowing users to create archives with the same native performance, zero-daemon footprint, and elegant Finder integration.

### 1. Compression Engine Architecture & Formats
- [ ] **Dual Engine Pipeline:**
  - Standard ZIP archiving via system `libarchive` for maximum compatibility.
  - High-compression 7Z archiving via bundled `7zz` helper.
- [ ] **Compression Level Control:**
  - Fast (Store / Fastest).
  - Normal (Standard balance).
  - Maximum / Ultra (Highest ratio for large files).
- [ ] **Encryption & Security:**
  - Password protection with standard ZipCrypto / AES-256 for ZIP.
  - Header encryption and AES-256 for 7Z.

### 2. Finder Integration for Compression
- [ ] **Finder Context Menu Quick Actions:**
  - *"Nén nhanh với UpackX"* (Quick Compress): Creates archive in place with standard options and progress HUD.
  - *"Nén… với UpackX"* (Compress To...): Opens native modal sheet to configure format, compression level, destination, password, and volume splitting.
- [ ] **Multi-Selection & Directory Compression:**
  - Support compressing multiple selected files into a single archive or separate archives.
  - Proper directory tree packing preserving POSIX permissions, symlinks, and timestamps.

### 3. Advanced Packaging & Volumes
- [ ] **Multi-Volume Splitting:**
  - Split archives into user-specified chunk sizes (e.g., 50 MB, 100 MB, 700 MB CD, 4.7 GB DVD, custom).
- [ ] **Large File Streaming:**
  - Chunker and streaming writer designed to maintain low CPU and memory footprint during multi-gigabyte compression.
- [ ] **Compression Job Queue:**
  - Sequential processing of multiple compression tasks with unified batch progress HUD.
- [ ] **Cloud Storage Sync Awareness:**
  - Safety checks when compressing files residing inside active Google Drive or iCloud sync roots.

---

## Future Explorations

- [ ] Universal 2 / Apple Silicon (ARM64) dual-architecture builds after dedicated hardware testing.
- [ ] Notification Center interactive actions (Open, Reveal, Share).
- [ ] Checksum verification utility (MD5, SHA-1, SHA-256) for archives.
