# LeHai Tools — Unified SketchUp Plugin

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
    └── dien_ten/
        ├── main.rb                  ← Module TuDong::DienTen
        ├── core/
        │   └── namer.rb
        ├── ui/
        │   ├── menu.rb              ← chỉ expose create_cmd, không đăng ký toolbar
        │   ├── dialog.rb
        │   └── dialog.html
        └── icons/
            ├── icon_16.png
            └── icon_24.png
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
[MyStudio::AutoEdgeBand, CanhCNC, Lehai::TamGoGen, LeHaiDecor::HaNen, TuDong::DienTen]
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

---

## Lịch sử thay đổi

| Phiên bản | Ngày       | Nội dung |
|-----------|------------|----------|
| 1.0.0     | 2026-06-08 | Gộp 5 plugin thành 1 bộ LeHai's Decor Tools |
