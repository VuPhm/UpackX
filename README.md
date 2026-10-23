# UpackX — Lightweight macOS Archive Extractor (Intel x86_64)

**UpackX** là ứng dụng giải nén native siêu nhẹ, ổn định dành riêng cho **MacBook Intel (x86_64)**, tích hợp trực tiếp vào menu chuột phải trong Finder của macOS (Sonoma 14+ / Ventura 13+).

---

## 1. Điểm nổi bật & Thống kê kỹ thuật

| Tiêu chí | UpackX | Ứng dụng thông thường (Electron / Java / GUI nặng) |
|---|---|---|
| **Dung lượng file thực thi** | **371 KB** (Mã máy native x86_64 tối ưu hoá `-O`) | > 80 – 150 MB |
| **Dung lượng toàn bộ .app** | **2.7 MB** (Đã đóng gói standalone `7zz` độc lập) | > 150 – 300 MB |
| **Mức tiêu thụ RAM (RSS)** | **~12.6 – 12.9 MB** khi giải nén file 120 MB – 500 MB | > 200 – 500 MB |
| **Phụ thuộc bên ngoài** | **0% (Không cần Homebrew)**, chạy ngay trên máy người dùng | Yêu cầu runtime, node_modules |
| **Tiến trình nền (Daemon)** | **Không có** (Không chạy thường trú, đóng app là tắt sạch) | Nhiều daemon ngốn pin |
| **Công nghệ** | Swift 6 + AppKit + system `libarchive.2.dylib` + `7zz` | WebKit / Chromium |

---

## 2. Tích hợp Finder (Menu chuột phải)

Sau khi cài đặt, khi chuột phải vào bất kỳ file nén nào (`.zip`, `.7z`, `.rar`, `.tar.gz`, v.v.) trong Finder, người dùng có 2 thao tác nhanh:

### A. Giải nén nhanh (Quick Extract)
* **Đích giải nén:** Giải nén ngay tại thư mục hiện tại chứa file nén.
* **Không tạo thư mục bao ngoài:** Giải nén thẳng vào thư mục hiện tại, giữ nguyên 100% cấu trúc thư mục con vốn có bên trong archive.
* **Không mở cửa sổ cấu hình:** Bắt đầu giải nén ngay tức thì.
* **An toàn xung đột:** Tuyệt đối không âm thầm ghi đè file hiện có. Nếu phát hiện file trùng tên, ứng dụng tự động bảo toàn file cũ và tạo bản sao an toàn (hoặc hỏi người dùng trong chế độ GUI).

### B. Giải nén… (Extract To...)
* Mở một hộp thoại nhỏ, thanh lịch:
  * **Thư mục đích:** Xem và chọn thư mục bất kỳ với nút duyệt thư mục trực quan.
  * **Tạo thư mục bao ngoài (`/<tên_file>`):** Mặc định **OFF** (tắt) theo yêu cầu.
  * **Chính sách xử lý file trùng:** Chọn giữa *Hỏi khi trùng*, *Bỏ qua file trùng*, *Tự động đổi tên (Giữ cả hai)*, hoặc *Ghi đè file cũ*.
  * **Hiển thị thông tin archive:** Xem nhanh định dạng nén, tổng dung lượng sau giải nén, số lượng file, trạng thái có mật khẩu.

---

## 3. Kiến trúc Engine giải nén (Streaming)

* **Engine chính — Native `LibarchiveExtractor`:**
  * Sử dụng trực tiếp dynamic library `/usr/lib/libarchive.2.dylib` có sẵn trong macOS.
  * Cơ chế streaming khối (chunked stream `32KB – 64KB` qua `archive_read_data_block`), **không bao giờ nạp toàn bộ archive vào RAM**.
  * Hỗ trợ file nén hàng chục GB mà RAM vẫn giữ nguyên mức ~12 – 15 MB.
* **Engine phụ trợ — Bundled `SevenZipExtractor`:**
  * Đóng gói sẵn binary độc lập `7zz` (chỉ link với system `libc++`), giải quyết các file nén RAR5/7Z có thuật toán phức tạp hoặc khối nén Solid.
  * Tự động điều hướng mà không cần cài đặt thêm bất kỳ gói Homebrew nào trên máy đích.
* **Bảo mật tuyệt đối:**
  * **Chống Zip-Slip & Path Traversal:** Module `PathSecurity` phân tích chuẩn hoá đường dẫn, loại bỏ mọi nỗ lực thoát khỏi thư mục giải nén (`../../`, đường dẫn tuyệt đối, ký tự null `\0`).
  * **Ghi file an toàn & Hủy sạch sẽ:** Dữ liệu giải nén được ghi vào file tạm ẩn `.<filename>.<uuid>.upackx_part` trước khi atomically rename sang file chính thức. Nếu người dùng nhấn **Hủy** (Cancel) hoặc gặp lỗi, toàn bộ file tạm được dọn sạch, tuyệt đối không làm hỏng hay xóa dữ liệu cũ đã tồn tại, và **không bao giờ báo thành công giả tạo** khi chỉ giải nén dở dang.

