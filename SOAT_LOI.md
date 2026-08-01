# Soát Lỗi Bộ Plugin — Danh Sách Để Kiểm Tay

**Lập 01/08/2026 · soi tĩnh code, CHƯA chạy SketchUp.**

Mỗi mục có phần **"Kiểm tay thế nào"** — làm được trong 1–2 phút ngay trên SketchUp, không cần
probe, không cần dựng mẫu chuẩn. Kiểm xong ghi ĐÚNG/SAI vào cột cuối bảng tổng.

Số mục trong ngoặc (3a, 5…) trỏ về [SKETCHUP_NEN_TANG.md](SKETCHUP_NEN_TANG.md).

> **Đọc cho đúng:** đây là **nghi**, chưa phải án. Soi tĩnh chỉ ra được "code không nhân
> transform" — nó có thành lỗi thật hay không còn tuỳ file khách có tấm bị Scale hay không.
> Kiểm tay là để biến nghi thành án hoặc xoá án.

---

# A. NẶNG — số sai đi thẳng ra sản phẩm

## A1. Điền Tên đặt SAI TÊN khi tấm bị Scale (và gộp nhóm sai)

**Ở đâu:** `dien_ten/core/namer.rb:78` (`group_key`) và `:91` (`group_label`)

```ruby
b = entity.definition.bounds        # ← kích thước BẢN GỐC, bỏ qua mọi transform
dims = [b.width, b.height, b.depth]
"#{dims[0]} x #{dims[1]} x #{dims[2]}"   # ← chuỗi này thành TÊN TẤM
```

**Sai gì.** Thợ kéo Scale tool giãn tấm (thay vì push/pull) thì hình gốc **không đổi**, chỉ
transform đổi. `definition.bounds` không biết chuyện đó. Hỏng **hai lần**:

1. **Tên sai** — tấm thật 800 mà tên ghi 400.
2. **Gộp nhóm sai** — hai tấm nhìn khác hẳn nhau nhưng chung bản gốc → cùng `group_key` →
   **bị gán CÙNG một tên**. Ngược lại hai tấm bằng nhau ngoài đời mà bản gốc khác nhau → tách
   thành hai nhóm.

**Nặng vì:** tên tấm là thứ đi thẳng ra xưởng. Sai tên là cắt nhầm.

**Điểm hay để kiểm:** `dien_ten/ui/dialog.rb:227` vẽ khung nổi bật thì **CÓ** nhân transform
(`wtr * lb.corner(i)`) — tức là **khung vẽ đúng, tên lại sai**. Hai thứ trong cùng một bảng
mà lệch nhau. Nhìn là thấy, không cần đo.

> ### Kiểm tay
> 1. Vẽ tấm **400 × 400 × 18**, Make Group.
> 2. Dùng **Scale tool** kéo ×2 theo chiều dài → nhìn thấy tấm dài 800.
> 3. Chạy **Điền Tên**, xem tên nó đề nghị.
> - Đề nghị **800 × 400 × 18** → tôi sai, xoá án.
> - Đề nghị **400 × 400 × 18** → **đúng bug**, khung vẽ ôm tấm 800 mà chữ ghi 400.

---

## A2. Kiểm Tra Độ Dày báo SAI ĐỘ DÀY khi tấm/tủ bị Scale

**Ở đâu:** `kiem_tra_do_day/main.rb:108-112`

```ruby
def self.own_thickness_mm(ents)
  bb = Geom::BoundingBox.new
  ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
  [bb.width, bb.height, bb.depth].min.to_mm     # ← KHÔNG nhân transform, một lần nào
end
```

**Sai gì.** Đo hộp bao các mặt **trong hệ toạ độ bản gốc**. Hàm này **không nhận tham số
transform** — nghĩa là scale ở chính tấm đó, hoặc ở bất kỳ cấp tủ nào bọc ngoài, đều bị bỏ qua.

**So sánh cho rõ — 6 tool anh em đều làm ĐÚNG chỗ này:** `kiem_tra_led`, `kiem_tra_lien_ket`,
`kiem_tra_ten`, `kiem_tra_ban_le_chan`, `trung_tam` đều có hàm `world_aabb(ents, te)` lấy 8 góc
hộp local rồi **nhân `te`** ra thế giới. Chỉ `kiem_tra_do_day` là thiếu. **Đây là chỗ lệch khỏi
khuôn chung của chính bộ plugin, không phải chuyện tôi bịa ra tiêu chuẩn mới.**

