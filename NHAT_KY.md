# Nhật Ký Phát Triển — LeHai Tools

Sổ ghi **vì sao**, không phải vì sao kỹ thuật khô khan mà là lý do thật đằng sau mỗi quyết định —
để sau này bất kỳ ai (kể cả một AI khác, hoặc chính Khoa) cầm repo lên đều hiểu được mạch suy nghĩ,
không phải đoán mò.

- **CLAUDE.md** = hiến pháp ngắn: cách làm việc + luật nhà + cấu trúc (đọc mỗi phiên).
- **NHAT_KY.md** (file này) = sổ công trình: kể lại từng quyết định + vì sao + bài học (tra khi cần).
- Mục mới thêm lên **trên cùng** (mới nhất trước).

Mỗi mục theo khung: **Vấn đề → Quyết định → Vì sao → Bài học/Rủi ro.**

---

## 2026-07-20 — Chống Bay v1.9.48: một chữ số, và mỗi lượt kéo đúng 9 cái

**Vấn đề:** Khoa xuất DXF sang Aspire, danh sách layer hiện `...1, ...10, ...11, ...12, ...2, ...3`.
Không phải DXF thiếu layer — đủ cả 24. Aspire **sắp tên bằng chuỗi**.

**Đây là con bug đã bắt hai lần trong chính code tool** (bảng điều khiển, rồi bảng tổng kết). Cả hai
lần tao vá đúng chỗ Khoa chỉ. Lần này nó xuất hiện ở nơi tao **không vá được** — Aspire không phải
code mình.

**Quyết định:** hạ trần từ 12 xuống **9 đợt**. Một chữ số thì sắp chuỗi trùng sắp số ở mọi phần mềm.

**Vì sao không đệm số 0 (`01`…`12`):** đệm 0 chữa được và giữ đủ 12 đợt — tao đã làm bản đó trước.
Nhưng đổi tên tag nghĩa là phải **khai lại toàn bộ tên bên ABF**, lệch một ký tự là ABF im lặng
không nhận. Khoa cân hai bên rồi chọn 9: xưởng chưa bao giờ chạm trần 12, còn khai lại tên là việc
tay có thể sai âm thầm.

**Sửa thứ hai (Khoa phát hiện khi nhìn màu):** một lượt kéo trúng 12 chi tiết thì số quay vòng —
chi tiết thứ 10 nhận lại số 1, **cùng màu với chi tiết thứ nhất trong cùng một lượt**. Nhìn không ra
là cố ý hay lỗi. Nay mỗi lượt kéo nhận tối đa `đợt_cuối − đợt_đầu + 1` chi tiết, dư thì bỏ phần cuối
và báo rõ; kéo lượt nữa cho chúng. Số **vẫn** lặp giữa các lượt — đó mới là nghĩa "đợt cắt".

**Bài học:**
1. **Khi một cái tên bị nhiều phần mềm đọc, sửa CÁI TÊN chứ đừng sửa từng người đọc.** Vá chỗ hiển
   thị là chữa triệu chứng ở những nơi mình với tay tới được, rồi để nguyên bệnh cho nơi mình không
   với tới. Ở đây "sửa tên" hoá ra là **thu hẹp miền giá trị** (≤9) — rẻ hơn đổi định dạng tên.
2. **Màu và số phải đọc được như nhau.** Màu sinh ra từ số, nên số trùng là màu trùng. Nếu miền số
   nhỏ hơn số vật thể thì đừng quay vòng im lặng — cắt bớt và nói ra.

---

## 2026-07-19 — Chống Bay: tool quét đổi tag chi tiết nhỏ (tool thứ 17)

**Vấn đề:** chi tiết nhỏ bay khi chạy đường cắt chính — mất lực hút chân không rồi văng. Khoa muốn
đánh dấu riêng mấy chi tiết đó để bên Aspire chạy dao khác (giữ lại, cắt sau, hoặc chừa da).

**Điều tra (probe đọc file đã nest):** ABF **không** dồn hết vào một tag — `ABF_cuttingLines` chỉ
chiếm 4.7% (250/5318 entity). Mỗi loại gia công có tag riêng: `ABF_Groove` (rãnh), `ABF-D35` +
`ABF-D3` (khoan cốc bản lề Ø35 + 2 lỗ vít Ø3), `ABF_Label`, `ABF_sheetBorder`. **Tag đặt theo đường
kính khoan** (`ABF-D<Ø>`) — nghĩa là muốn thêm lỗ vít chống bay thì đã có sẵn khuôn, không phải
phát minh gì.

**Quyết định:** viết tool quét riêng, **không dùng selection của SketchUp**. Tự chiếu cạnh thật của
từng chi tiết lên màn hình rồi so với khung quét (cắt đoạn thẳng, không dùng hộp bao).

**Vì sao không dùng selection:** chi tiết nằm trong `__ABF_Nesting`. Quét ở ngoài group thì SketchUp
chỉ chọn được nguyên cả cục — Khoa quét thật, Entity Info báo "No Selection". Không phải lỗi vặt sửa
được, là bản chất cách SketchUp chọn. Đã thử cả hướng SelectionObserver (quét xong tự đổi) — vẫn
chết vì cùng lý do: không có gì để observe.

**Vì sao không dùng hộp bao:** chi tiết nesting nằm xiên → hộp bao phình to, vừa vẽ xấu (khung chồng
nhau) vừa quét lẹm sang cái bên cạnh. Dùng cạnh thật chữa cả hai bằng một thay đổi.

**Bài học / Rủi ro (cả hai đều trả giá bằng lần chạy thật, không phải suy đoán):**
1. **Tag ABF nằm ở EDGE, không nằm ở GROUP vỏ.** Group `_ABF_Label`, `_ABF_hingeCup`,
   `_ABF_Intersect`, `__ABF_Nesting` đều đeo `Layer0`; edge bên trong mới mang tag thật. Chỉ đổi tag
   ở group thì **DXF ra layer rỗng mà trong SketchUp nhìn vẫn thấy "có tag"** — bug im lặng.
   (Ngoại lệ: `_ABF_cuttingLines` và `__ABF_sheetBorder` đeo tag ở cả hai cấp.)
2. **Chi tiết nesting DÙNG CHUNG group.** Lần chạy thật báo "tách 18 container dùng chung". Không
   `make_unique` trước khi sửa thì đổi 18 cái là 18 cái ở tấm khác đổi lây, không hiện triệu chứng
   gì cho tới lúc ra máy cắt. `make_unique` thay entity cũ bằng entity mới → phải **quét lại danh
   sách sau mỗi lần đổi**, không tin danh sách cũ.

**Chưa kiểm được:** máy không có Ruby nên chưa chạy `ruby -c`. Bản chạy tay qua Ruby Console (bản
nháp cùng logic) đã đổi được 33/50 chi tiết trên file thật. Bản đóng vào repo **chưa chạy lại** —
phải test qua Ruby Console trước khi release.

**Kiểm chứng rạng sáng 20/07 (Khoa chạy thật):** quét chi tiết có `_ABF_hingeCup` nằm LỒNG BÊN
TRONG — lỗ bản lề `ABF-D35`/`ABF-D3` **giữ nguyên tag**, chỉ viền `ABF_cuttingLines` bị đổi.
Xác nhận bộ lọc per-entity đúng như thiết kế: tool đi xuyên mọi tầng con nhưng chỉ đổi entity có
tag khớp họ cutting-lines/CHONGBAY; group lồng trong và mọi tag gia công khác không bị chạm.

**Bổ sung cùng ngày — chế độ GỠ, và cách gỡ ĐÚNG:**

Thiếu đường gỡ khi quét nhầm (Ctrl+Z chỉ lùi được theo thứ tự, không chọn được cái nào). Thêm
**chế độ GỠ vào chính vòng Tab** (TRAI → PHAI → GỠ), không thêm phím mới.

