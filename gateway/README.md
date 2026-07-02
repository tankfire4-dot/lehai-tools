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

Từ 2026-07-02 quản bằng **wrangler** (có `wrangler.toml` khai báo KV binding sẵn):

```
cd gateway
npx wrangler deploy
```

Thay ADMIN_KEY: ghi khóa vào file tạm (không newline) rồi
`Get-Content file | npx.cmd wrangler secret put ADMIN_KEY` — ĐỪNG gõ vào prompt
tương tác (dễ dính ký tự rác). Máy mới cần `npx wrangler login` một lần.
(Cách cũ upload qua curl + API token đã bỏ.)

## Hạn chế đã biết

- `/ping` mở công khai → người biết URL có thể bơm id giả làm phồng số đếm (phá vặt, rủi ro thấp).
- Đây là Nhịp 1. Nhịp 2 (private repo + cổng update) sẽ mở rộng chính Worker này.
