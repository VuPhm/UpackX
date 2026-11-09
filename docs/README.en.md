# UpackX — Lightweight Native Archive Extractor & Compressor for macOS

[![Release](https://img.shields.io/badge/release-v1.4.1--beta-blue.svg)](https://github.com/VuPhm/UpackX/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B%20%7C%20Universal%202-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-orange.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary%20%2F%20BSD%20Notices-lightgrey.svg)](../THIRD_PARTY_NOTICES.md)

*English Documentation • [Xem tài liệu tiếng Việt tại README.md](../README.md)*

**UpackX** is a high-performance, lightweight native archive extractor and compressor engineered for **macOS 14.0 Sonoma and macOS 15 Sequoia+**, running natively on both **Apple Silicon (`arm64`)** and **Intel (`x86_64`)** architectures. Built purely in native **Swift** and **AppKit**, UpackX integrates directly into the macOS Finder context menu with zero background daemons.

---

### 1. Key Highlights & Technical Specs

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                 UpackX — Native macOS Extractor & Compressor                │
├────────────────────────────────┬────────────────────────────────────────────┤
│ Executable Architecture        │ Universal 2 (Native Apple Silicon & Intel) │
│ Executable Size                │ ~1.6 MB (Fat Mach-O universal binary)      │
│ Total Application Bundle Size  │ ~13 MB (Includes standalone 7zz helper)    │
│ Peak Memory Usage (RSS)        │ ~13 – 28 MB constant during streaming      │
│ Background Daemons             │ 0 (Exits cleanly upon task completion)     │
│ Finder Integration             │ 4 Native Cocoa NSServices (Clean filters)  │
│ Core Compression Engine        │ Native libarchive streaming (Fast/Norm/Max)│
│ External Dependencies          │ Zero (Self-contained, no Homebrew needed)  │
│ Minimum System Requirement     │ macOS 14.0 Sonoma (arm64 & x86_64)         │
└────────────────────────────────┴────────────────────────────────────────────┘
```

---

### 2. Quick Download & Installation

Pre-built Universal 2 release packages are available on the [GitHub Releases page](https://github.com/VuPhm/UpackX/releases):

- **Apple Disk Image (Recommended):** `UpackX-v1.4.1-macOS-Universal.dmg`
- **Apple Installer Package:** `UpackX-v1.4.1-macOS-Universal.pkg`
- **Portable ZIP Bundle:** `UpackX-v1.4.1-macOS-Universal.zip`
- **Authoritative Checksums:** `SHA256SUMS.txt`

#### First-Launch Trust Guide (Gatekeeper)

As independent macOS software distributed outside the paid Apple Developer program, UpackX is ad-hoc signed and protected by macOS Gatekeeper:

1. **Install:** Double-click `UpackX-v1.4.1-macOS-Universal.dmg` and drag `UpackX.app` into `/Applications`.
2. **First Open:** Open `/Applications` and double-click `UpackX`.
3. **Authorize in System Settings:**
   - When macOS displays *"Apple cannot check it for malicious software"*, click **Done** or **Cancel**.
   - Open **System Settings** → **Privacy & Security**.
   - Scroll down to the **Security** section, locate the notice regarding UpackX, and click **Open Anyway**.
   - Enter your Mac administrator password / Touch ID and confirm **Open**.
4. **If "Open Anyway" is missing:** Re-attempt opening `UpackX` in `/Applications` once more, then return to Privacy & Security.
5. **Security Distinction:**
   - ℹ️ *Unidentified Developer warning* is normal for unnotarized independent software. Follow Step 3 to authorize.
   - ⛔ *Damaged or Malicious software warning* indicates a corrupted download. Do not bypass; delete and re-download from official GitHub releases.

---

### 3. Finder Context Menu Integration

Right-click any file or folder in Finder to access 4 dedicated native UpackX actions:

1. **Giải nén nhanh với UpackX (Quick Extract):** Direct in-place archive extraction alongside the source file without extra nested wrappers.
2. **Giải nén… với UpackX (Extract To...):** Native modal window to choose custom destination and conflict policies.
3. **Nén nhanh với UpackX (Quick Compress):** Direct in-place ZIP creation with automatic non-conflicting rename on collision.
4. **Nén… với UpackX (Compress To...):** Native modal window to pick custom archive name, destination folder, compression level, and size preview.

*Note: Extraction menu items strictly match supported archive formats (ZIP, 7Z, RAR, TAR, GZ, BZ2, XZ, ISO), leaving generic files and folders uncluttered.*

---

### 4. Supported Archive Formats

| Format | Extension | Extraction | Compression |
|---|---|---|---|
| **ZIP** | `.zip`, `.zipx`, `.jar` | Native `libarchive` | Native `libarchive` (Levels 1–9) |
| **7-Zip** | `.7z` | Bundled Universal `7zz` | Planned |
| **RAR** | `.rar`, `.cbr` | Bundled Universal `7zz` | N/A |
| **Tarball** | `.tar`, `.tar.gz`, `.tgz` | Native `libarchive` | Planned |
| **BZip2** | `.bz2`, `.tar.bz2` | Native `libarchive` | Planned |
| **XZ** | `.xz`, `.tar.xz` | Native `libarchive` | Planned |
| **Multi-Part** | `.part1.rar`, `.7z.001`, `.z01` | Integrated volume manager | Planned |

---

### 5. System Requirements

- **Processor:** Apple Silicon (`arm64`) or Intel (`x86_64`).
- **Operating System:** macOS 14.0 Sonoma or newer (tested on Sonoma 14 and Sequoia 15).
- **Homebrew / External Dependencies:** None.

