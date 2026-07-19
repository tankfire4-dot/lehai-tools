# LeHai Tools — Unified SketchUp Plugin

## Khởi động session

Đọc `C:\Users\tankf\.claude\profile\PROFILE.md` và các file liên quan trước khi làm việc.
Cập nhật profile nếu có thông tin mới đáng lưu trong session này.
Sau khi cập nhật bất kỳ file nào trong profile, chạy luôn: `cd C:\Users\tankf\.claude\profile && git add . && git commit -m "update: <nội dung>" && git push`

## Cách làm việc

- Xưng hô: **ông** (Claude) / **tôi** (Khoa) — luôn luôn
- Giải thích như báo cáo cho sếp không chuyên IT — tránh jargon kỹ thuật
- Đưa khuyến nghị rõ ràng, không liệt kê options trung lập

## Tài liệu

- **CLAUDE.md** (file này) = hiến pháp ngắn: cách làm việc + cấu trúc + con trỏ. Đọc mỗi phiên — giữ gọn.
- **[LUAT_NHA.md](LUAT_NHA.md)** = quy ước code thống nhất. **Đọc TRƯỚC khi viết/sửa code Ruby**,
  kèm dùng skill `sketchup-api`.
- **[NHAT_KY.md](NHAT_KY.md)** = nhật ký phát triển: vì sao đằng sau mỗi quyết định + bài học. Mỗi
  thay đổi đáng kể → ghi 1 mục (Vấn đề → Quyết định → Vì sao → Bài học). Đọc khi cần hiểu mạch cũ.

## Mục đích

Gộp tất cả plugin SketchUp của Le Hai Studio vào **1 file `.rbz` duy nhất**, 1 toolbar duy nhất.

---

## Cấu trúc thư mục

```
lehai_tools/
├── CLAUDE.md
├── release.py                       ← phát hành 1 lệnh (xem mục "Phát hành version mới")
├── LeHai_Tools.rb                   ← extension registrar
├── LeHai_Tools-1.x.x.rbz           ← file cài đặt (build tay theo LUAT_NHA mục 7)
└── LeHai_Tools/
    ├── main.rb                      ← unified loader: require tất cả tool + tạo toolbar
    ├── auto_dan_canh/
    │   ├── main.rb                  ← Module MyStudio::AutoEdgeBand
    │   └── icons/
    │       ├── edge_band_16.png
    │       └── edge_band_24.png
    ├── canh_cnc/
    │   ├── main.rb                  ← Module CanhCNC
    │   └── icons/
    │       ├── canh_cnc_16.png
    │       └── canh_cnc_24.png
    ├── tam_go/
    │   ├── main.rb                  ← Module Lehai::TamGoGen
    │   ├── ui/
    │   │   └── dialog.html
    │   └── icons/
    │       ├── tamgo_16.png
    │       └── tamgo_24.png
    ├── ha_nen/
    │   ├── main.rb                  ← Module LeHaiDecor::HaNen
    │   ├── LeHai_HaNen_16.png
    │   └── LeHai_HaNen_24.png
    ├── dien_ten/
    │   ├── main.rb                  ← Module TuDong::DienTen
    │   ├── core/
    │   │   └── namer.rb
    │   ├── ui/
    │   │   ├── menu.rb              ← chỉ expose create_cmd, không đăng ký toolbar
    │   │   ├── dialog.rb
    │   │   └── dialog.html
    │   └── icons/
    │       ├── icon_16.png
    │       └── icon_24.png
    ├── thu_vien/
        ├── main.rb                  ← Module TK::ThuVien
        ├── core/
        │   └── library.rb           ← quét .skp, thumbnail cache, chèn/lưu component
        ├── ui/
        │   ├── menu.rb              ← chỉ expose create_cmd
        │   ├── dialog.rb            ← HtmlDialog + action callbacks
        │   └── html/
        │       └── index.html       ← giao diện thư viện (sidebar 2 cấp + lưới thumbnail)
        ├── components/              ← thư viện .skp mặc định (chọn lại được qua nút ⚙)
        │   └── HUONG_DAN.txt
        └── icons/
            ├── tk_thuvien_16.png
            └── tk_thuvien_24.png
    ├── go_group/        ← Module TK::GoGroup    (Gỡ DC → Group) — main.rb + icons/
    ├── kiem_tra_do_day/ ← Module TK::ThickCheck (Kiểm Tra Độ Dày) — main.rb + icons/
    ├── tim_tam_loi/     ← Module TK::ABFFinder  (Tìm Tấm Lỗi — ABF) — main.rb + icons/
    ├── truc_toa_do/     ← Module TK::AxisFix    (Trục Tọa Độ) — main.rb + icons/
    ├── shared/          ← code dùng chung (vd laser_snap.rb)
    └── updater.rb       ← client auto-update qua version.json
```

---

## Kiến trúc gộp tool

Mỗi sub-tool **không** tự tạo toolbar hay menu. Thay vào đó, mỗi module expose method:

