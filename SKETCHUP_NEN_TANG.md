# SketchUp Nền Tảng — code lehai-tools ĐANG DÍNH chỗ nào

> **Phần kiến thức chung (8 chỗ SketchUp nói dối: lừa thế nào · dấu hiệu) đã chuyển về lab
> ngày 23/09/2026:** `agent_lab_khoa/shared-notes/sketchup-nen-tang.md`. **Đọc file đó TRƯỚC khi
> viết/sửa Ruby**, rồi đọc file này để biết tool nào trong kho đang dính. Số mục giữ nguyên hai bên.

> Mục "đang dính" là **NGHI**, chưa phải án. Xác nhận bằng cách chạy probe trên mẫu chuẩn
> (xem [MAU_CHUAN.md](MAU_CHUAN.md)). Không đoán — đo.

---

## 1. Đơn vị bên trong là INCH, không phải mm

**Đang dính.** Kho dùng lẫn 3 kiểu: `.mm` / `.to_mm` / nhân tay `25.4`
(`auto_dan_canh`, `kiem_tra_r100`, `kiem_tra_led`, `kiem_tra_lien_ket`, `trung_tam`, `tam_go`…).
Nhân tay `25.4` không sai về toán, nhưng **không tự lộ chiều** — đọc code không biết đang
đổi xuôi hay ngược. Chỗ nguy nhất là **so sánh và dung sai**: một ngưỡng viết bằng mm đem so
với một độ dài inch thì im lặng luôn.

---

## 2. Definition dùng chung — sửa một, lây tất

**Đang dính.** Đã học được — `chong_bay/main.rb:15` có nguyên đoạn ghi chú bài học này,
`chong_bay:578` và `truc_toa_do:92` gọi `make_unique` đúng. Đây là bằng chứng bài học có hiệu lực.
Cần soi: các tool **sửa hình** khác có gọi không.

---

## 3. `.bounds` KHÔNG phải kích thước tấm

**Đang dính — 2 nghi phạm nặng nhất kho:**

| Chỗ | Ngờ gì |
|---|---|
| `dien_ten/core/namer.rb:78, :91` | Dùng `definition.bounds` để **gom nhóm và ĐẶT TÊN tấm theo kích thước**. Tấm bị Scale → tên ghi số cũ. Tên tấm đi thẳng ra xưởng. |
| `dien_ten/ui/dialog.rb:226` | Cùng lỗi, hiển thị lên bảng cho người xác nhận → người nhìn số sai rồi bấm OK. |
| `ha_nen/main.rb:119, :215` | `entity.bounds` để lấy mốc đặt hình mới. Dính 3a + 3b. |
| `truc_toa_do/main.rb:94` | `definition.bounds.min.transform(t)` — **cái này có nhân transform, có vẻ ĐÚNG**. Dùng làm mẫu tham chiếu cho các chỗ khác. |

---

## 4. Transform có scale và có LẬT GƯƠNG

**Đang dính.** Kho có 51 chỗ đụng `transformation`. **Chưa soi được chỗ nào xét dấu định thức.**
Nghi `auto_dan_canh` (dán cạnh theo hướng camera) và `canh_cnc`. Đây là hạng mục cần probe nhất
sau mục 3.

---

## 5. Đang đứng ở đâu trong model quyết định toạ độ

**Đang dính.** `edit_transform` xuất hiện **đúng 1 lần** trong cả kho (`canh_cnc/main.rb:445`).

Nghi phạm số 2 của cả kho:

```ruby
# auto_dan_canh/main.rb:269 và :292
model.selection.each { |e| collect_boards(e, e.transformation, boards, 0) }
#                                            ^^^^^^^^^^^^^^^^
# Mồi chuỗi transform bằng transform của CHÍNH NÓ.
# Thiếu: transform của các cấp cha + edit_transform.
# Chọn tấm từ ngoài cùng -> đúng. Nhấp vào trong tủ rồi chọn tấm -> toạ độ thế giới sai.
```

---

## 6. Dung sai 0,001 inch = 0,0254 mm

**Đang dính.** Chưa soi. Cần xem các tool `kiem_tra_khoang_cach`, `kiem_tra_lien_ket`,
`kiem_tra_dan_canh` đang đặt ngưỡng dung sai bao nhiêu — **ngưỡng nhỏ hơn 0,0254 mm là ngưỡng
giả**, SketchUp không phân biệt nổi.

---

## 7. SketchUp tự gộp và tự cắt hình khi thêm

**Đang dính.** `ha_nen/main.rb:133` có `model.active_entities.add_group` — **đúng bài**, sinh
hình trong group riêng. Dùng làm mẫu. Cần soi các tool sinh hình khác (`tam_go`, `chia_lam`,
`canh_cnc`) có làm vậy không.

---

## 8. Không bọc `start_operation` thì undo vỡ

**Đang dính — đây là mục LÀNH NHẤT trong 8 mục.** Đã soi hết: **11/11 tool có sửa model đều bọc
`start_operation` + `commit_operation` đầy đủ.** Các file không bọc đều là loại chỉ-đọc
(`kiem_tra_*`, `tim_tam_loi`, `soat_truoc_xuat`) hoặc file nạp/giao diện — không bọc là **đúng**.
Riêng `thu_vien/core/library.rb:125` dùng `model.place_component` (bộ đặt của SketchUp tự lo undo)
— cũng đúng.

Chỗ còn hở là **đường thoát khi lỗi**, không phải chỗ bọc:

| File | start | commit | abort | Rủi ro |
|---|---|---|---|---|
| `chia_lam/main.rb` | 1 | 1 | ~~0~~ **1** | **ĐÃ VÁ 1.9.64** (23/09) — bọc rescue + abort |
| `kiem_tra_do_day/main.rb` | 2 | 2 | **0** | như trên |
| `dim_nhanh/main.rb` | 2 | 2 | **1** | thiếu 1 nhánh |

Ba chỗ này sửa nhanh và không cần mẫu chuẩn để xác nhận — sửa được ngay.
(LUAT_NHA mục A đã ghi nhận sự lệch này từ 20/06, chưa dọn.)

---

## Bảng tra nhanh — nghi phạm theo mục

| # | Nói dối ở đâu | Test model phẳng có lộ không? | Nghi phạm nặng nhất |
|---|---|---|---|
| 1 | Inch vs mm | Có, lộ ngay | ngưỡng so sánh trộn đơn vị |
| 2 | Definition dùng chung | Không | tool sửa hình thiếu `make_unique` |
| 3 | `.bounds` ba tầng lừa | **Không** | `dien_ten/core/namer.rb:78,91` |
| 4 | Lật gương | Không | `auto_dan_canh`, `canh_cnc` |
| 5 | Ngữ cảnh đang mở | **Không** | `auto_dan_canh:269,292` |
| 6 | Dung sai 0,0254 mm | Không | các tool `kiem_tra_*` đặt ngưỡng |
| 7 | Tự gộp/tự cắt hình | Chạy lần 2 mới lộ | tool sinh hình không dùng group |
| 8 | Undo | Chỉ lộ khi có lỗi | **đã soi xong — chỉ hở 3 chỗ `abort`** |

*Lập 01/08/2026. Nguồn nghi phạm: soi tĩnh code trong kho, chưa đo trên SketchUp thật.
Xác nhận/bác bỏ bằng probe trên [MAU_CHUAN.md](MAU_CHUAN.md) — kết quả ghi vào [NHAT_KY.md](NHAT_KY.md).*
