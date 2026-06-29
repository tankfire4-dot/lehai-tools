# Nhật Ký Phát Triển — LeHai Tools

Sổ ghi **vì sao**, không phải vì sao kỹ thuật khô khan mà là lý do thật đằng sau mỗi quyết định —
để sau này bất kỳ ai (kể cả một AI khác, hoặc chính Khoa) cầm repo lên đều hiểu được mạch suy nghĩ,
không phải đoán mò.

- **CLAUDE.md** = hiến pháp ngắn: cách làm việc + luật nhà + cấu trúc (đọc mỗi phiên).
- **NHAT_KY.md** (file này) = sổ công trình: kể lại từng quyết định + vì sao + bài học (tra khi cần).
- Mục mới thêm lên **trên cùng** (mới nhất trước).

Mỗi mục theo khung: **Vấn đề → Quyết định → Vì sao → Bài học/Rủi ro.**

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