**Nặng vì:** ván 17,5 và ván 18 là hai loại vật tư khác nhau. Cả tủ bị scale nhẹ → mọi tấm báo
sai dày → đặt nhầm vật tư.

### ❌ ĐÃ ĐO — KHÔNG PHẢI LỖI. A2 XUỐNG HẠNG (01/08, sau 2 vòng probe)

**Kết luận cuối: `kiem_tra_do_day` BÁO ĐÚNG. Tấm 33,1mm mới là cái sai.**

Probe 2 mổ tấm đó: **một khối liền, 10 mặt, là hộp chữ nhật sạch 33,06 × 254,5 × 1033mm.**
Kiểm chéo bằng diện tích 3 cặp mặt — cả ba trục đều khớp giả thiết "hộp đặc":

| Cặp mặt | Nếu là hộp thật | Probe đo được | Lệch |
|---|---|---|---|
| mặt lớn (254,5 × 1033) | 525.797 mm² | 515.439 mm² | 2,0% *(chỗ khoét rãnh)* |
| mặt cạnh (33,06 × 1033) | 68.302 mm² | 68.293 mm² | 0,0% |
| mặt đầu (33,06 × 254,5) | 16.828 mm² | 16.825 mm² | 0,0% |

Không phải hai tấm chồng, không phải rác lẫn, không nghiêng trục. **Tấm dày 33,06mm thật** —
một tấm sai vật tư nằm trong file khách, và tool đã bắt đúng, tô đỏ, cô lập ra. Đúng chức năng.

Con số 17,50 ở thanh Length: nhiều khả năng là cạnh khác (rãnh khoét) hoặc giá trị còn lại
của lần đo trước — ảnh cho thấy thao tác đo đang dở (*"Click to set second endpoint"*).

**Trạng thái A2 sau khi đo:**

- **Triệu chứng ban đầu → KHÔNG phải lỗi.** Xoá án.
- **Quan sát ở tầng code vẫn ĐÚNG và vẫn giữ:** `own_thickness_mm` thật sự không nhận tham số
  transform, lệch khỏi khuôn `world_aabb(ents, te)` của 6 tool anh em. Nhưng probe 1 cho thấy
  **384 tấm 17.5 + 48 tấm 9.0 đo hai cách ra kết quả y hệt** → file này không có group bị scale
  → lỗ hổng **chưa gây hại**. Xếp lại thành **rủi ro tiềm ẩn**, không phải bug đang chảy máu.
- **Còn treo:** tấm 200mm (probe 1: góc lệch 2,28°, hai cách đo chênh 325mm). Probe 2 **không
  tìm thấy nó nữa** — số container tụt 953 → 443 giữa hai lần chạy. **File đã đổi giữa hai lần
  đo, chưa kết luận được.** Phải chạy lại trên file nguyên trạng.

**Bài học phương pháp (giá trị hơn cả cái bug):** hai vòng probe đã bác **ba** giả thuyết liên
tiếp — (1) do Scale, (2) do nghiêng trục, (3) do túi chứa nhiều thứ. Và bác luôn **cách sửa tôi
định làm**: phép "chiếu lên pháp tuyến" cho tấm 200mm ra 525,85mm, tệ hơn cái đang hỏng. Nếu sửa
theo giả thuyết nghe-hợp-lý, đã thay một lỗi bằng một lỗi to hơn — **và nó vẫn sẽ "chạy êm".**

---

### Ghi chép vòng 1 (giữ lại để thấy mạch suy luận sai ở đâu)

Khoa chạy trên file khách thật: tool báo **33,1 mm** và **200 mm** (2 tấm, cột đỏ), thước
SketchUp đo tấm 33,1 đó ra **17,50 mm**. **Lỗi có thật, đã xác nhận.**

**Nhưng cơ chế KHÁC cái tôi dự đoán ở trên.** Nếu do Scale thì sai số phải là bội số tròn
(×2 → 35, ×1,5 → 26,25). **33,1 là số lẻ → không phải scale.**

