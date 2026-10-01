/* Dựng 3D từ số đo khảo sát -> DANH SÁCH KHỐI để plugin SketchUp vẽ (plugin chỉ vẽ, không tính).
 * Dùng chung lõi vị trí với app (js/geometry.js) + tên loại đồ (js/danh-muc.js) -> app và SketchUp tính MỘT kiểu.
 *
 * Toạ độ ra: mm, trục SketchUp — x sang phải, y LÊN phía trên hình app (lật y của app), z lên trần.
 * Mỗi khối (item):
 *   face  { pts }                          mặt phẳng (sàn, trần)
 *   wall  { pts, foot, out, T, holes[], recesses[], marks[] }
 *         tường DÀY T: pts = mặt trong (giáp phòng), foot = đế 4 góc ở z=0 (mặt trong + mặt ngoài, cắt vát
 *         ở góc để 2 tường khít nhau), out = hướng ra NGOÀI phòng. holes = lỗ khoét xuyên (cửa),
 *         recesses = { pts, d } lõm vào d mm (hốc có số sâu), marks = vùng tô màu (hốc chưa có số sâu)
 *   prism { base[], vec }                   lăng trụ: đa giác đáy đẩy theo vector vec (ổ điện, len, hộp trần...)
 *   line  { pts }  ·  text { pos, text }    đánh dấu chỗ hình không khép
 * Mọi khối có tag (tên tag SketchUp, ASCII), mat (khoá màu), name (tên hiện trong Outliner), raw (số gốc).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./geometry.js'), require('./danh-muc.js'));
  else root.Dung3D = factory(root.Geometry, root.DanhMuc);
})(typeof self !== 'undefined' ? self : this, function (G, DM) {
  'use strict';
  var H_TAM = 2700;          // cao trần tạm khi phòng chưa nhập (có cảnh báo)
  var GAP = 1500;            // khoảng hở giữa các phòng đặt cạnh nhau (app chưa lưu phòng nào cạnh phòng nào)
  var SIZE_TAM = 80;         // cỡ tạm của thiết bị điểm chưa nhập rộng/cao (có ghi "cỡ tạm" trong tên)
  var DIEN = { outlet: 1, switchx: 1, data: 1, tv: 1, panel: 1, ac: 1, camera: 1, wlight: 1 };
  var NUOC = { water: 1, drain: 1, wsprink: 1 };
  // Độ nhô ra khỏi mặt tường (mm) theo loại — chỉ để nhìn thấy khối, KHÔNG phải số đo.
  var NHO = { ac: 200, panel: 100, wlight: 80, camera: 60, tv: 30 };
  var TUONG_DAY = 100;       // tường dày 100 (Khoa chốt 30/09) — app chỉ đo mặt trong, tường đắp ra NGOÀI phòng

  function num(v) { var n = parseFloat(v); return isFinite(n) ? n : null; }
  function letter(i) { return String.fromCharCode(65 + i); }
  function add(a, b, k) { return [a[0] + b[0] * k, a[1] + b[1] * k]; }

  // Một phòng -> { name, items, warnings, width } ; ox = dời phòng sang phải (mm) để các phòng không chồng nhau.
  function buildRoom(r, ox) {
    var warn = [], items = [], n = (r.edges || []).length;
    if (r.phase !== 'edit' || n < 3) return { skip: 'chưa vẽ xong hình' };
    if (!G.allMeasured(r.edges)) return { skip: 'còn ' + G.missingCount(r.edges) + ' cạnh chưa có số' };
    var H = num(r.ceilingHeight);
    if (!(H > 0)) { H = H_TAM; warn.push('chưa nhập cao trần — tạm ' + H_TAM + 'mm'); }
    var v = G.buildVertsLive(r.edges), bb = G.boundingBox(v), sign = G.polyArea2(v, n);
    // toạ độ app (mm, y xuống) -> SketchUp (mm, y lên), dời phòng sang phải ox
    function P(p, z) { return [p.x - bb.minX + ox, bb.maxY - p.y, z || 0]; }
    function wallName(i) { return letter(i) + '–' + letter((i + 1) % n); }
    function inward(i) { var q = G.inwardN(v, n, i, sign); return [q.x, -q.y]; }
    // hình khép (lệch ≤ 1mm) thì góc đầu tường A cũng cắt vát với tường cuối; không khép thì cắt thẳng
    var closed = Math.hypot(v[n].x - v[0].x, v[n].y - v[0].y) <= 1;
    var ctx = { r: r, n: n, H: H, v: v, P: P, wallName: wallName, inward: inward, closed: closed, items: items, warn: warn };

    items.push({ t: 'face', tag: 'KS_San', mat: 'san', name: 'Sàn', pts: v.slice(0, n).map(function (p) { return P(p, 0); }) });
    items.push({ t: 'face', tag: 'KS_Tran', mat: 'tran', name: 'Trần (cao ' + H + ')', pts: v.slice(0, n).map(function (p) { return P(p, H); }) });
    for (var i = 0; i < n; i++) buildWall(ctx, i);
    buildClosure(ctx);
    (r.objects || []).forEach(function (o) {
      if (o.floor) buildFloorObj(ctx, o);
      else if (o.ceiling) buildCeilObj(ctx, o);
    });
    (r.zones || []).forEach(function (z, ix) { buildZone(ctx, z, ix); });
    return { name: r.name || 'Phòng', items: items, warnings: warn, width: bb.maxX - bb.minX };
  }

  // Góc mặt ngoài: điểm cắt vát giữa tường trước (hướng ngoài o1) và tường sau (o2), lùi ra T.
  // Công thức phân giác: T·(o1+o2)/(1+o1·o2) — góc vuông ra đúng T·(o1+o2); hai tường ngược chiều thì cắt thẳng.
  function miter(o1, o2, T) {
    var k = 1 + o1[0] * o2[0] + o1[1] * o2[1];
    if (k < 1e-6) return [o2[0] * T, o2[1] * T];
    return [T * (o1[0] + o2[0]) / k, T * (o1[1] + o2[1]) / k];
  }
  function outward(ctx, i) { var q = ctx.inward(((i % ctx.n) + ctx.n) % ctx.n); return [-q[0], -q[1]]; }

  // Tường i: khối dày T đắp ra NGOÀI mặt trong, cao tới trần, khoét cửa/cửa sổ; đồ trên tường + len chân tường.
  function buildWall(ctx, i) {
    var r = ctx.r, n = ctx.n, a = ctx.v[i], b = ctx.v[i + 1], A = ctx.P(a), B = ctx.P(b), T = TUONG_DAY;
    var L = Math.hypot(B[0] - A[0], B[1] - A[1]); if (L < 1) return;
    var u = [(B[0] - A[0]) / L, (B[1] - A[1]) / L], inn = ctx.inward(i), out = [-inn[0], -inn[1]], H = ctx.H;
    // đế tường: 2 góc mặt trong A,B + 2 góc mặt ngoài (cắt vát với tường kề; đầu hở thì cắt thẳng)
    var mA = i > 0 || ctx.closed ? miter(outward(ctx, i - 1), out, T) : [out[0] * T, out[1] * T];
    var mB = i < n - 1 || ctx.closed ? miter(out, outward(ctx, i + 1), T) : [out[0] * T, out[1] * T];
    var Ao = [A[0] + mA[0], A[1] + mA[1], 0], Bo = [B[0] + mB[0], B[1] + mB[1], 0];
    // mặt ngoài chạy từ sA tới sB (đo dọc tường như mặt trong): góc lồi dài thêm T, góc lõm ngắn đi T
    var sA = mA[0] * u[0] + mA[1] * u[1], sB = L + mB[0] * u[0] + mB[1] * u[1];
    var lo = Math.max(0, sA), hi = Math.min(L, sB);
    // điểm trên mặt tường: s = mm dọc tường tính từ góc đầu (góc i), z = cao từ sàn
    function W(s, z) { var p = add(A, u, s); return [p[0], p[1], z]; }
    function rect(s0, s1, z0, z1) { return [W(s0, z0), W(s1, z0), W(s1, z1), W(s0, z1)]; }
    var objs = (r.objects || []).filter(function (o) { return !o.ceiling && !o.floor && o.wall === i; });
    var holes = [], marks = [], recesses = [], doors = [];
    objs.forEach(function (o) {
      var pa = G.objPosA(o, L), w = num(o.w), nm = objName(ctx, o, i);
      if (o.kind === 'beam') return buildWallBeam(ctx, o, i, A, B, inn, nm);
      if (pa == null) { ctx.warn.push(nm + ': chưa có vị trí ngang — bỏ qua'); return; }
      var z = openingZ(o, H);
      if (z) {                                            // cửa / cửa sổ / hốc
        if (z.thieu) { ctx.warn.push(nm + ': thiếu ' + z.thieu + ' — bỏ qua'); return; }
        if (!(w > 0)) { ctx.warn.push(nm + ': thiếu rộng — bỏ qua'); return; }
        // lỗ xuyên phải nằm trong cả mặt trong lẫn mặt ngoài: sát góc lõm thì hẹp lại, có báo
        var xuyen = o.kind !== 'niche', s0 = Math.max(xuyen ? lo : 0, pa), s1 = Math.min(xuyen ? hi : L, pa + w);
        if (s1 - s0 < 1 || z[1] - z[0] < 1) { ctx.warn.push(nm + ': nằm ngoài tường — bỏ qua'); return; }
        if (xuyen && (s0 - Math.max(0, pa) > 1 || Math.min(L, pa + w) - s1 > 1))
          ctx.warn.push(nm + ': sát góc lõm, lỗ hẹp lại còn ' + Math.round(s1 - s0) + ' vì tường dày ' + T);
        if (!xuyen) {
          var d = num(o.dep);
          if (!(d > 0)) marks.push(rect(s0, s1, z[0], z[1]));   // hốc chưa đo sâu: chỉ tô màu trên mặt tường
          else {
            if (d > T - 10) { ctx.warn.push(nm + ': sâu ' + d + ' ≥ tường dày ' + T + ' — dựng sâu ' + (T - 10)); d = T - 10; }
            recesses.push({ pts: rect(s0, s1, z[0], z[1]), d: d });
          }
        } else holes.push(rect(s0, s1, z[0], z[1]));
        if (o.kind === 'door') doors.push([s0, s1]);
        return;
      }
      buildWallPoint(ctx, o, pa, w, W, inn, nm);
    });
    ctx.items.push({ t: 'wall', tag: 'KS_Tuong', mat: 'tuong', name: 'Tường ' + ctx.wallName(i) + ' (' + Math.round(L) + ')',
      pts: rect(0, L, 0, H), foot: [W(0, 0), W(L, 0), Bo, Ao], out: [out[0], out[1], 0], T: T,
      holes: holes, recesses: recesses, marks: marks });
    buildSkirt(ctx, i, L, doors, W, inn);
  }
  // Khoảng cao của lỗ cửa: cửa đi từ sàn, cửa sổ sill..head, hốc bottom..top; không phải lỗ thì null.
  // Thiếu số thì trả { thieu: 'tên số' } để báo đúng lý do (PN1 thật: cửa sổ có đáy mà trống đỉnh).
  function openingZ(o, H) {
    if (o.kind === 'door') return [0, Math.min(H, num(o.doorH) || H)];
    if (o.kind === 'window') return span(num(o.sill), num(o.head), 'đáy cửa sổ', 'đỉnh cửa sổ', H);
    if (o.kind === 'niche') return span(num(o.bottom), num(o.top), 'đáy hốc', 'đỉnh hốc', H);
    return null;
  }
  function span(lo, hi, tenLo, tenHi, H) {
    if (lo == null || hi == null) return { thieu: [lo == null ? tenLo : null, hi == null ? tenHi : null].filter(Boolean).join(' + ') };
    return [lo, Math.min(H, hi)];
  }
  // Thiết bị điểm (ổ điện, công tắc...): khối nhỏ nhô ra khỏi mặt tường, đúng vị trí + cao độ.
  // Độ nhô = số SÂU đo được (o.dep); chưa đo thì lấy độ nhô tạm theo loại, tên ghi "nhô tạm".
  function buildWallPoint(ctx, o, pa, w, W, inn, nm) {
    var oh = num(o.oh), h = num(o.h), dep = num(o.dep), tam = !(w > 0) || !(oh > 0);
    var nho = dep > 0 ? dep : (NHO[o.kind] || 25);
    if (h == null) { ctx.warn.push(nm + ': chưa có cao độ (sàn → đáy) — tạm đặt sát sàn'); h = 0; }
    var ww = w > 0 ? w : SIZE_TAM, hh = oh > 0 ? oh : SIZE_TAM;
    if (!(oh > 0) && o.at && o.at.y === 'tim') h -= hh / 2;  // đo tới tim mà chưa có cao vật: h đang là TIM, hạ nửa cỡ tạm
    var s0 = w > 0 ? pa : pa - ww / 2;                   // không có rộng: số đo là TÂM vật
    ctx.items.push({ t: 'prism', tag: DIEN[o.kind] || NUOC[o.kind] ? 'KS_DienNuoc' : 'KS_DoTuong',
      mat: NUOC[o.kind] ? 'nuoc' : DIEN[o.kind] ? 'dien' : 'do', name: nm + tamTxt(tam, !(dep > 0)),
      base: [W(s0, h), W(s0 + ww, h), W(s0 + ww, h + hh), W(s0, h + hh)], vec: [inn[0] * nho, inn[1] * nho, 0], raw: o });
  }
  // Dầm chạy dọc cả tường: đáy dầm ở cao độ "bottom", rộng w vào trong phòng.
  function buildWallBeam(ctx, o, i, A, B, inn, nm) {
    var w = num(o.w), bot = num(o.bottom);
    if (bot == null || bot >= ctx.H) { ctx.warn.push(nm + ': thiếu / sai cao độ đáy dầm — bỏ qua'); return; }
    var ww = w > 0 ? w : 200;
    ctx.items.push({ t: 'prism', tag: 'KS_DoTuong', mat: 'do', name: nm + (w > 0 ? '' : ' (rộng tạm 200)'), raw: o,
      base: [[A[0], A[1], bot], [B[0], B[1], bot], [B[0] + inn[0] * ww, B[1] + inn[1] * ww, bot], [A[0] + inn[0] * ww, A[1] + inn[1] * ww, bot]],
      vec: [0, 0, ctx.H - bot] });
  }
  // Len chân tường: dải cao × dày dọc tường, chừa chỗ cửa đi.
  function buildSkirt(ctx, i, L, doors, W, inn) {
    var sk = ctx.r.skirt, sh = sk && num(sk.h), t = (sk && num(sk.t)) || 10;
    if (!(sh > 0) || ctx.r.edges[i].noSkirt) return;
    var s = 0, cuts = doors.slice().sort(function (p, q) { return p[0] - q[0]; }).concat([[L, L]]);
    cuts.forEach(function (c) {
      if (c[0] - s >= 1) {
        var a = W(s, 0), b = W(c[0], 0);
        ctx.items.push({ t: 'prism', tag: 'KS_Len', mat: 'len', name: 'Len chân tường · ' + ctx.wallName(i) + ' (' + Math.round(c[0] - s) + ')',
          base: [a, b, [b[0] + inn[0] * t, b[1] + inn[1] * t, 0], [a[0] + inn[0] * t, a[1] + inn[1] * t, 0]], vec: [0, 0, sh] });
      }
      s = Math.max(s, c[1]);
    });
  }
  // Hình không khép (tường xéo / đo lệch): nối tạm điểm cuối về điểm đầu + ghi số lệch.
  function buildClosure(ctx) {
    var n = ctx.n, e = ctx.v[n], s = ctx.v[0], d = Math.hypot(e.x - s.x, e.y - s.y);
    if (d <= 1) return;
    ctx.items.push({ t: 'line', tag: 'KS_LoiKhep', mat: 'loi', name: 'Lệch khép', pts: [ctx.P(e, 0), ctx.P(s, 0)] });
    ctx.items.push({ t: 'text', tag: 'KS_LoiKhep', name: 'Lệch khép', pos: ctx.P(e, 0), text: 'Lệch khép ' + Math.round(d) + 'mm' });
    ctx.warn.push('hình lệch khép ' + Math.round(d) + 'mm — đã nối tạm, đánh dấu đỏ');
  }
  // Đuôi tên khối: số nào còn là số tạm (chưa đo) -> nhìn Outliner là biết cần đo lại gì.
  function tamTxt(co, nho) { var t = [co ? 'cỡ tạm' : null, nho ? 'nhô tạm' : null].filter(Boolean); return t.length ? ' (' + t.join(', ') + ')' : ''; }
  function centerBox(ctx, pm, len, w, z, h) {
    var c = ctx.P(pm, z), a = len / 2, b = w / 2;
    return { base: [[c[0] - a, c[1] - b, z], [c[0] + a, c[1] - b, z], [c[0] + a, c[1] + b, z], [c[0] - a, c[1] + b, z]], vec: [0, 0, h] };
  }
  // Đồ sàn: tâm theo 2 tường; cao = số nhô lên khỏi sàn (o.dep). Chưa đo: cột / hộp gen cao tới trần, còn lại tấm 20 "nhô tạm".
  function buildFloorObj(ctx, o) {
    var meta = DM.FKINDS[o.kind] || { ten: o.kind }, nm = meta.ten + ' (sàn)' + (o.note ? ' · ' + o.note : '');
    var pm = o.anchor && G.solveAnchorMM(ctx.r, o.anchor);
    if (!pm) { ctx.warn.push(nm + ': chưa đủ số vị trí — bỏ qua'); return; }
    var len = num(o.len), w = num(o.w), dep = num(o.dep), tam = !(len > 0) || !(w > 0), toiTran = o.kind === 'column' || o.kind === 'shaft';
    var cao = dep > 0 ? Math.min(dep, ctx.H) : toiTran ? ctx.H : 20;
    var box = centerBox(ctx, pm, len > 0 ? len : 100, w > 0 ? w : 100, 0, cao);
    ctx.items.push({ t: 'prism', tag: 'KS_DoSan', mat: 'dosan', name: nm + tamTxt(tam, !(dep > 0) && !toiTran), base: box.base, vec: box.vec, raw: o });
  }
  // Đồ trần: tâm theo 2 tường; thò xuống khỏi trần = o.dep (dầm có cao độ đáy thì theo đáy). Chưa đo: tấm 20 "nhô tạm".
  // Nằm lọt trong viền hộp trần thấp hơn -> gắn vào ĐÁY hộp (G.ceilMount); o.face -> gắn trên mặt đứng hộp.
  function buildCeilObj(ctx, o) {
    var meta = DM.CKINDS[o.kind] || { ten: o.kind }, nm = meta.ten + ' (trần)' + (o.note ? ' · ' + o.note : '');
    if (o.face) return buildFaceObj(ctx, o, meta);
    var pm = o.anchor && G.solveAnchorMM(ctx.r, o.anchor);
    if (!pm) { ctx.warn.push(nm + ': chưa đủ số vị trí — bỏ qua'); return; }
    var mt = meta.hasBottom ? null : G.ceilMount(ctx.r, pm, ctx.H, o.mount), top = mt ? mt.h : ctx.H;
    if (mt) nm = meta.ten + ' (đáy hộp trần ' + (mt.ix + 1) + ')' + (o.note ? ' · ' + o.note : '');
    var len = num(o.len), w = num(o.w), tam = !(len > 0) || !(w > 0), bot = num(o.bottom), dep = num(o.dep);
    var coDay = meta.hasBottom && bot != null && bot < ctx.H, coSau = dep > 0 && dep < top;
    var z = coDay ? bot : coSau ? top - dep : top - 20;
    var box = centerBox(ctx, pm, len > 0 ? len : 150, w > 0 ? w : 150, z, top - z);
    ctx.items.push({ t: 'prism', tag: 'KS_DoTran', mat: 'do', name: nm + tamTxt(tam, !coDay && !coSau), base: box.base, vec: box.vec, raw: o });
  }
  // Đồ trên MẶT ĐỨNG hộp trần: ô rộng (len, dọc mặt hộp) × cao (w) dựng đứng tại tim, nhô ra NGOÀI hộp o.dep (tạm 20).
  function buildFaceObj(ctx, o, meta) {
    var fp = G.facePoint(ctx.r, o.face), nm = meta.ten + ' (mặt đứng hộp' + (fp ? ' trần ' + (fp.ix + 1) : '') + ')' + (o.note ? ' · ' + o.note : '');
    var h = num(o.face.h);
    if (!fp || h == null) { ctx.warn.push(nm + ': chưa đủ số vị trí — bỏ qua'); return; }
    if (!fp.onEdge) ctx.warn.push(nm + ': nằm ngoài chiều dài cạnh hộp — kiểm lại số cách tường');
    if (fp.bot != null && (h < fp.bot || h > ctx.H)) ctx.warn.push(nm + ': cao ' + h + ' nằm ngoài mặt đứng hộp (' + fp.bot + '–' + ctx.H + ')');
    var len = num(o.len), w = num(o.w), dep = num(o.dep), a = (len > 0 ? len : SIZE_TAM) / 2, b = (w > 0 ? w : SIZE_TAM) / 2;
    var c = ctx.P(fp.p, h), u = [fp.u.x, -fp.u.y], out = [fp.out.x, -fp.out.y], nho = dep > 0 ? dep : 20;
    function Q(s, dz) { return [c[0] + u[0] * s, c[1] + u[1] * s, h + dz]; }
    ctx.items.push({ t: 'prism', tag: 'KS_DoTran', mat: 'do', name: nm + tamTxt(!(len > 0) || !(w > 0), !(dep > 0)),
      base: [Q(-a, -b), Q(a, -b), Q(a, b), Q(-a, b)], vec: [out[0] * nho, out[1] * nho, 0], raw: o });
  }
  // Hộp trần / giật cấp: khối từ cao độ đáy hộp lên tới trần.
  function buildZone(ctx, z, ix) {
    var nm = z.band ? 'Dải trần dọc tường ' + ctx.wallName(Number(z.band.idx)) : 'Hộp trần ' + (ix + 1);
    var um = G.zoneUnmeasured(z);   // vùng tự vẽ: cạnh chưa đo đang theo nét vẽ tay -> không dựng như thật (28/09 PN1 lòi ra ngoài)
    if (um) { ctx.warn.push(nm + ': còn ' + um + ' cạnh chưa đo (đang theo nét vẽ tay) — bỏ qua'); return; }
    var h = num(z.height), pts = G.zoneVertsMM(ctx.r, z);
    if (!pts || pts.length < 3) { ctx.warn.push(nm + ': chưa đủ số — bỏ qua'); return; }
    if (!(h > 0) || h >= ctx.H) { ctx.warn.push(nm + ': thiếu / sai cao độ đáy (phải thấp hơn trần ' + ctx.H + ') — bỏ qua'); return; }
    ctx.items.push({ t: 'prism', tag: 'KS_HopTran', mat: 'hop', name: nm + ' (đáy ' + h + ')', base: pts.map(function (p) { return ctx.P(p, h); }), vec: [0, 0, ctx.H - h], raw: z });
  }
  function objName(ctx, o, i) {
    var meta = DM.KINDS[o.kind] || { ten: o.kind }, pos = [];
    if (o.fromA != null) pos.push('cách tường ' + ctx.wallName((i - 1 + ctx.n) % ctx.n) + ' ' + o.fromA);
    else if (o.toB != null) pos.push('cách tường ' + ctx.wallName((i + 1) % ctx.n) + ' ' + o.toB);
    if (o.h != null) pos.push('sàn ' + o.h);
    return meta.ten + ' · ' + ctx.wallName(i) + (pos.length ? ' · ' + pos.join(' · ') : '') + (o.note ? ' · ' + o.note : '');
  }

  // Cả công trình (hoặc các phòng chọn) -> kế hoạch vẽ. Phòng đặt cạnh nhau từ trái sang phải.
  function build(project, roomIds) {
    var out = { project: project.name || 'Công trình', rooms: [], skipped: [] }, ox = 0;
    (project.rooms || []).forEach(function (r) {
      if (roomIds && roomIds.indexOf(r.id) < 0) return;
      var res = buildRoom(r, ox);
      if (res.skip) { out.skipped.push((r.name || 'Phòng') + ': ' + res.skip); return; }
      out.rooms.push({ id: r.id, name: res.name, items: res.items, warnings: res.warnings });
      ox += res.width + GAP;
    });
    return out;
  }
  // Tình trạng từng phòng để hiện trong bảng chọn (dựng được không, vì sao).
  function roomState(r) {
    var n = (r.edges || []).length;
    if (r.phase !== 'edit' || n < 3) return { ok: false, text: 'chưa vẽ xong hình' };
    if (!G.allMeasured(r.edges)) return { ok: false, text: 'còn ' + G.missingCount(r.edges) + ' cạnh chưa có số' };
    return { ok: true, text: n + ' cạnh · ' + (r.objects || []).length + ' đồ' + (num(r.ceilingHeight) > 0 ? ' · trần ' + r.ceilingHeight : ' · chưa có cao trần') };
  }
  return { build: build, buildRoom: buildRoom, roomState: roomState };
});