Bản đầu gỡ bằng cách **gán về `ABF_cuttingLines`**. Khoa bác: *"nhiều khi cái suy nghĩ xóa để về lại
ABF cutting line của ABF lại lỗi, vì tụi mình không hiểu rõ nó là gì."* Đúng — đó là **giả định**
không có gì bảo đảm. Nay đổi: lúc gắn thì **ghi tag gốc lên chính entity** (`LeHai_ChongBay/tag_goc`),
lúc gỡ thì đọc ra mà trả về, xong xoá ghi chú. `ABF_cuttingLines` tụt xuống chỉ còn là **đường lui**
khi không có ghi chú. Khuôn: `auto_dan_canh/main.rb:504-517` (nhớ `OriginalMat` rồi trả lại).

Ghi tag gốc **một lần duy nhất** — chuyển trái ↔ phải nhiều lần vẫn gỡ về đúng cái ban đầu.

**Bài học (Khoa dạy, đáng giữ):** khi phải hoàn tác một thay đổi, đừng hỏi "trạng thái ban đầu chắc
là gì" — hãy **ghi lại nó lúc còn thấy**. Suy đoán về hệ thống mình không viết ra là chỗ đẻ lỗi.

**Sự cố cùng ngày:** bê code từ scratchpad sang repo, rơi mất hàm `find_tag` mà vẫn giữ 2 chỗ gọi →
`undefined method` chỉ nổ trên nhánh gỡ. Mất 3 vòng test của Khoa. Cách chặn (quét gọi-vs-định-nghĩa,
không cần Ruby) đã ghi vào `shared-notes/sketchup-api.md` mục 1b, kèm mẫu bọc `rescue` cho callback
của `Sketchup::Tool` — SketchUp nuốt exception trong callback thành backtrace cụt, không hộp thoại.

**Bỏ cột "Phiên này" trong bảng tổng kết:** cột đó cộng dồn từng nhát quét nên quét đi quét lại thì
đội số lên quá cả số chi tiết có thật (báo "vừa gắn 34" trong khi cả file có 26). Khoa phát hiện vì
**con số vô lý với thực tế xưởng**. Đã bỏ hẳn cột, bảng chỉ báo trạng thái hiện tại. Bất biến kiểm
được bằng mắt: **số lớn + "chưa gắn" = tổng chi tiết của file**.

**Phụ — bảng namespace trong CLAUDE.md đã lệch, nay sửa:** Claude nói "tool thứ 17" trong khi
toolbar thật chỉ có 13 nút; Khoa nhìn toolbar thấy vênh nên hỏi lại. Truy ra bảng cũ vừa **thiếu**
(không có `LedCheck`, `NameCheck`, `EdgeBandCheck`) vừa **không phân biệt** module có nút riêng với
module chạy trong dashboard. Nay bảng có cột "Nút", ghi rõ nguồn sự thật của từng cột (thư mục
`LeHai_Tools/*/` cho module, mảng `groups` trong `main.rb` cho nút), và cảnh báo rằng **module chạy
trong dashboard KHÔNG nằm trong `require` của `main.rb`** — dashboard tự nạp lấy
(`soat_truoc_xuat/main.rb:21`), nên `main.rb` không phải danh sách module đầy đủ.

Bài học: **tài liệu đếm số là thứ tự hỏng âm thầm.** Không ai sai lúc viết, nó lệch dần theo mỗi
lần thêm tool. Cách chữa không phải "nhớ cập nhật" mà là **ghi nguồn sự thật ngay trong bảng** để
lần sau kiểm được bằng một lệnh thay vì bằng trí nhớ.

---

## 2026-07-03 — Liên Kết: đo ĐÂM XUYÊN GỖ THẬT thay bbox + check Đặt Tên (v1.9.38)

**Vấn đề (Khoa phát hiện):** JointCheck dùng bounding box → mù với ngàm KHẤU TAY (đục mộng thủ công,
không dấu ABF). 110 mối "thiếu ngàm" phần lớn là báo nhầm ngàm khấu tay. Khoa hỏi: dùng hình học thật
của tấm có phân biệt được không?

**Điều tra (probe `dam_xuyen_probe.rb`):** đo % đâm xuyên gỗ đặc (point-in-solid bằng bắn tia) cho
từng cặp. Kết quả LẬT NGƯỢC giả định: **84 mối "đã làm bằng ABF" thì 76 vẫn đâm xuyên 100%** → ABF chỉ
DÁN NHÃN `_ABF_Intersect`, KHÔNG cắt khối 3D (cắt xảy ra ở khâu xuất DXF). Ngược lại 30 mối "thiếu"
thực ra đã khấu TAY (đâm xuyên ~0%, vì cắt gỗ thật trong model).

**Quyết định:** Công thức đúng = **Đã xử lý nếu (có dấu ABF) HOẶC (gỗ đã khoét = đâm xuyên < 40%)**;
Lỗi nếu (không ABF) VÀ (còn đâm xuyên). Thêm point-in-solid (Möller–Trumbore ray +X) vào JointCheck,
CHỈ đo cặp không-ABF (tối ưu). Ngàm quay về LỖI ĐỎ (bỏ cảnh báo vàng — giờ đã chính xác). Vẫn phân
biệt rãnh hậu 10mm vs ngàm 17.5mm bằng band.

**Tối ưu tốc độ:** probe thô 30s → sau tối ưu <10s. Bằng: (1) chỉ đo cặp không-ABF, (2) lọc tam giác
theo Y-Z bbox + xmax trước khi tính giao, (3) lưới mẫu 3×3×3, (4) lazy build tam giác + cache 1 lần
quét (dashboard gọi audit 2 lần rãnh hậu/ngàm dùng chung).

**Đặt Tên — `TK::NameCheck` (kiem_tra_ten):** CẢNH BÁO vàng. "Chưa đặt tên" = rỗng HOẶC số trơn
(vd "31", "608" — SketchUp tự đặt). Vì nhiều check (Bản Lề) dựa tên. Dashboard giờ 8 mục.

**Bài học:** (1) LUÔN đo trên file thật — giả định "ABF cắt gỗ" sai hoàn toàn. (2) Bounding box nhanh
nhưng mù chi tiết; point-in-solid chậm hơn nhưng "nhìn gỗ thật" — dùng bbox prefilter + point-in-solid
xác nhận là cân bằng tốt. (3) Ngưỡng đâm xuyên 40% + lưới 3×3×3 có thể cần tinh chỉnh nếu gặp khấu nông.

---

## 2026-07-03 — Rãnh Led (cảnh báo) + Xóa tên cho Dọn Component (v1.9.36)

**Rãnh Led — `TK::LedCheck` (folder kiem_tra_led):** mảnh cuối bộ Check Chốt Sản Xuất. Điểm khác mọi
check trước: **trạng thái CẢNH BÁO (vàng)**, không phải lỗi đỏ — vì ~80% căn có led nhưng KHÔNG xác
định chắc căn nào có. Dashboard thêm status `:warn` (chấm vàng, banner vàng riêng, không kích hoạt
"có lỗi cần xử lý"), nút Xem vẫn lướt được.

Bài học đắt: ban đầu tôi thiết kế check dựa THANH ĐÈN led (NTT: `ABF_LED`/tag `NTT_led`). Test file
thật → SAI: file sản xuất chỉ còn RÃNH PHAY led (ABF: `_ABF_Intersect`/tag `ABF_PHAYLED`, cùng họ
`ABF_PHAYRANHHAU`/`ABF_NGAM`), đã bỏ thanh đèn (đèn mua sẵn, không cắt CNC). Phải LẬT NGƯỢC: rãnh phay
mới là bằng chứng "đã làm led". Luật cuối: có rãnh phay → ĐẠT (xanh, lướt xem rãnh); có thanh đèn mà
thiếu rãnh gần (NEAR 60mm) → cảnh báo lướt thanh; không có gì → cảnh báo mức file. → **Bài học: luôn
test trên FILE THẬT (đã qua quy trình sản xuất) chứ không chỉ file dựng thử.**

