# UpackX — Ứng dụng nén & giải nén native siêu nhẹ cho macOS

[![Release](https://img.shields.io/badge/release-v1.4.1--beta-blue.svg)](https://github.com/VuPhm/UpackX/releases)
[![Platform](https://img.shields.io/badge/nền_tảng-macOS%2014.0%2B%20%7C%20Universal%202-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/kiến_trúc-Apple%20Silicon%20%7C%20Intel-orange.svg)]()
[![License](https://img.shields.io/badge/giấy_phép-Proprietary%20%2F%20BSD%20Notices-lightgrey.svg)](THIRD_PARTY_NOTICES.md)

*Tài liệu Tiếng Việt (Mặc định) • [English Documentation in docs/README.en.md](docs/README.en.md)*

**UpackX** là ứng dụng native siêu nhẹ, hiệu năng cao phục vụ nhu cầu **Nén và Giải nén** trên macOS 14 Sonoma và macOS 15 Sequoia+. Ứng dụng chạy native trên cả **Apple Silicon (`arm64`)** lẫn **Intel (`x86_64`)** thông qua định dạng Universal 2, tích hợp 4 tác vụ trực tiếp vào menu chuột phải của Finder và tuyệt đối không có tiến trình chạy ngầm (zero daemons).

---

## 1. Tải về & Cài đặt nhanh

Bản phát hành chính thức được đóng gói sẵn tại trang [GitHub Releases](https://github.com/VuPhm/UpackX/releases):

| Tệp cài đặt | Định dạng | Mô tả |
|---|---|---|
| **[`UpackX-v1.4.1-macOS-Universal.dmg`](https://github.com/VuPhm/UpackX/releases/download/v1.4.1/UpackX-v1.4.1-macOS-Universal.dmg)** | **Apple Disk Image** | **Khuyên dùng:** Kéo thả vào Applications, có kèm sẵn hướng dẫn cài đặt HTML. |
| **`UpackX-v1.4.1-macOS-Universal.pkg`** | Apple Installer | Bộ cài đặt có giao diện hướng dẫn từng bước. |
| **`UpackX-v1.4.1-macOS-Universal.zip`** | Portable ZIP | Bản chạy trực tiếp không cần mount đĩa. |
| **`SHA256SUMS.txt`** | Text | Mã băm kiểm tra tính toàn vẹn của tệp cài đặt. |

### Các bước cài đặt:
1. Tải tệp **`UpackX-v1.4.1-macOS-Universal.dmg`**.
2. Nhấp đúp mở file `.dmg`, kéo biểu tượng **`UpackX.app`** vào lối tắt thư mục **`Applications`**.
3. Vào `Applications` và mở `UpackX` lần đầu tiên.

---

## 2. Hướng dẫn cấp quyền mở lần đầu (Gatekeeper Trust UX)

UpackX là phần mềm phân phối độc lập bên ngoài Mac App Store và chưa tham gia chương trình thu phí chứng chỉ Apple Developer ID ($99/năm). Ứng dụng được ký số ad-hoc hợp lệ nhưng macOS Gatekeeper sẽ hiển thị thông báo bảo vệ trong lần đầu mở:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       QUY TRÌNH CẤP QUYỀN TRÊN MACOS                        │
│            (macOS 14 Sonoma, macOS 15 Sequoia và các bản mới hơn)           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Nhấp đúp mở UpackX trong thư mục Applications.                          │
│                                                                             │
│  2. Khi xuất hiện cảnh báo "Apple cannot check it for malicious software"   │
│     (hoặc "Không thể mở vì Apple không thể kiểm tra phần mềm độc hại"):     │
│     👉 Nhấn [Xong] (Done) hoặc [Hủy] (Cancel) để đóng thông báo.            │
│                                                                             │
│  3. Mở Cài đặt hệ thống (System Settings) trên máy Mac của bạn.             │
│                                                                             │
│  4. Chọn mục Quyền riêng tư & Bảo mật (Privacy & Security).                 │
│                                                                             │
│  5. Cuộn xuống phần Bảo mật (Security), tìm dòng thông báo về UpackX:       │
│     👉 Nhấn nút [Vẫn mở] (Open Anyway).                                     │
│                                                                             │
│  6. Nhập mật khẩu máy Mac hoặc chạm Touch ID, sau đó bấm [Mở] (Open).       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

> [!TIP]
> **Xử lý khi chưa thấy nút "Vẫn mở" (Open Anyway) trong Cài đặt hệ thống:**  
> macOS chỉ hiển thị nút này sau khi phát hiện bạn đã cố gắng mở ứng dụng ít nhất một lần. Nếu chưa thấy, hãy quay lại thư mục `/Applications`, nhấp đúp vào `UpackX.app` một lần nữa để máy ghi nhận, sau đó quay lại phần *Quyền riêng tư & Bảo mật* để nhấn *Vẫn mở*.

### 🛡️ Phân biệt cảnh báo an toàn & Cảnh báo nguy hiểm
- ℹ️ **Cảnh báo Nhà phát triển chưa xác định (HOÀN TOÀN BÌNH THƯỜNG):**  
  *Thông báo:* `"Apple cannot check it for malicious software"` hoặc `"Nhà phát triển chưa được xác minh"`.  
  Đây là cơ chế mặc định của Apple khi ứng dụng chưa mua chứng chỉ Apple Developer ID thường niên. Bạn an tâm cấp quyền theo hướng dẫn trên nếu đã tải từ GitHub chính thức.
- ⛔ **Cảnh báo TỆP BỊ HỎNG hoặc ĐỘC HẠI (TUYỆT ĐỐI KHÔNG CẤP QUYỀN):**  
  *Thông báo:* `"UpackX is damaged and can't be opened"` (Ứng dụng bị hỏng) hoặc `"App will damage your computer"` (Ứng dụng sẽ gây hại cho máy tính).  
  Cảnh báo này xuất hiện khi file tải về bị đứt đoạn hoặc đã bị can thiệp trái phép. **Tuyệt đối không tìm cách vượt qua cảnh báo này!** Hãy xóa file và tải lại từ GitHub Releases chính thức.

> [!IMPORTANT]
> **Cam kết bảo mật của UpackX:**  
> - Không yêu cầu người dùng phải gõ lệnh Terminal hay tắt Gatekeeper (`spctl --master-disable`).  
> - Không tự ý xóa thuộc tính kiểm dịch quarantine bằng `xattr`.  
> - Không yêu cầu quyền quản trị viên (`sudo` / `root`).  
> - Không có bất kỳ tiến trình chạy ngầm nào (zero background daemons).

---

## 3. Cách sử dụng từ Menu chuột phải trong Finder

Sau khi mở lần đầu thành công, UpackX tự động đăng ký **4 tác vụ native** trong menu chuột phải của Finder:

1. **Giải nén nhanh với UpackX:** Giải nén ngay lập tức bên cạnh file gốc, không tạo thư mục lồng nhau thừa thãi.
2. **Giải nén… với UpackX:** Mở cửa sổ tùy chọn cho phép chọn thư mục đích, quy tắc giải quyết trùng lặp (Bỏ qua, Đổi tên thành copy `(1)`, Ghi đè) và nhập mật khẩu.
3. **Nén nhanh với UpackX:** Nén nhanh các file hoặc thư mục đã chọn thành file `.zip` tại chỗ.
4. **Nén… với UpackX:** Mở cửa sổ tùy chọn đặt tên archive, chọn thư mục lưu, mức độ nén (Nhanh, Tiêu chuẩn, Tối đa) và xem trước dung lượng nguồn.

*Ghi chú: Menu giải nén được lọc thông minh bằng UTI (`Info.plist`), chỉ xuất hiện trên các file nén được hỗ trợ (`.zip`, `.7z`, `.rar`, `.tar`, `.gz`, `.bz2`, `.xz`, `.iso`), không gây rối mắt trên các file văn bản, ảnh hoặc thư mục thông thường.*

---

## 4. Giao diện chính & Thông số kỹ thuật

```text
  ┌──────────────────────────────────────────────────────────────┐
  │  ● ● ●   UpackX — Native macOS Extractor & Compressor        │
  ├──────────────────────────────────────────────────────────────┤
  │                                                              │
  │     ┌──────────────────────────────────────────────────┐     │
  │     │                                                  │     │
  │     │                    [📦]                          │     │
  │     │                                                  │     │
  │     │      Kéo thả file nén hoặc thư mục vào đây       │     │
  │     │                                                  │     │
  │     └──────────────────────────────────────────────────┘     │
  │                                                              │
  │   Finder Services: Sẵn sàng (4 mục: 2 nén, 2 giải nén)       │
  │                                                              │
  │    [ Chọn file giải nén... ]     [ Chọn mục nén... ]         │
  │                                                              │
  │                [ Kiểm tra Finder Services ]                  │
  └──────────────────────────────────────────────────────────────┘
```

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BẢNG THÔNG SỐ KỸ THUẬT UPACKX v1.4.1                     │
├────────────────────────────────┬────────────────────────────────────────────┤
│ Kiến trúc nhị phân             │ Universal 2 (Chạy native Apple Silicon &   │
│                                │ Intel x86_64, không cần Rosetta)           │
│ Kích thước tệp thực thi        │ ~1.6 MB (Fat Mach-O universal binary)      │
│ Dung lượng toàn bộ Bundle .app │ ~13 MB (Đã bao gồm helper 7zz độc lập)     │
│ Mức chiếm dụng RAM (Peak RSS)  │ ~13 – 28 MB duy trì ổn định khi streaming  │
│ Tiến trình chạy ngầm (Daemons) │ 0 (Thoát hoàn toàn sau khi xong tác vụ)     │
│ Thư viện bên ngoài             │ Không (100% tự chứa, không cần Homebrew)   │
│ Yêu cầu hệ điều hành tối thiểu │ macOS 14.0 Sonoma (hỗ trợ cả Sequoia 15+)   │
└────────────────────────────────┴────────────────────────────────────────────┘
```

---

## 5. Bảng định dạng lưu trữ được hỗ trợ

| Định dạng | Phần mở rộng | Giải nén | Nén | Ghi chú kỹ thuật |
|---|---|---|---|---|
| **ZIP** | `.zip`, `.zipx`, `.jar` | Native `libarchive` | Native `libarchive` (Mức 1–9) | Bảo toàn thuộc tính, không lỗi font tiếng Việt |
| **7-Zip** | `.7z` | Helper `7zz` Universal | Sắp ra mắt | Hỗ trợ nén solid và mã hóa AES |
| **RAR** | `.rar`, `.cbr` | Helper `7zz` Universal | Không áp dụng | Hỗ trợ RAR4 và RAR5 |
| **Tarball** | `.tar`, `.tar.gz`, `.tgz` | Native `libarchive` | Sắp ra mắt | Hỗ trợ định dạng chuẩn POSIX |
| **BZip2** | `.bz2`, `.tar.bz2` | Native `libarchive` | Sắp ra mắt | Streaming dung lượng lớn |
| **XZ** | `.xz`, `.tar.xz` | Native `libarchive` | Sắp ra mắt | Tỉ lệ nén cao |
| **Phân mảnh** | `.part1.rar`, `.7z.001` | Nhận diện tự động | Sắp ra mắt | Tự động ghép nối các volume |

---

## 6. Yêu cầu hệ thống

- **Bộ vi xử lý:** Apple Silicon (`arm64`: M1, M2, M3, M4) hoặc Intel (`x86_64`).
- **Hệ điều hành:** macOS 14.0 Sonoma trở lên (tương thích hoàn toàn macOS 15 Sequoia).
- **Phụ thuộc:** Không yêu cầu cài đặt Homebrew, Xcode hay công cụ dòng lệnh nào.

---

## 7. Cập nhật & Gỡ cài đặt sạch sẽ

### Kiểm tra bản cập nhật mới
- Trong giao diện chính của ứng dụng, nhấn nút **Kiểm tra bản cập nhật** (Check for Updates).
- Hoặc chạy lệnh kiểm tra qua CLI: `upackx --check-update`.
- Bộ máy cập nhật của UpackX tự động so khớp kiến trúc chip của bạn để tải đúng bản cài đặt tương thích nhất.

### Gỡ cài đặt sạch sẽ (Clean Uninstall)
Nếu bạn không còn nhu cầu sử dụng, việc gỡ bỏ hoàn toàn an toàn và không để lại tệp rác:
1. Thoát UpackX nếu đang mở.
2. Kéo `UpackX.app` từ `/Applications` vào Thùng rác (Trash).
3. Làm sạch Thùng rác. Các dịch vụ trong Finder sẽ tự động biến mất theo cơ chế quản lý vòng đời của macOS LaunchServices.

---

## 8. Tài liệu tiếng Anh (English Documentation)

To read this documentation in English, please visit [docs/README.en.md](docs/README.en.md).
