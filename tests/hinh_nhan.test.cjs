// Test lõi toán Hình Nhân — chạy: node tests/hinh_nhan.test.cjs
// Nằm NGOÀI LeHai_Tools/ nên release.py không gửi file này xuống máy thợ.
const HN = require('../LeHai_Tools/hinh_nhan/hinh_nhan.js');

let pass = 0, fail = 0;
function kiem(ten, dung, chiTiet) {
  if (dung) { pass++; } else { fail++; console.log('  TRƯỢT:', ten, chiTiet === undefined ? '' : chiTiet); }
}
const gan = (a, b, sai) => Math.abs(a - b) <= sai;
const moiDiem = (r, ten) => r.khoi.filter(k => !ten || k.ten === ten).flatMap(k => k.luoi.diem);

// 1. ĐỨNG THẲNG (mọi góc = 0): số đo khớp phải trùng tỉ lệ Drillis — chứng minh khung
//    xương + bước hạ sàn đúng (đáy bàn chân nằm đúng 0.039H dưới mắt cá).
{
  const H = 1700;
  const r = HN.dung(H, 64, 'dung_nau', { than: 0, co: 0, vai: 0, khuyu: 0, hang: 0, goi: 0 });
  kiem('đỉnh đầu = H', gan(r.so.dinhDau, H, 1), r.so.dinhDau);
  kiem('tầm mắt = 0.936H', gan(r.so.tamMat, 0.936 * H, 1), r.so.tamMat);
  kiem('khuỷu = 0.630H', gan(r.so.khuyuTay, 0.630 * H, 3), r.so.khuyuTay);   // 0.818−0.186 = 0.632 (bảng gốc làm tròn)
  kiem('đầu ngón = 0.377H', gan(r.so.dauNgon, 0.377 * H, 4), r.so.dauNgon);  // 0.818−0.440 = 0.378
  kiem('tay buông không vươn tới', gan(r.so.voiTruoc, 0, 1), r.so.voiTruoc);
  // vỏ đầu kết thúc đúng tại đỉnh đầu (đầu tròn đã rút vào trục)
  const dinhVo = Math.max(...moiDiem(r, 'Dau').map(q => q[2]));
  kiem('vỏ đầu chạm đúng đỉnh đầu', gan(dinhVo, H, 2), dinhVo);
}

// 1b. BỀ NGANG (đo trên lưới): vai ngoài ≈ 0.259H (Drillis), hông ngoài ≈ 0.20–0.23H.
//     Bắt lại lỗi 24/09: dùng bề ngang NGOÀI làm khoảng cách KHỚP → vai 0.33H, hông 0.31H.
{
  const H = 1600, r = HN.dung(H, 55, 'dung_nau', { than: 0, co: 0, vai: 0, khuyu: 0, hang: 0, goi: 0 });
  const ngang = (ten, z0, z1) => {
    const x = r.khoi.filter(k => ten.includes(k.ten)).flatMap(k => k.luoi.diem).filter(q => q[2] > z0 && q[2] < z1).map(q => q[0]);
    return Math.max(...x) - Math.min(...x);
  };
  const vai = ngang(['CanhTay', 'Than'], 0.74 * H, 0.84 * H), hong = ngang(['Dui', 'Than'], 0.46 * H, 0.54 * H);
  kiem('ngang vai ≈ 0.259H (±0.02H)', gan(vai, 0.259 * H, 0.02 * H), Math.round(vai));
  // Atlat nhân trắc người Việt 1986: rộng mông nam 29,5/160,7 = 0.184H, nữ 28,8/150,3 = 0.192H
  kiem('ngang hông ≈ Atlat VN 0.18–0.20H', hong > 0.18 * H && hong < 0.20 * H, Math.round(hong));
  kiem('hông hẹp hơn vai', hong < vai);
}

// 2. NGỒI GHẾ: khớp gối cao 0.285H → gối (vỏ) nhô trên khớp bằng bề dày đùi; mặt ngồi
//    là đáy đùi/mông, nằm dưới khớp háng một bề dày đùi.
{
  const H = 1600, r = HN.dung(H, 55, 'ngoi_ghe');
  kiem('đỉnh gối = 0.285H + 0.02…0.06H', r.so.dinhGoi > 0.305 * H && r.so.dinhGoi < 0.345 * H, r.so.dinhGoi);
  kiem('mặt ngồi hợp lý 340–430mm (người 1m60)', r.so.matNgoi > 340 && r.so.matNgoi < 430, r.so.matNgoi);
  kiem('gối lọt dưới bàn 750', r.so.dinhGoi < 700, r.so.dinhGoi);
  kiem('mặt ngồi thấp hơn đỉnh gối', r.so.matNgoi < r.so.dinhGoi);
}

// 3. VỚI TỦ TRÊN: tầm với cao ~1.2–1.3H (số đo nhân trắc thường gặp cho tầm với đứng).
{
  const H = 1700, r = HN.dung(H, 64, 'voi_tu_tren');
  kiem('tầm với 1.2–1.3H', r.so.dauNgon > 1.2 * H && r.so.dauNgon < 1.3 * H, r.so.dauNgon);
}