**Xóa tên — Dọn Component (`TK::GoGroup`):** thêm checkbox "Xóa tên (gồm cả tấm con)" — xóa Instance
name của group/component, đệ quy toàn cây (nhất quán với xóa màu/tag/thuộc tính). Nằm trong 1 operation
nên Ctrl+Z lùi được.

---

## 2026-07-02 — Đồng bộ giao diện 8 dialog theo theme LeHai (v1.9.33)

**Vấn đề:** Các dialog mỗi tool một kiểu (đen tím "lập trình viên", xanh dương văn phòng, hồng neon,
xanh Google...) — không khớp màu chủ đạo kem+walnut+amber đã chốt cho icon toolbar + theme.

**Quyết định:** Khoác đồng phục cho CẢ 8 dialog còn lệch: Tạo Tấm Gỗ, Điền Tên, Kiểm Tra Độ Dày,
Dọn Component, Trục Tọa Độ, Tạo Cánh CNC, Auto Dán Cạnh, Thư Viện (2 cái đã chuẩn từ trước: Check
Chốt Sản Xuất + bảng kê Dim Nhanh → 10/10). CHỈ đổi CSS/màu/font — không đụng nút, ô nhập, logic.
Kèm polish: thanh cuộn + ::selection theo theme (đặt trong `shared/lehai_theme.css` để mọi dialog
inject hưởng chung; 3 dialog dùng file .html riêng thì chép khối đó vào).

**Vì sao / Cách làm:** Dialog xây HTML trong Ruby → đọc file theme nhét vào `<style>#{theme}` (mẫu
Dim Nhanh). Dialog dùng file .html riêng → nhúng `:root` biến LeHai trực tiếp (không link tương đối
— tự chứa, không sợ đường dẫn gãy). Thư Viện đã dùng biến CSS sẵn → chỉ thay giá trị bảng màu gốc.
NGOẠI LỆ có chủ đích: nút X/Y/Z của Trục Tọa Độ giữ đỏ-lục-lam (màu trục chuẩn SketchUp — ngữ nghĩa,
đổi là mất thông tin); màu gỗ trong canvas preview Tạo Tấm Gỗ giữ nguyên (nó LÀ gỗ).

**Bài học / Rủi ro:** Font DM Sans load từ Google Fonts — máy offline sẽ rơi về Segoe UI (chấp nhận
được, màu vẫn đúng). Soát mặt hàng loạt bằng `claude_work/xem_giao_dien.rb` (mở 7 dialog 1 lệnh).

---

## 2026-07-02 — Trạm phát update (chuẩn bị khóa repo private) (v1.9.31)

**Vấn đề:** Repo public = luật nghề xưởng (rãnh hậu 10mm, ngàm 17.5, quy tắc bản lề, cấu trúc ABF)
phơi công khai — ai cũng đọc/copy được. Repo private thì auto-update của máy thợ (đọc raw GitHub) chết.
Phương án "đặt pass trong plugin" bị loại: chìa nằm trên mọi máy thợ + token hết hạn = cả xưởng chết
update không cứu từ xa được.

**Quyết định:** Dựng **trạm phát** — Cloudflare Worker `lehai-update` (`tram_phat/worker.js`, cùng
account với máy đếm `gateway/`). Trạm giữ GH_TOKEN (fine-grained, CHỈ-ĐỌC, CHỈ repo lehai-tools,
không hết hạn) trong secret Cloudflare; máy thợ hỏi trạm thay vì GitHub. Trạm CHỈ phát version.json +
LeHai_Tools* — không phát lịch sử git/file khác. v1.9.31 đổi URL updater (cả emergency updater) sang
`https://lehai-update.tankfire4.workers.dev/`, phát qua đường cũ lần cuối.

**Trình tự an toàn (QUAN TRỌNG cho lần sau):** dựng trạm → phát bản đổi đường → **CHỜ mọi máy lên
1.9.31** (soi `/stats?key=...` của máy đếm — có bảng theo version) → LÚC ĐÓ mới chuyển repo private.
Khóa sớm = máy chưa update kẹt vĩnh viễn, phải cài tay .rbz.

**Bài học:** (1) Dán secret vào prompt tương tác của wrangler dễ dính ký tự rác (secret thành 1 ký
tự "*") — dùng `Get-Content file | wrangler secret put X` chắc ăn; debug bằng cách in tokenLen (không
lộ token). (2) `git add -A` trong release.py vơ cả file nháp message → file nháp phải để NGOÀI repo
(đã vá). (3) PowerShell máy Khoa chặn npx.ps1 (execution policy) → dùng `npx.cmd`.

---

## 2026-07-02 — release.py: phát hành 1 lệnh, khai tử quy trình tay

**Vấn đề:** Quy trình phát hành tay đã dính 3 loại sẹo lặp lại: (1) PowerShell ghi file chèn BOM →
auto-update chết im lặng; (2) QUÊN thêm file mới vào `version.json` → máy thợ "cập nhật một phần"
(vụ thiếu spacing_24.png); (3) heredoc PowerShell nuốt ngoặc kép → hỏng commit. Tần suất phát hành
tăng (5 bản/2 ngày) nên xác suất lỗi tay tăng theo. Và chỉ Claude thạo quy trình = phụ thuộc.

**Quyết định:** Viết `release.py` (Python — né hẳn PowerShell): bump version cả 2 file, **tự quét
thư mục sinh `ruby_files`** + báo diff thêm/bớt cho mắt người soát, kiểm BOM 2 lớp, build .rbz,
commit qua file message, push. Quy ước mới: file bắt đầu `_` = đồ dev, không ship. Xóa `release.ps1`
lỗi thời. Cùng ngày: xóa hẳn repo `lehai-check` (vụ tách/gộp), chốt KHÔNG làm kênh beta — 1 luồng
duy nhất, khi nào sẵn sàng mới push.

**Vì sao:** Nỗi đau đã lặp ≥3 lần → đủ chuẩn "chỉ đổi khi đau thật". Tự sinh danh sách file giết hẳn
nguyên loại lỗi "quên file". Dry-run đầu tiên lập tức bắt được `_theme_preview.html` lọt lưới — 
chứng minh giá trị ngay. Khoa tự chạy được không cần Claude → giảm phụ thuộc (đúng nguyên tắc nền).

**Bài học / Rủi ro:** Danh sách tự quét = ship MỌI thứ trong thư mục — file rác lỡ bỏ vào LeHai_Tools/
sẽ bị ship (đã chặn bằng quy ước `_` + diff hỏi xác nhận). Updater KHÔNG tự xóa file cũ trên máy thợ
khi mình bỏ file khỏi danh sách — file mồ côi nằm lại (vô hại nhưng cần biết).

---

## 2026-07-01 — Bộ "Soát Trước Xuất": chốt chặn trước khi xuất DXF (v1.9.25)

**Vấn đề:** Trước khi xuất DXF đi cắt CNC, file hay dính lỗi làm phế phôi mà không ai soi kịp: sai độ
dày, tấm hở < 7mm, **trùng tấm** (copy chồng khít), **cánh thiếu bản lề**, **thiếu liên kết** (rãnh
hậu / ngàm). Tool lẻ (Độ Dày, Khoảng Cách) đã có nhưng rời rạc, dễ quên chạy.

**Quyết định:** Làm 3 check mới + 1 dashboard gom tất cả, mỗi check tự expose `audit` (chỉ đọc → PASS/
FAIL) và `review` (mở xem chi tiết):
- `TK::DuplicateCheck` (Trùng Tấm): soi MÔ HÌNH 3D (không nesting — nesting không bao giờ trùng). Trùng
  khít = cùng tâm world + **3 vector cạnh khớp** (cùng hướng). Vector cạnh phân biệt "chồng khít" thật
  với "cắt mộng chữ thập" (2 tấm xoay 90° cùng tâm+bao nhưng cạnh lệch → không báo).
