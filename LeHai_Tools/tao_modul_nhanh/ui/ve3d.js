// ============================================================
//  VE3D — bộ vẽ 3D hộp thẳng trục trên canvas, không thư viện (27/09/2026)
//
//  Dùng chung cho mọi bảng Tạo Modul Nhanh (hoc_keo.html, khung_bao.html) — MỘT bộ vẽ,
//  sửa một chỗ. Hình lấy NGUYÊN từ danh sách tấm lõi Ruby gửi sang; file này không có
//  công thức kết cấu nào, chỉ biết vẽ hộp.
//
//  Toạ độ mm của SketchUp: x phải, y vào trong (sau), z lên. Một tấm = { ten, x:[a,b],
//  y:[a,b], z:[a,b], kich_thuoc?, khoet? }.
//
//  Cách vẽ: xoay 8 đỉnh mỗi hộp, sắp tấm xa camera vẽ trước (hai hộp tách nhau theo một
//  trục thì biết chắc cái nào sau), bỏ mặt quay lưng. Chỉ vẽ khi có thao tác — không vòng lặp nền.
// ============================================================
(function () {
  // 6 mặt của hộp: chỉ số đỉnh (bit 1 = x1, 2 = y1, 4 = z1) + pháp tuyến ra ngoài
  var MAT = [
    [[0, 2, 6, 4], [-1, 0, 0]], [[1, 5, 7, 3], [1, 0, 0]],
    [[0, 4, 5, 1], [0, -1, 0]], [[2, 3, 7, 6], [0, 1, 0]],
    [[0, 1, 3, 2], [0, 0, -1]], [[4, 6, 7, 5], [0, 0, 1]]
  ];
  var GOC = { yaw: -0.6, pitch: 0.35, zoom: 1, tam: null };   // tam null = tâm của khung ôm

  function so(v) { return Math.round(v * 10) / 10; }

  // Màu gỗ theo tên tấm: mặt hộc / cánh = kem, đáy hộc = gỗ đậm, còn lại = gỗ sáng
  function mauMacDinh(ten) {
    if (/mặt (lọt|phủ)$/.test(ten) || /^Cánh/.test(ten)) return [251, 247, 240];
    if (/đáy$/.test(ten)) return [214, 181, 138];
    return [232, 201, 160];
  }

  // Tấm có khoét góc (hông né len: khoet.y × khoet.z ở góc sau-dưới) → 2 hộp để vẽ.
  // Chỉ là cách VẼ phần đặc còn lại, số lấy nguyên từ lõi.
  function tachKhoet(s) {
    if (!s.khoet) return [s];
    var a = {}, b = {};
    for (var k in s) { a[k] = s[k]; b[k] = s[k]; }
    a.y = [s.y[0], s.khoet.y[0]];
    b.y = [s.khoet.y[0], s.y[1]]; b.z = [s.khoet.z[1], s.z[1]];
    a.goc = b.goc = s;
    return [a, b];
  }

  window.Ve3D = function (cv, tro) {
    var g = cv.getContext('2d'), self = this;
    var cam = {}, hop = [], bien = null, kich = [], cat = null, daVe = [], dangTro = null, keo = null, hen = 0;
    var pitchMin = -1.5, pitchMax = 1.5;
    for (var k in GOC) cam[k] = GOC[k];

    self.mau = mauMacDinh;
    self.tachKhoet = tachKhoet;

    // ds: [{ s: tấm, loai: 'tam' (đặc) | 'nen' (mờ: khoang, tường, len), dy? }]
    // khungOm: [[x0,y0,z0],[x1,y1,z1]] — vùng để căn giữa + tỉ lệ; bỏ trống = ôm mọi hộp
    self.dat = function (ds, khungOm) { hop = ds || []; bien = khungOm || null; self.ve(); };
    // đường kích thước: [{ a:[x,y,z], b:[x,y,z], chu:'10', sang:bool }]
    self.kich = function (ds) { kich = ds || []; };
    // mặt cắt: { truc: 0|1|2, max: v, min?: v } → chỉ giữ phần tấm trong [min, max] theo trục đó
    // (lát cắt mỏng nhìn vào trong tủ, như mặt cắt 2D)
    self.cat = function (c) { cat = c || null; };
    self.gioiHanPitch = function (a, b) { pitchMin = a; pitchMax = b; };
    self.datGoc = function () { self.bay(GOC); };

    // Bay camera tới góc nhìn đích — chuyển động ngắn cho mắt theo kịp
    self.bay = function (dich, ms) {
      var tu = { yaw: cam.yaw, pitch: cam.pitch, zoom: cam.zoom, tam: cam.tam || tamOm() };
      var toi = { yaw: dich.yaw, pitch: dich.pitch, zoom: dich.zoom, tam: dich.tam || tamOm() };
      var dai = ms == null ? 320 : ms, t0 = performance.now(), ma = ++hen;
      // quay đường ngắn nhất
      while (toi.yaw - tu.yaw > Math.PI) toi.yaw -= 2 * Math.PI;
      while (toi.yaw - tu.yaw < -Math.PI) toi.yaw += 2 * Math.PI;
      function buoc(now) {
        if (ma !== hen) return;                       // có lệnh bay mới / người dùng kéo → dừng
        var r = Math.min(1, (now - t0) / dai), e = r * r * (3 - 2 * r);
        cam.yaw = tu.yaw + (toi.yaw - tu.yaw) * e;
        cam.pitch = tu.pitch + (toi.pitch - tu.pitch) * e;
        cam.zoom = tu.zoom * Math.pow(toi.zoom / tu.zoom, e);
        cam.tam = [0, 1, 2].map(function (i) { return tu.tam[i] + (toi.tam[i] - tu.tam[i]) * e; });
        if (r >= 1 && !dich.tam) cam.tam = null;
        self.ve();
        if (r < 1) requestAnimationFrame(buoc);
      }
      requestAnimationFrame(buoc);
    };

    function om() {
      if (bien) return bien;
      var lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
      hop.forEach(function (h) {
        [h.s.x, h.s.y, h.s.z].forEach(function (a, i) { lo[i] = Math.min(lo[i], a[0]); hi[i] = Math.max(hi[i], a[1]); });
      });
      return [lo, hi];
    }
    function tamOm() { var b = om(); return [0, 1, 2].map(function (i) { return (b[0][i] + b[1][i]) / 2; }); }

    function xoay(p) {
      var cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw), cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
      var x1 = p[0] * cy - p[1] * sy, y1 = p[0] * sy + p[1] * cy, z1 = p[2];
      return [x1, y1 * cp - z1 * sp, y1 * sp + z1 * cp];   // [ngang, sâu (xa = lớn), dọc]
    }

    self.ve = function () {
      var r = window.devicePixelRatio || 1, W = cv.clientWidth, H = cv.clientHeight;
      if (!W || !H) return;
      cv.width = W * r; cv.height = H * r;
      g.setTransform(r, 0, 0, r, 0, 0);
      g.clearRect(0, 0, W, H);
      daVe = [];
      if (!hop.length) return;

      // tỉ lệ theo bán kính khung ôm → không đổi khi xoay
      var b = om(), tam = cam.tam || tamOm();
      var R = Math.sqrt(Math.pow(b[1][0] - b[0][0], 2) + Math.pow(b[1][1] - b[0][1], 2) + Math.pow(b[1][2] - b[0][2], 2)) / 2 || 1;
      var k = Math.min(W, H) / (2.3 * R) * cam.zoom;
      function chieu(p) {
        var q = xoay([p[0] - tam[0], p[1] - tam[1], p[2] - tam[2]]);
        return { x: W / 2 + q[0] * k, y: H / 2 - q[2] * k, sau: q[1] };
      }

      // Hộp để vẽ: tách khoét, áp mặt cắt
      var ds = [];
      hop.forEach(function (h) {
        tachKhoet(h.s).forEach(function (s) {
          var lo = [s.x[0], s.y[0] + (h.dy || 0), s.z[0]], hi = [s.x[1], s.y[1] + (h.dy || 0), s.z[1]];
          if (cat) {
            var tr = cat.truc, mn = cat.min == null ? -1e9 : cat.min;
            if (lo[tr] >= cat.max || hi[tr] <= mn) return;
            hi[tr] = Math.min(hi[tr], cat.max);
            lo[tr] = Math.max(lo[tr], mn);
          }
          ds.push({ s: s.goc || s, loai: h.loai, lo: lo, hi: hi });
        });
      });

      var cy = Math.cos(cam.yaw), sy = Math.sin(cam.yaw), cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
      var huong = [sy * cp, cy * cp, -sp];   // hướng nhìn trong toạ độ thế giới (sâu tăng theo hướng này)
      ds.forEach(function (h) {
        h.sau = 0; for (var i = 0; i < 3; i++) h.sau += huong[i] * (h.lo[i] + h.hi[i]) / 2;
      });
      ds.sort(function (a, c) {
        for (var i = 0; i < 3; i++) {
          if (Math.abs(huong[i]) < 1e-6) continue;
          if (a.hi[i] <= c.lo[i] + 0.01) return huong[i] > 0 ? 1 : -1;   // a nằm phía thấp trục i
          if (c.hi[i] <= a.lo[i] + 0.01) return huong[i] > 0 ? -1 : 1;
        }
        return c.sau - a.sau;
      });

      ds.forEach(function (h) {
        var dinh = [];
        for (var i = 0; i < 8; i++) dinh.push(chieu([h[i & 1 ? 'hi' : 'lo'][0], h[i & 2 ? 'hi' : 'lo'][1], h[i & 4 ? 'hi' : 'lo'][2]]));
        MAT.forEach(function (m) {
          if (xoay(m[1])[1] >= 0 && h.loai !== 'nen') return;   // mặt quay lưng: bỏ (nền mờ thì vẽ cả)
          var pts = m[0].map(function (i) { return dinh[i]; });
          g.beginPath();
          pts.forEach(function (p, i) { if (i) g.lineTo(p.x, p.y); else g.moveTo(p.x, p.y); });
          g.closePath();
          if (h.loai === 'nen') {
            g.fillStyle = 'rgba(124,45,18,0.06)'; g.fill();
            g.strokeStyle = 'rgba(124,45,18,0.35)'; g.lineWidth = 1; g.stroke();
          } else {
            var c = self.mau(h.s.ten), n = m[1];
            var sang = 0.78 + 0.22 * (n[2] > 0 ? 1 : n[0] !== 0 ? 0.35 : n[1] < 0 ? 0.7 : 0);   // nóc sáng, hông tối
            var chon = dangTro === h.s;
            g.fillStyle = 'rgb(' + c.map(function (v) { return Math.round(v * sang); }).join(',') + ')';
            g.fill();
            g.strokeStyle = chon ? '#b45309' : 'rgba(28,10,0,0.55)'; g.lineWidth = chon ? 2 : 1; g.stroke();
            daVe.push({ s: h.s, pts: pts });
          }
        });
      });

      // Đường kích thước nổi trên cùng: sáng = ô đang sửa
      kich.forEach(function (d) {
        var a = chieu(d.a), c = chieu(d.b), dx = c.x - a.x, dy = c.y - a.y, dai = Math.sqrt(dx * dx + dy * dy) || 1;
        var nx = -dy / dai * 5, ny = dx / dai * 5;   // vạch chặn hai đầu, vuông góc trên màn hình
        g.strokeStyle = d.sang ? '#b45309' : 'rgba(107,66,38,0.75)'; g.lineWidth = d.sang ? 2.2 : 1;
        g.beginPath();
        g.moveTo(a.x, a.y); g.lineTo(c.x, c.y);
        g.moveTo(a.x - nx, a.y - ny); g.lineTo(a.x + nx, a.y + ny);
        g.moveTo(c.x - nx, c.y - ny); g.lineTo(c.x + nx, c.y + ny);
        g.stroke();
        g.font = (d.sang ? '700 13px ' : '500 11px ') + "'DM Sans', 'Segoe UI', sans-serif";
        var w = g.measureText(d.chu).width + 8, mx = (a.x + c.x) / 2, my = (a.y + c.y) / 2;
        g.fillStyle = d.sang ? '#fef3c7' : 'rgba(255,255,255,0.9)';
        g.fillRect(mx - w / 2, my - 9, w, 18);
        g.fillStyle = d.sang ? '#92400e' : '#6b4226';
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText(d.chu, mx, my);
      });
    };

    // ── Chuột: kéo xoay · lăn phóng · rê hiện tên + kích thước tấm ──
    cv.addEventListener('mousedown', function (e) {
      hen++;                                           // người dùng cầm lái → dừng mọi lệnh bay
      if (!cam.tam) cam.tam = tamOm();
      keo = { x: e.clientX, y: e.clientY, yaw: cam.yaw, pitch: cam.pitch };
      cv.classList.add('keo');
    });
    window.addEventListener('mouseup', function () { keo = null; cv.classList.remove('keo'); });
    window.addEventListener('mousemove', function (e) {
      if (keo) {
        cam.yaw = keo.yaw + (e.clientX - keo.x) * 0.01;
        cam.pitch = Math.max(pitchMin, Math.min(pitchMax, keo.pitch + (e.clientY - keo.y) * 0.01));
        self.ve(); return;
      }
      var bb = cv.getBoundingClientRect(), x = e.clientX - bb.left, y = e.clientY - bb.top, trung = null;
      if (x >= 0 && y >= 0 && x <= bb.width && y <= bb.height) {
        for (var i = daVe.length - 1; i >= 0; i--) if (trong(daVe[i].pts, x, y)) { trung = daVe[i].s; break; }
      }
      if (trung !== dangTro) { dangTro = trung; self.ve(); }
      if (!tro) return;
      if (dangTro) {
        var d = dangTro.kich_thuoc || [];
        tro.textContent = dangTro.ten + ' — ' + d.map(so).join(' × ');
        tro.style.left = (x + 14) + 'px'; tro.style.top = (y + 10) + 'px'; tro.style.display = 'block';
      } else tro.style.display = 'none';
    });
    cv.addEventListener('wheel', function (e) {
      e.preventDefault();
      hen++;
      cam.zoom = Math.max(0.3, Math.min(40, cam.zoom * (e.deltaY < 0 ? 1.12 : 1 / 1.12)));
      self.ve();
    }, { passive: false });
    function trong(pts, x, y) {
      var c = false;
      for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        if ((pts[i].y > y) !== (pts[j].y > y) && x < (pts[j].x - pts[i].x) * (y - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x) c = !c;
      }
      return c;
    }
    window.addEventListener('resize', function () { self.ve(); });
  };
})();
