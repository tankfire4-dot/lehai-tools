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

**Đây là script DÒ, không phải mã sản phẩm.** Không đăng ký vào toolbar, không nằm trong
`version.json`, thợ không bao giờ nhận. Muốn làm thật thì đọc `LUAT_NHA.md` trước, và
`agent_lab_khoa/shared-notes/sketchup-api.md` — cẩm nang đã chắt lọc.

Nếu tới lúc nào đó chốt là **không bao giờ làm** mấy tính năng này, xóa cả folder, khỏi tiếc.
