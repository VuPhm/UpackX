# UpackX v1.2.0 — Lightweight macOS Archive Extractor (Intel x86_64)

**UpackX** là ứng dụng giải nén native siêu nhẹ, ổn định dành riêng cho **MacBook Intel (x86_64)**, tích hợp trực tiếp vào menu chuột phải Finder của macOS (Sonoma 14+), hỗ trợ đầy đủ archive nhiều phần (Multipart), bảo vệ thư mục mount Google Drive for Desktop và sở hữu icon phong cách macOS hiện đại.

---

## 1. Điểm nổi bật & Thống kê kỹ thuật

| Tiêu chí | UpackX v1.2.0 | Ứng dụng thông thường (Electron / Java / GUI nặng) |
|---|---|---|
| **Dung lượng file thực thi** | **438 KB** (Mã máy native x86_64 tối ưu `-O`) | > 80 – 150 MB |
| **Dung lượng toàn bộ .app** | **3.4 MB** (Đã đóng gói standalone `7zz` + Full `.icns` đa kích thước) | > 150 – 300 MB |
| **Mức tiêu thụ RAM (RSS)** | **~12.5 – 27.3 MB** khi stream giải nén 120 MB – 500 MB | > 200 – 500 MB |
| **Phụ thuộc bên ngoài** | **0% (Không cần Homebrew)**, chạy độc lập trên máy đích | Cần runtime, Node.js, thư viện phụ trợ |
| **Tiến trình nền (Daemon)** | **Không có** (Zero daemon, hoàn tất tác vụ là thoát sạch) | Chạy ngầm tốn RAM và hao pin |
| **Công nghệ** | Swift 6 + AppKit + system `libarchive.2.dylib` + `7zz` | WebKit / Chromium |
| **Cơ chế Finder Menu** | **Native Cocoa NSServices** (Duy nhất 1 cơ chế, 0 trùng lặp) | Tiện ích mở rộng hoặc daemon nền |
| **Hệ điều hành tối thiểu** | macOS 14.0 Sonoma (x86_64) | Đa dạng nhưng cồng kềnh |

---

## 2. Giải quyết triệt để vấn đề 4 mục Finder bị trùng

### 2.1. Điều tra nguồn gốc 4 mục menu chuột phải cũ
Trước phiên bản 1.2, khi chuột phải vào file nén trong Finder xuất hiện 4 tùy chọn liên quan đến UpackX do tồn tại song song hai cơ chế đăng ký có cùng tên hiển thị:
1. **Mục 1:** `UpackX - Giải nén nhanh.workflow` trong `~/Library/Services` (đăng ký qua Automator Quick Actions).
2. **Mục 2:** `UpackX - Giải nén….workflow` trong `~/Library/Services` (đăng ký qua Automator Quick Actions).
3. **Mục 3:** `quickExtractService` ("Giải nén nhanh với UpackX") trong `Info.plist` của `/Applications/UpackX.app` (Native Cocoa `NSServices`).
4. **Mục 4:** `extractToService` ("Giải nén… với UpackX") trong `Info.plist` của `/Applications/UpackX.app` (Native Cocoa `NSServices`).
Đồng thời, LaunchServices còn giữ bản index của cả bản debug `build/UpackX.app` và bản cài đặt `/Applications/UpackX.app`.

### 2.2. Chọn duy nhất một cơ chế: Native Cocoa NSServices
UpackX v1.2 đã chuyển đổi toàn bộ sang **Native Cocoa NSServices**:
- Xóa sạch toàn bộ các bundle workflow cũ trong `~/Library/Services/`.
- Hủy đăng ký bản build trung gian khỏi LaunchServices (`lsregister -u`).
- Khởi tạo đúng 2 endpoint trong `Info.plist` và kích hoạt tự động qua `pbs` (Pasteboard Server):
  - **Giải nén nhanh với UpackX** (`quickExtractService`): Giải nén ngay cạnh archive, không tạo thư mục bao ngoài, không mở cấu hình.
  - **Giải nén… với UpackX** (`extractToService`): Mở hộp thoại native chọn thư mục đích và tùy chỉnh xung đột.
- Đảm bảo Finder chỉ hiển thị đúng **2 mục duy nhất**, không chạy daemon nền, không cần Automator runner.

