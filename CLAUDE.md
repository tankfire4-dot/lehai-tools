# LeHai Tools — Unified SketchUp Plugin

## Khởi động session

Đọc `C:\Users\tankf\.claude\profile\PROFILE.md` và các file liên quan trước khi làm việc.
Cập nhật profile nếu có thông tin mới đáng lưu trong session này.
Sau khi cập nhật bất kỳ file nào trong profile, chạy luôn: `cd C:\Users\tankf\.claude\profile && git add . && git commit -m "update: <nội dung>" && git push`

## Cách làm việc

- Xưng hô: **ông** (Claude) / **tôi** (Khoa) — luôn luôn
- Giải thích như báo cáo cho sếp không chuyên IT — tránh jargon kỹ thuật
- Đưa khuyến nghị rõ ràng, không liệt kê options trung lập

## Mục đích

Gộp tất cả plugin SketchUp của Le Hai Studio vào **1 file `.rbz` duy nhất**, 1 toolbar duy nhất.

---

## Cấu trúc thư mục

```
lehai_tools/
├── CLAUDE.md
├── release.ps1                      ← script phát hành version mới
├── LeHai_Tools.rb                   ← extension registrar
├── LeHai_Tools-1.x.x.rbz           ← file cài đặt (tái tạo bằng release.ps1)
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
    └── thu_vien/
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
```

---

## Kiến trúc gộp tool

Mỗi sub-tool **không** tự tạo toolbar hay menu. Thay vào đó, mỗi module expose method:

```ruby
def self.create_cmd   # → trả về UI::Command đã config đầy đủ
```

`LeHai_Tools/main.rb` gom tất cả lại:

```ruby
toolbar = UI::Toolbar.new("LeHai's Decor Tools")
[MyStudio::AutoEdgeBand, CanhCNC, Lehai::TamGoGen, LeHaiDecor::HaNen, TuDong::DienTen, TK::ThuVien]
  .each { |mod| toolbar.add_item(mod.create_cmd) }
toolbar.restore
```

---

## Phát hành version mới

```powershell
cd C:\Users\tankf\Desktop\lehai_tools
.\release.ps1 -Version "1.1.0"
```

Script tự động:
1. Xóa `.rbz` cũ
2. Cập nhật `ext.version` trong `LeHai_Tools.rb`
3. Tái tạo `LeHai_Tools-1.1.0.rbz`
4. Cập nhật `plugins.json` trong `sketchup-plugins` repo (URL + version)
5. Commit + push cả 2 repo

---

## Cài đặt

**SketchUp → Window → Extension Manager → Install Extension** → chọn `LeHai_Tools-x.x.x.rbz`

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
4. Chạy `release.ps1 -Version "x.x.x"`

---

## Namespace các tool

| Tool | Module |
|------|--------|
| Auto Dán Cạnh | `MyStudio::AutoEdgeBand` |
| Tạo Cánh CNC | `CanhCNC` |
| Tạo Tấm Gỗ | `Lehai::TamGoGen` |
| Hạ Nền Uốn Cong | `LeHaiDecor::HaNen` |
| Điền Tên Nhanh | `TuDong::DienTen` |
| Thư Viện Component | `TK::ThuVien` |
| Gỡ DC → Group | `TK::GoGroup` |

---

## Lịch sử thay đổi

| Phiên bản | Ngày       | Nội dung |
|-----------|------------|----------|
| 1.9.2     | 2026-06-17 | Gỡ DC → Group: quét toàn model xóa hết nhãn ABF (group có instance name bắt đầu `_ABF_Label` hoặc tag `ABF_Label`). Nhãn ABF là group riêng nằm cạnh tấm gỗ |
| 1.9.1     | 2026-06-17 | Gỡ DC → Group: thêm pass làm sạch — xóa material/màu (cả back_material) + toàn bộ attribute dictionaries trên mọi entity, giữ lại group + tên + tag. Mục tiêu: group thuần để xuất CNC/gắn nhãn |
| 1.9.0     | 2026-06-16 | Thêm tool Gỡ DC → Group (`go_group/`, module `TK::GoGroup`): biến Component/Dynamic Component thành group lồng nhau, giữ nguyên từng tấm + tên + tag, không phải group lại tay. Dùng trước khi gắn nhãn ABF (ABF không chịu component nhưng chịu group). Cách an toàn: tạo group rỗng → add_instance bản sao → explode trong group → erase gốc (tránh add_group trên geometry vừa nổ → bugsplat) |
| 1.0.0     | 2026-06-08 | Gộp 5 plugin thành 1 bộ LeHai's Decor Tools |
| 1.7.4     | 2026-06-13 | AutoDánCạnh: dán toàn bộ cung khi camera thấy bất kỳ mặt nào trong cung (`group_arc_faces` + `shared_arc_edge?`) — trước đó mỗi mặt cong check riêng lẻ → dán vá víu |
| 1.7.3     | 2026-06-13 | AutoDánCạnh: bỏ filter axis-alignment — cho phép dán toàn bộ mặt cong góc bo (trước đó chỉ dán mặt thẳng do filter AXIS_ALIGN_THRESHOLD quá nghiêm) |
| 1.7.1     | 2026-06-13 | CanhCNC: preview 3D cánh ma khi chọn điểm 2 (đúng số cánh/khe hở/độ dày, khung đỏ khi hở vượt khoang); tách công thức `door_layout` dùng chung cho preview + dựng thật |
| 1.7.0     | 2026-06-12 | Thêm tool Thư Viện Component (`thu_vien/`, module `TK::ThuVien`): trình duyệt thư viện .skp dùng chung — thumbnail, danh mục 2 cấp, tìm kiếm, chèn component, lưu component từ model vào thư viện (save_as → thumbnail iso chuẩn), chọn thư mục thư viện trên ổ mạng/Drive |
