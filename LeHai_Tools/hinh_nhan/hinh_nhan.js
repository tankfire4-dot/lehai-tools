// Hình Nhân — lõi toán dựng dáng (chạy trong hộp thoại SketchUp VÀ trong Node để test).
// Ruby chỉ nhận toạ độ từ đây rồi vẽ khối; mọi con số nghiệp vụ nằm ở file này.
//
// Hệ toạ độ (mm): Z hướng LÊN, người nhìn về phía -Y (mặt trước), X = trái/phải.
// Mọi chuyển động nằm trong mặt phẳng dọc YZ nên trục X (ngang người) không bao giờ đổi.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.HinhNhan = factory();
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ── TỈ LỆ CHIỀU DÀI theo chiều cao H — Drillis & Contini (1966), in lại ở
  // Winter, "Biomechanics and Motor Control of Human Movement", Hình 4.1.
  // Đọc thẳng từ hình, KHÔNG phải số nhớ. Người Việt thấp hơn mẫu gốc nhưng tỉ lệ
  // theo chiều cao vẫn là xấp xỉ tốt khi chưa đo trực tiếp.
  var TL = {
    mat: 0.936,        // tầm mắt đứng = 0.936 × chiều cao
    cam: 0.870,        // cằm
    vai: 0.818,        // khớp vai
    khuyu: 0.630,      // khớp khuỷu khi tay buông
    hang: 0.530,       // khớp háng (mấu chuyển lớn)
    goi: 0.285,        // khớp gối
    coChan: 0.039,     // mắt cá chân
    dau: 0.130,        // đỉnh đầu → cằm
    vaiNgang: 0.259,   // bề ngang VAI PHÍA NGOÀI (không phải khoảng cách 2 khớp — sửa 24/09)
    nguc: 0.174,       // bề ngang ngực
    hangNgang: 0.191,  // bề ngang HÔNG phía ngoài (ở mức khớp háng)
    canhTay: 0.186,    // vai → khuỷu
    cangTay: 0.146,    // khuỷu → cổ tay
    banTay: 0.108,     // cổ tay → đầu ngón
    banChan: 0.152,    // dài bàn chân
    rongChan: 0.055    // rộng bàn chân
  };

  // ── DÁNG VỎ (bo tròn) — mỗi khúc là một ỐNG THUÔN có đầu tròn ──
  // vong: các vòng mặt cắt dọc theo khúc [t, rộng, sâu, lệch]: t = 0 (đầu khúc) → 1 (cuối khúc);
  //       rộng = nửa bề ngang (theo X, ngang người), sâu = nửa bề dày trước-sau, lệch = dời
  //       tâm vòng theo trục v = u × X (tuỳ chọn). Đơn vị: × H.
  //       Chiều của v: THÂN (trục hướng lên) → v chỉ ra LƯNG; TAY/CHÂN buông (trục hướng
  //       xuống) → v chỉ ra TRƯỚC. Nên: mông ra sau = lệch dương ở thân; bắp chân ra sau =
  //       lệch âm ở cẳng chân; đùi trước căng = lệch dương ở đùi.
  // dauA/dauB: độ gồ của đầu tròn ở hai đầu khúc (× H).
  // ƯỚC LƯỢNG ở BMI 22, CHƯA CÓ NGUỒN — bảng Drillis chỉ có chiều dài. Tỉ lệ ngang đã khoá
  // bằng test (vai ≈ 0.259H, hông 0.20–0.23H). Quan trọng cho kiểm tủ: 'dui' (mặt ngồi, gối).
  var VO = {
    // thân: mông ra sau, eo thắt, ngực nhô tới, lưng trên hơi gù, vai thu vào cổ
    than:     { vong: [[0, .084, .060, .010], [.14, .086, .064, .012], [.30, .079, .056, .002], [.47, .082, .058, -.004],
                       [.62, .091, .066, -.008], [.78, .100, .063, -.004], [.90, .104, .058, .002], [1, .092, .046, .006]],
                dauA: .046, dauB: .040 },
    co:       { vong: [[0, .028, .028], [.5, .024, .025], [1, .025, .026]], dauA: .020, dauB: .020 },
    // đầu: trứng, sọ sau gồ ra sau, cằm hơi hẹp
    dau:      { vong: [[0, .040, .042, -.004], [.3, .049, .055, .000], [.6, .052, .061, .004], [1, .046, .054, .006]], dauA: .024, dauB: .036 },
    // cánh tay: vai tròn (đầu gồ to), bắp tay hơi phồng trước
    canhTay:  { vong: [[0, .033, .032], [.35, .029, .030, .002], [.7, .026, .026], [1, .023, .024]], dauA: .034, dauB: .023 },
    cangTay:  { vong: [[0, .023, .024], [.25, .025, .026, .002], [.6, .021, .021], [1, .016, .014]], dauA: .023, dauB: .014 },
    banTay:   { vong: [[0, .016, .022], [.45, .015, .026], [.8, .013, .022], [1, .010, .017]], dauA: .010, dauB: .012 },
    // đùi: gốc đầy, trước đùi căng, thuôn về gối
    dui:      { vong: [[0, .050, .054], [.2, .049, .053, .003], [.5, .043, .047, .004], [.8, .036, .039, .002], [1, .032, .034]],
                dauA: .045, dauB: .032 },
    // cẳng chân: gối gọn, bắp chân phồng ra SAU (lệch âm), cổ chân thon
    cangChan: { vong: [[0, .031, .033], [.12, .031, .035, -.004], [.32, .033, .039, -.008], [.6, .026, .029, -.004], [1, .019, .021]],
                dauA: .032, dauB: .021 },
    // bàn chân: 'sâu' là bề DÀY đứng; giữ đúng 0.0195H để đáy chân nằm đúng 0.039H dưới mắt cá
    banChan:  { vong: [[0, .021, .0195], [.35, .024, .0195], [.7, .027, .0185], [1, .019, .012]], dauA: .020, dauB: .018 }
  };
  var DAY = VO;   // tên cũ, giữ cho code ngoài đang gọi HinhNhan.DAY

  // ── VỊ TRÍ KHỚP theo bề ngang (× H, tính từ đường giữa) — suy từ Drillis, sửa 24/09 ──
  // Bảng Drillis cho bề ngang PHÍA NGOÀI; tâm khớp nằm vào trong một bề dày tay/đùi:
  //   vai: 0.259H / 2 = 0.1295H ngoài cùng − bán kính cánh tay ~0.03H ≈ 0.100H
  //   háng: bề ngang hông ~0.22H / 2 = 0.11H − bán kính gốc đùi ~0.055H ≈ 0.052H
  //         (khoảng cách 2 tâm khớp háng ≈ 0.104H ≈ 17cm ở người 1m60 — khớp số đo y văn)
  //   (24/09: hông hạ về 0.045H + gốc đùi 0.050H → rộng mông ≈ 0.19H, khớp Atlat người Việt
  //    1986: nam 29,5/160,7 = 0.184H, nữ 28,8/150,3 = 0.192H)
  var KHOP = { vai: 0.100, hang: 0.045 };

  // Số cạnh quanh mỗi vòng và số vòng của đầu tròn — mượt mà file vẫn nhẹ (~9 nghìn tam giác/người).
  var QUANH = 20, VONG_DAU = 5;

  // Hệ số béo gầy: chỉ số BMI = cân nặng (kg) / chiều cao (m)². Độ dày tỉ lệ với căn bậc
  // hai của BMI/22 (thiết diện ~ khối lượng / chiều dài, bán kính ~ căn thiết diện).
  // Kẹp BMI 15–40 để nhập nhầm không ra hình quái.
  // Xương không to ra theo cân nặng, chỉ phần mềm → chỉ lấy 80% phần chênh (sửa 24/09 sau khi
  // Khoa thấy người 84kg đùi to quá).
  function heSoBeo(h, kg) {
    var bmi = kg / Math.pow(h / 1000, 2);
    bmi = Math.min(40, Math.max(15, bmi));
    return { bmi: bmi, f: 1 + 0.8 * (Math.sqrt(bmi / 22) - 1) };
  }

  // ── BẢNG DÁNG — góc khớp (độ). ƯỚC LƯỢNG, CHỜ KHOA DUYỆT bằng mắt nghề ──
  //   than   : thân nghiêng TỚI so với phương đứng (âm = ngả ra sau)
  //   co     : cúi đầu tới so với thân (âm = ngửa lên)
  //   vai    : cánh tay giơ TỚI so với thân (0 = buông dọc thân, âm = đưa ra sau)
  //   khuyu  : gập khuỷu (0 = duỗi thẳng)
  //   hang   : đùi giơ tới (0 = đứng thẳng, 90 = đùi nằm ngang khi ngồi, âm = đùi ra sau)
  //   goi    : gập gối (0 = duỗi thẳng)
  //   Thêm hậu tố P / T để hai bên khác nhau: vaiP = tay PHẢI, hangT = chân TRÁI…
  //   (người nhìn về −Y nên bên PHẢI của người nằm ở phía X âm)
  //   nam    : true = xoay cả người nằm ngửa
  //   phong  : nhóm nút trong hộp thoại; hien: số đo ước lượng lưu vào component (không hiện
  //            trên hộp thoại — Khoa 24/09: bảng số làm người thiết kế phân tâm)
  var DANG = {
    // Bếp
    dung_nau:    { phong: 'Bếp', ten: 'Đứng nấu / rửa bát', than: 15, co: 20, vai: 35, khuyu: 65, hang: 0, goi: 0,
                   hien: ['khuyuTay', 'dauNgon', 'voiTruoc', 'tamMat'] },
    voi_tu_tren: { phong: 'Bếp', ten: 'Với tủ trên', than: 0, co: -20, vai: 160, khuyu: 10, hang: 0, goi: 0,
                   hien: ['dauNgon', 'tamMat', 'dinhDau'] },
    cui_tu_duoi: { phong: 'Bếp', ten: 'Khom lấy đồ tủ dưới', than: 70, co: -10, vai: 70, khuyu: 10, hang: 0, goi: 15,
                   hien: ['dauNgon', 'voiTruoc', 'caoNhat', 'chieuSau'] },
    ngoi_xom:    { phong: 'Bếp', ten: 'Ngồi xổm (tủ thấp, lau sàn)', than: 30, co: 0, vai: 55, khuyu: 20, hang: 120, goi: 140,
                   hien: ['dauNgon', 'caoNhat', 'chieuSau'] },
    // Phòng tắm
    rua_mat:     { phong: 'Phòng tắm', ten: 'Rửa mặt ở lavabo', than: 35, co: 20, vai: 45, khuyu: 50, hang: 0, goi: 5,
                   hien: ['dauNgon', 'khuyuTay', 'tamMat', 'chieuSau'] },
    ngoi_bon_cau:{ phong: 'Phòng tắm', ten: 'Ngồi bồn cầu', than: 15, co: 15, vai: 30, khuyu: 60, hang: 95, goi: 100,
                   hien: ['matNgoi', 'dinhGoi', 'chieuSau', 'tamMat'] },
    // Phòng ngủ
    treo_do:     { phong: 'Phòng ngủ', ten: 'Treo đồ tủ áo (một tay)', than: 0, co: -15, vai: 0, vaiP: 150, khuyu: 5, khuyuP: 20, hang: 0, goi: 0,
                   hien: ['dauNgon', 'tamMat'] },
    nam_giuong:  { phong: 'Phòng ngủ', ten: 'Nằm giường', than: 0, co: 0, vai: 0, khuyu: 0, hang: 0, goi: 0, nam: true,
                   hien: ['chieuDai', 'caoNhat', 'ngangNguoi'] },
    // Ăn / làm việc / khách
    ngoi_ghe:    { phong: 'Ăn · làm việc · khách', ten: 'Ngồi ghế ăn / bàn học', than: 0, co: 15, vai: 25, khuyu: 75, hang: 90, goi: 90,
                   hien: ['matNgoi', 'dinhGoi', 'khuyuTay', 'tamMat'] },
    ngoi_sofa:   { phong: 'Ăn · làm việc · khách', ten: 'Ngồi sofa', than: -25, co: 10, vai: 10, khuyu: 40, hang: 80, goi: 80,
                   hien: ['matNgoi', 'dinhGoi', 'tamMat', 'chieuSau'] },
    ngoi_bet:    { phong: 'Ăn · làm việc · khách', ten: 'Ngồi bệt (sập, bàn trà thấp)', than: -10, co: 10, vai: 15, khuyu: 30, hang: 90, goi: 0,
                   hien: ['tamMat', 'khuyuTay', 'chieuSau'] },
    // Lối đi · cửa
    dung_thang:  { phong: 'Lối đi · cửa', ten: 'Đứng thẳng (cửa, gầm thang)', than: 0, co: 0, vai: 0, khuyu: 0, hang: 0, goi: 0,
                   hien: ['dinhDau', 'tamMat', 'ngangNguoi', 'chieuSau'] },
    di_bo:       { phong: 'Lối đi · cửa', ten: 'Đi bộ (lối đi)', than: 3, co: 0, vai: 0, vaiP: 20, vaiT: -20, khuyu: 15,
                   hang: 0, hangP: -15, hangT: 22, goi: 0, goiP: 5, goiT: 12,
                   hien: ['ngangNguoi', 'chieuSau', 'dinhDau'] }
  };

  // ── SỐ ĐO CHUẨN (tư thế TĨNH) — DÙNG ĐỂ THIẾT KẾ ──
  // Chỉ gồm số có NGUỒN, tính thẳng = tỉ lệ × chiều cao, không qua hình nhân tạo dáng.
  // Đối chiếu 24/09: tỉ lệ Drillis khớp Atlat nhân trắc học người Việt Nam trong lứa tuổi lao
  // động (1986) trong ~1%: cao vai 0.810H (Atlat) vs 0.818H; dài tay 0.439–0.440H vs 0.440H;
  // dài chân 0.524–0.532H vs 0.530H. Các số là TRUNG BÌNH theo tỉ lệ — người thật lệch vài %.
  var CHUAN = [
    { key: 'matDung',   ten: 'Tầm mắt — đứng',                 tl: 0.936, nguon: 'Drillis & Contini' },
    { key: 'vaiDung',   ten: 'Vai — đứng',                     tl: 0.818, nguon: 'Drillis · Atlat VN 0,810H' },
    { key: 'khuyuDung', ten: 'Khuỷu tay — đứng, tay buông',    tl: 0.630, nguon: 'Drillis & Contini' },
    { key: 'coTayDung', ten: 'Cổ tay — đứng, tay buông',       tl: 0.485, nguon: 'Drillis & Contini' },
    { key: 'ngonDung',  ten: 'Đầu ngón tay — đứng, tay buông', tl: 0.377, nguon: 'Drillis & Contini' },
    { key: 'goiDung',   ten: 'Khớp gối — đứng',                tl: 0.285, nguon: 'Drillis & Contini' },
    { key: 'caoNgoi',   ten: 'Chiều cao ngồi (mặt ghế → đỉnh đầu)', tl: 0.532, nguon: 'Atlat VN 1986' }
  ];
  function soChuan(h) {
    return CHUAN.map(function (c) { return { key: c.key, ten: c.ten, mm: Math.round(c.tl * h), nguon: c.nguon }; });
  }

  // Vóc người chọn nhanh. Trung bình theo Tổng điều tra dinh dưỡng 2019–2020 (Bộ Y tế):
  // thanh niên nam 168,1 cm, nữ 156,2 cm. Cân nặng lấy quanh BMI 20–23 (ƯỚC LƯỢNG).
  // Kiểm ĐỘ HỞ (đầu, gối) dùng người CAO; kiểm TẦM VỚI (tủ trên, thanh treo) dùng người THẤP.
  var VOC = [
    { ten: 'Nữ thấp', cao: 150, nang: 45 },
    { ten: 'Nữ TB', cao: 156, nang: 50 },
    { ten: 'Nam TB', cao: 168, nang: 63 },
    { ten: 'Nam cao', cao: 175, nang: 70 }
  ];
  var VOC_MAC_DINH = 2;   // Nam TB 168 cm

  var RAD = Math.PI / 180;
  // Hướng theo "góc tới tính từ phương thẳng XUỐNG": 0 = xuống, 90 = ra trước (-Y).
  function huongXuong(goc) { var a = goc * RAD; return [0, -Math.sin(a), -Math.cos(a)]; }
  // Hướng theo "góc tới tính từ phương thẳng LÊN": 0 = lên, dương = ngả tới (-Y).
  function huongLen(goc) { var a = goc * RAD; return [0, -Math.sin(a), Math.cos(a)]; }
  function cong(p, v, k) { return [p[0] + v[0] * k, p[1] + v[1] * k, p[2] + v[2] * k]; }

  // Dựng dáng. h = chiều cao (mm), kg = cân nặng, key = khoá trong DANG, gocDe = góc
  // ghi đè (tuỳ chọn, để thử dáng khác). Trả { khoi: [...], so: {...}, bmi }.
  function dung(h, kg, key, gocDe) {
    var d = Object.assign({}, DANG[key] || DANG.dung_nau, gocDe || {});
    var b = heSoBeo(h, kg), f = b.f;
    var L = {};
    Object.keys(TL).forEach(function (k) { L[k] = TL[k] * h; });

    // Khung xương, gốc = tâm 2 khớp háng tại (0,0,0) trước khi hạ xuống sàn.
    var P = [0, 0, 0];
    var len = huongLen(d.than);
    var S = cong(P, len, L.vai - L.hang);                 // tâm đường vai: thân = 0.818H − 0.530H
    var dauHuong = huongLen(d.than + d.co);
    var C = cong(S, dauHuong, L.cam - L.vai);             // cằm: cổ = 0.870H − 0.818H
    var D = cong(C, dauHuong, L.dau);                     // đỉnh đầu: đầu = 0.130H
    var M = cong(C, dauHuong, L.dau - (1 - TL.mat) * h);  // mắt: dưới đỉnh đầu (1 − 0.936)H

    // Hệ số béo gầy theo khúc: thân/tay chân theo f; đầu gần như không đổi; bàn tay theo
    // căn f; bàn chân chỉ nở ngang (kẹp 1.3), bề dày đứng giữ nguyên để đáy chân đúng.
    var HS = { than: f, co: f, dau: 1, canhTay: f, cangTay: f, banTay: Math.sqrt(f), dui: f, cangChan: f, banChan: 1 };

    var khoi = [];
    // Một khúc: ống từ a tới b theo bảng VO[loai]. 'rut' = rút hai đầu trục vào đúng bằng
    // độ gồ của đầu tròn, để phần gồ kết thúc ĐÚNG tại a/b (dùng cho đầu, bàn tay, bàn chân
    // — nơi mép ngoài là số đo thật). Không rút thì đầu tròn trùm qua khớp, nối liền khúc kế.
    function khuc(ten, loai, a, b, rut) {
      var vo = VO[loai], k = HS[loai];
      var u = tru3(b, a), dai = do3(u); u = nhan3(u, 1 / dai);
      var capA = vo.dauA * h * k, capB = vo.dauB * h * k;
      if (loai === 'banChan') { capA = vo.dauA * h; capB = vo.dauB * h; }
      if (rut) { a = cong(a, u, capA); b = cong(b, u, -capB); }
      khoi.push({ ten: ten, luoi: ong(a, b, vo, h, k, loai === 'banChan' ? Math.min(f, 1.3) : k, capA, capB) });
    }

    khuc('Than', 'than', cong(P, len, -0.01 * h), cong(S, len, 0.01 * h), false);
    khuc('Co', 'co', S, C, false);
    khuc('Dau', 'dau', C, D, true);

    // Góc của một bên: 'vaiP' (phải) / 'vaiT' (trái) nếu có, không thì dùng chung 'vai'.
    // ben = −1 là bên PHẢI của người (người nhìn về −Y), ben = +1 là bên TRÁI.
    function gocBen(ten, ben) {
      var rieng = d[ten + (ben < 0 ? 'P' : 'T')];
      return rieng === undefined ? d[ten] : rieng;
    }

    // Tay: góc thật của cánh tay = góc giơ tới − độ nghiêng thân (thân cúi thì tay
    // buông theo thân hướng ra sau). Cẳng tay = cánh tay + độ gập khuỷu.
    var so = { tay: [], goi: [] };
    [-1, 1].forEach(function (ben) {
      var gocTay = gocBen('vai', ben) - d.than, gocCang = gocTay + gocBen('khuyu', ben);
      var Vai = [ben * KHOP.vai * h, S[1], S[2]];
      var Khuyu = cong(Vai, huongXuong(gocTay), L.canhTay);
      var CoTay = cong(Khuyu, huongXuong(gocCang), L.cangTay);
      var Ngon = cong(CoTay, huongXuong(gocCang), L.banTay);
      khuc('CanhTay', 'canhTay', Vai, Khuyu, false);
      khuc('CangTay', 'cangTay', Khuyu, CoTay, false);
      khuc('BanTay', 'banTay', CoTay, Ngon, true);
      so.tay.push({ khuyu: Khuyu, ngon: Ngon });
    });

    // Chân: đùi theo góc gập háng; cẳng chân = đùi − gập gối. Bàn chân nằm ngang ra trước.
    [-1, 1].forEach(function (ben) {
      var gocDui = gocBen('hang', ben), gocCangChan = gocDui - gocBen('goi', ben);
      var Hang = [ben * KHOP.hang * h, 0, 0];
      var Goi = cong(Hang, huongXuong(gocDui), L.hang - L.goi);            // đùi = 0.530H − 0.285H
      var MatCa = cong(Goi, huongXuong(gocCangChan), L.goi - L.coChan);   // cẳng chân = 0.285H − 0.039H
      khuc('Dui', 'dui', Hang, Goi, false);
      khuc('CangChan', 'cangChan', Goi, MatCa, false);
      // Bàn chân: gót lùi 1/4 chiều dài sau mắt cá, mũi ra trước 3/4; trục ở giữa bề dày
      // (mắt cá cao 0.039H → trục cách mắt cá 0.0195H, đáy chân chạm đúng mặt sàn).
      //   Cẳng chân gần thẳng đứng (lệch ≤ 60°): bàn chân đặt PHẲNG trên sàn (đứng, ngồi ghế, ngồi xổm).
      //   Cẳng chân nằm ngang (ngồi bệt duỗi chân): bàn chân VUÔNG GÓC cẳng chân, mũi chĩa lên.
      var phang = Math.abs(gocCangChan) <= 60;
      var huongChan = phang ? [0, -1, 0] : huongXuong(gocCangChan + 90);
      var huongDay = phang ? [0, 0, -1] : huongXuong(gocCangChan);
      var tamChan = cong(MatCa, huongDay, L.coChan / 2);
      khuc('BanChan', 'banChan', cong(tamChan, huongChan, -L.banChan * 0.25), cong(tamChan, huongChan, L.banChan * 0.75), true);
      so.goi.push(Goi);
    });

    // Nằm NGỬA: xoay 90° quanh trục X — đầu về phía +Y, mặt (vốn hướng -Y) quay lên +Z.
    // (y, z) → (z, −y). Kiểm: đỉnh đầu (0,0,1) → (0,1,0); mặt trước (0,−1,0) → (0,0,1).
    function xoay(p) { return d.nam ? [p[0], p[2], -p[1]] : p; }
    khoi.forEach(function (k) { k.luoi.diem = k.luoi.diem.map(xoay); });
    so.tay = so.tay.map(function (t) { return { khuyu: xoay(t.khuyu), ngon: xoay(t.ngon) }; });
    so.goi = so.goi.map(xoay);
    var diem = { M: xoay(M), D: xoay(D), P: xoay(P) };

    // Hạ xuống sàn: đỉnh lưới thấp nhất chạm z = 0.
    var thap = Infinity;
    khoi.forEach(function (k) { k.luoi.diem.forEach(function (q) { thap = Math.min(thap, q[2]); }); });
    function ha(q) { return [q[0], q[1], q[2] - thap]; }
    khoi.forEach(function (k) { k.luoi.diem = k.luoi.diem.map(ha); });

    function moiDiem(loc) {
      return khoi.filter(function (k) { return !loc || loc.indexOf(k.ten) >= 0; })
        .reduce(function (m, k) { return m.concat(k.luoi.diem); }, []);
    }
    var tatCa = moiDiem();
    // Đỉnh gối: điểm cao nhất của đùi + cẳng chân quanh khớp gối (trong 0.08H), xét cả 2 gối.
    var cacGoi = so.goi.map(ha);
    var quanhGoi = moiDiem(['Dui', 'CangChan']).filter(function (q) {
      return cacGoi.some(function (g) { return Math.hypot(q[0] - g[0], q[1] - g[1], q[2] - g[2]) < 0.08 * h; });
    });
    // Tay dùng để đo = tay có đầu ngón CAO nhất (treo đồ một tay → tay đang giơ).
    var tayDo = so.tay.map(function (t) { return { khuyu: ha(t.khuyu), ngon: ha(t.ngon) }; })
      .sort(function (a, b2) { return b2.ngon[2] - a.ngon[2]; })[0];
    function bienTruc(i) {
      var v = tatCa.map(function (q) { return q[i]; });
      return Math.max.apply(null, v) - Math.min.apply(null, v);
    }

    // ── SỐ ĐO KIỂM CÔNG NĂNG (mm, làm tròn). Mọi số về VỎ đo thẳng trên lưới đã dựng. ──
    var ra = function (v) { return Math.round(v); };
    var ketQua = {
      dinhDau: ra(ha(diem.D)[2]),                    // cao nhất của đầu
      tamMat: ra(ha(diem.M)[2]),                     // cao tầm mắt
      khuyuTay: ra(tayDo.khuyu[2]),                  // cao khuỷu tay
      dauNgon: ra(tayDo.ngon[2]),                    // cao đầu ngón tay (với tủ trên: tầm với cao nhất)
      voiTruoc: ra(-(tayDo.ngon[1] - ha(diem.P)[1])),// đầu ngón ra trước bao xa tính từ tâm háng
      dinhGoi: ra(Math.max.apply(null, quanhGoi.map(function (q) { return q[2]; }))), // mặt trên đầu gối
      matNgoi: ra(Math.min.apply(null, moiDiem(['Than', 'Dui']).map(function (q) { return q[2]; }))), // đáy mông/đùi ≈ mặt ghế
      chieuDai: ra(bienTruc(1)),                     // nằm: dài chiếm chỗ (theo Y)
      chieuSau: ra(bienTruc(1)),                     // đứng/ngồi: chiếm chỗ trước–sau (theo Y)
      ngangNguoi: ra(bienTruc(0)),                   // bề ngang chiếm chỗ (theo X) — lối đi, cửa
      caoNhat: ra(Math.max.apply(null, tatCa.map(function (q) { return q[2]; })))   // điểm cao nhất
    };
    return { khoi: khoi, so: ketQua, hien: d.hien || [], bmi: Math.round(b.bmi * 10) / 10, dang: d.ten, key: key };
  }

  // ── Vector 3 chiều ──
  function tru3(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
  function nhan3(a, k) { return [a[0] * k, a[1] * k, a[2] * k]; }
  function do3(a) { return Math.hypot(a[0], a[1], a[2]); }
  function cheo3(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function cham3(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

  // Lưới một ống thuôn đầu tròn, từ a tới b.
  //   Vòng mặt cắt là elip: bán trục 'rộng' theo X (ngang người), 'sâu' theo v = u × X.
  //   Đầu tròn: VONG_DAU vòng co dần theo cos, lùi ra theo sin — một nửa elipxoit.
  // Trả { diem: [[x,y,z]...], mat: [[i,j,k(,l)]...] } — chỉ số từ 0, pháp tuyến quay RA NGOÀI.
  function ong(a, b, vo, h, kRong, kRongX, capA, capB) {
    var u = tru3(b, a), dai = do3(u); u = nhan3(u, 1 / dai);
    var X = [1, 0, 0], v = cheo3(u, X); v = nhan3(v, 1 / do3(v));
    var vong = vo.vong.map(function (r) {
      return { t: r[0] * dai, rx: r[1] * h * kRongX, rv: r[2] * h * kRong, lech: (r[3] || 0) * h * kRong };
    });
    var dau = vong[0], cuoi = vong[vong.length - 1];
    var cacVong = [];                                         // {tam, rx, rv}
    for (var i = VONG_DAU - 1; i >= 1; i--) {                 // đầu tròn phía a (từ gần đỉnh ra)
      var ph = i / VONG_DAU * Math.PI / 2;
      cacVong.push({ tam: cong(cong(a, v, dau.lech), u, -capA * Math.sin(ph)), rx: dau.rx * Math.cos(ph), rv: dau.rv * Math.cos(ph) });
    }
    vong.forEach(function (r) { cacVong.push({ tam: cong(cong(a, u, r.t), v, r.lech), rx: r.rx, rv: r.rv }); });
    for (var j = 1; j < VONG_DAU; j++) {                      // đầu tròn phía b
      var ph2 = j / VONG_DAU * Math.PI / 2;
      cacVong.push({ tam: cong(cong(b, v, cuoi.lech), u, capB * Math.sin(ph2)), rx: cuoi.rx * Math.cos(ph2), rv: cuoi.rv * Math.cos(ph2) });
    }
    var diem = [cong(cong(a, v, dau.lech), u, -capA)];        // 0 = đỉnh cực phía a
    cacVong.forEach(function (vg) {
      for (var q = 0; q < QUANH; q++) {
        var th = 2 * Math.PI * q / QUANH;
        diem.push(cong(cong(vg.tam, X, vg.rx * Math.cos(th)), v, vg.rv * Math.sin(th)));
      }
    });
    var cuc = diem.length; diem.push(cong(cong(b, v, cuoi.lech), u, capB)); // đỉnh cực phía b
    var mat = [];
    var o = function (vi, q) { return 1 + vi * QUANH + (q % QUANH); };
    for (var q2 = 0; q2 < QUANH; q2++) {
      mat.push([0, o(0, q2 + 1), o(0, q2)]);
      // Ô giữa hai vòng chia 2 TAM GIÁC: vòng elip to nhỏ khác nhau nên ô tứ giác không phẳng
      // tuyệt đối, tài liệu Trimble không nói add_faces_from_mesh xử lý ô cong ra sao → tam giác
      // luôn phẳng, khỏi đoán.
      for (var vi = 0; vi < cacVong.length - 1; vi++) {
        mat.push([o(vi, q2), o(vi, q2 + 1), o(vi + 1, q2 + 1)]);
        mat.push([o(vi, q2), o(vi + 1, q2 + 1), o(vi + 1, q2)]);
      }
      mat.push([cuc, o(cacVong.length - 1, q2), o(cacVong.length - 1, q2 + 1)]);
    }
    // Chuẩn chiều pháp tuyến: thử một mặt thân ống; quay vào trong thì đảo cả lưới.
    var m0 = mat[1], p0 = diem[m0[0]], p1 = diem[m0[1]], p2 = diem[m0[2]];
    var n = cheo3(tru3(p1, p0), tru3(p2, p0));
    var giua = cong(a, u, cham3(tru3(p0, a), u));
    if (cham3(n, tru3(p0, giua)) < 0) mat = mat.map(function (m) { return m.slice().reverse(); });
    return { diem: diem, mat: mat };
  }

  // Nhãn tiếng Việt cho từng số đo — hộp thoại và Ruby dùng chung.
  var NHAN = {
    dinhDau: 'Đỉnh đầu', tamMat: 'Tầm mắt', khuyuTay: 'Khuỷu tay', dauNgon: 'Đầu ngón tay',
    voiTruoc: 'Tay vươn ra trước (từ tâm háng)', dinhGoi: 'Mặt trên đầu gối', matNgoi: 'Mặt ngồi (đáy mông)',
    chieuDai: 'Chiều dài nằm', caoNhat: 'Điểm cao nhất',
    chieuSau: 'Chiếm chỗ trước–sau', ngangNguoi: 'Bề ngang người'
  };

  return { CHUAN: CHUAN, soChuan: soChuan, VOC: VOC, VOC_MAC_DINH: VOC_MAC_DINH, TL: TL, VO: VO, DAY: DAY, KHOP: KHOP, DANG: DANG, NHAN: NHAN, heSoBeo: heSoBeo, dung: dung, ong: ong };
}));
