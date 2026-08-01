# SketchUp Nền Tảng — 8 Chỗ SketchUp Nói Dối

**Đọc file này TRƯỚC khi viết/sửa bất kỳ dòng Ruby nào trong kho.**

Đây không phải tài liệu API. API SketchUp có hàng trăm trang, 95% không dính tới nghề tủ bếp.
File này chỉ gom **8 chỗ mà SketchUp trả về một con số trông rất hợp lý nhưng SAI** — loại lỗi
không crash, không báo, cứ thế chạy thẳng vào file CNC.

Mỗi mục có 3 phần: **nó lừa thế nào · dấu hiệu nhận ra · code trong kho đang dính chỗ nào.**

> Cột "đang dính" là **NGHI**, chưa phải án. Xác nhận bằng cách chạy probe trên mẫu chuẩn
> (xem [MAU_CHUAN.md](MAU_CHUAN.md)). Không đoán — đo.

---

## 1. Đơn vị bên trong là INCH, không phải mm

**Lừa thế nào.** Mọi độ dài SketchUp trả về đều tính bằng **inch**, bất kể ô Model Info của
người dùng đang để mm. Một tấm dày 18 mm, hỏi máy nó nói `0.7086614...`. Con số đó trông như
lỗi làm tròn nên rất dễ bị đem đi `.round(1)` cho "sạch" — và thế là mất 2,5 mm.

```ruby
18.mm        # mm  -> inch  (0.708...)   dùng khi ĐƯA số vào SketchUp
len.to_mm    # inch -> mm   (18.0)       dùng khi LẤY số ra khỏi SketchUp
25.4         # hằng số tự nhân tay — chạy được nhưng dễ quên chiều
```

**Dấu hiệu.** Kết quả lệch đúng hệ số 25,4 (hoặc 1/25,4). Số ra bé tí hoặc to khủng.
Hoặc: so sánh `if width > 500` mà `width` là inch — điều kiện gần như không bao giờ đúng.

**Đang dính.** Kho dùng lẫn 3 kiểu: `.mm` / `.to_mm` / nhân tay `25.4`
(`auto_dan_canh`, `kiem_tra_r100`, `kiem_tra_led`, `kiem_tra_lien_ket`, `trung_tam`, `tam_go`…).
Nhân tay `25.4` không sai về toán, nhưng **không tự lộ chiều** — đọc code không biết đang
đổi xuôi hay ngược. Chỗ nguy nhất là **so sánh và dung sai**: một ngưỡng viết bằng mm đem so
với một độ dài inch thì im lặng luôn.

---

## 2. Definition dùng chung — sửa một, lây tất

**Lừa thế nào.** Group và Component đều không tự chứa hình. Chúng trỏ tới một **definition**
(bản gốc). Nhiều instance có thể trỏ chung một definition. Sửa `entity.entities` là sửa **bản
gốc** → mọi tấm khác cùng bản gốc đổi theo.

Chỗ chết người: trong SketchUp bằng tay, ông nhấp đúp vào group để sửa thì SketchUp thường tự
tách bản riêng cho ông. **Ruby thì KHÔNG.** Code sửa thẳng vào definition, lây sang tấm khác,
mà màn hình lúc đó ông đang nhìn tấm này nên không thấy.

```ruby
inst.make_unique   # tách bản riêng TRƯỚC khi sửa
# CẢNH BÁO: make_unique thay entity cũ bằng entity MỚI.
# Mọi biến/danh sách đang giữ entity cũ thành rác -> phải lấy lại tay cầm.
```

**Dấu hiệu.** Sửa 1 tấm, mở ra thấy 5 tấm đổi theo. Hoặc: chạy tool xong, `entity.deleted?`
trả `true` ở chỗ không ngờ.

**Đang dính.** Đã học được — `chong_bay/main.rb:15` có nguyên đoạn ghi chú bài học này,
`chong_bay:578` và `truc_toa_do:92` gọi `make_unique` đúng. Đây là bằng chứng bài học có hiệu lực.
Cần soi: các tool **sửa hình** khác có gọi không.

---

## 3. `.bounds` KHÔNG phải kích thước tấm

Đây là chỗ nguy nhất trong cả 8 mục, vì `.bounds` trông đúng là thứ để đo tấm. Nó lừa **ba tầng**:

### 3a. Hộp bao luôn THẲNG TRỤC — tấm xoay thì hộp phình ra

`bounds` là hộp chữ nhật thẳng theo trục đỏ/xanh/lam của thế giới. Tấm xoay chéo 30° thì hộp
bao vẫn thẳng trục → nó **to hơn tấm**.

```
Tấm thật 800 × 400, xoay 30°:
   bounds.width  = 800·cos30 + 400·sin30 = 892,8 mm   ← KHÔNG phải 800
   bounds.height = 800·sin30 + 400·cos30 = 746,4 mm   ← KHÔNG phải 400
```