- `TK::HingeCheck` (Bản Lề): group tên có "cánh"/"canh" = cánh tủ → phải có ≥2 `_ABF_hingeCup` con.
  Bỏ qua "hộc kéo" (mặt hộc kéo không gắn bản lề) và nhánh nesting.
- `TK::JointCheck` (Liên Kết): 2 tấm ăn nhau (AABB world, tủ thẳng trục) ~10mm → cần rãnh hậu
  (`ABF_PHAYRANHHAU`), ~17.5mm → cần ngàm (`ABF_NGAM*`). Thiếu group `_ABF_Intersect` đúng loại ở vùng
  giao → báo. Chặn nhầm "chồng mặt lớn" (trùng/ghép 2 lớp) bằng điều kiện vùng giao cục bộ; khử đếm đôi
  bằng "tấm là lá" (không lấy mảnh con) + dedupe cặp tên.
- `TK::PreExportCheck` (Soát Trước Xuất): dashboard theme LeHai, mỗi check 1 dòng chấm xanh/đỏ + nút
  Xem. Đặt CUỐI toolbar, icon **khiên + tick** (mảng tô đậm) vì là bước quan trọng nhất.

**Vì sao:** 3 lỗi đầu là hình học thuần → tự đo được. "Liên kết ABF" là LUẬT NGHỀ (không có trong hình
học) → phải đọc dữ liệu thật trước (2 vòng probe: đọc dấu vết `_ABF_Intersect` + đo phân bố độ ăn sâu)
rồi mới chốt ngưỡng — KHÔNG đoán mò, vì báo nhầm "PASS" cho phôi thiếu rãnh còn nguy hiểm hơn không có
tool. Adapter `audit`/`review` cho mỗi check để dashboard chỉ gọi lại, không viết trùng logic quét.

**Bài học / Rủi ro:** Dò liên kết dựa AABB → chỉ đúng cho tủ **thẳng trục** (tủ xoay/nghiêng sẽ sót —
đã hỏi Khoa, xưởng gần như luôn thẳng trục). Ngưỡng band (rãnh hậu 8–12.5mm, ngàm 15–20mm) chọn từ
dữ liệu probe thật, có thể cần nới nếu gặp kích thước khác. **Rãnh Led để sau** (Khoa chưa giảng cơ chế).
Bẫy đã tránh: `_ABF_Intersect` là dấu vết CHUNG cho mọi liên kết (phân biệt bằng tag) → 2 tấm ăn nhau
có thể dùng ngàm thay rãnh hậu, đừng ép "cứ ăn nhau là phải rãnh hậu".

---

## 2026-06-30 — Dim Nhanh: chế độ Diện tích (m²) (v1.9.24)

**Vấn đề:** Cần đọc m² của mảng (tường/sàn) để báo giá ốp lát/sơn. Mảng hay bị kẻ chia nhiều mặt, và
mặt cong là "Surface" (nhiều mảnh nối bằng cạnh mềm) — không phải 1 mặt phẳng.

**Quyết định:** Thêm chế độ thứ 3 `:area` vào `TK::QuickDim` (Tab xoay 3 chế độ):
- Rê mảng → **gom mặt liền tục**: nối qua cạnh MỀM (soft/smooth = mặt cong "surface") HOẶC đồng phẳng
  (mặt phẳng bị kẻ chia) → ra cả mảng + m². Click → cộng dồn; ESC → bảng kê m² + tổng + Copy.
- **Tô nền** mảng đã đếm (mesh tam giác, draw2d translucent) để biết đã click cái nào; chống đếm trùng.
- **Giữ Alt** = chỉ lấy 1 mặt (khi muốn tách mảng đồng phẳng/đồng surface).
- Tổng quát hóa bảng kê dùng chung cho mm (chiều dài) và m² (diện tích).

**Vì sao:** Face.area có sẵn → không cần "đoán hình qua camera". Gom theo soft-edge = đúng khái niệm
Surface của SketchUp (mặt cong). Coplanar-merge thêm để gộp mặt phẳng bị kẻ vụn. m² = tổng area các
mảnh = diện tích thật (kể cả mặt cong, đã trừ lỗ cửa nếu mặt đã khoét).

**Bài học / Rủi ro:** Mặt cong = nhiều mảnh nối soft-edge, KHÔNG coplanar — phải gom theo soft/smooth.
Diện tích chưa tính scale của component (hiếm gặp ở model kiến trúc). Mặt cong rất lớn có thể vẽ
highlight hơi rậm/chậm — để tối ưu (vẽ viền ngoài) khi cần.

---

## 2026-06-26 — Dim Nhanh: phân biệt vòng tròn liền (D) vs cung bo (R) (v1.9.23)

**Vấn đề:** Vòng tròn liền (logo) bị tính lỗi (điểm đầu trùng cuối) và ghi R vô nghĩa — tròn liền
thì phải đo đường kính D.

**Quyết định:** (1) Fit circumradius bằng 3 điểm cách đều (0, n/3, 2n/3) thay vì đầu/giữa/cuối → vòng
kín không lỗi. (2) `full_circle?`: ArcCurve sweep ≈ 2π, hoặc curve khép kín (đầu≈cuối) → vòng liền →
ghi **D{đường kính}**; còn lại cung hở → **R{bán kính}**. Theo Khoa, ký hiệu dùng chữ **D** (không Ø).

**Bài học:** Closed-curve fit phải tránh đỉnh đầu==cuối; chọn điểm cách đều ổn định hơn.

---

## 2026-06-26 — Dim Nhanh: 2 chế độ + tự ghi R + dọn dim (v1.9.22)

**Vấn đề:** Dim xong để báo giá thì đống dim thành rác. Vòng bo phải bật Text gõ "R50" tay. Và R
không cộng được vào tổng nên không thể lẫn chung với chế độ đo cộng dồn.

**Quyết định:** Nâng `TK::QuickDim`:
- **2 chế độ (Tab đổi):** *Báo giá* (cộng dồn cạnh thẳng → bảng kê tổng + Copy + Dọn dim; cung bị
  chặn vì không cộng được) và *Ghi chú* (dim + tự ghi R, không cộng, ESC thoát giữ lại annotation).
- **Tự ghi R:** rê vào đường cong → tính bán kính bằng **vòng tròn ngoại tiếp 3 điểm** (đầu/giữa/cuối)
  → chính xác cho cung thật, áp được cả cong tay. Nhận MỌI `Sketchup::Curve` (không chỉ ArcCurve).
- **Nút Dọn dim** trong bảng kê: xoá đúng các dim/text vừa tạo trong phiên (lưu entity), dim tay giữ.
- **Copy** trong bảng kê: copy con số TỔNG (dán Excel/báo giá).

**Vì sao:** Cạnh trong group → `transformation_at` ra world-coords (đã làm). Khóa offset theo trục
X/Y/Z cho dim ngay ngắn. R tách hẳn sang Ghi chú vì không cộng được. Tất cả dùng theme chung.

**Bài học:** 3 điểm xác định 1 vòng tròn → circumradius `(abc)/(4·diện tích)` cho R chính xác, không
cần đối tượng Arc. Tách chế độ giúp ngữ nghĩa rõ (đo-để-tính vs ghi-chú-giữ-lại).

---

## 2026-06-26 — Updater: thử lại file hụt (v1.9.21)

**Vấn đề:** Sau khi thêm icon, version.json lên 52 file. Auto-update tải dồn dập → raw github
timeout/chặn 1 file (`spacing_24.png`) → báo "cập nhật một phần", không ghi installed_version →
lần sau lại tải cả mớ, dễ hụt nữa.