---

## 3. Minimal App Icon (Thiết kế Native macOS)

UpackX v1.2 được tích hợp bộ nhận diện icon ứng dụng hoàn toàn mới:
- **Ý tưởng:** Một hộp lưu trữ tối giản đang mở với đường khóa kéo / đường tách tinh tế ở giữa và mũi tên thăng hoa, gợi trực tiếp hành động giải nén dữ liệu.
- **Màu sắc & Chất liệu:** Nền graphite / xanh xám đậm (`#13161C` đến `#282F3B`) với viền specular tinh xảo chuẩn squircle macOS; thân hộp bằng màu xám bạc neutral bạch kim và điểm nhấn cyan điện quang (`#38BDF8`).
- **Tập tin nguồn vector:** `Resources/AppIcon.svg`.
- **Đầy đủ kích thước hệ thống:** Được render vector và biên dịch qua `iconutil` thành `Resources/AppIcon.icns` với 10 độ phân giải (16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024 cả chuẩn 1x và Retina 2x), nhận diện sắc nét trên Dock, Finder, Spotlight và Launchpad.

---

## 4. Các tính năng cốt lõi & Cải tiến ổn định

### 4.1. Giải nén nhanh (Quick Extract)
* Giải nén ngay tại thư mục chứa file nén.
* Không tạo thư mục bao ngoài (No extra enclosing folder).
* HUD tiến trình thanh lịch với thanh đo phần trăm, tốc độ stream (MB/s) và nút Hủy an toàn.

### 4.2. Giải nén… (Extract To...)
* Hộp thoại native AppKit nổi phía trước (`NSWindow.level = .floating`).
* Lựa chọn thư mục đích linh hoạt qua sheet native.
* Tùy chọn tạo thư mục bao ngoài (mặc định tắt theo chuẩn macOS).
* Chính sách xử lý xung đột: *Hỏi khi trùng* (mặc định), *Bỏ qua*, *Tự động đổi tên*, *Ghi đè*.

### 4.3. Bảo vệ thư mục & Nhập an toàn (Safe Directory Merge)
* Khi giải nén vào thư mục đã tồn tại (đặc biệt trên Google Drive for Desktop): UpackX **bảo tồn nguyên vẹn thư mục đích**, an toàn nhập (merge) các file con vào trong mà tuyệt đối không xóa hay thay thế toàn bộ thư mục cha.
* Trường hợp file trùng, UpackX xử lý theo từng file độc lập.

### 4.4. Xử lý file nén có mật khẩu (Password Prompting)
* Tự động phát hiện archive mã hóa (ZIP AES, RAR, 7Z).
* Hiển thị hộp thoại AppKit `PasswordDialog` yêu cầu nhập mật khẩu thay vì báo lỗi đột ngột.
* Tự động giải nén lại với mật khẩu đã cung cấp.

### 4.5. Nút "Xem trong Finder" (Show in Finder)
* Sau khi giải nén thành công, thông báo hệ thống của macOS hiển thị action button **"Xem trong Finder"**.
* Người dùng click vào thông báo hoặc nút action, Finder lập tức mở và làm nổi bật (highlight) thư mục đích vừa giải nén.

### 4.6. Archive nhiều phần (Multipart Volumes)
* Hỗ trợ đầy đủ `.7z.001`, `.part1.rar`, `.z01`, `.r00`...
* Tự động nhóm volume: chọn bất kỳ part nào (vd `.003`) cũng tự tìm và kích hoạt từ part đầu (`.001`).
* Khử trùng lặp: chọn nhiều volume cùng lúc chỉ sinh đúng 1 tác vụ.
* Quét toàn vẹn: từ chối giải nén và báo lỗi rõ ràng nếu thiếu bất kỳ volume nào.

### 4.7. Tương thích Google Drive for Desktop
* Nhận diện mount Google Drive (`/Library/CloudStorage/GoogleDrive-...` hoặc `/Volumes/GoogleDrive`).
* Phát hiện cờ `SF_DATALESS` của macOS File Provider: cảnh báo file placeholder chưa tải về máy.
* Fallback non-atomic rename cho các phân vùng ảo.
* Phân biệt rõ thông báo ghi cục bộ và đồng bộ đám mây.

