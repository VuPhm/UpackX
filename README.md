# UpackX — Lightweight Native Archive Extractor & Compressor for macOS

[![Release](https://img.shields.io/badge/release-v1.4.0-blue.svg)](https://github.com/VuPhm/UpackX/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B%20%7C%20Universal%202-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-orange.svg)]()
[![License](https://img.shields.io/badge/license-Proprietary%20%2F%20BSD%20Notices-lightgrey.svg)](THIRD_PARTY_NOTICES.md)

**UpackX** is a high-performance, lightweight native archive extractor and compressor engineered for **macOS 14.0 Sonoma and macOS 15 Sequoia+**, running natively on both **Apple Silicon (`arm64`)** and **Intel (`x86_64`)** architectures. Built purely in native **Swift** and **AppKit**, UpackX integrates directly into the macOS Finder context menu with zero background daemons.

[English](#english) • [Tiếng Việt](#tiếng-việt)

---

<a name="english"></a>
## English Documentation

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
- **Clean Context Menu Filters:** Extraction options appear strictly for supported archive formats; generic files and folders are never cluttered.
- **Collision & Overwrite Safety:** Interactive prompt when a file conflict occurs (Skip, Auto-rename copy `(1)`, or Overwrite).
- **Safe Directory Merging:** When extracting into existing folders, files are merged safely without deleting directory structures.
- **Zip-Slip Prevention:** Strict validation blocks path traversal attacks (`../../`).
- **Encrypted Archives:** Automatic password prompt dialog with secure stdin piping (never exposed in process arguments or logs).
- **Multi-Part Volume Support:** Automatically groups `.part1.rar`, `.7z.001`, `.z01`, and `.r00` volumes; warns if any volume is missing.

#### Compression
- **Native Streaming ZIP Engine:** Uses `libarchive` with fixed 64 KB buffers keeping memory usage < 14 MB RSS.
- **Structure Preservation:** Single directory `Photos/` compresses into `Photos.zip` preserving `Photos/...` internal hierarchy. Quick extract recovers original structure cleanly.
- **Single File & Multi-Item Support:** Compress individual files or multiple files/folders into a unified `Archive.zip`.
- **Dual Compression Finder Actions:**
  - `Nén nhanh với UpackX` (Quick Compress): In-place ZIP creation with automatic non-conflicting rename on collision.
  - `Nén… với UpackX` (Compress To...): Native AppKit modal window to pick custom archive name, destination folder, compression level, and preview source size.
- **Compression Levels:** Fast (level 1), Normal (level 6), and Maximum (level 9).
- **Self-Inclusion Protection:** Output archives created inside a folder being compressed are automatically excluded from the archive contents.
- **Atomic Staging & Rollback:** Data is compressed into a temporary staging file (`.upackx_compress_<uuid>.tmp`) and verified before replacing existing files.

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

### 5. Download

Pre-built Universal 2 release packages are available on the [GitHub Releases page](https://github.com/VuPhm/UpackX/releases):

- **Apple Disk Image (Recommended):** `UpackX-v1.4.0-macOS-Universal.dmg`
- **Apple Installer Package:** `UpackX-v1.4.0-macOS-Universal.pkg`
- **Portable ZIP Bundle:** `UpackX-v1.4.0-macOS-Universal.zip`
- **Checksums:** `SHA256SUMS.txt`

---

### 6. Installation & First-Launch Trust Guide (macOS 14 Sonoma & Sequoia 15+)

As an independent open-source application distributed without a paid Apple Developer ID certificate, UpackX is ad-hoc signed and protected by macOS Gatekeeper:

1. **Download & Mount:** Download **`UpackX-v1.4.0-macOS-Universal.dmg`** and double-click to open.
2. **Install:** Drag **`UpackX.app`** into your **`Applications`** folder.
3. **First Open:** Open `/Applications` and double-click **`UpackX`**.
4. **Grant Trust (Gatekeeper):**
   - If macOS displays *"Apple cannot check it for malicious software"*, click **Done** or **Cancel** to dismiss the prompt.
   - Go to **System Settings** → **Privacy & Security**.
   - Scroll down to the **Security** section, find the message mentioning UpackX, and click **Open Anyway**.
   - Enter your Mac administrator password / Touch ID, then click **Open**.
5. **If "Open Anyway" is missing:** macOS only displays this button after an open attempt has been made. Double-click `UpackX.app` in `/Applications` again, then return to Privacy & Security.
6. **Security Distinction:**
   - ℹ️ *Unidentified Developer warning* is normal for unnotarized open-source software.
   - ⛔ *Damaged or Malicious software warning* indicates a corrupted download. Do not bypass; delete and re-download from official GitHub releases.

---

<a name="tiếng-việt"></a>
## Tiếng Việt

### 1. Giới thiệu tổng quan

**UpackX** là ứng dụng native siêu nhẹ, hiệu năng cao phục vụ cả hai nhu cầu **Nén và Giải nén** trên macOS 14 Sonoma và macOS 15 Sequoia+. Hỗ trợ native cả **Apple Silicon (`arm64`)** lẫn **Intel (`x86_64`)** thông qua bản phân phối **Universal 2**. Tích hợp 4 tác vụ trực tiếp vào menu ngữ cảnh Finder với 0 daemon chạy ngầm.

### 2. Điểm nổi bật phiên bản v1.4.0

- **Hỗ trợ Universal 2 Native (Apple Silicon & Intel):**
  - Cả ứng dụng chính và helper `7zz` đều được đóng gói đa kiến trúc native.
  - Hoàn toàn độc lập, không phụ thuộc Homebrew trên máy người dùng.
- **Trải nghiệm cấp Trust lần đầu tinh gọn:**
  - Tích hợp sẵn tài liệu HTML hướng dẫn cài đặt và cấp quyền trực tiếp trong file DMG.
  - Hướng dẫn chuẩn hóa cho macOS 14 Sonoma và macOS 15 Sequoia qua mục *Quyền riêng tư & Bảo mật (Privacy & Security)*.
  - Không yêu cầu gõ lệnh Terminal hay tắt Gatekeeper.
- **Tối ưu menu ngữ cảnh chuột phải Finder:**
  - Bộ lọc UTI chính xác trong `Info.plist`: menu giải nén chỉ xuất hiện khi nhấp vào file nén thực tế, không gây rối mắt trên các file tài liệu hoặc thư mục thông thường.
  - 4 dịch vụ native: *Giải nén nhanh*, *Giải nén…*, *Nén nhanh*, và *Nén…*.
- **Bộ máy cập nhật thông minh (`UpdateManager`):**
  - Quản lý release stable/beta chuẩn SemVer, tự động nhận diện kiến trúc máy để tải đúng asset.

### 3. Hướng dẫn cài đặt & Cấp quyền mở lần đầu

1. **Tải về:** Tải file **`UpackX-v1.4.0-macOS-Universal.dmg`** từ mục Releases chính thức.
2. **Cài đặt:** Mở file DMG và kéo biểu tượng **`UpackX.app`** vào thư mục **`Applications`**.
3. **Mở lần đầu:** Vào thư mục `Applications` và nhấp đúp mở `UpackX`.
4. **Cấp quyền bảo mật (Privacy & Security):**
   - Khi macOS hiện cảnh báo *"Không thể mở vì Apple không thể kiểm tra phần mềm độc hại"*, nhấn **Xong (Done)** hoặc **Hủy (Cancel)**.
   - Mở **Cài đặt hệ thống (System Settings)** → chọn **Quyền riêng tư & Bảo mật (Privacy & Security)**.
   - Cuộn xuống phần **Bảo mật (Security)**, tìm mục UpackX và nhấn nút **Vẫn mở (Open Anyway)**.
   - Nhập mật khẩu máy Mac hoặc dùng Touch ID, sau đó bấm **Mở (Open)** để xác nhận.
5. **Trường hợp chưa thấy nút "Vẫn mở":** Hãy quay lại `Applications`, nhấp đúp mở `UpackX` một lần nữa, sau đó quay lại phần Quyền riêng tư & Bảo mật để kiểm tra.
6. **Lưu ý bảo mật:**
   - ℹ️ Cảnh báo *"Nhà phát triển chưa xác định"* là bình thường với ứng dụng mã nguồn mở tự do chưa đăng ký Apple Developer ID trả phí.
   - ⛔ Cảnh báo *"Ứng dụng bị hỏng và không thể mở"* là do file tải về bị lỗi. Tuyệt đối không tìm cách vượt qua; hãy xóa và tải lại từ GitHub chính thức.
