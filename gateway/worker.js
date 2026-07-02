// LeHai Tools — máy đếm cài đặt (Cloudflare Worker)
//
//   GET /ping?id=<machine>&v=<version>&n=<tên máy>  → plugin gọi mỗi lần mở SketchUp
//   GET /stats?key=<ADMIN_KEY>          → trang xem số máy (chỉ admin, mở bằng trình duyệt)
//   GET /stats?key=<ADMIN_KEY>&format=json → trả JSON thô
//   GET /debug                          → khai độ dài ADMIN_KEY (chẩn đoán, không lộ khóa)
//
// Chỉ lưu mã máy ngẫu nhiên + tên máy tính (COMPUTERNAME) + version. Bí mật
// ADMIN_KEY đặt bằng Cloudflare secret (không nằm trong file này).
//
// Trang /stats tách MÁY ĐANG DÙNG (mở trong 7 ngày) khỏi MÁY IM LẶNG — vì
// nhiều máy xưởng chỉ cài 1 lần rồi không mở SketchUp nữa, gộp chung gây
// hiểu lầm "16 máy đang chạy". Bản mới nhất lấy sống từ trạm phát.

const ACTIVE_DAYS = 7;
const UPDATE_URL  = 'https://lehai-update.tankfire4.workers.dev/version.json';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const p = url.pathname;

    if (p === '/ping') {
      const id = (url.searchParams.get('id') || '').slice(0, 80);
      const v  = (url.searchParams.get('v')  || '').slice(0, 40);
      const n  = (url.searchParams.get('n')  || '').slice(0, 60);
      if (!id) return new Response('missing id', { status: 400 });
      const now = new Date().toISOString();
      const rec = { first_seen: now, last_seen: now, version: v, name: n, count: 1 };
      try {
        const prev = await env.INSTALLS.get('m:' + id, { type: 'json' });
        if (prev) {
          rec.first_seen = prev.first_seen || now;
          rec.count = (prev.count || 0) + 1;
          if (!n && prev.name) rec.name = prev.name; // ping cũ không gửi tên -> giữ tên đã biết
        }
      } catch (e) { /* ghi mới nếu đọc lỗi */ }
      await env.INSTALLS.put('m:' + id, JSON.stringify(rec));
      return new Response('ok', { headers: { 'access-control-allow-origin': '*' } });
    }

    // chẩn đoán secret (không lộ khóa)
    if (p === '/debug') {
      const a = env.ADMIN_KEY || '';
      return new Response(`ADMIN_KEY: len=${a.length} trimLen=${a.trim().length}`);
    }

    if (p === '/stats') {
      // .trim() cả hai phía — chống ký tự xuống dòng lọt vào secret
      const given = (url.searchParams.get('key') || '').trim();
      const admin = (env.ADMIN_KEY || '').trim();
      if (!admin || given !== admin) {
        return new Response('Sai hoac thieu key.', { status: 403 });
      }

      // đọc toàn bộ máy
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

      // bản mới nhất — hỏi trạm phát qua ống nội bộ (service binding UPDATER)
      let latest = '?';
      try {
        const vr = await env.UPDATER.fetch(UPDATE_URL);
        if (vr.ok) latest = ((await vr.json()).version || '?').trim();
      } catch (e) { /* trạm lỗi thì hiện ? */ }

      // phân loại + làm giàu dữ liệu
      const now = Date.now();
      machines.forEach((m) => {
        const t = Date.parse(m.last_seen || 0) || 0;
        m.days_ago  = Math.floor((now - t) / 86400000);
        m.active    = m.days_ago <= ACTIVE_DAYS;
        m.on_latest = latest !== '?' && (m.version || '') === latest;
      });
      machines.sort((a, b) => (b.last_seen || '').localeCompare(a.last_seen || ''));
      const act  = machines.filter((m) => m.active);
      const dorm = machines.filter((m) => !m.active);

      if (url.searchParams.get('format') === 'json') {
        return new Response(JSON.stringify({
          latest_version: latest,
          dang_dung_7ngay: act.length,
          da_len_ban_moi_nhat: act.filter((m) => m.on_latest).length,
          tong_tung_cai: machines.length,
          machines
        }, null, 2), { headers: { 'content-type': 'application/json; charset=utf-8' } });
      }

      const when = (m) => {
        if (m.days_ago <= 0) return 'hôm nay';
        if (m.days_ago === 1) return 'hôm qua';
        return `${m.days_ago} ngày trước`;
      };
      const label = (m) => m.name
        ? `<b>${esc(m.name)}</b>`
        : `<span class="mono" title="máy chưa gửi tên — sẽ có tên sau khi lên bản mới">${esc((m.id || '').slice(0, 8))}…</span>`;
      const verCell = (m) => m.on_latest
        ? `<span class="ok">✔ ${esc(m.version)}</span>`
        : `<span class="old">⚠ ${esc(m.version || '?')}</span>`;
      const row = (m) =>
        `<tr><td>${label(m)}</td><td>${verCell(m)}</td><td>${when(m)}</td><td>${m.count || 1}</td></tr>`;

      const html = `<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LeHai Tools — Thống kê máy</title>
<style>
body{font-family:Segoe UI,system-ui,sans-serif;margin:0;padding:24px;background:#f5f0e8;color:#1c0a00}
h1{font-size:20px;margin:0 0 4px} .sub{color:#a08060;font-size:13px;margin-bottom:18px}
.cards{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:8px}
.card{background:#fff;border:1.5px solid rgba(124,45,18,.18);border-radius:11px;padding:14px 22px;min-width:150px}
.big{font-size:38px;font-weight:700;line-height:1.1}
.c1 .big{color:#15803d} .c2 .big{color:#b45309} .c3 .big{color:#a08060}
.lbl{font-size:12px;color:#6b4226;margin-top:2px}
table{border-collapse:collapse;width:100%;background:#fff;border:1.5px solid rgba(124,45,18,.18);border-radius:11px;overflow:hidden;margin-top:8px}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid rgba(124,45,18,.10);font-size:13px}
th{background:#fef3c7;color:#92400e;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
.mono{font-family:Consolas,monospace;font-size:11px;color:#a08060}
.ok{color:#15803d;font-weight:700} .old{color:#b45309;font-weight:700}
h2{font-size:14px;margin:24px 0 0;color:#7c2d12}
.note{font-size:12px;color:#a08060;margin-top:6px;line-height:1.5}
</style></head><body>
<h1>LeHai Tools — Thống kê máy</h1>
<div class="sub">Bản mới nhất trên trạm: <b>${esc(latest)}</b> · Tải lại trang để làm mới.</div>
<div class="cards">
  <div class="card c1"><div class="big">${act.length}</div><div class="lbl">máy ĐANG DÙNG (mở trong ${ACTIVE_DAYS} ngày)</div></div>
  <div class="card c2"><div class="big">${act.filter((m) => m.on_latest).length}/${act.length}</div><div class="lbl">máy đang dùng ĐÃ lên bản mới nhất</div></div>
  <div class="card c3"><div class="big">${machines.length}</div><div class="lbl">tổng máy từng cài</div></div>
</div>
<h2>Máy đang dùng (${act.length})</h2>
<table><tr><th>Máy</th><th>Version</th><th>Mở lần cuối</th><th>Số lần mở</th></tr>${act.map(row).join('') || '<tr><td colspan=4>—</td></tr>'}</table>
<h2>Máy im lặng — quá ${ACTIVE_DAYS} ngày không mở SketchUp (${dorm.length})</h2>
<table><tr><th>Máy</th><th>Version</th><th>Mở lần cuối</th><th>Số lần mở</th></tr>${dorm.map(row).join('') || '<tr><td colspan=4>—</td></tr>'}</table>
<div class="note">Máy im lặng thường là máy cài hàng loạt nhưng không dùng SketchUp thường xuyên — plugin trên đó vẫn
chạy bình thường, chỉ chưa cập nhật. Khi máy nào cần bản mới: cài tay file .rbz mới nhất (sau khi kho đã khóa,
máy bản quá cũ không tự cập nhật được nữa). Tên máy chỉ hiện sau khi máy đó lên bản ≥1.9.32.</div>
</body></html>`;
      return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
    }

    return new Response('LeHai stats worker — OK', { status: 200 });
  }
};

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