**Quyết định:** Thêm `_http_get_retry` (thử 3 lần, lùi nhẹ 0.5–2s) cho cả version.json lẫn từng file
trong `_do_update_check`. File hụt do blip mạng sẽ tự tải lại.

**Vì sao:** File càng nhiều, xác suất 1 request lỗi càng cao; retry là cách rẻ + bền nhất (không cần
đổi cơ chế). Trước mắt máy đang kẹt thì cài tay .rbz là đủ. Updater bền chỉ có tác dụng từ bản này
trở đi (máy phải có bản updater mới — cài 1.9.21 .rbz tay 1 lần).

**Bài học:** Mọi vòng lặp tải file qua mạng phải có retry. (Emergency updater trong LeHai_Tools.rb
cũng nên thêm sau, nhưng nó chỉ chạy khi crash nên để dịp khác.)

---

## 2026-06-26 — Tool mới "Dim Nhanh" + khung giao diện chung (v1.9.20)

**Vấn đề:** Dim tay từng cạnh (cho bản vẽ báo giá) quá cực. Cần tool dim như Dimension mặc định
nhưng tiện hơn, kèm bảng kê chiều dài cho báo giá.

**Quyết định:** Tool `TK::QuickDim` (folder `dim_nhanh`) — Tool TƯƠNG TÁC: rê chuột vào cạnh →
sáng amber; click → đặt dim, rê khóa theo trục X/Y/Z (như Dimension xịn) cho ngay ngắn; click đặt;
tự quay lại cho cạnh tiếp. ESC → hiện BẢNG KÊ (chiều dài từng cạnh + tổng + nút Copy tổng). Dim là
entity thật → kéo dời được. Đây là **dialog đầu tiên dùng khung giao diện chung mới**
`shared/lehai_theme.css` (kem + walnut + amber + DM Sans, đồng bộ bộ icon).

**Vì sao:** (1) Tool tương tác thay vì "chọn trước rồi chạy" — đúng thói quen Dimension. (2) Cạnh
nằm trong group/component → phải lấy kèm `transformation_at` đổi sang TỌA ĐỘ THẬT, nếu không dim/nét
sáng nhảy lung tung. (3) Khóa trục: bắt offset về X/Y/Z gần nhất, bỏ trục trùng hướng cạnh. (4) Lập
`lehai_theme.css` dùng chung để thay dần giao diện các tool cũ (dọn dần, không đập loạt).

**Bài học:** PickHelper trả entity + `transformation_at(i)` để ra world-coords — bắt buộc khi làm
việc với hình trong group. Khung CSS chung = nền để đồng bộ UI dần. Nhớ khai `lehai_theme.css` vào
version.json (dialog đọc file này lúc chạy).

---

## 2026-06-26 — Thay toàn bộ icon toolbar (v1.9.19)

**Vấn đề:** Khoa thiết kế lại bộ icon trên Claude Design (claude.ai/design) cho thống nhất —
11 icon outline nét walnut #7c2d12, stroke 1.5px, bo tròn, mảng tô nâu nhạt, nền trong suốt.

**Quyết định:** Lấy bundle handoff (`SketchUp plugin icon redesign-handoff.zip`), đọc thiết kế gốc là
SVG trong `LeHai Tools Icons.dc.html`. Vì máy chỉ có PIL (không cairosvg/inkscape), viết
`render_icons.py` mô phỏng các nét SVG (rect bo, line, circle, polyline, polygon, quadratic bezier),
render supersample ×16 rồi thu nhỏ LANCZOS → PNG 16/24 (thu_vien thêm 48 cho @2x). Thay đúng 23 file
icon theo tên cũ từng tool. Bổ sung MỌI icon vào `version.json` (trước đây thiếu icon của tam_go,
canh_cnc, ha_nen, auto_dan_canh, dien_ten → auto-update không tải) để máy thợ nhận đủ.

**Vì sao:** Không kéo được file qua DesignSync MCP (cần /design-login tương tác, phiên nền không có) →
Khoa tải bundle về `claude_work` rồi đọc trực tiếp. Tự render bằng PIL cho chủ động + chắc kết quả
(màu/nền/stroke kiểm soát được), thay vì lệ thuộc lib SVG có thể không cài được trên Windows.

**Bài học:** Icon SVG đơn giản hoàn toàn render được bằng PIL (supersample + LANCZOS cho anti-alias).
Khi thêm icon mới phải nhớ khai vào `version.json` — nay đã đưa hết icon vào để khỏi sót lần sau.

---

## 2026-06-26 — Kiểm Tra Khoảng Cách: tăng tốc quét (v1.9.18)

**Vấn đề:** Quét 42 tấm ván hơi lag (đứng hình vài giây) vì `min_dist` đo seg-seg MỌI cặp cạnh giữa
2 tấm gần nhau, kể cả cặp cạnh ở xa tít — phần lớn là việc thừa.

**Quyết định:** Thêm lọc thô cấp-cạnh trong `min_dist`: tính AABB mỗi cạnh, bỏ qua cặp cạnh có AABB
cách nhau > GAP (không thể là min < 7mm) → chỉ chạy seg-seg cho cặp cạnh thật sự gần.

**Vì sao:** Kết quả KHÔNG đổi (nếu min thật < GAP thì cặp cạnh đó AABB chắc chắn < GAP nên không bị
bỏ) — chỉ cắt việc thừa. Cùng tư duy "lọc thô → tính kỹ" đã dùng ở cấp tấm (`aabb_far?`), nay thêm
một tầng ở cấp cạnh. Lọc 2 tầng → nhanh hẳn.

**Bài học:** Trước phép tính đắt, chèn một phép kiểm rẻ để loại 99% ca không thể đúng — broad-phase
trước narrow-phase. Đã thử nhánh "tự sửa" (xô 1 tấm / cascade dồn khối) nhưng Khoa chọn bỏ: đó là
bài xếp lại nesting (việc của ABF), không nên nhồi vào máy soi. Tool giữ đúng vai CHỈ ĐỌC.

---

## 2026-06-25 — Thêm tool "Kiểm Tra Khoảng Cách" (v1.9.17)

**Vấn đề:** Sau khi nesting bằng ABF, cần biết các tấm chi tiết có cách nhau (và cách mép tấm ván)
đủ 7mm không — dao CNC không lọt thì phạm sang tấm bên / cắt lụt ra ngoài phôi. Trước phải soi mắt.

**Quyết định:** Tool mới `TK::SpacingCheck` (thư mục `kiem_tra_khoang_cach/`): quét mọi tấm ván, đo
khoảng hở **tấm↔tấm** (cùng sheet) và **tấm↔mép tấm ván**; cặp < 7mm → tô đỏ 2 tấm + vạch hồng cánh
sen ghi số mm tại chỗ hở, sắp theo hở nhỏ nhất trước, ← → / gõ số để lướt từng cặp. Chỉ đọc.

**Vì sao:** (1) Tấm nesting **chỉ có edges, phẳng tuyệt đối** (dò ra) → đo khoảng cách 2 tập đoạn
thẳng (seg-seg 3D), KHÔNG dùng bounding box (sai với góc bo cong). (2) Gồm cả nét trong vẫn đúng vì
hở nhỏ nhất luôn ở viền ngoài. (3) Lọc thô bằng AABB trước (job 42 sheet) cho nhanh. (4) Màu vàng
ban đầu chìm trên nền xám → đổi hồng cánh sen + số mm trên chip tối + vạch 2 đầu kiểu thước đo.

**Bài học / Rủi ro:** Khớp/đo bằng hình học thật thay vì hộp bao là chìa khóa đúng. Hiệu năng: brute
seg-seg có AABB prefilter đủ nhanh cho 42 sheet; nếu sau này job lớn hơn chậm thì thêm lưới không
gian. Đã test qua console (`spacing_check.rb`) trước khi wire vào toolbar — đúng quy trình Luật Nhà.