```ruby
def self.create_cmd   # → trả về UI::Command đã config đầy đủ
```

`LeHai_Tools/main.rb` gom tất cả lại — **require từng tool có `rescue` riêng** (1 tool lỗi không làm
sập cả bộ), rồi dựng 1 toolbar từ `create_cmd` của **cả 10 module**, mỗi tool có guard `defined?`:

```ruby
toolbar = UI::Toolbar.new("LeHai's Decor Tools")
[ Lehai::TamGoGen, CanhCNC, LeHaiDecor::HaNen,             # cụm Dựng hình
  MyStudio::AutoEdgeBand, TuDong::DienTen,                 # cụm Gia công & nhãn
  TK::ThuVien,                                             # cụm Thư viện
  TK::GoGroup, TK::ThickCheck, TK::ABFFinder, TK::AxisFix  # cụm DC / xuất CNC (đặt cuối)
].each { |mod| toolbar.add_item(mod.create_cmd) if defined?(mod) }
toolbar.get_last_state == TB_NEVER_SHOWN ? toolbar.show : toolbar.restore
```

> Thứ tự = nhóm theo cụm (SketchUp không cho vạch ngăn trong 1 toolbar). Bản thật trong `main.rb`
> còn in diagnostic `defined?` từng module ra Ruby Console để debug khi 1 tool không load.

---

## Nguồn / vị trí (source of truth)

- **GitHub `tankfire4-dot/lehai-tools` = nguồn chính dài hạn.** Mất file trên máy vẫn còn GitHub.
- **`C:\Users\tankf\Desktop\agent_lab_khoa\projects\lehai-tools`** = bản làm việc trên máy (git repo riêng,
  nằm trong workspace lab từ 10/07/2026 — bản cũ ở `claude_work` KHÔNG còn). Sửa ở đây → **push** lên GitHub.
- Repo GitHub **cố ý để PUBLIC** (12/07/2026): máy thợ auto-update phụ thuộc nó, chuyển private là đứt update.
- **`%AppData%\SketchUp\SketchUp 2025\SketchUp\Plugins\LeHai_Tools`** = bản đang chạy (auto-update tải về).

## Phát hành version mới

Dùng **`release.py`** (Python, từ 2026-07-02) — 1 lệnh làm trọn: bump version cả 2 file,
**tự quét sinh `ruby_files`** (kèm báo diff thêm/bớt), kiểm BOM, build `.rbz`, commit + push:

```
python release.py 1.9.31 -m "mo ta thay doi"          # đầy đủ (hỏi xác nhận diff)
python release.py 1.9.31 -m "..." --dry-run           # xem trước, không ghi gì
python release.py 1.9.31 -m "..." --yes               # bỏ hỏi (Claude/tự động dùng)
python release.py 1.9.31 -m "..." --no-push           # build + commit, chưa push
```

Quy ước: file bắt đầu bằng `_` = đồ dev, **không ship** xuống máy thợ. Máy thợ tự cập nhật
qua `version.json`. Chi tiết từng bước tay (nếu cần hiểu/làm thủ công): [LUAT_NHA.md](LUAT_NHA.md) mục 7.

> ⚠️ `release.ps1` (PowerShell) đã **lỗi thời, KHÔNG dùng** — chính nó từng chèn BOM làm hỏng
> auto-update. `release.py` ghi UTF-8 không BOM + tự kiểm byte đầu, an toàn.

---

## Cài đặt

**SketchUp → Window → Extension Manager → Install Extension** → chọn `LeHai_Tools-x.x.x.rbz`

---

## Test nhanh khi đang phát triển (KHÔNG qua Extension Manager)

> 💡 **Nhắc Khoa dùng cách này** thay cho vòng lặp chậm uninstall → cài lại → test → gỡ.

Mở **Window → Ruby Console**, nạp thẳng file đang sửa từ bản repo và gọi luôn:

```ruby
load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/LeHai_Tools/<ten_tool>/main.rb'
TK::ABFFinder.prompt   # ← gọi method của tool để chạy thử ngay
```

- `load` chạy lại file → **định nghĩa lại code mới nhất ngay lập tức**, không cần khởi động lại.
- Tool theo luật nhà **không tự tạo toolbar** → nạp kiểu này **không để lại rác toolbar**.
- Tool **chỉ-đọc** (vd Tìm Tấm Lỗi) **không ghi gì vào file .skp** → không rác trong model.
- (Tiện: `claude_work/abf_finder.rb` là shortcut dev — `load` nó sẽ tự nạp Tìm Tấm Lỗi + mở hộp nhập.)

**Giới hạn — việc nào vẫn phải cài rbz / restart:**
- Nút + icon trên toolbar, thứ tự nút → do `LeHai_Tools/main.rb` dựng lúc khởi động.
- Cơ chế auto-update (`version.json`) → phải cài + push mới kiểm được.
- Tool **sửa model**: nếu lỗi giữa chừng có thể để lại thuộc tính/định mức trong `.skp` — test trên **file nháp** hoặc Ctrl+Z sau mỗi lần.

