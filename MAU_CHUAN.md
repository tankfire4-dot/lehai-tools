# Mẫu Chuẩn — Thước Đo Cho Plugin

**Đây là cái thước.** Không có nó thì "tool chạy đúng" chỉ là cảm giác.

Một file SketchUp duy nhất chứa 9 tấm gỗ **đã biết trước kích thước thật**, mỗi tấm cố tình
dựng theo một kiểu bậy mà thợ hay làm. Chạy tool lên file này, số nào lệch bảng đáp án là lộ.

Dựng **một lần**, dùng mãi. Khoảng 20–25 phút.

---

## Quy ước chung

- File lưu tại: `lehai-tools/mau_chuan/MAU_CHUAN_v1.skp`
  *(thư mục ở gốc kho → `release.py` **không** đóng gói vào `.rbz`, thợ không nhận. Đã kiểm.)*
- Đơn vị model: **mm** (Window → Model Info → Units → Millimeters, Precision 0,0mm)
- **Mỗi tấm phải đặt TÊN** qua Entity Info → ô Name: `MC_A`, `MC_B`, … `MC_I`.
  Probe tìm tấm theo tên này. Sai tên là probe mù.
- Vật liệu: để mặc định, không sơn. Tag/Layer: để `Untagged` hết.
- Xếp các tấm cách nhau ~1000 mm cho dễ nhìn, trừ MC_F (cố tình ở xa) và MC_I (cố tình sát nhau).

**Tấm nền dùng chung:** vẽ hình chữ nhật → Push/Pull ra độ dày → chọn hết → chuột phải → Make Group.

---

## 9 tấm

### MC_A — Tấm chuẩn (mốc so sánh)
Vẽ 800 × 400, push/pull **18**. Group. Đặt tại gốc toạ độ.
**Thật: 800 × 400 × 18**
→ *Bẫy: không có. Đây là mốc. Tool nào sai ở đây thì sai cơ bản, dừng luôn khỏi đo tiếp.*

### MC_B — Tấm bị Scale
Vẽ **400** × 400, push/pull 18, Group. Rồi dùng **Scale tool kéo ×2 theo chiều dài** (không
push/pull, không vẽ lại) cho ra 800.
**Thật: 800 × 400 × 18**
→ *Bẫy mục 3c. `definition.bounds` sẽ nói **400**. Tool đặt tên tấm sẽ ghi số sai.*

### MC_C — Tấm xoay chéo
Copy MC_A, **xoay 30° quanh trục lam (Z)**.
**Thật: 800 × 400 × 18**
→ *Bẫy mục 3a. `bounds` thẳng trục sẽ nói **≈ 892,8 × 746,4**. Cả hai số đều sai, cả hai đều
trông "hợp lý".*

### MC_D — Tấm lồng 3 cấp
Vẽ 600 × 300 × 18, Group. Rồi bọc thêm 2 lớp group nữa (chọn → Make Group, làm 2 lần).
**Dời cụm ngoài cùng đi (300, 200, 0) mm** — để lệch mới lộ được lỗi.
Đặt tên: cấp ngoài cùng `MC_D`, tấm trong cùng `MC_D_loi`.
**Thật: 600 × 300 × 18**, tâm tấm ở (300, 200, 9) so với thế giới
→ *Bẫy mục 3b + mục 5. Phải nhân dồn transform qua đủ 3 cấp. Thiếu 1 cấp là sai vị trí.*

### MC_E — Tấm lật gương
Copy MC_A, đặt cạnh bên, rồi chuột phải → **Flip Along → Group's Red**.
**Thật: 800 × 400 × 18** (kích thước y hệt MC_A)
→ *Bẫy mục 4. Định thức transform **âm**. Cạnh trái ↔ cạnh phải đảo. Tool dán cạnh phải ra
kết quả đối xứng với MC_A — nếu ra giống hệt MC_A là đã bỏ qua lật.*

### MC_F — Tấm ở xa gốc
Copy MC_A, dời tới **(50000, 30000, 0) mm** (50 m × 30 m — cỡ một mặt bằng lớn).
**Thật: 800 × 400 × 18**
→ *Bẫy mục 6. Xa gốc thì sai số dấu phẩy động phình lên, dung sai 0,0254 mm có thể không còn
giữ được. Kích thước phải vẫn ra đúng 800 × 400 × 18.*