Giả thuyết mới (đang dò bằng `probes/do_day_probe.rb`): **hộp bao phồng vì tấm nằm nghiêng
so với trục của chính group nó** — mục 3a, không phải 3c.

```
hộp bao dày = 17,5·cos(góc) + CHIỀU DÀI TẤM·sin(góc)
                             └────────┬────────┘
                          số này to → góc tí xíu cũng phình
tấm dài 1000mm nghiêng 0,9°  →  hộp bao 33,1mm
```

**Nếu đúng, đây là chuyện nặng hơn tôi tưởng:** không cần nghiêng nhiều — **lệch trục dưới
1 độ** là đủ, vì tấm càng dài sai số càng lớn. File tên `cat_GOC` (cắt góc) đúng loại việc
hay sinh tấm lệch trục.

**Hệ quả cho cách sửa:** thêm nhân transform **không cứu được gì**. Phải **bỏ hẳn cách đo bằng
hộp bao**, thay bằng: lấy pháp tuyến mặt lớn nhất → chiếu mọi đỉnh lên pháp tuyến đó → khoảng
max-min chính là độ dày thật, đúng bất kể tấm nghiêng bao nhiêu.

> **Chưa chốt** cho tới khi probe xác nhận. Không sửa code theo giả thuyết.

*(Cách kiểm tay bằng Scale ở dưới vẫn giữ — nó dò một cơ chế KHÁC có thể cũng đang tồn tại
song song. Chưa kiểm.)*

> ### Kiểm tay (cơ chế scale — vẫn chưa kiểm)
> 1. Vẽ tấm bất kỳ dày **18**, Make Group.
> 2. Scale tool kéo ×2 **theo chiều dày**. Đo bằng thước SketchUp: thật là **36**.
> 3. Chạy **Kiểm Tra Độ Dày**.
> - Báo **36** → cơ chế scale không dính.
> - Báo **18** → dính **cả hai** cơ chế cùng lúc.

---

## A3. Trung Tâm phân loại tấm bằng kích thước BẢN GỐC

**Ở đâu:** `trung_tam/main.rb:145-152`

```ruby
ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
dims = [bb.width.to_f, bb.height.to_f, bb.depth.to_f].sort   # ← local, chưa nhân te
return unless th_mm >= MIN_TH_MM && th_mm <= MAX_TH_MM       # ← lọc bằng số local
...
pts = box_corners(bb, te)                                    # ← chỗ VẼ thì có nhân te
```

**Sai gì.** Cùng một hàm: **lọc bằng số local, vẽ bằng số world.** Tấm bị scale ra ngoài dải
`MIN_TH_MM..MAX_TH_MM` sẽ bị **loại khỏi danh sách** — tool coi như tấm đó không tồn tại.

**Nặng vì:** đây là **bỏ sót im lặng**. Tool không báo sai, nó báo *"không thấy tấm nào"* —
mà thực ra là nó không nhìn.

> ### Kiểm tay
> Lấy tấm ở A2 (đã scale dày thành 36), chạy **Trung Tâm**. Tấm đó có xuất hiện trong danh
> sách không? Nếu tấm biến mất khỏi danh sách mà mắt vẫn thấy nó trong model → đúng bug.

---

# B. NẶNG — bỏ sót im lặng khi tấm NGHIÊNG

**Ở đâu:** `kiem_tra_ten/main.rb:104` · `kiem_tra_ban_le_chan/main.rb:189` ·
`kiem_tra_lien_ket/main.rb:366` · `kiem_tra_led/main.rb:139`

Bốn tool này dùng `world_aabb(ents, te)` — **có nhân transform, đúng bài về scale**. Nhưng hộp
bao ra là **hộp THẲNG TRỤC theo thế giới** (mục 3a). Rồi lấy luôn các cạnh hộp đó làm
"dày / rộng / dài" để **lọc xem có phải tấm ván không**:

```ruby
dz <= DAY_MAX_MM && dx >= CANH_MIN_MM && dy >= CANH_MIN_MM   # kiem_tra_ban_le_chan:189-191
th >= MIN_TH_MM && th <= MAX_TH_MM && ...                    # kiem_tra_ten:104
```

