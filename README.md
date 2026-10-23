# UpackX — Lightweight Native Archive Extractor & Compressor for macOS

[![Release](https://img.shields.io/badge/release-v1.3.1-blue.svg)](https://github.com/VuPhm/UpackX/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B%20%7C%20Intel%20x86__64-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/arch-x86__64-orange.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary%20%2F%20BSD%20Notices-lightgrey.svg)](THIRD_PARTY_NOTICES.md)

**UpackX** is a high-performance, lightweight native archive extractor and compressor engineered specifically for **Intel-based Macs** running macOS 14.0 Sonoma or newer. Built purely in native **Swift** and **AppKit**, UpackX integrates directly into the macOS Finder context menu with zero background daemons.

[English](#english) • [Tiếng Việt](#tiếng-việt)

---

<a name="english"></a>
## English Documentation

### 1. Key Highlights & Technical Specs

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                 UpackX — Native macOS Extractor & Compressor                │
├────────────────────────────────┬────────────────────────────────────────────┤
│ Executable Size                │ ~590 KB (Swift native, -O optimized)       │
│ Total Application Bundle Size  │ 3.6 MB (Includes standalone 7zz helper)    │
│ Peak Memory Usage (RSS)        │ ~12.5 – 27.2 MB constant during streaming  │
│ Background Daemons             │ 0 (Exits cleanly upon task completion)     │
│ Finder Integration             │ 4 Native Cocoa NSServices (Zero duplicates)│
│ Core Compression Engine        │ Native libarchive streaming (Fast/Norm/Max)│
│ External Dependencies          │ Zero (Self-contained, no Homebrew needed)  │
│ Minimum System Requirement     │ macOS 14.0 Sonoma (Intel x86_64)           │
└────────────────────────────────┴────────────────────────────────────────────┘
```

---

### 2. User Interface

```text
  ┌──────────────────────────────────────────────────────────────┐
  │  ● ● ●   UpackX — Native macOS Extractor & Compressor        │
  ├──────────────────────────────────────────────────────────────┤
  │                                                              │
  │     ┌──────────────────────────────────────────────────┐     │
  │     │                                                  │     │
  │     │                    [📦]                          │     │
  │     │                                                  │     │
  │     │        Drag & drop archives or folders here      │     │
  │     │                                                  │     │
  │     └──────────────────────────────────────────────────┘     │
  │                                                              │
  │   Finder Services: Active (4 services: 2 Extract, 2 Compress)│
  │                                                              │
  │    [ Extract Archive... ]        [ Compress ZIP... ]         │
  │                                                              │
  │                [ Check Finder Services ]                     │
  └──────────────────────────────────────────────────────────────┘
```

---

### 3. Features

#### Extraction
- **Direct Extraction (No Wrapper Folder):** Uncompresses archive contents directly alongside the source archive without creating unnecessary enclosing wrapper folders.
- **Dual Extraction Finder Actions:**
  - `Giải nén nhanh với UpackX` (Quick Extract): Instantly extracts to the parent directory.
  - `Giải nén… với UpackX` (Extract To...): Displays a native modal window to choose custom destination and conflict rules.
- **Collision & Overwrite Safety:** Interactive prompt when a file conflict occurs (Skip, Auto-rename copy `(1)`, or Overwrite).
- **Safe Directory Merging:** When extracting into existing folders, files are merged safely without deleting directory structures.
- **Zip-Slip Prevention:** Strict validation blocks path traversal attacks (`../../`).
- **Encrypted Archives:** Automatic password prompt dialog with secure stdin piping (never exposed in process arguments or logs).
- **Multi-Part Volume Support:** Automatically groups `.part1.rar`, `.7z.001`, `.z01`, and `.r00` volumes; warns if any volume is missing.

#### Compression (v1.3.0 MVP)
- **Native Streaming ZIP Engine:** Uses `libarchive` with fixed 64 KB buffers keeping memory usage < 13 MB RSS.
- **Structure Preservation:** Single directory `Photos/` compresses into `Photos.zip` preserving `Photos/...` internal hierarchy. Quick extract recovers original structure cleanly.
- **Single File & Multi-Item Support:** Compress individual files or multiple files/folders into a unified `Archive.zip`.
- **Dual Compression Finder Actions:**
  - `Nén nhanh với UpackX` (Quick Compress): In-place ZIP creation with automatic non-conflicting rename on collision.
  - `Nén… với UpackX` (Compress To...): Native AppKit modal window to pick custom archive name, destination folder, compression level, and preview source size.
- **Compression Levels:** Fast (level 1), Normal (level 6), and Maximum (level 9).
- **Self-Inclusion Protection:** Output archives created inside a folder being compressed are automatically excluded from the archive contents.
- **Atomic Staging:** Data is compressed into a temporary staging file (`.upackx_compress_<uuid>.tmp`) and renamed upon validation. Cancellation leaves zero orphaned files.

---

### 4. Supported Archive Formats

| Format | Extension | Extraction | Compression |
|---|---|---|---|
| **ZIP** | `.zip` | Native `libarchive` | Native `libarchive` (Levels 1–9) |
| **7-Zip** | `.7z` | Bundled `7zz` | Planned (Round C) |
| **RAR** | `.rar` | Bundled `7zz` | N/A |
| **Tarball** | `.tar`, `.tar.gz`, `.tgz` | Native `libarchive` | Planned |
| **BZip2** | `.bz2`, `.tar.bz2` | Native `libarchive` | Planned |
| **XZ** | `.xz`, `.tar.xz` | Native `libarchive` | Planned |
| **Multi-Part** | `.part1.rar`, `.7z.001`, `.z01` | Integrated volume manager | Planned |

---

### 5. System Requirements

- **Processor:** Intel 64-bit (`x86_64`).
- **Operating System:** macOS 14.0 Sonoma or newer.

---

### 6. Download

Pre-built release packages are available on the [GitHub Releases page](https://github.com/VuPhm/UpackX/releases):

- **Apple Disk Image (Recommended):** `UpackX-v1.3.1-macOS-Intel.dmg`
- **Apple Installer Package:** `UpackX-v1.3.1-macOS-Intel.pkg`
- **Portable ZIP Bundle:** `UpackX-v1.3.1-macOS-Intel.zip`
- **Checksums:** `SHA256SUMS.txt`

---

### 7. Finder Quick Actions

Right-click on any file or folder in **Finder** to access 4 dedicated native UpackX actions:
1. **Giải nén nhanh với UpackX:** Direct in-place archive extraction.
2. **Giải nén… với UpackX:** Customizable extraction destination and conflict policies.
3. **Nén nhanh với UpackX:** Direct in-place ZIP creation.
4. **Nén… với UpackX:** Customizable ZIP name, destination, and compression level.

---

<a name="tiếng-việt"></a>
## Tiếng Việt

### 1. Giới thiệu tổng quan

**UpackX** là ứng dụng native siêu nhẹ, hiệu năng cao phục vụ cả hai nhu cầu **Nén và Giải nén** trên macOS Intel (x86_64). Tích hợp native 4 thao tác trực tiếp vào menu ngữ cảnh Finder với 0 daemon chạy ngầm.

### 2. Điểm nổi bật phiên bản v1.3.1
- **Toàn vẹn dữ liệu nén tuyệt đối:**
  - Không bao giờ âm thầm bỏ sót file hay báo thành công trên archive chưa hoàn chỉnh.
  - Xử lý phân biệt EOF và lỗi đọc I/O, kiểm tra chặt chẽ `EINTR`.
  - Đối chiếu số byte ghi thực tế với kích thước khai báo, phát hiện file bị thay đổi/rút ngắn khi đang nén.
  - Kiểm tra toàn bộ mã trả về của `archive_write_set_options`, `archive_write_close` và các thao tác libarchive.
  - Từ chối an toàn các file socket, named pipe (FIFO) và device nodes mà không bị treo tiến trình.
- **Cam kết Atomic Commit & Rollback:**
  - Không bao giờ xóa archive cũ trước khi bản thay thế hoàn tất và được xác thực.
  - Sử dụng cơ chế thay thế nguyên tử kết hợp sao lưu tạm (`.upackx_backup_<uuid>.tmp`) và tự động rollback nếu gặp lỗi.
  - Bảo vệ an toàn kể cả trên đường dẫn Google Drive File Provider.
- **4 thao tác Finder rõ ràng (2 Nén, 2 Giải nén):**
  - `Giải nén nhanh với UpackX` / `Giải nén… với UpackX`
  - `Nén nhanh với UpackX` / `Nén… với UpackX`
- **Bộ kiểm thử 50 tests tự động:** Kiểm tra lỗi có chủ đích, fault injection, streaming, benchmark bộ nhớ (< 13 MB RSS).

### 3. Cài đặt

1. Tải **`UpackX-v1.3.1-macOS-Intel.dmg`** từ mục Releases.
2. Mở DMG và kéo `UpackX.app` vào thư mục `Applications`.
3. Nhấp chuột phải vào `UpackX.app` và chọn **Open** trong lần đầu tiên để kích hoạt Finder Services.