---

## 5. Hướng dẫn Quản trị & Cài đặt

### Các lệnh Makefile:

```bash
# 1. Biên dịch bản Release x86_64 kèm icon:
make build

# 2. Cài đặt vào /Applications và kích hoạt Services:
make install

# 3. Clean Reinstall (Gỡ sạch bản cũ, dọn workflow, build & cài bản mới):
make reinstall

# 4. Gỡ cài đặt hoàn toàn khỏi hệ thống (Idempotent):
make uninstall

# 5. Chạy toàn bộ 22 bài kiểm thử chất lượng:
make test
```

### Sử dụng qua dòng lệnh (CLI):
```bash
# Giải nén nhanh tại chỗ:
upackx --quick /path/to/archive.zip

# Mở hộp thoại tùy chọn:
upackx --extract-to /path/to/archive.7z

# Giải nén với chính sách trùng file:
upackx --quick --rename /path/to/archive.zip
upackx --quick --skip /path/to/archive.zip
upackx --quick --overwrite /path/to/archive.zip

# Kích hoạt lại Finder Services:
upackx --install-services
```

---

## 6. Kết quả kiểm thử thực tế (Test Suite)

Bộ kiểm thử tự động `make test` đạt kết quả **22/22 Tests Passed (100%)**:

1. **Test 1 — Định dạng cơ bản & Unicode Tiếng Việt:** ZIP, TAR.GZ bảo toàn nguyên vẹn tên tiếng Việt có dấu.
2. **Test 2 — Thư mục lồng 10 cấp:** Tái hiện chính xác cấu trúc sâu.
3. **Test 3 — An toàn xung đột file:** Tuyệt đối không ghi đè âm thầm, hỗ trợ tự sinh bản sao `(1)`.
4. **Test 4 — Chống Zip-Slip:** Chặn đứng nỗ lực giải nén thoát khỏi thư mục đích (`../../`).
5. **Test 5 — Phát hiện file hỏng:** Dữ liệu rác bị từ chối với exit code khác 0.
6. **Test 6 — Nhận diện nhóm volume Multipart:** Phân tích đúng 3 bộ volume độc lập, gom part về primary volume.
7. **Test 7 — Benchmark file 120 MB:** RAM đỉnh chỉ đạt **27.0 MB**.
8. **Test 8 — Finder Native Services:** Xác minh 0 workflow thừa trong `~/Library/Services` và `Info.plist` khai báo đúng 2 Cocoa NSServices.
9. **Test 9 — File nén có mật khẩu:** Bắt buộc mật khẩu, từ chối giải nén khi thiếu mật khẩu.
10. **Test 10 — Hàng đợi nhiều archive:** Xử lý tuần tự an toàn không lỗi.
11. **Test 11 — Hủy giữa chừng:** Dọn sạch 100% file tạm `.upackx_part`, không để lại rác trên ổ cứng.
12. **Test 12 — Benchmark file lớn 500 MB:** RAM đỉnh chỉ **27.1 MB** với cơ chế stream bộ nhớ cố định.
13. **Test 13 — Thực thi Native NSService thực tế:** `NSPerformService("Giải nén nhanh với UpackX")` giải nén đúng thư mục chứa archive không sinh thư mục bao ngoài.
14. **Test 14 — Giải nén Multipart thực tế (.7z.001 - .004):** Chọn part 3, giải nén hoàn chỉnh byte-for-byte khớp 100% file gốc.
15. **Test 15 — Từ chối Multipart thiếu volume:** Phát hiện thiếu volume `.002`, từ chối giải nén và báo lỗi chi tiết.
16. **Test 16 — Google Drive Mount:** Giải nén trực tiếp vào `My Drive/Project/` không sinh thư mục lồng.
17. **Test 17 — Safe Directory Merge:** Nhập nội dung vào thư mục đã có mà không xóa hay thay thế toàn bộ thư mục.
18. **Test 18 — Minimal AppIcon Bundle:** Xác minh `AppIcon.icns` đa kích thước và vector gốc `AppIcon.svg`.
19. **Test 19 — Script Reinstall & Uninstall:** Kiểm tra tính sẵn sàng và tính thực thi của các script bảo trì.