**Sai gì.** Tấm nằm ngang, xoay quanh trục đứng → hộp bao vẫn cho độ dày đúng, **không sao**.
Nhưng tấm **NGHIÊNG** (kệ vát, tấm trần dốc, hông tủ xiên) → hộp bao thẳng trục **phồng theo
chiều dày**. Tấm dày 18 nghiêng 30° cho `dz ≈ 18·cos30 + rộng·sin30` — có thể ra hàng trăm mm.
Vượt `DAY_MAX_MM` → **rớt khỏi bộ lọc → không bao giờ được kiểm**.

**Nặng vì:** giống A3 — tool báo "đạt" trong khi nó **chưa từng nhìn** vào tấm đó. Đây là kiểu
sai tệ nhất: nó tạo cảm giác đã kiểm rồi.

> ### Kiểm tay
> 1. Lấy một tấm bình thường, **xoay nghiêng 30°** (nghiêng thật, không phải xoay nằm ngang).
> 2. Cố tình để tấm đó **thiếu tên** (hoặc thiếu bản lề, tuỳ tool đang thử).
> 3. Chạy **Kiểm Tra Tên** (rồi **Kiểm Tra Bản Lề Chân**).
> - Tool tìm ra tấm thiếu tên → tôi sai.
> - Tool báo "tất cả đã có tên" → **đúng bug**: nó bỏ qua tấm nghiêng.

---

# C. VỪA — sai khi thợ đang ĐỨNG TRONG tủ

**Ở đâu:** `auto_dan_canh/main.rb:269` và `:292`

```ruby
model.selection.each { |e| collect_boards(e, e.transformation, boards, 0) }
#                                            ^^^^^^^^^^^^^^^^ mồi chuỗi transform
```

**Sai gì.** `e.transformation` là transform **so với ngữ cảnh đang mở**, không phải so với thế
giới. Người dùng nhấp đúp **vào trong** tủ rồi chọn tấm → thiếu `model.edit_transform` → toạ độ
thế giới lệch đúng bằng vị trí của tủ.

**Bằng chứng đây là lỗi chứ không phải kiểu code:** **chính file này** ở dòng `96` và `195` làm
ĐÚNG — dựng đủ chuỗi từ `path[0..-2]`. Một tool, hai đường, hai kiểu. Và `model.edit_transform`
xuất hiện **đúng 1 lần trong cả 11.000 dòng** của kho (`canh_cnc/main.rb:445`).

> ### Kiểm tay
> 1. Dựng tủ: tấm trong group, group đặt **cách gốc toạ độ vài mét**.
> 2. **Nhấp đúp vào tủ** để chui vào trong, rồi chọn một tấm.
> 3. Chạy **Auto Dán Cạnh**.
> - Cạnh dán đúng lên tấm → tôi sai.
> - Cạnh dán lệch đi (hoặc rơi về gần gốc toạ độ) → **đúng bug**.
> 4. Đối chứng: thoát ra ngoài cùng, chọn cả tủ, chạy lại → lần này phải đúng.

---

# D. VỪA — pháp tuyến tính sai khi tấm bị scale lệch / lật gương

**Ở đâu:** `auto_dan_canh/main.rb:459` · `chia_lam/main.rb:183, :324` ·
`dim_nhanh/main.rb:376` · `shared/laser_snap.rb:354`

```ruby
world_normal = local_normal.transform(world_xform)    # auto_dan_canh:459
n = tr * face.normal                                  # dim_nhanh:376
```

**Sai gì.** Vectơ pháp tuyến **không** biến đổi bằng chính ma trận — nó biến đổi bằng
**nghịch đảo-chuyển vị**. Chỗ này chỉ đúng khi transform là xoay + dời + phóng ĐỀU. Gặp:

- **scale lệch một chiều** (kéo giãn tấm theo 1 trục) → pháp tuyến **hết vuông góc với mặt**
- **lật gương** (Flip Along — cánh trái/cánh phải!) → pháp tuyến **chỉ ngược hướng**, đâm vào
  trong tấm thay vì ra ngoài

`auto_dan_canh` dùng `world_normal` so với hướng camera để quyết định đâu là **mặt tiền**. Pháp
tuyến ngược → chọn nhầm mặt → **dán cạnh sai mặt, mà màn hình vẫn thấy có dán**.

