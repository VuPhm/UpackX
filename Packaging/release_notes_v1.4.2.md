## UpackX v1.4.2 Beta — Path & Archive Structure Fix (Bản sửa lỗi đường dẫn & cấu trúc nén/giải nén)

**UpackX v1.4.2 Beta** là bản cập nhật sửa lỗi trọng tâm (hotfix release) giải quyết triệt để các vấn đề về xử lý đường dẫn đích, cô lập trạng thái giữa **Giải nén nhanh (Quick Extract)** và **Giải nén… (Extract To)**, ngăn chặn việc tạo thư mục bao ngoài trùng tên (`Folder/Folder/`), đồng thời gia cố toàn diện tính năng nén ZIP và an toàn dữ liệu trên macOS 14 Sonoma & macOS 15 Sequoia+ (**Universal 2**: Apple Silicon `arm64` & Intel `x86_64`).

---

### 1. Các lỗi đã khắc phục triệt để trong bản v1.4.2 Beta

- **Cô lập hoàn toàn trạng thái giữa Giải nén nhanh (Quick Extract) và Giải nén… (Extract To):**
  - Thiết kế cơ chế `ExtractionDestinationMode` gắn trực tiếp vào từng tác vụ (`ExtractionQueueJob`), loại bỏ hoàn toàn biến trạng thái đích dùng chung trước đây.
  - **Quick Extract** luôn giải nén độc lập ngay cạnh file nén gốc (`archiveURL.deletingLastPathComponent()`) và không tạo thư mục bao ngoài, tuyệt đối không bị kế thừa đường dẫn tùy chỉnh (`custom destination`) từ lần giải nén trước đó.
  - Khắc phục lỗi vòng đời cửa sổ khi chuyển từ hộp thoại *Giải nén…* / *Nén…* sang tiến trình xử lý thực tế từ Finder Services.
- **Loại bỏ hiện tượng tạo thư mục bao ngoài hai lần (`Video/Video/`):**
  - Khi **tắt** tùy chọn *Tạo thư mục bao ngoài* (mặc định) hoặc dùng *Giải nén nhanh*: giải nén trực tiếp ra thư mục đích và bảo toàn 100% cấu trúc thư mục thực sự có sẵn bên trong archive (không tự ý thêm wrapper và không tự động flatten thư mục gốc thật).
  - Khi **bật** tùy chọn *Tạo thư mục bao ngoài*: tự động kiểm tra cấu trúc gốc của archive và tên thư mục đích trên cả hai bộ máy `LibarchiveExtractor` và `SevenZipExtractor`. Nếu archive đã có sẵn thư mục gốc tương đương (ví dụ `Video/clip.mp4` trong `Video.zip`), UpackX giữ nguyên một cấp `Video/` thay vì tạo lồng hai lần `Video/Video/`.
  - Xử lý chính xác tên cơ sở (`archiveBaseName`) đối với các định dạng đuôi kép (`.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tgz`) và bộ nén chia phần (`.part1.rar`, `.7z.001`, `.z01`).
- **Chuẩn hóa cơ chế xử lý đường dẫn thống nhất (`PathSecurity`):**
  - Hỗ trợ đồng nhất đường dẫn mặc định, đường dẫn nhập tay, chọn qua `NSOpenPanel`, kéo-thả thư mục và dán từ Clipboard (`Cmd+V` thư mục copy từ Finder, đường dẫn chứa `~`, `file://`, dấu `/` cuối, dấu nháy `"..."`/`'...'`, khoảng trắng thoát `\ ` và Unicode tiếng Việt).
  - Kéo-thả hoặc dán thư mục trực tiếp vào ô nhập đường dẫn sẽ thay thế sạch đường dẫn đích thay vì chèn nối vào giữa chuỗi cũ.
  - Loại bỏ việc rơi ngầm về `currentDirectoryPath` (CWD) khi trường đường dẫn rỗng hoặc nhập đường dẫn tương đối không rõ gốc trong giao diện.