### MC_G — Component dùng chung, một bản bị scale
Vẽ 700 × 350 × 18 → **Make Component** (không phải Group), tên definition `MC_G_def`.
Copy ra 1 bản thứ hai, **Scale bản thứ hai ×1,5 theo chiều dài**.
Đặt tên instance: `MC_G1` (bản gốc), `MC_G2` (bản đã scale).
**Thật: MC_G1 = 700 × 350 × 18 · MC_G2 = 1050 × 350 × 18**
→ *Bẫy mục 2 + 3c. Hai instance **chung một definition**. Tool nào sửa hình mà không
`make_unique` sẽ làm hỏng cả hai. Tool nào đo bằng `definition.bounds` sẽ nói cả hai đều 700.*

### MC_H — Độ dày lẻ
Vẽ 750 × 360, push/pull **17,5**. Group.
**Thật: 750 × 360 × 17,5**
→ *Bẫy mục 1. Tool làm tròn ẩu sẽ báo 18 (ván 17,5 và ván 18 là hai loại vật tư khác nhau,
đặt nhầm là mất tiền thật).*

### MC_I — Hai tấm hở dưới dung sai
Hai tấm 400 × 400 × 18, đặt **cách nhau đúng 0,02 mm** theo chiều dài.
Đặt tên `MC_I1`, `MC_I2`.
**Thật: hở 0,02 mm — tức là DƯỚI ngưỡng 0,0254 mm của SketchUp**
→ *Bẫy mục 6. SketchUp coi hai tấm này là **chạm nhau**. Tool báo "chạm" là đúng theo SketchUp;
tool báo "hở 0,02" là đang tự tính bằng số thực và **bất đồng với SketchUp** — cần biết tool nào
thuộc loại nào, vì kết quả sẽ đổi tuỳ chỗ nào hỏi trước.*

> Nếu đặt 0,02 mm khó quá (SketchUp có thể tự hít vào nhau), cứ đặt sát rồi ghi lại thực tế
> đặt được bao nhiêu — con số thật quan trọng hơn con số đẹp.

---

## Bảng đáp án

| Mã | Rộng | Sâu | Dày | Bẫy nhắm | Số SAI mà tool hay trả về |
|---|---|---|---|---|---|
| MC_A | 800 | 400 | 18 | — (mốc) | — |
| MC_B | 800 | 400 | 18 | scale (3c) | **400** × 400 × 18 |
| MC_C | 800 | 400 | 18 | xoay (3a) | **892,8 × 746,4** × 18 |
| MC_D | 600 | 300 | 18 | lồng 3 cấp (3b, 5) | đúng size, **sai vị trí** |
| MC_E | 800 | 400 | 18 | lật gương (4) | đúng size, **sai bên cạnh** |
| MC_F | 800 | 400 | 18 | xa gốc (6) | lệch ở số lẻ mm |
| MC_G1 | 700 | 350 | 18 | definition chung (2) | — |
| MC_G2 | 1050 | 350 | 18 | scale + chung (2, 3c) | **700** × 350 × 18 |
| MC_H | 750 | 360 | **17,5** | làm tròn (1) | dày **18** |
| MC_I | 2×400 | 400 | 18 | dung sai (6) | "hở 0,02" thay vì "chạm" |

---

## Sau khi dựng xong

1. Lưu `mau_chuan/MAU_CHUAN_v1.skp`, báo tôi một dòng.
2. Tôi viết probe đọc file này, so từng tấm với bảng đáp án trên.
3. Ông chạy probe trong SketchUp (Ruby Console), gửi tôi kết quả.
4. Tôi ra danh sách tool sai im lặng, xếp theo mức nguy → sửa dần.

**Luật đi kèm (chốt cùng file này):**

> **Chưa đo trên mẫu chuẩn thì chưa gọi là ĐẠT.** "Mở lên thấy chạy" chỉ là *chưa crash*.
> Tool mới, hoặc tool cũ vừa sửa, đều phải qua mẫu chuẩn trước khi lên `.rbz`.

**Mẫu chuẩn là file sống.** Mỗi lần phát hiện một kiểu bậy mới ngoài thực tế (thợ dựng kiểu lạ,
file khách có gì đó phá tool), thêm một tấm `MC_J`, `MC_K`… vào đây kèm đáp án. Thước dài ra thì
đo được nhiều hơn.

---

*Lập 01/08/2026. Đi kèm [SKETCHUP_NEN_TANG.md](SKETCHUP_NEN_TANG.md) — số trong ngoặc (3a, 5…)
là mục trong file đó.*