**Bằng chứng phụ:** soi cả kho, **không một dòng nào** xét định thức ma trận hay cờ lật gương.
Bộ plugin hiện **mù hoàn toàn** với chuyện lật gương.

> ### Kiểm tay
> 1. Dựng một tấm cánh, chạy **Auto Dán Cạnh** → ghi nhớ nó dán cạnh nào.
> 2. Copy tấm đó, chuột phải → **Flip Along → Red** (thành cánh đối xứng).
> 3. Chạy **Auto Dán Cạnh** lên tấm đã lật.
> - Dán ra cạnh **đối xứng** với bản gốc → đúng, tôi sai.
> - Dán ra **y hệt** bản gốc, hoặc dán sang mặt sau → **đúng bug**.

---

# E. NHẸ — sửa được ngay, không cần kiểm gì

Thiếu `abort_operation` ở nhánh lỗi → tool chết giữa chừng thì model **kẹt nửa vời**, Ctrl+Z
không gỡ được bằng một phím.

| File | start | commit | abort |
|---|---|---|---|
| `chia_lam/main.rb` | 1 | 1 | **0** |
| `kiem_tra_do_day/main.rb` | 2 | 2 | **0** |
| `dim_nhanh/main.rb` | 2 | 2 | **1** (thiếu 1 nhánh) |

*(LUAT_NHA mục A đã ghi nhận từ 20/06, chưa dọn. 11/11 tool sửa model đều bọc start+commit
đầy đủ — chỉ hở đường thoát.)*

---

# F. CHƯA RÕ Ý ĐỊNH — cần ông trả lời, không phải lỗi

## F1. Điền Tên đổi tên tấm bên trong Component → lây sang MỌI bản sao của tủ

`dien_ten/core/namer.rb:58` đi vào `entity.definition.entities` để gom tấm, rồi `:43`
`entity.name = ...`. Tấm nằm trong definition của một Component là **dùng chung**: đặt tên tấm
trong tủ bếp số 1 thì tủ bếp số 2, 3, 4 (cùng component) **đổi tên theo**. Không có `make_unique`.

**Có thể đây là điều ông muốn** (cùng component = cùng tên, hợp lý). Cũng có thể không.

> **Câu hỏi cho ông:** khi hai tủ giống hệt nhau là **cùng một Component**, ông muốn tấm trong
> đó mang **cùng tên** (hiện tại đang vậy), hay mỗi tủ một tên riêng?

---

# Bảng tổng — điền khi kiểm

| # | Tool | Nghi gì | Nặng | Kiểm tay | Kết quả |
|---|---|---|---|---|---|
| A1 | Điền Tên | tên sai + gộp nhóm sai khi tấm bị Scale | ●●● | scale ×2, xem tên | |
| A2 | Kiểm Tra Độ Dày | bỏ qua transform hoàn toàn | ●●● | scale dày ×2, xem số | |
| A3 | Trung Tâm | lọc bằng số local → tấm biến mất | ●●● | tấm scale còn trong list? | |
| B | Tên · Bản Lề Chân · Liên Kết · LED | tấm NGHIÊNG bị bỏ sót im lặng | ●●● | xoay nghiêng 30°, xem có bắt | |
| C | Auto Dán Cạnh | sai khi đứng trong tủ | ●● | nhấp vào tủ rồi chạy | |
| D | Dán Cạnh · Chia Lam · Dim · LaserSnap | pháp tuyến sai khi lật gương | ●● | Flip Along rồi chạy | |
| E | Chia Lam · Độ Dày · Dim | thiếu `abort_operation` | ● | không cần kiểm, sửa luôn | |
| F1 | Điền Tên | tên lây sang mọi bản sao component | ? | ông trả lời câu hỏi trên | |

---

## Đọc bảng này thế nào

**Ba mục nặng nhất (A2, A3, B) đều là BỎ SÓT im lặng, không phải số sai.** Tool không nói dối —
nó nói *"không có vấn đề"* trong khi nó chưa từng nhìn vào tấm đó. Đó là lý do bộ plugin chạy
êm suốt thời gian qua: **những tấm gây lỗi chính là những tấm nó bỏ qua.**