// 4. ĐỨNG NẤU: khuỷu hơi thấp hơn lúc buông vì thân cúi; tay ra trước.
{
  const H = 1600, r = HN.dung(H, 55, 'dung_nau');
  kiem('khuỷu 0.55–0.65H', r.so.khuyuTay > 0.55 * H && r.so.khuyuTay < 0.65 * H, r.so.khuyuTay);
  kiem('tay vươn ra trước', r.so.voiTruoc > 150, r.so.voiTruoc);
}

// 5. NẰM NGỬA: dài theo Y, thấp sát nền, đầu về +Y, mũi chân chĩa lên.
{
  const H = 1700, r = HN.dung(H, 64, 'nam_giuong');
  kiem('nằm: chiều dài ~ H', gan(r.so.chieuDai, H, 0.08 * H), r.so.chieuDai);
  kiem('nằm: cao nhất < 0.2H', r.so.caoNhat < 0.2 * H, r.so.caoNhat);
  const dauY = Math.max(...moiDiem(r, 'Dau').map(q => q[1]));
  kiem('nằm NGỬA: đầu về phía +Y', dauY > 0, dauY);
  const chan = moiDiem(r, 'BanChan');
  kiem('nằm NGỬA: bàn chân dựng lên (cao hơn gót)', Math.max(...chan.map(q => q[2])) > 0.12 * H);
}

// 5b. ĐỘNG TÁC MỚI (24/09)
{
  const H = 1680, kg = 63;
  // Đứng thẳng dùng làm dáng thật (không chỉ qua gocDe) phải khớp Drillis
  const t = HN.dung(H, kg, 'dung_thang');
  kiem('đứng thẳng: đỉnh đầu = H', gan(t.so.dinhDau, H, 1), t.so.dinhDau);
  // Ngồi bệt: cẳng chân nằm ngang → bàn chân dựng đứng, mũi chân chĩa LÊN
  const bet = HN.dung(H, kg, 'ngoi_bet');
  const chanBet = bet.khoi.filter(k => k.ten === 'BanChan').flatMap(k => k.luoi.diem);
  kiem('ngồi bệt: bàn chân dựng (cao > 0.12H)', Math.max(...chanBet.map(q => q[2])) > 0.12 * H, Math.max(...chanBet.map(q => q[2])));
  kiem('ngồi bệt: tầm mắt 0.40–0.50H', bet.so.tamMat > 0.40 * H && bet.so.tamMat < 0.50 * H, bet.so.tamMat);
  // Ngồi xổm: bàn chân vẫn PHẲNG trên sàn (cao bàn chân ≈ bề dày chân 0.039H)
  const xom = HN.dung(H, kg, 'ngoi_xom');
  const chanXom = xom.khoi.filter(k => k.ten === 'BanChan').flatMap(k => k.luoi.diem);
  kiem('ngồi xổm: bàn chân phẳng', Math.max(...chanXom.map(q => q[2])) < 0.06 * H, Math.max(...chanXom.map(q => q[2])));
  kiem('ngồi xổm: thấp hơn 0.62H', xom.so.caoNhat < 0.62 * H, xom.so.caoNhat);
  // Treo đồ MỘT tay: số đo lấy tay đang giơ, tay kia vẫn buông
  const treo = HN.dung(H, kg, 'treo_do');
  const ngon = treo.khoi.filter(k => k.ten === 'BanTay').map(k => Math.max(...k.luoi.diem.map(q => q[2])));
  kiem('treo đồ: một tay cao > 1.15H, tay kia < 0.6H', Math.max(...ngon) > 1.15 * H && Math.min(...ngon) < 0.6 * H, ngon.map(Math.round));
  kiem('treo đồ: số đo theo tay đang giơ', treo.so.dauNgon > 1.15 * H, treo.so.dauNgon);
  // Đi bộ: bước chân làm người chiếm chỗ trước–sau nhiều hơn lúc đứng
  const di = HN.dung(H, kg, 'di_bo');
  kiem('đi bộ: sâu hơn đứng thẳng ≥ 0.2H', di.so.chieuSau > t.so.chieuSau + 0.2 * H, [di.so.chieuSau, t.so.chieuSau]);
  // Khom lấy tủ dưới: đầu ngón xuống dưới gối
  const khom = HN.dung(H, kg, 'cui_tu_duoi');
  kiem('khom: đầu ngón thấp hơn 0.25H', khom.so.dauNgon < 0.25 * H, khom.so.dauNgon);
  // Vóc người: mặc định Nam TB 168 (Tổng điều tra dinh dưỡng 2019–2020)
  kiem('vóc mặc định = Nam TB 168', HN.VOC[HN.VOC_MAC_DINH].cao === 168);
  kiem('mọi dáng thuộc một phòng + có số đo lưu kèm', Object.values(HN.DANG).every(d => d.phong && d.hien.length && d.hien.every(k => HN.NHAN[k])));
}

