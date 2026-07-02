# Trạm phát update (lehai-update)

Worker Cloudflare đứng giữa máy thợ và repo private. Xem giải thích đầy đủ trong
`worker.js`. Tóm tắt vận hành:

## Vì sao có trạm này
Repo `lehai-tools` là PRIVATE (chứa luật nghề xưởng). Máy thợ không tự đọc GitHub
được → auto-update đi qua trạm: `https://lehai-update.<subdomain>.workers.dev/<file>`.
Chìa khóa (GH_TOKEN — fine-grained, chỉ-đọc, chỉ repo này) nằm trong secret của
Cloudflare, KHÔNG nằm trên máy thợ.

## Deploy / cập nhật trạm
```
cd tram_phat
npx wrangler deploy                 # đẩy worker.js lên Cloudflare
npx wrangler secret put GH_TOKEN    # dán token khi được hỏi (chỉ cần khi thay chìa)
```
(Cần `npx wrangler login` một lần trên máy mới.)

## Thay chìa hằng năm (token hết hạn ≤366 ngày)
1. GitHub → Settings → Developer settings → Fine-grained tokens → tạo token mới:
   Only select repositories = lehai-tools; Contents = Read-only; hạn 366 ngày.
2. `npx wrangler secret put GH_TOKEN` → dán token mới. Xong. Máy thợ không cần biết.

## Thử trạm sống không
Mở `https://lehai-update.<subdomain>.workers.dev/` → phải thấy "LeHai update relay OK".
Thử `/version.json` → phải ra nội dung JSON version hiện hành.

## Nếu trạm chết
Máy thợ chỉ NGỪNG update (im lặng, không hỏng gì). Sửa trạm hoặc cài tay .rbz.