---

## 2026-06-25 — Thêm tool "Tìm Tấm Lỗi" (v1.9.15)

**Vấn đề:** Máy CNC báo một tấm lỗi theo **board-index** (số thứ tự cắt), nhưng thợ phải dò mắt trên
nesting + trong tủ 3D để tìm đúng tấm đó — mất thời gian, hay nhầm. Plugin ABF có tính năng tương tự
nhưng phải click vào hình, không gõ số được, và tấm hay bị tấm khác che.

**Quyết định:** Tool mới `TK::ABFFinder` (thư mục `tim_tam_loi/`): gõ board-index → tô sáng tấm trên
cả nesting (đỏ) lẫn tủ 3D (xanh), zoom thẳng vào mặt tấm tủ 3D. Khớp bằng **thuộc tính ẩn ABF**
(`is-board` + `board-index`), KHÔNG đọc tên. Đặt nút cạnh "Kiểm Tra Độ Dày" (cùng kính lúp soi tấm).

**Vì sao:** (1) Khớp bằng attribute thay vì tên → miễn nhiễm tên có dấu/khoảng trắng, chắc 100%.
(2) Vẽ overlay (3D + dấu 2D chiếu lên màn hình LUÔN nổi trên cùng) thay vì `select` — vì 2 tấm nằm 2
group lồng khác ngữ cảnh, SketchUp không select chéo được; dấu 2D giải quyết cảnh tấm bị che. (3) Chỉ
đọc, không sửa model → 0 rủi ro hỏng file. (4) Bỏ ý tưởng "ẩn tấm khác" (đã thử) vì Khoa thấy quá tay.

**Bài học / Rủi ro:** `view.zoom` KHÔNG nhận BoundingBox → phải đặt camera tay (tính theo fov). Cấu
trúc dữ liệu ABF đã reverse-engineer: nesting `__ABF_Nesting` > tấm ván `__..mm-sheet-N` > chi tiết
(dict `ABF`: board-index, is-board); chi tiết tủ 3D cũng mang cùng board-index + cùng tên → khớp 1-1.

**v1.9.16 (cùng ngày):** đang sáng tấm, gõ số khác vào ô đo (VCB) + Enter → đổi tấm tại chỗ, khỏi
Esc rồi mở lại. Dùng `enableVCB?` + `onUserText`; tách `resolve(numbers)` để `find` (mở tool) và
`retarget` (đổi trong tool) dùng chung logic lọc.

---

## 2026-06-22 — Thư Viện: bỏ hẳn Phong cách + Phòng

**Vấn đề:** Khoa quyết thư viện không cần tag/lọc theo Phòng lẫn Phong cách — chỉ cần danh mục + tên
+ kích thước + lưu ý + người lưu. (Đầu tiên định bỏ mỗi Phòng, sau nghĩ lại bỏ luôn Phong cách.)

**Quyết định:** Gỡ style+phong khỏi **giao diện** (index.html): thanh filter, ô chọn trong form
lưu/sửa, nhãn trên thẻ, và mọi hàm/biến JS liên quan (renderFilterBar, renderChips, renderFormChips,
activeStyle/Phong, STYLE/PHONG_LABELS...). Đã grep xác nhận không còn tham chiếu mồ côi.

**Vì sao:** Khoa muốn thư viện gọn, nhất quán. Dữ liệu style/phong cũ trong catalog.json KHÔNG xóa
(chỉ ẩn) → đổi ý vẫn khôi phục được.

**Bài học / nợ kỹ thuật:** Cố ý KHÔNG gỡ phần Ruby (STYLES/PHONGS, style/phong trong save/edit/
item_for của library.rb) và vài rule CSS chết (`#filter-bar`, `.chip`, `.tag`, `.form-chip`) — vì
gỡ chúng rủi ro thấp nhưng churn nhiều, dễ sót làm hỏng luồng lưu. Để dọn sau khi đụng lại file
(đúng nguyên tắc "dọn dần"). Hành vi hiện tại đúng: lưu mới không có style/phong; sửa item cũ sẽ
strip style/phong (hợp ý vì đang bỏ chúng).

---

## 2026-06-22 — Máy đếm cài đặt (Nhịp 1: telemetry, chưa private)

**Vấn đề:** Khoa không biết bao nhiêu máy đang dùng plugin, và lo bị tuồn ra ngoài. Phát hiện repo
đang PUBLIC (toàn bộ source phơi trên GitHub) — rủi ro lớn hơn cả .rbz.

**Quyết định:** Làm theo 2 nhịp. **Nhịp 1 (đã làm):** dựng máy đếm trên Cloudflare Worker
(`lehai-stats`, KV `INSTALLS`). Plugin gửi ping ẩn danh (mã máy ngẫu nhiên UUID lưu trong
`write_default('TK_LeHai','machine_id')` + version) mỗi lần mở SketchUp, qua `ping_stats` trong
updater.rb (timer 6s, bắn-rồi-quên). Admin xem ở `/stats?key=...`. **Nhịp 2 (sau):** private repo +
cổng update — chính Worker này sẽ mở rộng thành cổng.

**Vì sao:** Tách 2 nhịp để không ôm rủi ro một lúc — Nhịp 1 KHÔNG đụng cơ chế update, gần như 0 rủi
ro, trả lời ngay "bao nhiêu máy". Telemetry nuốt mọi lỗi (offline/lỗi không được làm phiền plugin).
Token Cloudflare CHỈ dùng tạm ngoài repo, không commit; ADMIN_KEY là secret trên Cloudflare.

**Bài học (kỹ thuật):** (1) Token account-scoped không qua được `/user/tokens/verify` nhưng vẫn dùng
được cho account — test thẳng quyền thật (KV/Workers list) mới đúng. (2) curl mingw (Git Bash) cần
đường dẫn file kiểu `C:/...` cho `@`/`<`, dùng `/c/...` thì câm (cờ `-s` nuốt luôn lỗi mở file).
(3) Upload Worker = multipart: part `metadata` (JSON khai binding+secret) + part `worker.js` module.

**Sự thật cần nhớ:** Nhịp 1 KHÔNG bảo vệ source (repo vẫn public). Chỉ trả lời "bao nhiêu máy".
Bảo vệ chống tuồn ra ngoài là việc của Nhịp 2 (private + cổng) — và kể cả vậy cũng chỉ nâng rào,
không khóa tuyệt đối (xem bàn luận: chỉ license gắn máy mới khóa thật).

---

## 2026-06-20 — Thư Viện: thêm "Lưu ý khi dùng" cho component

**Vấn đề:** Mỗi component có những "bẫy" riêng (vd là DC phải gỡ trước khi xuất CNC, nhớ kiểm độ dày
sau scale) nhưng kiến thức đó nằm trong đầu người tạo, người khác chèn về dễ sập bẫy.

**Quyết định:** Thêm trường `note` vào `catalog.json` (cạnh style/phong/kích thước). Form lưu + form
sửa có ô "📌 Lưu ý khi dùng". Trong lưới: component có lưu ý hiện **badge 📌**, **rê chuột → bảng
lưu ý nổi lên** trước khi bấm chèn.

**Vì sao:** Đúng tinh thần "kiến thức đi theo vật" — gotcha của component travel cùng nó trong thư
viện dùng chung, không phải truyền miệng. Lưu trong catalog.json (không nhúng vào .skp) để sửa được
mà không phải mở file.

**Bài học (kỹ thuật):** Bảng hover dùng 1 element `#note-tip` nổi (position:fixed) định vị bằng JS
theo `getBoundingClientRect`, không nhét trong card — vì card có `overflow:hidden` và lưới cuộn sẽ
cắt mất popover. Badge để `pointer-events:none` để không chặn click chèn.

---