Muốn kích thước THẬT của tấm xoay: phải đo trong hệ toạ độ riêng của tấm, không đọc bounds thế giới.

### 3b. `entity.bounds` nằm ở hệ toạ độ của CHA, không phải thế giới

Tấm nằm trong group, group nằm trong group. `tam.bounds` cho toạ độ so với **group mẹ trực tiếp**.
Ở cấp cao nhất thì trùng thế giới nên test ở model phẳng **không bao giờ lộ**. Vào tủ thật lồng
3 cấp là sai vị trí.

### 3c. `definition.bounds` BỎ QUA hoàn toàn transform — kể cả scale

`definition.bounds` là kích thước **bản gốc chưa biến đổi**. Thợ kéo Scale tool giãn tấm (thay
vì push/pull) thì hình gốc **không đổi**, chỉ transform đổi. Nhìn model thấy 800, hỏi
`definition.bounds` nó nói 400.

**Dấu hiệu.** Số đúng trên model demo phẳng, sai trong file khách thật. Kích thước lẻ hơn thực
tế (do xoay). Kích thước tròn trịa nhưng khác hẳn mắt nhìn (do scale).

**Đang dính — 2 nghi phạm nặng nhất kho:**

| Chỗ | Ngờ gì |
|---|---|
| `dien_ten/core/namer.rb:78, :91` | Dùng `definition.bounds` để **gom nhóm và ĐẶT TÊN tấm theo kích thước**. Tấm bị Scale → tên ghi số cũ. Tên tấm đi thẳng ra xưởng. |
| `dien_ten/ui/dialog.rb:226` | Cùng lỗi, hiển thị lên bảng cho người xác nhận → người nhìn số sai rồi bấm OK. |
| `ha_nen/main.rb:119, :215` | `entity.bounds` để lấy mốc đặt hình mới. Dính 3a + 3b. |
| `truc_toa_do/main.rb:94` | `definition.bounds.min.transform(t)` — **cái này có nhân transform, có vẻ ĐÚNG**. Dùng làm mẫu tham chiếu cho các chỗ khác. |

---

## 4. Transform có scale và có LẬT GƯƠNG

**Lừa thế nào.** Transform không chỉ là dời + xoay. Nó còn chứa **phóng to** và **lật gương**.
Tấm cánh trái/cánh phải trong tủ thường là một tấm bị lật — hình gốc y hệt nhau.

Lật gương làm **định thức của ma trận âm**. Hệ quả: pháp tuyến mặt lật ngược (mặt trước thành
mặt sau), thứ tự cạnh đảo, và "cạnh trái" hoá "cạnh phải". Tool dán cạnh mà không xét lật thì
dán nhầm bên — và nhìn trên màn hình **vẫn thấy có dán**, chỉ sai bên.

**Dấu hiệu.** Cánh trái đúng, cánh phải sai. Mặt vân gỗ quay ra sau. Cạnh dán lệch đúng đối xứng.

**Đang dính.** Kho có 51 chỗ đụng `transformation`. **Chưa soi được chỗ nào xét dấu định thức.**
Nghi `auto_dan_canh` (dán cạnh theo hướng camera) và `canh_cnc`. Đây là hạng mục cần probe nhất
sau mục 3.

---

## 5. Đang đứng ở đâu trong model quyết định toạ độ

**Lừa thế nào.** Nếu người dùng đang nhấp đúp **vào trong** một group để sửa, thì:

- `model.active_entities` ≠ `model.entities` (một cái là ruột group, một cái là cấp cao nhất)
- `model.selection` chứa entity **của ngữ cảnh đó**
- `e.transformation` của entity đó là **so với ngữ cảnh**, không phải so với thế giới

Muốn ra thế giới phải nhân thêm `model.edit_transform`. Bỏ quên → toạ độ lệch đúng bằng vị trí
của group đang mở. Người dùng đứng ngoài (không mở group nào) thì `edit_transform` là ma trận
đơn vị → **test kiểu bình thường không bao giờ lộ lỗi này.**

**Dấu hiệu.** Tool chạy đúng khi chọn tấm từ ngoài, sai khi người dùng lỡ đang ở trong tủ.
Hình mới sinh ra bị dời đi một khoảng đúng bằng vị trí tủ.

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

**Lừa thế nào.** SketchUp **gộp** hai điểm cách nhau dưới ~0,001 inch thành một. So sánh
`Point3d` cũng dùng dung sai này, không so tuyệt đối.

Nghĩa là: mọi thứ nhỏ hơn **0,0254 mm** SketchUp coi như bằng nhau. Khe hở 0,02 mm là **không
tồn tại** với SketchUp. Nhưng nếu code tự so bằng số thực (`a == b` trên float đã đổi ra mm)
thì code lại thấy có khe → code và SketchUp bất đồng, kết quả tuỳ chỗ nào hỏi trước.