**Thứ tự nên kiểm:** A2 trước (dễ dựng nhất, 1 phút, và chắc chắn nhất — hàm đó không nhận
tham số transform, không có đường nào để đúng). Rồi A1, rồi B.

---

*Nguồn: soi tĩnh 11.000 dòng Ruby trong `LeHai_Tools/`, 01/08/2026. Chưa chạy SketchUp lần nào.
Mỗi mục kiểm xong → ghi kết quả vào bảng + một dòng vào [NHAT_KY.md](NHAT_KY.md).*

---

# G. Kiểm Tra Liên Kết (ngàm) — ĐÃ ĐO, KHÔNG PHẢI LỖI

**01/08.** Khoa: dashboard báo *4 mối ngàm "2 tấm đâm xuyên 17.5mm chưa khoét"* trong khi nhìn
model không thấy gỗ nào cấn vào.

**Kết luận: tool báo ĐÚNG.** Khoa tự dựng file đối chứng 2 tấm có ngàm thật + dấu ABF → tool
nhận đúng *"Đã làm NGÀM ✓"*, cả bảng xanh. Còn trong file gốc, gỗ **thật sự đang chồng gỗ
17.5mm** — chỗ đó Khoa cố ý để vậy vì sẽ **khoét tay ở xưởng**, không làm ngàm trong model.

**Cách tool nghĩ** (đọc `kiem_tra_lien_ket/main.rb`, ghi lại để khỏi phải đọc lại):

```
GĐ1 — xếp cặp + ra con số 17.5mm:  CHỈ dùng HỘP BAO world (overlap_box:176).
      Chưa nhìn thấy một mặt gỗ nào. Cạnh nhỏ nhất khối giao rơi 15–20mm → gọi "ngàm".
GĐ2 — phán đã khoét hay chưa:      CÓ dùng mặt thật (collide_frac:202) — dựng tam giác
      từ Face, bắn tia +X đếm giao lẻ, lưới SAMPLE_N=3 (27 điểm), ngưỡng 0.4.
      made = frac < 0.4  (đâm xuyên thấp = đã khoét bằng tay)
```

Tức là **tên gọi và con số đến từ hộp; lời phán đến từ mặt.** GĐ2 chính là cái chặn được
"hộp bao lừa" — nên giả thuyết hộp-lừa không giải thích được ca này, và hoá ra không cần
giải thích, vì không có lỗi.

## G1. VIỆC THẬT CẦN LÀM — không phải sửa lỗi, là thêm trạng thái thứ 3

Tool có 2 trạng thái, thực tế Khoa có 3:

| | Thực tế | Tool xếp | Đúng? |
|---|---|---|---|
| 1 | đã làm (có ABF / đã khoét trong model) | xanh | ✓ |
| 2 | quên chưa làm | đỏ | ✓ |
| 3 | **cố ý để vậy, khoét tay ở xưởng** | đỏ | ✗ **dồn nhầm vào (2)** |

**Rủi ro thật không phải báo thừa** — mà là Khoa dần quen với chấm đỏ vô hại rồi **bắt đầu bỏ
qua chấm đỏ**, đến lúc có mối quên thật thì nó trôi qua. Đây là kiểu hỏng của hệ thống báo động,
không phải của code. File 4 mối còn nhớ được; file 40 mối thì không.

**Hướng làm (chưa chốt, cần Khoa quyết):** cho phép đánh dấu một mối là *"cố ý — khoét tay"*
rồi tool nhớ và xếp riêng, thay vì bắt Khoa nhớ trong đầu.

> **Câu hỏi cho Khoa:** đánh dấu theo cách nào tiện cho ông nhất — đặt tên tấm theo quy ước,
> gắn tag, hay bấm nút ngay trong bảng khi đang soi mối đó?

## G2. Ghi nhận cách kiểm của Khoa — nên thành thói quen

Khoa tự dựng file sạch 2 tấm để thử cái **đã biết trước câu trả lời**, thay vì tranh luận trên
file khách 443 tấm. Đó chính là tinh thần `MAU_CHUAN.md`, làm theo bản năng chứ không theo tài
liệu. **Ca nào nghi ngờ tool → dựng 2 tấm thử trước, rẻ hơn mọi cách khác.**
