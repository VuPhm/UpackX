## UpackX v1.4.0 — Release Readiness, Universal Compatibility & Trust UX

**UpackX v1.4.0** delivers native Universal 2 architecture support (Apple Silicon `arm64` and Intel `x86_64`), a standardized release packaging pipeline, clean Finder context menu filtering, a modern update subsystem with prerelease support, and an intuitive first-launch trust experience for macOS Sonoma 14 and Sequoia 15+.

---

### Highlights in v1.4.0

1. **Universal 2 Architecture Support (Apple Silicon & Intel):**
   - Both the main application executable (`UpackX`) and the standalone helper (`7zz`) are compiled and packaged as native Universal 2 binaries containing both `arm64` and `x86_64` Mach-O slices.
   - Built for macOS 14.0 Sonoma and macOS 15 Sequoia+.
   - Zero Homebrew dependencies on user machines; links exclusively to macOS system libraries (`/usr/lib/libarchive.2.dylib`, `/usr/lib/libSystem`, `/usr/lib/libc++`).

2. **Standardized Release Pipeline & Packaging:**
   - Single Universal 2 DMG distribution (`UpackX-v1.4.0-macOS-Universal.dmg`) as the primary installation method.
   - Secondary Apple Installer PKG (`UpackX-v1.4.0-macOS-Universal.pkg`) and portable ZIP (`UpackX-v1.4.0-macOS-Universal.zip`).
   - Version `1.4.0` synchronized from `Resources/Info.plist` across build scripts, distribution XML, and Swift code.
   - Ad-hoc code signing valid on disk with strict nested signature verification.
   - Automated release pre-flight QA check (`Packaging/release_check.sh`) enforcing binary architecture, linkage, metadata, DMG structure, and checksum integrity.

3. **First-Launch Trust UX (Unnotarized Gatekeeper Flow):**
   - Self-contained, lightweight bilingual HTML guide (`Hướng Dẫn Cài Đặt (Install Guide).html`) bundled directly inside the DMG.
   - Step-by-step guidance for macOS 14 Sonoma & macOS 15 Sequoia:
     1. Drag `UpackX.app` to `Applications`.
     2. Open `UpackX.app` once from `Applications`.
     3. When Gatekeeper displays the unidentified developer warning, go to **System Settings → Privacy & Security → Security** and click **Open Anyway**.
     4. Confirm **Open** to proceed.
   - Guidance on what to do if "Open Anyway" has not appeared yet (re-attempt opening the app first).
   - Clear distinction between expected unidentified developer notices (safe for official open-source downloads) and dangerous damaged/malicious app warnings (do not bypass).
   - Zero Terminal commands or security bypass techniques required.

4. **Cleaner Finder Integration & Context Menu Filtering:**
   - 4 native NSServices maintained: *Giải nén nhanh*, *Giải nén…*, *Nén nhanh*, and *Nén…*.
   - Strict UTI filtering in `Info.plist`: removed `public.item` and `public.data` from extraction services so that extraction options only appear on supported archive files, preventing clutter on generic documents or folders.
   - Standardized on Apple's AppKit `NSUpdateDynamicServices()` API instead of editing internal `pbs` domain preferences.
   - Added in-app status diagnostics and direct button to open macOS Keyboard Shortcuts services configuration.

5. **Enhanced Update Subsystem (`UpdateManager`):**
   - Replaced `/releases/latest` with `/releases` endpoint to properly handle stable vs prerelease versions without 404 or false negative results.
   - Smart architecture-aware asset matching prioritizing Universal DMG, matching host architecture, and favoring DMG > PKG > ZIP.
   - Dynamic User-Agent header matching host CPU architecture.

---

### Verification & Checksums

| Package | Format | Description |
|---|---|---|
| **`UpackX-v1.4.0-macOS-Universal.dmg`** | Apple Disk Image | **Recommended:** Drag-and-drop installer with bundled HTML Install & Trust Guide. |
| **`UpackX-v1.4.0-macOS-Universal.pkg`** | Apple Installer | Secondary installer package with welcome and conclusion screens. |
| **`UpackX-v1.4.0-macOS-Universal.zip`** | Portable ZIP | Standalone `.app` bundle preserving metadata via `ditto`. |
| **`SHA256SUMS.txt`** | Text | Authoritative SHA-256 verification hashes for all release packages. |

#### SHA-256 Checksums
```text
be5777d13acf1220bd6a72bcb2d6ae2582c533bfa793e3f5e200e6596fad0f3a  UpackX-v1.4.0-macOS-Universal.dmg
cd71ad0482d150fa731e48df544a0d3ca17895395e9d702aafdd38709fea1f23  UpackX-v1.4.0-macOS-Universal.pkg
e2c80f878ff1a17569c09afa5178ae5b38c63dd317eb5774b388c48b304b3b57  UpackX-v1.4.0-macOS-Universal.zip
```
*(Digest of `SHA256SUMS.txt`: `44dae67dc0d6891f155df1a1ca77bb6f78789237c45f7e9a81197b1e8161770a`)*

---

### Installation & Trust Instructions (macOS 14 Sonoma & macOS 15 Sequoia+)

#### Tiếng Việt
1. Tải **`UpackX-v1.4.0-macOS-Universal.dmg`** từ trang phát hành chính thức.
2. Mở file DMG và kéo `UpackX.app` vào thư mục `Applications`.
3. Nhấp đúp mở `UpackX.app` từ `/Applications`.
4. Nếu macOS thông báo *"Không thể mở vì Apple không thể kiểm tra phần mềm độc hại"*:
   - Nhấn **Xong** hoặc **Hủy** để đóng hộp thoại.
   - Mở **Cài đặt hệ thống (System Settings)** → chọn **Quyền riêng tư & Bảo mật (Privacy & Security)**.
   - Cuộn xuống mục **Bảo mật (Security)** và nhấn **Vẫn mở (Open Anyway)** cạnh tên UpackX.
   - Nhập mật khẩu máy Mac / Touch ID và xác nhận **Mở (Open)**.
5. Sau lần đầu cấp quyền, UpackX sẽ hoạt động ổn định và tích hợp đầy đủ 4 tác vụ chuột phải trong Finder.

#### English
1. Download **`UpackX-v1.4.0-macOS-Universal.dmg`** from official GitHub Releases.
2. Open the DMG and drag `UpackX.app` into your `Applications` folder.
3. Double-click `UpackX.app` in `/Applications`.
4. If macOS displays *"Apple cannot check it for malicious software"*:
   - Click **Done** or **Cancel** to dismiss the prompt.
   - Open **System Settings** → **Privacy & Security**.
   - Scroll down to the **Security** section and click **Open Anyway** next to UpackX.
   - Enter your Mac credentials / Touch ID and confirm **Open**.
5. Once authorized, UpackX runs normally with native Finder right-click actions enabled.
