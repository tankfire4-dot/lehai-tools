# Luật Nhà — Quy Ước Code LeHai Tools

Mục tiêu: code **nhất quán** để bất kỳ ai (Claude phiên mới, thợ code lạ) đọc cũng thấy cùng một
phong cách → dễ tiếp quản, dễ kiểm, thoát phụ thuộc một người.

**Claude đọc file này TRƯỚC khi viết/sửa bất kỳ code Ruby nào trong repo**, kèm
[SKETCHUP_NEN_TANG.md](SKETCHUP_NEN_TANG.md) — 8 chỗ SketchUp trả số sai mà không báo lỗi.

> **Sửa 01/08/2026:** dòng này trước ghi "dùng skill `sketchup-api`". **Skill đó chưa từng tồn tại**
> trên máy — nghĩa là mọi dòng Ruby trong kho từ trước tới nay viết bằng trí nhớ của model, không
> có tài liệu nào đối chiếu. Đó là gốc của rủi ro "sai mà không biết". Nay trỏ về file thật.

Nguyên tắc áp dụng: **code mới theo Luật nhà; code cũ chỉ sửa khi đụng tới** (không đập đi xây lại
hàng loạt — rủi ro cao, đúng tinh thần "ổn định hơn tối ưu"). Mỗi lần dọn 1 file về chuẩn thì ghi
1 dòng vào [NHAT_KY.md](NHAT_KY.md).

---

## A. Các chỗ đang lệch (tính tới 2026-06-20)

Soi thật từ code hiện có — đây là nợ kỹ thuật cần gỡ dần:

| Chủ đề | Đang lệch thế nào |
|---|---|
| Biến dialog | `@dlg` (truc_toa_do, kiem_tra, go_group) vs `@dialog` (tam_go, auto_dan_canh) vs local `dialog` (canh_cnc) |
| Báo kết quả/lỗi | Báo trong bảng qua `status()` (truc_toa_do, go_group, kiem_tra) vs `UI.messagebox` popup (canh_cnc, ha_nen, tam_go) |
| `rescue` | `rescue StandardError` nuốt im lặng (nhiều chỗ) vs `rescue => e` có surface — cái nuốt im lặng từng giấu lỗi xoay trục |
| Hủy thao tác lỗi | `abort_operation rescue nil` (auto_dan_canh) vs `abort_operation` trơn vs không abort |
| Tiếng Việt | tam_go dùng ASCII không dấu ("Loi", "Kich thuoc", "Do day") vs các tool khác có dấu đầy đủ |
| Format lỗi | `"Lỗi: #{msg}"` vs `"Lỗi: #{msg}\n\n#{backtrace}"` vs `"Loi: ..."` |

---

## B. Luật nhà (chốt — áp dụng từ giờ)

### 1. Cấu trúc tool
- Mỗi tool = thư mục `ten_tool/main.rb` + `icons/`. Module mới đặt trong **`TK::`**.
- Tool **KHÔNG** tự tạo toolbar/menu. Chỉ expose `def self.create_cmd` trả về `UI::Command`.
- Đầu mỗi file `.rb`: `# encoding: UTF-8`. File config (JSON) **không BOM**.

### 2. Dialog (HtmlDialog)
- Biến singleton tên **`@dlg`** (không `@dialog`, không local).
- Đầu `show`: guard
  ```ruby
  if @dlg&.visible? then @dlg.bring_to_front; return end
  ```
- Chỉ dùng `sketchup.ready()` khi cần **đẩy dữ liệu ban đầu** lúc mở (vd quét model). Không thì bỏ.

### 3. Báo kết quả & lỗi
- Tool **có dialog** → báo **trong bảng** (dòng `status()` qua `execute_script`). Không popup vặt.
- Tool **không dialog** → `UI.messagebox`.
- Format lỗi cho người dùng: **`"Lỗi: #{e.message}"`** (tiếng Việt có dấu). Thêm
  `\n\n#{e.backtrace.first(3).join("\n")}` **chỉ khi** cần để debug.

### 4. `rescue` — không nuốt lỗi im lặng
- Thao tác chính (sửa model) **luôn surface** lỗi (status/messagebox) hoặc tối thiểu `puts`.
- `rescue ...; nil/false` **chỉ** cho helper thuần-đọc nơi nil/false là kết quả hợp lệ (vd hàm đo
  đạc), và **phải có chú thích** vì sao nuốt được.

### 5. Bọc thao tác model — một mẫu duy nhất
```ruby
model.start_operation('Ten thao tac', true)   # tên ASCII không dấu (tên undo kỹ thuật)
begin
  # ... sửa model ...
  model.commit_operation
rescue => e
  model.abort_operation
  status("Lỗi: #{e.message}")                  # hoặc UI.messagebox nếu không có dialog
end
```
- `make_unique` trước khi sửa một component/definition dùng chung.

### 6. Tiếng Việt
- Mọi chuỗi **hiển thị cho người dùng**: tiếng Việt **có dấu** đầy đủ.
- Riêng **tên `start_operation`** (tên undo) để **ASCII không dấu** cho an toàn — đây là tên kỹ
  thuật, không phải nội dung hiển thị.

### 7. Lên version (quy trình release)
1. Sửa version bằng **Edit tool** — **KHÔNG** PowerShell `Set-Content -Encoding UTF8` (chèn BOM).
2. Bump ở **cả** `LeHai_Tools.rb` lẫn `version.json`.
3. Thêm mọi file mới vào `version.json` → `ruby_files`.
4. Rebuild `.rbz`. Kiểm `version.json` **không BOM** (`xxd version.json | head -1` phải là `7b` = `{`).
5. Commit + push. Nhớ cache `raw.githubusercontent.com` ~5 phút.

### 8. Comment
- Tiếng Việt. Tiêu đề mục dùng dạng `# ── Tên mục ──────`.