**Rác cosmetic cần biết:** tool nào tự `UI::Toolbar.new('X')` (vi phạm luật nhà) sẽ để lại 1 thanh
toolbar rỗng tên `X` mà SketchUp nhớ — gỡ ở **View → Toolbars → bỏ tick**. Tool đúng luật nhà không bị.

---

## Thêm tool mới vào bộ gộp

1. Tạo thư mục `LeHai_Tools/{ten_tool}/`
2. Viết `main.rb` với logic tool + `def self.create_cmd` (không có toolbar/menu riêng)
3. Thêm vào `LeHai_Tools/main.rb`:
   ```ruby
   require File.join(path, 'ten_tool', 'main')
   # ...
   [... , TenModule].each { |mod| toolbar.add_item(mod.create_cmd) }
   ```
4. Phát hành theo quy trình tay ở [LUAT_NHA.md](LUAT_NHA.md) mục 7 (bump version + thêm file vào `version.json` + build + push)

---

## Namespace các tool

**Đọc kỹ cột "Nút" — hai cách đếm khác nhau, đừng trộn.** Số module ≠ số nút trên toolbar.
Có module **không có nút riêng**: nó chạy từ trong dashboard Check Chốt Sản Xuất (icon khiên cuối
hàng). Tính tới 19/07/2026: **20 module, 14 nút**.

Nguồn sự thật cho từng cột: cột Module = thư mục trong `LeHai_Tools/`; cột Nút = mảng `groups`
trong `LeHai_Tools/main.rb` (chỗ DUY NHẤT quyết định nút nào lên toolbar và theo thứ tự nào).
Sửa bảng này thì đối chiếu lại cả hai chỗ, đừng chép từ trí nhớ.

⚠️ **Module chạy trong dashboard KHÔNG nằm trong danh sách `require` của `main.rb`** — dashboard tự
nạp lấy (`soat_truoc_xuat/main.rb:21`). Nên đừng lấy `main.rb` làm danh sách module đầy đủ; nó chỉ
là danh sách nút. Muốn biết đủ module thì `ls LeHai_Tools/*/`.

| Tool | Module | Nút |
|------|--------|-----|
| Tạo Tấm Gỗ | `Lehai::TamGoGen` | ✓ |
| Tạo Cánh CNC | `CanhCNC` | ✓ |
| Hạ Nền Uốn Cong | `LeHaiDecor::HaNen` | ✓ |
| Auto Dán Cạnh | `MyStudio::AutoEdgeBand` | ✓ |
| Điền Tên Nhanh | `TuDong::DienTen` | ✓ |
| Thư Viện Component | `TK::ThuVien` | ✓ |
| Gỡ DC → Group | `TK::GoGroup` | ✓ |
| Kiểm Tra Độ Dày | `TK::ThickCheck` | ✓ |
| Tìm Tấm Lỗi | `TK::ABFFinder` | ✓ |
| Kiểm Tra Khoảng Cách | `TK::SpacingCheck` | ✓ |
| **Chống Bay** (quét đổi tag chi tiết nhỏ, sau nesting) | `TK::ChongBay` | ✓ |
| Trục Tọa Độ | `TK::AxisFix` | ✓ |
| Dim Nhanh | `TK::QuickDim` | ✓ |
| **Check Chốt Sản Xuất** (dashboard, cuối toolbar, icon khiên) | `TK::PreExportCheck` | ✓ |
| Trùng Tấm | `TK::DuplicateCheck` | — chạy trong dashboard |
| Bản Lề Cánh | `TK::HingeCheck` | — chạy trong dashboard |
| Liên Kết (rãnh hậu + ngàm) | `TK::JointCheck` | — chạy trong dashboard |
| Kiểm Tra LED | `TK::LedCheck` | — chạy trong dashboard |
| Kiểm Tra Đặt Tên | `TK::NameCheck` | — chạy trong dashboard |
| Kiểm Tra Dán Cạnh | `TK::EdgeBandCheck` | — chạy trong dashboard |

> Thứ tự dòng trong bảng = thứ tự nút trên toolbar (nhóm theo cụm), rồi tới nhóm không có nút.

> Bộ "Check Chốt Sản Xuất" từng tách ra repo `lehai-check` (2026-07-01) rồi **GỘP TRỞ LẠI**
> lehai-tools (2026-07-01, v1.9.30) khi Khoa quyết định phát cho thợ. Repo `lehai-check` giờ
> KHÔNG dùng nữa — nếu máy nào lỡ cài extension `LeHai_Check` thì GỠ đi để khỏi trùng nút.

---

## Lịch sử thay đổi

→ Đã dời sang **[NHAT_KY.md](NHAT_KY.md)** (mục "Bảng phiên bản" + các mục "vì sao" chi tiết). CLAUDE.md giữ gọn, không chứa lịch sử.