## 2026-06-20 — Tài liệu trỏ sai đường dẫn nguồn (release.ps1 lỗi thời)

**Vấn đề:** Khoa phát hiện CLAUDE.md + `release.ps1` ghi đường phát hành là `Desktop\lehai_tools` —
thư mục KHÔNG tồn tại. Repo thật ở `claude_work\lehai-tools`. Đó là lý do mọi lần release đều làm tay.

**Quyết định:** Chốt **GitHub `tankfire4-dot/lehai-tools` = nguồn chính dài hạn**; máy chỉ là bản làm
việc. Sửa CLAUDE.md (thêm mục "Nguồn / vị trí", trỏ đúng claude_work, chỉ sang LUAT_NHA.md mục 7).
Đánh dấu `release.ps1` lỗi thời + chặn chạy (exit 1) để không đạp lại lỗi BOM.

**Vì sao:** GitHub là chỗ xây dài hạn — mất file trên máy vẫn còn (dự phòng 1-trong-2). `release.ps1`
hỏng 3 tầng: sai đường dẫn, cập nhật plugins.json/congty_loader (không tồn tại), ghi file bằng
PowerShell Set-Content → chèn BOM (chính lỗi đã trị). Quy trình tay hiện tại mới đúng + an toàn.

**Bài học:** Tài liệu trôi khỏi thực tế cũng nguy như code trôi — script "tự động" trỏ sai còn tệ hơn
không có, vì tạo ảo giác an toàn. Khi dời thư mục/đổi cơ chế, phải rà lại mọi đường dẫn cứng trong docs.

---

## 2026-06-20 — Chốt Luật nhà (quy ước code)

**Vấn đề:** Code 9 tool bị trôi phong cách: biến dialog lúc `@dlg` lúc `@dialog` lúc local; báo lỗi
lúc popup lúc trong bảng; `rescue` lúc nuốt im lặng lúc surface; tam_go còn dùng tiếng Việt không dấu.
Mỗi đoạn chạy được nhưng ghép lại như nhà mỗi phòng một kiểu.

**Quyết định:** Tạo [LUAT_NHA.md](LUAT_NHA.md) — vừa liệt kê thẳng các chỗ đang lệch (mục A), vừa
chốt quy ước thống nhất (mục B): dùng `@dlg`, báo trong bảng nếu có dialog, không nuốt lỗi im lặng,
một mẫu bọc `start_operation` duy nhất, tiếng Việt có dấu cho chuỗi hiển thị, quy trình release
không-BOM. CLAUDE.md thêm lệnh "đọc LUAT_NHA.md trước khi code".

**Vì sao:** Đây là câu trả lời trực tiếp cho nỗi lo "code Claude không nhất quán" + "sợ phụ thuộc".
Nhật ký ghi *vì sao*; Luật nhà ép *cách làm* đồng nhất về sau. Code nhất quán = ai cũng tiếp quản
được = thoát khóa vào một người.

**Bài học:** Không refactor hàng loạt code cũ (rủi ro cao). Luật nhà áp cho code mới + dọn dần khi
đụng file. Nợ kỹ thuật (mục A) gỡ từ từ, không vội.

---

## 2026-06-20 — Lập "luật nhà" + cuốn nhật ký này

**Vấn đề:** Khoa nhận ra hai điều: (1) code Claude viết đôi khi không nhất quán — đoạn sau khác
đoạn trước dù vẫn chạy; (2) lo bị phụ thuộc vào Claude. Đồng thời nhận ra "vì sao" đằng sau code
đang rơi vãi (chat bị nén mất dần, changelog chỉ ghi *làm gì* chứ ít ghi *vì sao*).

**Quyết định:** Tách bạch ba nơi lưu trữ — CLAUDE.md (hiến pháp ngắn, đọc mỗi phiên), NHAT_KY.md
(nhật ký, đọc khi cần), memory (hồ sơ về Khoa + cách làm việc, xuyên dự án). Sắp tới soạn thêm
"Luật nhà" (quy ước code thống nhất: báo lỗi một kiểu, mở dialog một kiểu, đặt tên, lên version).

**Vì sao:** Hai nỗi lo trên thực ra là một. *Code lộn xộn + không tài liệu = Khoa bị khóa vào Claude.
Code nhất quán + có tài liệu = thay Claude bằng bất kỳ thợ code/AI nào cũng được.* Tính nhất quán
chính là tấm vé tự do, không phải đi học code. Và cái "vì sao" trong nhật ký là thứ lấy kiến thức
ra khỏi đầu Claude, đặt vào repo — nơi ai cũng đọc được.

**Bài học:** Không dồn nhật ký vào CLAUDE.md — vì CLAUDE.md bị đọc mỗi phiên, phình ra sẽ tốn chi
phí mỗi lần và chôn lẫn các luật quan trọng. Thứ đọc-mỗi-lần phải ngắn; thứ tra-khi-cần thì để riêng.

---

## 2026-06-20 — Lỗi BOM làm chết auto-update cả xưởng

**Vấn đề:** Bump version 1.9.6 xong, máy Khoa reset nhiều lần vẫn không cập nhật. Im lặng, không báo lỗi.

**Quyết định:** Ghi lại version.json không BOM (bằng công cụ ghi file chuẩn, KHÔNG dùng PowerShell
`Set-Content -Encoding UTF8`). Thêm bước "lột BOM phòng hộ" trong updater + emergency updater.

**Vì sao:** PowerShell trên Windows luôn chèn ký tự ẩn BOM (EF BB BF) vào đầu file. Ruby `JSON.parse`
không nuốt được BOM → ném lỗi → updater bị `rescue` nuốt im lặng → không ai biết. Bản 1.9.5 trước
không BOM nên chạy tốt; chính commit thêm BOM mới làm hỏng.

**Bài học:** (1) Không ghi file config (JSON) mà tool khác sẽ đọc bằng PowerShell `-Encoding UTF8`.
(2) Sau khi push, `raw.githubusercontent.com` cache ~5 phút — kiểm bằng git blob sha (so local với
GitHub API) chứ đừng tin `curl` raw ngay. (3) File `.rb` Ruby chấp nhận BOM (vô hại); chỉ JSON hỏng.
(4) `rescue` nuốt lỗi là con dao hai lưỡi — giấu lỗi làm khó debug.

---

## 2026-06-20 — Phải gỡ DC trước khi reset trục tọa độ

**Vấn đề:** Reset trục trên tấm tủ (Dynamic Component) "có vẻ chạy" nhưng trục vẫn ở gốc (0,0,0)
trong khi hình nằm cách 58.25cm. Reset không ăn.

**Quyết định:** Tool Reset phát hiện DC (có dictionary `dynamic_attributes`) → bỏ qua + cảnh báo
"gỡ DC trước". Quy trình đúng: Dọn Component (DC→group) → rồi mới Reset trục.

**Vì sao:** DC có "động cơ chạy ngầm" giữ Position theo công thức/x-y-z lưu sẵn. Khi đổi transformation
bằng tay, động cơ DC áp lại giá trị cũ → kéo trục về chỗ cũ. Dữ liệu Ruby Console chứng minh đen
trắng: trục thật [0,0,0] nhưng bounds hình ở 582.5mm.

**Bài học:** Có hai hệ tọa độ phục vụ hai mục đích khác nhau — hệ "thiết kế" (SketchUp, tối ưu dựng
hình/copy) và hệ "gia công" (CNC, cần gốc tại góc tấm). Tool của mình làm nhiệm vụ phiên dịch giữa
hai hệ. Trên DC còn sống thì phiên dịch không ăn — phải "tắt động cơ" (gỡ DC) trước.

---

## 2026-06-16 → 06-20 — Biến component ↔ group an toàn

**Vấn đề:** ABF chỉ dán nhãn được lên group, không chịu component. Cần biến component/DC thành group
(và ngược lại khi copy sản phẩm sẵn có). Bản đầu bấm cái là nổ màn hình (bugsplat).