- **Chuẩn hóa tính năng Nén nhanh & Nén… (`ZipCompressor`, `CompressToWindowController`):**
  - Giữ nguyên dấu chấm, khoảng trắng và tiếng Việt trong tên thư mục khi đặt tên file ZIP mặc định (ví dụ: thư mục `Project v1.4.1` tạo đúng `Project v1.4.1.zip`, không bị cắt thành `Project v1.4.zip`).
  - Kiểm tra nghiêm ngặt tên file nén nhập riêng: chặn ký tự phân cấp thư mục (`/`, `\`, `:`), ngăn lỗi nối `.zip.zip` hai lần.
  - Quét và xác thực danh sách nguồn trước khi tạo thư mục đích mới để ngăn lỗi self-inclusion ngay cả khi lưu file ZIP vào một thư mục con mới bên trong chính thư mục nguồn.
  - Khi chính sách xử lý trùng tên là **Bỏ qua (Skip)**: phản ánh đúng trạng thái `wasSkipped`, hiển thị thông báo *"Đã bỏ qua nén file"* / log CLI `"Skipped compression"` thay vì báo thành công giả như vừa tạo archive mới.
- **Tăng cường an toàn dữ liệu, Symlink, Multi-archive & LaunchServices:**
  - Kiểm tra canonical containment theo ranh giới path component và kiểm tra `lstat` trên từng cấp thư mục trung gian nhằm chặn đứng tấn công Zip-Slip qua symlink (`symlink -> /tmp` kèm entry con) hoặc symlink tồn tại sẵn tại đích.
  - Bảo vệ tuyệt đối thư mục dữ liệu hiện có của người dùng khi xảy ra xung đột tên với file giải nén hoặc file ZIP đầu ra.
  - Phân biệt khóa nhóm multipart theo cả đường dẫn thư mục cha và tên cơ sở, đảm bảo các bộ multipart trùng tên ở các thư mục khác nhau được giải nén độc lập.
  - Tự động dọn đăng ký LaunchServices trùng lặp (như bản build tạm trong `build/`), đảm bảo 4 tác vụ Finder Services luôn trỏ duy nhất tới `/Applications/UpackX.app`.

---

### 2. Trạng thái kiểm thử thực tế (Local QA & Regression Suite)

- **Kiểm thử hồi quy tự động (`Scripts/run_tests.sh`):** **88 Passed, 0 Failed, 0 Skipped** (57 nhóm kịch bản bao gồm ZIP, TAR.GZ, 7Z, RAR thực tế có đối chiếu SHA-256, chuỗi thao tác `Extract To A → Quick Extract B → Extract To C`, 4 Finder Services trên `/Applications/UpackX.app`, symlink, Google Drive path, self-inclusion và rollback).
- **Kiểm tra xuất xưởng (`Packaging/release_check.sh`):** **24 Passed, 0 Failed**.
- **Lưu ý về GitHub Actions CI & Phần cứng:** Toàn bộ quá trình biên dịch Universal 2, đóng gói và kiểm thử 88 test case được thực thi và xác minh trực tiếp trên máy macOS local (`x86_64`). Slice `arm64` đã được xác minh kiến trúc Mach-O và linkage hệ thống qua `lipo`/`otool`/`codesign`.

---

### 3. Tải về & Bảng mã băm xác thực SHA-256

| Tệp phát hành | Định dạng | Mô tả |
|---|---|---|
| **`UpackX-v1.4.2-macOS-Universal.dmg`** | Apple Disk Image | **Khuyên dùng:** Kéo thả vào Applications, có kèm hướng dẫn HTML. |
| **`UpackX-v1.4.2-macOS-Universal.pkg`** | Apple Installer | Gói cài đặt có giao diện hướng dẫn từng bước. |
| **`UpackX-v1.4.2-macOS-Universal.zip`** | Portable ZIP | Bản chạy trực tiếp không cần mount đĩa. |
| **`SHA256SUMS.txt`** | Text | Bảng mã băm đối chiếu toàn vẹn tệp tin. |

#### Mã băm SHA-256 (SHA256SUMS):
```text
0532ff7a6d08e01af4386a0cd80aa771434d383837ce1824138e357caa7aee97  UpackX-v1.4.2-macOS-Universal.dmg
efefdb95193649d3f32456ca015d68120010e0130e09f081cd096b701c7a9a53  UpackX-v1.4.2-macOS-Universal.pkg
b7efcfb627d1367407d9a6fb996650dbf6efb34dbb88f416a4c883637ebca97a  UpackX-v1.4.2-macOS-Universal.zip
```

---

### 4. Hướng dẫn cài đặt & Cấp quyền mở lần đầu (macOS 14 Sonoma & macOS 15 Sequoia+)

UpackX là phần mềm phân phối độc lập ngoài Mac App Store (chưa có chứng chỉ Apple Developer ID). macOS Gatekeeper sẽ hiển thị thông báo trong lần đầu mở:

1. Tải và mở tệp **`UpackX-v1.4.2-macOS-Universal.dmg`**.
2. Kéo biểu tượng **`UpackX.app`** vào thư mục **`Applications`**.
3. Vào thư mục `Applications` và nhấp đúp mở `UpackX`.
4. Khi macOS thông báo *"Apple cannot check it for malicious software"* (hoặc *"Không thể mở vì Apple không thể kiểm tra phần mềm độc hại"*):
   - Nhấn **Xong (Done)** hoặc **Hủy (Cancel)** để đóng thông báo.
   - Mở **Cài đặt hệ thống (System Settings)** → chọn **Quyền riêng tư & Bảo mật (Privacy & Security)**.
   - Cuộn xuống mục **Bảo mật (Security)**, tìm dòng thông báo về UpackX và nhấn nút **Vẫn mở (Open Anyway)**.
   - Nhập mật khẩu máy Mac hoặc dùng Touch ID, sau đó bấm **Mở (Open)** để xác nhận.
5. *Trường hợp chưa thấy nút "Vẫn mở":* Hãy mở lại `UpackX` trong `Applications` một lần nữa để macOS ghi nhận, sau đó quay lại phần Quyền riêng tư & Bảo mật để kiểm tra.
6. Sau lần cấp quyền đầu tiên, bạn có thể nhấp chuột phải vào bất kỳ tệp nén hoặc thư mục nào trong Finder để sử dụng 4 thao tác nén/giải nén.