**Dấu hiệu.** Cạnh "biến mất" sau khi thêm hình. Hai tấm lúc thì báo chạm lúc thì báo hở.
Số đo dao động ở chữ số thập phân thứ 2–3 của mm.

**Đang dính.** Chưa soi. Cần xem các tool `kiem_tra_khoang_cach`, `kiem_tra_lien_ket`,
`kiem_tra_dan_canh` đang đặt ngưỡng dung sai bao nhiêu — **ngưỡng nhỏ hơn 0,0254 mm là ngưỡng
giả**, SketchUp không phân biệt nổi.

---

## 7. SketchUp tự gộp và tự cắt hình khi thêm

**Lừa thế nào.** Thêm hình vào một `entities` không phải là "để nó vào đó". SketchUp lập tức
sáp nhập vào hình có sẵn: mặt đồng phẳng **gộp làm một**, cạnh cắt nhau **tự chẻ đôi cả hai**.

Hệ quả: `entities.add_face(...)` trả về một face, nhưng face đó có thể **đã bị chẻ thành nhiều
mảnh** ngay sau đó, hoặc đã nuốt mất một mặt cũ. Đếm mặt trước/sau không khớp. Tay cầm giữ face
cũ có thể thành `deleted?`.

**Cách né.** Vẽ hình mới vào **group riêng** rồi mới đặt vào chỗ cần — group là vách ngăn,
hình trong group không sáp nhập với hình ngoài.

**Dấu hiệu.** Chạy tool lần 1 đúng, chạy lần 2 trên cùng model thì hỏng. Số mặt tăng bất thường.
`deleted?` bật `true` giữa chừng.

**Đang dính.** `ha_nen/main.rb:133` có `model.active_entities.add_group` — **đúng bài**, sinh
hình trong group riêng. Dùng làm mẫu. Cần soi các tool sinh hình khác (`tam_go`, `chia_lam`,
`canh_cnc`) có làm vậy không.

---

## 8. Không bọc `start_operation` thì undo vỡ

**Lừa thế nào.** Không bọc thì mỗi thay đổi nhỏ thành một bước undo riêng. Tool sửa 200 tấm =
200 lần Ctrl+Z. Tệ hơn: tool **lỗi giữa chừng** thì model nằm lại ở trạng thái nửa vời — sửa
xong 80 tấm, 120 tấm còn nguyên, không có gì báo và không lùi lại được bằng một phím.

```ruby
model.start_operation('Ten thao tac', true)   # tên ASCII; true = tắt cập nhật màn hình (nhanh hơn nhiều)
begin
  # ... sửa model ...
  model.commit_operation
rescue => e
  model.abort_operation      # BẮT BUỘC — không có thì model kẹt nửa vời
  raise
end
```

**Dấu hiệu.** Ctrl+Z không lùi hết. Model hỏng sau khi tool báo lỗi. Tool chạy chậm bất thường
(thiếu `true` ở tham số thứ 2).

**Đang dính — đây là mục LÀNH NHẤT trong 8 mục.** Đã soi hết: **11/11 tool có sửa model đều bọc
`start_operation` + `commit_operation` đầy đủ.** Các file không bọc đều là loại chỉ-đọc
(`kiem_tra_*`, `tim_tam_loi`, `soat_truoc_xuat`) hoặc file nạp/giao diện — không bọc là **đúng**.
Riêng `thu_vien/core/library.rb:125` dùng `model.place_component` (bộ đặt của SketchUp tự lo undo)
— cũng đúng.

Chỗ còn hở là **đường thoát khi lỗi**, không phải chỗ bọc:

| File | start | commit | abort | Rủi ro |
|---|---|---|---|---|
| `chia_lam/main.rb` | 1 | 1 | **0** | lỗi giữa chừng → model kẹt nửa vời |
| `kiem_tra_do_day/main.rb` | 2 | 2 | **0** | như trên |
| `dim_nhanh/main.rb` | 2 | 2 | **1** | thiếu 1 nhánh |

Ba chỗ này sửa nhanh và không cần mẫu chuẩn để xác nhận — sửa được ngay.
(LUAT_NHA mục A đã ghi nhận sự lệch này từ 20/06, chưa dọn.)

---

## Bảng tra nhanh

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

**Đọc cột thứ 3 cho kỹ.** 6/8 mục **không lộ** trên model demo phẳng. Đó là lý do 20 tool
"chạy ổn" suốt thời gian qua mà vẫn có thể sai — chưa cái nào bị đo trên hình khó.

---

*Lập 01/08/2026. Nguồn nghi phạm: soi tĩnh code trong kho, chưa đo trên SketchUp thật.
Xác nhận/bác bỏ bằng probe trên [MAU_CHUAN.md](MAU_CHUAN.md) — kết quả ghi vào [NHAT_KY.md](NHAT_KY.md).*