**Quyết định:** component→group bằng cách: tạo group rỗng → `add_instance` bản sao vào trong →
`explode` trong group → `erase` gốc. Chiều ngược lại dùng `group.to_component`. Tự `purge_unused`
sau mỗi lần đổi.

**Vì sao:** `add_group(geometry vừa nổ)` là lỗi API gây bugsplat — phải nổ *bên trong* group rỗng để
hình không dính/gộp với hình bên cạnh. `purge_unused` vì mỗi lần đổi qua lại sinh ra "bản gốc rác"
không ai dùng → file phình + số đuôi #N leo thang; dọn để dùng dài hạn không tích tụ.

**Bài học:** Đổi qua lại nhiều lần không làm hỏng hình (nhờ nổ trong group rỗng), nhưng DC mất hẳn
sau lần đổi đầu (đúng thiết kế), và cấu trúc lồng nhau trôi một chiều (con bên trong thành group).

---

## 2026-06-20 — Dọn Component mặc định bỏ tick hết

**Vấn đề:** Bảng Dọn Component nhớ lựa chọn lần trước, mở ra đã tick sẵn các thao tác xóa.

**Quyết định:** Luôn mở với tất cả checkbox bỏ tick; bỏ phần nhớ lựa chọn cũ.

**Vì sao:** Tool này có thao tác *xóa* (màu/tag/thuộc tính/object ABF). Tick sẵn dễ bấm "Thực hiện"
mà lỡ xóa nhầm. An toàn quan trọng hơn tiện một nhịp.

**Bài học:** Với thao tác phá hủy (không hoàn tác dễ), mặc định nên là "không làm gì" — bắt người
dùng chủ động chọn.

---

## Bảng phiên bản (mục lục nhanh)

Tóm tắt 1 dòng mỗi version. Lý do chi tiết của các thay đổi gần đây nằm ở các mục "vì sao" phía trên.

| Phiên bản | Ngày       | Nội dung |
|-----------|------------|----------|
| 1.9.48    | 2026-07-20 | Chống Bay: trần 9 đợt (một chữ số → Aspire sắp tên bằng chuỗi vẫn ra đúng thứ tự số); mỗi lượt kéo nhận tối đa `đợt_cuối−đợt_đầu+1` chi tiết, dư thì cắt bớt + báo, KHÔNG quay vòng (quay vòng làm hai chi tiết cùng lượt trùng số trùng màu) |
| 1.9.10    | 2026-06-20 | Trục Tọa Độ: Reset phát hiện Dynamic Component (có dict `dynamic_attributes`) → bỏ qua + cảnh báo "gỡ DC trước" thay vì lặng lẽ không ăn (engine DC giữ Position kéo trục về chỗ cũ). Lý do: reset đổi transformation nhưng DC áp lại x/y/z stored → trục không bám góc tấm. Phải Dọn Component (DC→group) trước rồi mới reset |
| 1.9.9     | 2026-06-20 | Thêm tool Trục Tọa Độ (`truc_toa_do/`, module `TK::AxisFix`): 1 icon mở bảng nhỏ — nút Reset trục về global (+ gốc về góc hình, khử -0) và 3 nút X/Y/Z xoay vật thể 90° quanh trục. Kết quả báo ngay trong bảng (không popup). Ở cụm DC, cuối toolbar |
| 1.9.8     | 2026-06-20 | Dọn Component: tự `purge_unused` sau khi đổi component↔group → tránh rác definition phình file + số đuôi #N leo thang khi đổi qua lại nhiều lần |
| 1.9.7     | 2026-06-20 | Dọn Component: mặc định bỏ tick hết checkbox (an toàn, tránh bấm nhầm thao tác xóa); bỏ phần nhớ lựa chọn cũ |
| 1.9.6     | 2026-06-20 | Dọn Component: thêm chức năng "Biến group → component" (ngược với component→group, dùng khi copy sản phẩm sẵn có dạng group). HOTFIX: bỏ BOM khỏi version.json (BOM làm Ruby JSON.parse hỏng → auto-update im lặng thất bại); thêm lột BOM phòng hộ trong updater |
| 1.9.5     | 2026-06-17 | Gỡ DC → đổi thành "Dọn Component": bấm icon hiện bảng checkbox chọn thao tác (biến component→group / xóa màu / xóa tag / xóa thuộc tính / xóa object ABF), tích cái nào làm cái đó. Nhớ lựa chọn lần trước qua write_default |
| 1.9.4     | 2026-06-17 | Thêm tool Kiểm Tra Độ Dày (`kiem_tra_do_day/`, module `TK::ThickCheck`): quét mọi tấm, đo độ dày từ mặt phẳng riêng (bỏ qua con lồng/rãnh phay ABF), biểu đồ cột (xanh=chuẩn 9/10/17.5/18, đỏ=sai), bấm cột → cô lập (ẩn tấm khác)+zoom. Lọc bỏ <1mm. + Sắp lại toolbar theo cụm: Dựng hình → Gia công&nhãn → Thư viện → Cụm DC (GoGroup, ThickCheck) ở cuối |
| 1.9.3     | 2026-06-17 | Gỡ DC → Group: mở rộng quét — xóa MỌI object ABF (nhãn, phay rãnh, giao cắt...) theo prefix chung: instance name bắt đầu `_ABF` HOẶC tag bắt đầu `ABF_` |
| 1.9.2     | 2026-06-17 | Gỡ DC → Group: quét toàn model xóa hết nhãn ABF (group có instance name bắt đầu `_ABF_Label` hoặc tag `ABF_Label`). Nhãn ABF là group riêng nằm cạnh tấm gỗ |
| 1.9.1     | 2026-06-17 | Gỡ DC → Group: thêm pass làm sạch — xóa material/màu (cả back_material) + toàn bộ attribute dictionaries trên mọi entity, giữ lại group + tên + tag. Mục tiêu: group thuần để xuất CNC/gắn nhãn |
| 1.9.0     | 2026-06-16 | Thêm tool Gỡ DC → Group (`go_group/`, module `TK::GoGroup`): biến Component/Dynamic Component thành group lồng nhau, giữ nguyên từng tấm + tên + tag, không phải group lại tay. Dùng trước khi gắn nhãn ABF (ABF không chịu component nhưng chịu group). Cách an toàn: tạo group rỗng → add_instance bản sao → explode trong group → erase gốc (tránh add_group trên geometry vừa nổ → bugsplat) |
| 1.0.0     | 2026-06-08 | Gộp 5 plugin thành 1 bộ LeHai's Decor Tools |
| 1.7.4     | 2026-06-13 | AutoDánCạnh: dán toàn bộ cung khi camera thấy bất kỳ mặt nào trong cung (`group_arc_faces` + `shared_arc_edge?`) — trước đó mỗi mặt cong check riêng lẻ → dán vá víu |
| 1.7.3     | 2026-06-13 | AutoDánCạnh: bỏ filter axis-alignment — cho phép dán toàn bộ mặt cong góc bo (trước đó chỉ dán mặt thẳng do filter AXIS_ALIGN_THRESHOLD quá nghiêm) |
| 1.7.1     | 2026-06-13 | CanhCNC: preview 3D cánh ma khi chọn điểm 2 (đúng số cánh/khe hở/độ dày, khung đỏ khi hở vượt khoang); tách công thức `door_layout` dùng chung cho preview + dựng thật |
| 1.7.0     | 2026-06-12 | Thêm tool Thư Viện Component (`thu_vien/`, module `TK::ThuVien`): trình duyệt thư viện .skp dùng chung — thumbnail, danh mục 2 cấp, tìm kiếm, chèn component, lưu component từ model vào thư viện (save_as → thumbnail iso chuẩn), chọn thư mục thư viện trên ổ mạng/Drive |
