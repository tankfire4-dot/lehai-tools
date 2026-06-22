// LeHai Tools — máy đếm cài đặt (Cloudflare Worker)
//
//   GET /ping?id=<machine>&v=<version>  → plugin gọi mỗi lần mở SketchUp
//   GET /stats?key=<ADMIN_KEY>          → trang xem số máy (chỉ admin, mở bằng trình duyệt)
//   GET /stats?key=<ADMIN_KEY>&format=json → trả JSON thô
//
// Không lưu tên người / đường dẫn — chỉ mã máy ngẫu nhiên + version. Bí mật ADMIN_KEY
// đặt bằng Cloudflare secret (không nằm trong file này).

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const p = url.pathname;

    if (p === '/ping') {
      const id = (url.searchParams.get('id') || '').slice(0, 80);
      const v  = (url.searchParams.get('v')  || '').slice(0, 40);
      if (!id) return new Response('missing id', { status: 400 });
      const now = new Date().toISOString();
      const rec = { first_seen: now, last_seen: now, version: v, count: 1 };
      try {
        const prev = await env.INSTALLS.get('m:' + id, { type: 'json' });
        if (prev) {
          rec.first_seen = prev.first_seen || now;
          rec.count = (prev.count || 0) + 1;
        }
      } catch (e) { /* ghi mới nếu đọc lỗi */ }
      await env.INSTALLS.put('m:' + id, JSON.stringify(rec));
      return new Response('ok', { headers: { 'access-control-allow-origin': '*' } });
    }

    if (p === '/stats') {
      if (!env.ADMIN_KEY || (url.searchParams.get('key') || '') !== env.ADMIN_KEY) {
        return new Response('Sai hoac thieu key.', { status: 403 });
      }
      const machines = [];
      let cursor;
      do {
        const list = await env.INSTALLS.list({ prefix: 'm:', cursor });
        for (const k of list.keys) {
          const rec = (await env.INSTALLS.get(k.name, { type: 'json' })) || {};
          machines.push({ id: k.name.slice(2), ...rec });
        }
        cursor = list.list_complete ? null : list.cursor;
      } while (cursor);

      machines.sort((a, b) => (b.last_seen || '').localeCompare(a.last_seen || ''));
      const byVersion = {};
      machines.forEach((m) => { const vv = m.version || '?'; byVersion[vv] = (byVersion[vv] || 0) + 1; });

      if (url.searchParams.get('format') === 'json') {
        return new Response(JSON.stringify({ total: machines.length, by_version: byVersion, machines }, null, 2),
          { headers: { 'content-type': 'application/json; charset=utf-8' } });
      }

      const verRows = Object.keys(byVersion).sort().reverse()
        .map((v) => `<tr><td>${esc(v)}</td><td>${byVersion[v]}</td></tr>`).join('');
      const machRows = machines.map((m) =>
        `<tr><td class="mono">${esc(m.id)}</td><td>${esc(m.version || '?')}</td>` +
        `<td>${esc((m.last_seen || '').replace('T', ' ').slice(0, 16))}</td><td>${m.count || 1}</td></tr>`).join('');

      const html = `<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LeHai Tools — Thống kê cài đặt</title>
<style>
body{font-family:Segoe UI,system-ui,sans-serif;margin:0;padding:24px;background:#f5f6f8;color:#24292f}
h1{font-size:20px;margin:0 0 4px} .sub{color:#6e7781;font-size:13px;margin-bottom:18px}
.card{background:#fff;border:1px solid #e1e4e8;border-radius:8px;padding:16px 22px;display:inline-block}
.big{font-size:42px;font-weight:700;color:#1a73e8;line-height:1}
table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #e1e4e8;border-radius:8px;overflow:hidden;margin-top:10px}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid #eef0f2;font-size:13px}
th{background:#fafbfc;color:#6e7781;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
.mono{font-family:Consolas,monospace;font-size:11px;color:#6e7781}
h2{font-size:14px;margin:22px 0 0}
</style></head><body>
<h1>📊 LeHai Tools — Thống kê cài đặt</h1>
<div class="sub">Tải lại trang để làm mới.</div>
<div class="card"><div class="big">${machines.length}</div><div>máy đã cài</div></div>
<h2>Theo phiên bản</h2>
<table><tr><th>Version</th><th>Số máy</th></tr>${verRows}</table>
<h2>Danh sách máy</h2>
<table><tr><th>Mã máy</th><th>Version</th><th>Lần cuối mở</th><th>Số lần mở</th></tr>${machRows}</table>
</body></html>`;
      return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
    }

    return new Response('LeHai stats worker — OK', { status: 200 });
  }
};

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
