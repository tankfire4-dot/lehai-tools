# Gateway — máy đếm cài đặt (Cloudflare Worker)

Đếm số máy đang dùng LeHai Tools. Plugin gửi 1 ping ẩn danh mỗi lần mở SketchUp.

## Hiện trạng (Nhịp 1 — chỉ đếm máy)

- **Worker:** `lehai-stats` → URL `https://lehai-stats.tankfire4.workers.dev`
- **Kho KV:** `INSTALLS` (binding tên `INSTALLS` trong Worker)
- **Secret:** `ADMIN_KEY` (đặt bằng Cloudflare secret — **KHÔNG nằm trong repo**)
- Tài khoản Cloudflare: Tankfire4@gmail.com

## Endpoint

| Đường dẫn | Ai gọi | Tác dụng |
|---|---|---|
| `/ping?id=<máy>&v=<version>` | plugin (tự động) | Ghi nhận máy + version |
| `/stats?key=<ADMIN_KEY>` | admin (trình duyệt) | Trang HTML xem số máy |
| `/stats?key=<ADMIN_KEY>&format=json` | admin | Trả JSON thô |

Chỉ lưu **mã máy ngẫu nhiên + version** — không có tên người / đường dẫn.

## Deploy lại (khi sửa worker.js)

Cần API token Cloudflare (quyền Workers + KV). Upload bằng Cloudflare API:

```bash
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/workers/scripts/lehai-stats" \
  -H "Authorization: Bearer <TOKEN>" \
  -F "metadata=<metadata.json;type=application/json" \
  -F "worker.js=@worker.js;type=application/javascript+module"
```

`metadata.json` khai báo binding KV (`INSTALLS`) + secret `ADMIN_KEY`. Lưu ý: curl mingw (Git Bash)
cần đường dẫn file kiểu `C:/...`, không phải `/c/...`.

## Hạn chế đã biết

- `/ping` mở công khai → người biết URL có thể bơm id giả làm phồng số đếm (phá vặt, rủi ro thấp).
- Đây là Nhịp 1. Nhịp 2 (private repo + cổng update) sẽ mở rộng chính Worker này.
