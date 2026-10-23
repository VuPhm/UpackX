# UpackX — Lightweight Native Archive Extractor for macOS

[![Release](https://img.shields.io/badge/release-v1.2.0-blue.svg)](https://github.com/VuPhm/UpackX/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B%20%7C%20Intel%20x86__64-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/arch-x86__64-orange.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary%20%2F%20BSD%20Notices-lightgrey.svg)](THIRD_PARTY_NOTICES.md)

**UpackX** is a high-performance, lightweight native archive extractor engineered specifically for **Intel-based Macs** running macOS 14.0 Sonoma or newer. Built purely in native **Swift** and **AppKit**, UpackX integrates directly into the macOS Finder context menu with zero background daemons.

[English](#english) • [Tiếng Việt](#tiếng-việt)

---

<a name="english"></a>
## English Documentation

### 1. Key Highlights & Technical Specs

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                      UpackX — Native macOS Extractor                        │
├────────────────────────────────┬────────────────────────────────────────────┤
│ Executable Size                │ 438 KB (Swift native, -O optimized)        │
│ Total Application Bundle Size  │ 3.4 MB (Includes standalone 7zz helper)    │
│ Peak Memory Usage (RSS)        │ ~12.5 – 27.2 MB constant during streaming  │
│ Background Daemons             │ 0 (Exits cleanly upon task completion)     │
│ Finder Integration             │ 2 Native Cocoa NSServices (Zero duplicates)│
│ External Dependencies          │ Zero (Self-contained, no Homebrew needed)  │
│ Minimum System Requirement     │ macOS 14.0 Sonoma (Intel x86_64)           │
└────────────────────────────────┴────────────────────────────────────────────┘
```

---

### 2. User Interface

```text
  ┌──────────────────────────────────────────────────────────────┐
  │  ● ● ●   UpackX — Lightweight macOS Archive Extractor        │
  ├──────────────────────────────────────────────────────────────┤
  │                                                              │
  │     ┌──────────────────────────────────────────────────┐     │
  │     │                                                  │     │
  │     │                    [📦]                          │     │
  │     │                                                  │     │
  │     │          Drag & drop archive file here           │     │
  │     │                                                  │     │
  │     └──────────────────────────────────────────────────┘     │
  │                                                              │
  │      Finder Services: Active (2 services) • Intel x86_64     │
  │                                                              │
  │       [ Select Archive... ]    [ Check Finder Services ]     │
  └──────────────────────────────────────────────────────────────┘
```

---

### 3. Current Features

- **Direct Extraction (No Wrapper Folder):** Uncompresses archive contents directly alongside the source archive without creating unnecessary enclosing wrapper folders.
- **Dual Finder Quick Actions:**
  - `Giải nén nhanh với UpackX` (Quick Extract): Instantly extracts to the parent directory.
  - `Giải nén… với UpackX` (Extract To...): Displays a native modal window to choose custom destination and conflict rules.
- **Collision & Overwrite Safety:** Interactive prompt when a file conflict occurs (Skip, Auto-rename copy `(1)`, or Overwrite).
- **Safe Directory Merging:** When extracting into existing folders (e.g. Google Drive sync folders), existing files and directory structures are safely merged rather than replaced destructively.
- **Zip-Slip Attack Prevention:** Strict validation blocks any archive attempting path traversal outside destination boundaries (`../../`).
- **Encrypted Archives:** Automatic password prompt dialog for encrypted ZIP, 7Z, and RAR archives.
- **Multi-Part Volume Support:** Automatically groups `.part1.rar`, `.7z.001`, `.z01`, and `.r00` volumes; detects and warns if any volume is missing.
- **Google Drive for Desktop Support:** Detects virtual mount points, handles `SF_DATALESS` placeholder files, and provides robust non-atomic rename fallbacks.

---

### 4. Supported Archive Formats

| Format | Extension | Engine | Encryption Support |
|---|---|---|---|
| **ZIP** | `.zip` | System `libarchive` | ZipCrypto, AES-128, AES-256 |
| **7-Zip** | `.7z` | Standalone `7zz` helper | AES-256 |
| **RAR** | `.rar` | Standalone `7zz` helper | RAR4 / RAR5 encrypted |
| **Tarball** | `.tar`, `.tar.gz`, `.tgz` | System `libarchive` | N/A |
| **BZip2** | `.bz2`, `.tar.bz2` | System `libarchive` | N/A |
| **XZ** | `.xz`, `.tar.xz` | System `libarchive` | N/A |
| **Multi-Part** | `.part1.rar`, `.7z.001`, `.z01` | Integrated volume manager | Supported |

---

### 5. System Requirements

- **Processor:** Intel 64-bit (`x86_64`).
- **Operating System:** macOS 14.0 Sonoma or newer.
- *Note:* Apple Silicon (M1/M2/M3/M4) native binaries have not been certified for this release.

---

### 6. Download

Pre-built release packages are available on the [GitHub Releases page](https://github.com/VuPhm/UpackX/releases):

- **Apple Disk Image (Recommended):** `UpackX-v1.2.0-macOS-Intel.dmg`
- **Apple Installer Package:** `UpackX-v1.2.0-macOS-Intel.pkg`
- **Portable ZIP Bundle:** `UpackX-v1.2.0-macOS-Intel.zip`
- **Checksums:** `SHA256SUMS.txt`

---

### 7. Installation

#### Method A: Disk Image (.dmg) — Recommended
1. Download `UpackX-v1.2.0-macOS-Intel.dmg`.
2. Double-click to mount the DMG.
3. Drag **UpackX.app** into the **Applications** shortcut.
4. Launch UpackX once from `/Applications` to activate Finder Services in your user session.

#### Method B: Apple Installer (.pkg)
1. Download `UpackX-v1.2.0-macOS-Intel.pkg`.
2. Double-click to run the standard macOS installer wizard.
3. Follow the on-screen steps.
4. Launch UpackX once from `/Applications` to finalize Finder Services registration.

> [!NOTE]
> **Gatekeeper Notice (Developer / Ad-hoc Signed Release):**
> Because this initial production release is signed with an ad-hoc / developer signature without Apple Developer ID notarization, macOS Gatekeeper may show a notice on first launch. To open:
> - **Right-click (or Control-click)** on `UpackX.app` in `/Applications` and select **Open**, then click **Open** in the dialog.
> - You only need to do this once. Do not disable system-wide Gatekeeper.

---

### 8. How to Use Finder Services

1. Open **Finder** and locate any archive file.
2. **Right-click** on the archive.
3. Select from the context menu:
   - **Giải nén nhanh với UpackX:** Files are extracted immediately into the containing folder.
   - **Giải nén… với UpackX:** An AppKit dialog opens allowing you to pick a destination folder and configure conflict rules.

---

### 9. Uninstallation

#### Standard Uninstall (Finder)
1. Quit UpackX if running.
2. Drag `/Applications/UpackX.app` to the Trash.

#### Complete Clean Uninstall
To remove the application, CLI symlinks, and clear macOS Services cache:
```bash
./Scripts/uninstall.sh
```

---

### 10. Current Limitations

- **Extraction Only:** Creating archives (compression) is planned for Round 2.
- **Intel x86_64:** Compiled specifically for Intel Macs; Apple Silicon native universal binary is scheduled for a future milestone.
- **macOS 14+:** Built and verified for macOS Sonoma (14.0+).

---

### 11. Development Roadmap

See [ROADMAP.md](ROADMAP.md) for detailed release plans, including the upcoming **Native Compression Engine** (ZIP & 7Z compression, Finder quick compress, compression levels, and multi-volume splitting).

---

<a name="tiếng-việt"></a>
## Tiếng Việt

### 1. Giới thiệu tổng quan

**UpackX** là ứng dụng giải nén native siêu nhẹ, ổn định dành riêng cho máy Mac chạy vi xử lý **Intel (x86_64)** trên macOS 14.0 Sonoma trở lên. Ứng dụng được viết hoàn toàn bằng **Swift** và **AppKit**, tích hợp mượt mà vào menu chuột phải của Finder và tuyệt đối không duy trì tiến trình chạy ngầm (zero daemon).

### 2. Điểm nổi bật & Tối ưu kỹ thuật

- **Không tạo thư mục lồng:** Dữ liệu được giải nén trực tiếp ngay cạnh file nén.
- **2 dịch vụ Finder Native duy nhất:**
  - `Giải nén nhanh với UpackX`: Giải nén tức thì không mở cửa sổ cấu hình.
  - `Giải nén… với UpackX`: Hộp thoại chọn nơi lưu và chính sách file trùng.
- **An toàn tuyệt đối:** Tự động phát hiện và chặn đứng tấn công Zip-Slip (`../../`), bảo vệ file trùng lặp (không ghi đè âm thầm).
- **Hỗ trợ đầy đủ Multipart:** Tự nhận diện và gom nhóm các volume `.part1.rar`, `.7z.001`, `.z01`; từ chối giải nén nếu thiếu file volume.
- **Tương thích Google Drive:** Tương thích tốt với thư mục mount Google Drive for Desktop và cờ `SF_DATALESS`.
- **Tiêu thụ RAM cực thấp:** Cơ chế stream giữ mức tiêu thụ RAM ổn định ở ~12.5 – 27.2 MB kể cả khi giải nén file 500 MB.

### 3. Tải về và Cài đặt

Truy cập mục [GitHub Releases](https://github.com/VuPhm/UpackX/releases) để tải:
- **Bộ cài DMG:** `UpackX-v1.2.0-macOS-Intel.dmg` (Kéo vào thư mục Applications).
- **Bộ cài PKG:** `UpackX-v1.2.0-macOS-Intel.pkg` (Trình cài đặt native chuẩn macOS).

**Lưu ý khi mở lần đầu:**
Nhấp chuột phải vào `UpackX.app` trong thư mục Applications và chọn **Open (Mở)** để hệ thống ghi nhớ quyền chạy. Mở ứng dụng lần đầu sẽ tự động kích hoạt 2 dịch vụ chuột phải trong Finder.

### 4. Gỡ cài đặt

- Kéo `/Applications/UpackX.app` vào Thùng rác (Trash).
- Hoặc chạy script dọn sạch triệt để: `./Scripts/uninstall.sh`.
