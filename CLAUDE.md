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

## Nguồn / vị trí (source of truth)

- **GitHub `tankfire4-dot/lehai-tools` = nguồn chính dài hạn.** Mất file trên máy vẫn còn GitHub.
- **`C:\Users\tankf\Desktop\claude_work\lehai-tools`** = bản làm việc trên máy (git repo). Sửa ở đây → **push** lên GitHub.
- **`%AppData%\SketchUp\SketchUp 2025\SketchUp\Plugins\LeHai_Tools`** = bản đang chạy (auto-update tải về).

## Phát hành version mới

Làm **bằng tay** theo quy trình ở **[LUAT_NHA.md](LUAT_NHA.md) mục 7** (tóm: bump version bằng Edit
tool ở cả `LeHai_Tools.rb` + `version.json` → thêm file mới vào `version.json` → build `.rbz` →
kiểm không BOM → commit + push). Máy thợ tự cập nhật qua `version.json`.

> ⚠️ `release.ps1` đã **lỗi thời, KHÔNG dùng**: trỏ đường dẫn `Desktop\lehai_tools` (không tồn tại),
> cập nhật `plugins.json`/`congty_loader` (không tồn tại), và ghi file bằng PowerShell → chèn BOM
> (đúng cái làm hỏng auto-update). Cơ chế update thật bây giờ là `version.json`, bump tay.

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
4. Phát hành theo quy trình tay ở [LUAT_NHA.md](LUAT_NHA.md) mục 7 (bump version + thêm file vào `version.json` + build + push)

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
| Kiểm Tra Độ Dày | `TK::ThickCheck` |
| Trục Tọa Độ | `TK::AxisFix` |

---

## Lịch sử thay đổi

→ Đã dời sang **[NHAT_KY.md](NHAT_KY.md)** (mục "Bảng phiên bản" + các mục "vì sao" chi tiết). CLAUDE.md giữ gọn, không chứa lịch sử.
