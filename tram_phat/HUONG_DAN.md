# Trạm phát update (lehai-update)

Worker Cloudflare đứng giữa máy thợ và repo GitHub. Xem giải thích đầy đủ trong
`worker.js`. Tóm tắt vận hành:

## Vì sao có trạm này
Trạm là **địa chỉ cố định** mà updater trên mọi máy thợ đã trỏ vào:
`https://lehai-update.<subdomain>.workers.dev/<file>`.

Lịch sử: trạm dựng 07/2026 để chuẩn bị khóa repo private. Nhưng **12/07/2026 Khoa
chốt repo GIỮ PUBLIC** (máy thợ auto-update phụ thuộc vào nó — xem `decisions.md`
của lab). Trạm vẫn giữ vì hai lý do:
1. Đổi URL update = phải phát một bản update qua đường cũ trước — rủi ro không đáng
   khi trạm đang chạy tốt và miễn phí.
2. Nếu sau này cần khóa repo lại, chỉ việc khóa — máy thợ không cần biết gì.

Chìa khóa (GH_TOKEN — fine-grained, chỉ-đọc, chỉ repo này) nằm trong secret của
Cloudflare, KHÔNG nằm trên máy thợ. Repo đang public nên chìa không bắt buộc,
nhưng cứ giữ để sẵn sàng cho ngày khóa repo.

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