// 5c. SỐ ĐO CHUẨN (24/09): chỉ số có nguồn, tỉ lệ thẳng theo chiều cao; đối chiếu Atlat VN.
{
  const c = Object.fromEntries(HN.soChuan(1680).map(x => [x.key, x.mm]));
  kiem('chuẩn: tầm mắt đứng = 0.936H', c.matDung === Math.round(0.936 * 1680), c.matDung);
  kiem('chuẩn: khuỷu đứng = 0.630H', c.khuyuDung === Math.round(0.630 * 1680), c.khuyuDung);
  kiem('chuẩn: cao ngồi = 0.532H (Atlat)', c.caoNgoi === Math.round(0.532 * 1680), c.caoNgoi);
  kiem('chuẩn: mọi số có nguồn', HN.CHUAN.every(x => x.nguon && x.tl > 0 && x.tl < 1));
  // Drillis vs Atlat người Việt 1986 (nam 160,7 cm): cao vai 130,2 · dài tay 70,6 · dài chân 85,5
  const T = HN.TL;
  kiem('Drillis ≈ Atlat: cao vai (±1.5%)', gan(T.vai, 130.2 / 160.7, 0.015), T.vai);
  kiem('Drillis ≈ Atlat: dài tay (±1.5%)', gan(T.canhTay + T.cangTay + T.banTay, 70.6 / 160.7, 0.015));
  kiem('Drillis ≈ Atlat: dài chân (±1.5%)', gan(T.hang, 85.5 / 160.7, 0.015));
  // Hình nhân ngồi thẳng phải cho chiều cao ngồi gần số Atlat 0.532H (±3%)
  const H = 1607, r = HN.dung(H, 49, 'ngoi_ghe', { than: 0, co: 0 });
  const dinh = Math.max(...r.khoi.filter(k => k.ten === 'Dau').flatMap(k => k.luoi.diem).map(q => q[2]));
  kiem('hình nhân ngồi thẳng: cao ngồi ≈ 0.532H (±3%)', gan((dinh - r.so.matNgoi) / H, 0.532, 0.016), ((dinh - r.so.matNgoi) / H).toFixed(3));
}

// 6. LƯỚI của MỌI dáng × vài vóc người:
//    - số hữu hạn, chỉ số mặt hợp lệ, mặt không suy biến
//    - KÍN: mỗi cạnh đúng 2 mặt (SketchUp làm mượt + solid đúng)
//    - pháp tuyến quay RA NGOÀI (không thì hiện màu mặt sau)
//    - không chìm dưới sàn, chạm đúng sàn
function kiemLuoi(k) {
  const { diem, mat } = k.luoi;
  if (!diem.every(q => q.every(Number.isFinite))) return 'toạ độ không hữu hạn';
  if (!mat.every(m => m.length >= 3 && m.every(i => i >= 0 && i < diem.length))) return 'chỉ số mặt sai';
  const canh = new Map();
  for (const m of mat) for (let i = 0; i < m.length; i++) {
    const a = m[i], b = m[(i + 1) % m.length], key = a < b ? a + '-' + b : b + '-' + a;
    canh.set(key, (canh.get(key) || 0) + 1);
  }
  if ([...canh.values()].some(n => n !== 2)) return 'lưới hở / cạnh dùng >2 mặt';
  // pháp tuyến ra ngoài: tổng thể tích có dấu (công thức phân kỳ) phải dương
  let V = 0;
  for (const m of mat) for (let i = 1; i + 1 < m.length; i++) {
    const a = diem[m[0]], b = diem[m[i]], c = diem[m[i + 1]];
    V += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6;
  }
  if (!(V > 0)) return 'pháp tuyến quay vào trong (thể tích âm ' + V.toFixed(0) + ')';
  return null;
}
for (const key of Object.keys(HN.DANG)) {
  for (const [H, kg] of [[1500, 45], [1650, 60], [1850, 95]]) {
    const r = HN.dung(H, kg, key);
    const loi = r.khoi.map(k => [k.ten, kiemLuoi(k)]).filter(x => x[1]);
    kiem(`${key} ${H}/${kg}: lưới kín + pháp tuyến ra ngoài`, loi.length === 0, JSON.stringify(loi.slice(0, 2)));
    const zs = moiDiem(r).map(q => q[2]);
    kiem(`${key} ${H}/${kg}: chạm đúng sàn z=0`, gan(Math.min(...zs), 0, 0.001), Math.min(...zs));
    const soMat = r.khoi.reduce((s, k) => s + k.luoi.mat.length, 0);
    // Trần 9000 (24/09: nâng từ 6000 khi tăng độ mượt 16→20 cạnh, ~7.500 tam giác). Một bếp
    // đặt 3 hình nhân ≈ 22 nghìn mặt — SketchUp vẫn nhẹ. Vượt trần = đang làm nặng file.
    kiem(`${key} ${H}/${kg}: số mặt vừa phải (< 9000)`, soMat < 9000, soMat);
  }
}

// 7. BMI kẹp 15–40: nhập nhầm 500kg không ra hình quái.
kiem('BMI kẹp trên', HN.heSoBeo(1600, 500).bmi === 40);
kiem('BMI kẹp dưới', HN.heSoBeo(1600, 10).bmi === 15);

console.log(`HINH NHAN: ${pass} đạt, ${fail} trượt`);
process.exit(fail ? 1 : 0);