---

## 4. Hướng dẫn Build & Cài đặt

### Yêu cầu môi trường build:
* Máy Mac Intel (x86_64) hoặc Apple Silicon (hỗ trợ biên dịch `-target x86_64-apple-macos14.0`).
* Xcode Command Line Tools (`swiftc`, `clang`).

### Lệnh build và cài đặt nhanh:

```bash
# 1. Clone hoặc di chuyển vào thư mục project
cd /Users/vup/Documents/agy/upackx

# 2. Biên dịch UpackX.app
make

# 3. Cài đặt vào /Applications và kích hoạt Finder Quick Actions
make install

# 4. Chạy toàn bộ test suite kiểm tra chất lượng
make test
```

### Sử dụng qua Terminal (CLI):
```bash
# Giải nén nhanh tại chỗ:
upackx --quick /path/to/archive.zip

# Mở hộp thoại chọn thư mục và tùy chọn:
upackx --extract-to /path/to/archive.7z

# Giải nén với chính sách trùng tên xác định:
upackx --quick --skip /path/to/archive.tar.gz
upackx --quick --overwrite /path/to/archive.rar

# Cài đặt hoặc làm mới Finder Quick Actions:
upackx --install-services
```

---

## 5. Kết quả kiểm thử thực tế (Test Suite)

Chạy tự động qua `make test` (17/17 test cases Passed):

1. **Test 1 — Định dạng cơ bản & Tiếng Việt:** ZIP, TAR.GZ, 7Z, RAR giải nén chính xác 100%, bảo toàn nguyên vẹn tên file tiếng Việt có dấu Unicode (`Tiếng Việt có dấu - Đồ án tốt nghiệp.txt`).
2. **Test 2 — Thư mục nhiều cấp:** Cấu trúc thư mục 10 cấp lồng nhau được tái hiện chuẩn xác.
3. **Test 3 — Xử lý xung đột file an toàn:** File ban đầu chứa dữ liệu gốc `ORIGINAL USER DATA` không bao giờ bị ghi đè âm thầm. Bản sao được tự động đánh số `(1)` an toàn.
4. **Test 4 — Chống Zip-Slip:** File archive chứa đường dẫn `../../evil_slip.txt` bị chặn đứng ngay lập tức, không thoát ra ngoài thư mục đích.
5. **Test 5 — Phát hiện file hỏng:** Archive chứa byte rác ngẫu nhiên bị từ chối với mã lỗi khác 0 và thông báo rõ ràng.
6. **Test 6 — Nhận diện archive nhiều phần (Stage 2):** Nhóm chuẩn xác `movie.part1.rar` (3 phần) và `dataset.7z.001` (2 phần), chỉ đưa phần đầu vào hàng đợi giải nén.
7. **Test 7 — Benchmark file 120 MB:** RAM đỉnh chỉ đạt **12.6 MB**.
8. **Test 8 — Tích hợp Finder Quick Actions:** Cài đặt đầy đủ `document.wflow` và `Info.plist` vào `~/Library/Services/`.
9. **Test 9 — File nén có mật khẩu:** Bắt buộc nhập mật khẩu, từ chối giải nén nếu không có passphrase.
10. **Test 10 — Giải nén hàng loạt:** Nhiều archive được chọn cùng lúc đều được giải nén tuần tự an toàn.
11. **Test 11 — Hủy giữa chừng:** Không để lại bất kỳ file rác `*.upackx_part` nào trên ổ cứng.
12. **Test 12 — Benchmark file lớn 500 MB:** RAM đỉnh chỉ **12.9 MB** trong toàn bộ quá trình stream.

---

## 6. Sẵn sàng cho Giai đoạn 2 (Multipart Archives + Google Drive)

Kiến trúc mã nguồn đã được tách lớp sẵn sàng:
1. **`MultipartDetector.swift`:** Đã hiện thực giải thuật phân tích regex cho `.partN.rar`, `.7z.00N`, `.z0N`, gom nhóm volume và chỉ gọi giải nén từ primary volume.
2. **Google Drive Mount:** Hỗ trợ nhận diện đường dẫn mount của Google Drive for Desktop (`/Volumes/GoogleDrive` hoặc `~/Library/CloudStorage/GoogleDrive-...`). Khi người dùng chọn giải nén trong thư mục Google Drive, UpackX tự động sử dụng chính thư mục đó làm đích mặc định, thực hiện hàng đợi batch và xác nhận trước khi thao tác.
