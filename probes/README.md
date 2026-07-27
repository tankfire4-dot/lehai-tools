# probes — script dò API SketchUp cho tính năng CHƯA làm

Cứu ra từ `_reset_backup/` ngày 21/07/2026 trước khi xóa đống đó.

**Vì sao giữ đúng 4 file này mà bỏ 7 file probe còn lại:** 7 cái kia (`abf`, `ban_le`,
`dan_canh`, `dao_ten`, `spacing`, `ranh_led`, `trung_tam`) đều đã có **module tương ứng đang
chạy** trong plugin — kiến thức dò được đã nằm trong code thật, giữ bản nháp là thừa.

Bốn file dưới đây **không có module nào**: chúng là nghiên cứu chưa thành sản phẩm. Xóa là mất
hẳn phần đã dò được về cách SketchUp trả dữ liệu cho mấy chi tiết này.

| File | Dò cái gì |
|---|---|
| `ranh_hau_probe.rb` | rãnh hậu — vòng 1 |
| `ranh_hau_probe2.rb` | rãnh hậu — vòng 2 |
| `dam_xuyen_probe.rb` | dầm xuyên |
| `ngam_probe.rb` | ngàm |
| `dan_canh_3d_probe.rb` | **ABF ghi dấu dán cạnh ở đâu trên 3D** (27/07) — đã CHỐT: không phải tên group mà là **attribute** `ABF/edge-band-types` (group tấm) + `ABF/edge-band-id` (face). Kèm phát hiện ngoài dự tính: group rãnh mang `ABF/setting-name = "Rãnh hậu"` — ABF vẫn khai loại rãnh, chỉ chuyển từ tag sang attribute. |
| `abf_attr_full.rb` | **vòng 2 — in đầy đủ giá trị** (27/07). Ba câu còn treo: `edge-band-types` mã hoá cạnh nào · vì sao 16 tấm khai / 18 face có id / 13 dấu ở bản 2D · cả 4 rãnh có cùng `setting-name` không. |
| `tag_audit.rb` | **SỔ ĐO TAG cho buổi dựng full một dự án CNC (28/07)** — `TagAudit.snap 'ten moc'` sau mỗi bước, ghi tích luỹ vào `tag_audit.txt`. Đo cả tên group, tag ở group, tag ở edge, số face và chiều nhỏ nhất (mm) — chiều nhỏ nhất là cái phân biệt rãnh hậu ~10mm với ngàm ~17,5mm khi tag giống hệt nhau. |
| `tag_intersect_probe.rb` | **tag thật của dấu `_ABF_Intersect`** (27/07) — đếm từng kiểu tag ở group LẪN ở edge. Dò vì file đã làm rãnh hậu vẫn bị báo đỏ: tag là `ABF_Groove`, không phải `...PHAYRANHHAU...` như `kiem_tra_lien_ket` đang chờ. Cái này KHÁC 4 file trên: nó dò cho một module ĐANG CHẠY, không phải tính năng chưa làm. |

**Đây là script DÒ, không phải mã sản phẩm.** Không đăng ký vào toolbar, không nằm trong
`version.json`, thợ không bao giờ nhận. Muốn làm thật thì đọc `LUAT_NHA.md` trước, và
`agent_lab_khoa/shared-notes/sketchup-api.md` — cẩm nang đã chắt lọc.

Nếu tới lúc nào đó chốt là **không bao giờ làm** mấy tính năng này, xóa cả folder, khỏi tiếc.
