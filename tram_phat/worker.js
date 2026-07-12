// ============================================================
//  lehai-update — TRẠM PHÁT update cho LeHai Tools (Cloudflare Worker)
//
//  Vì sao tồn tại: trạm là ĐỊA CHỈ CỐ ĐỊNH mà updater mọi máy thợ đã trỏ vào.
//  Dựng 07/2026 để chuẩn bị khóa repo private; 12/07/2026 Khoa chốt repo GIỮ PUBLIC.
//  Trạm vẫn giữ: đổi URL update là phải phát update qua đường cũ trước (rủi ro
//  không đáng), và nếu sau này khóa repo lại thì máy thợ không cần biết gì.
//  Trạm giữ chìa GH_TOKEN (fine-grained, CHỈ-ĐỌC, CHỈ repo lehai-tools) trong
//  két secret của Cloudflare — chìa KHÔNG BAO GIỜ nằm trên máy thợ.
//
//  Máy thợ gọi:  GET https://lehai-update.<subdomain>.workers.dev/<đường-dẫn>
//     vd  /version.json   /LeHai_Tools/main.rb   /LeHai_Tools/dim_nhanh/icons/dim_24.png
//
//  Trạm CHỈ phát file plugin hiện hành (version.json + LeHai_Tools*).
//  Không phát lịch sử git, không phát repo khác, đường dẫn lạ = chặn.
//
//  Thay chìa (mỗi ≤366 ngày): tạo token mới trên GitHub → Cloudflare dash →
//  worker lehai-update → Settings → Variables and Secrets → sửa GH_TOKEN.
//  Máy thợ không cần biết gì.
// ============================================================

const REPO   = 'tankfire4-dot/lehai-tools';
const BRANCH = 'master';

export default {
  async fetch(request, env) {
    const url  = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, '');

    // trang chủ trạm — để thử nhanh trạm còn sống không
    if (!path) return new Response('LeHai update relay OK', { status: 200 });

    // chặn đường dẫn lách (.. , %2e%2e)
    if (path.includes('..')) return new Response('bad path', { status: 400 });

    // CHỈ phát file plugin — mọi thứ khác coi như không tồn tại
    const allowed = path === 'version.json'
                 || path === 'LeHai_Tools.rb'
                 || path.startsWith('LeHai_Tools/');
    if (!allowed) return new Response('not found', { status: 404 });

    // vào kho GitHub lấy file (Contents API, nhận bản raw)
    const encoded = path.split('/').map(encodeURIComponent).join('/');
    const gh = `https://api.github.com/repos/${REPO}/contents/${encoded}?ref=${BRANCH}`;
    const r = await fetch(gh, {
      headers: {
        // .trim() — chống ký tự xuống dòng lọt vào secret khi nạp qua pipe
        'Authorization': `Bearer ${(env.GH_TOKEN || '').trim()}`,
        'Accept': 'application/vnd.github.raw+json',
        'User-Agent': 'lehai-update-worker'
      }
    });
    if (!r.ok) return new Response('not found', { status: 404 });

    return new Response(r.body, {
      status: 200,
      headers: {
        'Content-Type': 'application/octet-stream',
        'Cache-Control': 'no-store'
      }
    });
  }
};
