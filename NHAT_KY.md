# Nhật Ký Phát Triển — LeHai Tools

Sổ ghi **vì sao**, không phải vì sao kỹ thuật khô khan mà là lý do thật đằng sau mỗi quyết định —
để sau này bất kỳ ai (kể cả một AI khác, hoặc chính Khoa) cầm repo lên đều hiểu được mạch suy nghĩ,
không phải đoán mò.

- **CLAUDE.md** = hiến pháp ngắn: cách làm việc + luật nhà + cấu trúc (đọc mỗi phiên).
- **NHAT_KY.md** (file này) = sổ công trình: kể lại từng quyết định + vì sao + bài học (tra khi cần).
- Mục mới thêm lên **trên cùng** (mới nhất trước).

Mỗi mục theo khung: **Vấn đề → Quyết định → Vì sao → Bài học/Rủi ro.**

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
