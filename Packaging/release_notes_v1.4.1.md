## UpackX v1.4.1 Beta — Bản phát hành thử nghiệm đa kiến trúc & Trải nghiệm Trust UX

**UpackX v1.4.1 Beta** là bản phát hành thử nghiệm đầu tiên hỗ trợ kiến trúc **Universal 2** (chạy native trên cả Apple Silicon `arm64` lẫn Intel `x86_64`), chuẩn hóa toàn diện tài liệu theo hướng **Vietnamese-first**, tối ưu hóa bộ lọc tác vụ trong Finder và cung cấp trải nghiệm cấp quyền cài đặt (Trust UX) an toàn cho macOS 14 Sonoma và macOS 15 Sequoia+.

---

### 1. Điểm nổi bật trong bản v1.4.1 Beta

- **Hỗ trợ Universal 2 Native (Apple Silicon & Intel):**
  - Cả ứng dụng chính (`UpackX`) và helper nhúng độc lập (`7zz`) đều là fat Mach-O Universal 2 chứa đủ 2 slice `arm64` và `x86_64`.
  - 100% tự chứa, không yêu cầu cài đặt Homebrew hay bất kỳ thư viện bên thứ ba nào trên máy người dùng.
- **Tài liệu ưu tiên Tiếng Việt (Vietnamese-First):**
  - Toàn bộ hướng dẫn tải về, cài đặt và xử lý Gatekeeper được trình bày bằng tiếng Việt ngay đầu tài liệu. Tài liệu tiếng Anh được tách riêng tại `docs/README.en.md`.
  - Tích hợp tài liệu hướng dẫn HTML (`Hướng Dẫn Cài Đặt (Install Guide).html`) ngay bên trong file DMG để người dùng đọc trước khi cấp quyền.
- **Tối ưu menu chuột phải Finder (NSServices):**
  - Đã tinh chỉnh bộ lọc UTI trong `Info.plist`: menu *Giải nén* chỉ hiển thị khi nhấp vào file nén thực tế (`.zip`, `.7z`, `.rar`, `.tar`, `.gz`, `.bz2`, `.xz`, `.iso`), không hiển thị tràn lan trên tài liệu hay thư mục.
  - Sử dụng API chuẩn `NSUpdateDynamicServices()` của AppKit.
- **Bộ máy cập nhật thông minh (`UpdateManager`):**
  - Tự động nhận diện kiến trúc CPU của máy để tải đúng file DMG tương thích.
  - Xử lý mượt mà cả kênh phát hành Stable và Beta (Prerelease).

---

### 2. Trạng thái kiểm chứng & Giới hạn kỹ thuật

> [!WARNING]
> **Lưu ý kiểm thử phần cứng Apple Silicon:**  
> - **Intel x86_64:** Đã kiểm thử thực tế và đạt 100% (54 test case tự động và 24 tiêu chuẩn xuất xưởng QA PASS).
> - **Apple Silicon arm64:** `Chưa kiểm thử thực tế trên thiết bị`. Slice `arm64` đã được kiểm chứng chuẩn xác về mặt cấu trúc Mach-O, linkage hệ thống qua `lipo` và `otool`, nhưng cần sự phản hồi và xác nhận từ người dùng thực tế trên chip M1/M2/M3/M4.

---

### 3. Tải về & Bảng mã băm xác thực SHA-256

| Tệp phát hành | Định dạng | Mô tả |
|---|---|---|
| **`UpackX-v1.4.1-macOS-Universal.dmg`** | Apple Disk Image | **Khuyên dùng:** Kéo thả vào Applications, có kèm hướng dẫn HTML. |
| **`UpackX-v1.4.1-macOS-Universal.pkg`** | Apple Installer | Gói cài đặt có giao diện hướng dẫn từng bước. |
| **`UpackX-v1.4.1-macOS-Universal.zip`** | Portable ZIP | Bản chạy trực tiếp không cần mount đĩa. |
| **`SHA256SUMS.txt`** | Text | Bảng mã băm đối chiếu toàn vẹn tệp tin. |

#### Mã băm SHA-256 (SHA256SUMS):
```text
4acb6a71259182ffbb51aa19b836bb2e049dc4574af09ee2a61b3d88ed8bf4bf  UpackX-v1.4.1-macOS-Universal.dmg
2bbd8666b429a73b3869d9a677145a117e5e8a8c3db35602e418b343b738bc9e  UpackX-v1.4.1-macOS-Universal.pkg
f8bced0671101180b701acb49b806ef821fa0d390bfa07f67571d2d791eac9f1  UpackX-v1.4.1-macOS-Universal.zip
```

---

### 4. Hướng dẫn cài đặt & Cấp quyền mở lần đầu (macOS 14 Sonoma & macOS 15 Sequoia+)

UpackX là phần mềm phân phối độc lập ngoài Mac App Store (chưa có chứng chỉ Apple Developer ID). macOS Gatekeeper sẽ hiển thị thông báo trong lần đầu mở:

1. Tải và mở tệp **`UpackX-v1.4.1-macOS-Universal.dmg`**.
2. Kéo biểu tượng **`UpackX.app`** vào thư mục **`Applications`**.
3. Vào thư mục `Applications` và nhấp đúp mở `UpackX`.
4. Khi macOS thông báo *"Apple cannot check it for malicious software"* (hoặc *"Không thể mở vì Apple không thể kiểm tra phần mềm độc hại"*):
   - Nhấn **Xong (Done)** hoặc **Hủy (Cancel)** để đóng thông báo.
   - Mở **Cài đặt hệ thống (System Settings)** → chọn **Quyền riêng tư & Bảo mật (Privacy & Security)**.
   - Cuộn xuống mục **Bảo mật (Security)**, tìm dòng thông báo về UpackX và nhấn nút **Vẫn mở (Open Anyway)**.
   - Nhập mật khẩu máy Mac hoặc dùng Touch ID, sau đó bấm **Mở (Open)** để xác nhận.
5. *Trường hợp chưa thấy nút "Vẫn mở":* Hãy mở lại `UpackX` trong `Applications` một lần nữa để macOS ghi nhận, sau đó quay lại phần Quyền riêng tư & Bảo mật để kiểm tra.
6. Sau lần cấp quyền đầu tiên, bạn có thể nhấp chuột phải vào bất kỳ tệp nén hoặc thư mục nào trong Finder để sử dụng 4 thao tác nén/giải nén.
