// Thử LÕI TOÁN Tạo Bo (LeHai_Tools/tao_bo/toan.rb) NGOÀI SketchUp (Ruby 3.3 wasm):
//   node projects/lehai-tools/tests/tao_bo.test.mjs [thư mục ruby.wasm]
// Chỉ thử phần toán (chiều dài trải, vị trí vùng hạ nền, khung đặt tấm). Lớp SketchUp (main.rb) phải
// chạy trong SketchUp thật — đối chiếu mẫu NTT 08/10 (scratch/tao-bo/do_bo.txt).
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module';
import { WASI } from 'node:wasi';
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const LAB = path.resolve(here, '../../..');
const wasmDir = path.resolve(process.argv[2] || path.join(LAB, 'scratch/khao-sat-hien-truong/rubywasm'));
const { RubyVM } = createRequire(path.join(wasmDir, 'package.json'))('@ruby/wasm-wasi');
const wasm = await WebAssembly.compile(fs.readFileSync(path.join(wasmDir, 'node_modules/@ruby/3.3-wasm-wasi/dist/ruby+stdlib.wasm')));
const nap = (ten, s) => `eval('${Buffer.from(s, 'utf8').toString('base64')}'.unpack1('m0').force_encoding('UTF-8'), binding, '${ten}')`;
const doc = f => fs.readFileSync(f, 'utf8');
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const c = JSON.parse(vm.eval(`require 'json'\n${nap('toan.rb', doc(path.join(here, '../LeHai_Tools/tao_bo/toan.rb')))}\n${nap('tao_bo_ca.rb', doc(path.join(here, 'tao_bo_ca.rb')))}`).toString());

let hong = 0;
const j = x => JSON.stringify(x);
const kiem = (ten, dung, chi) => { if (!dung) hong++; console.log(`  ${dung ? 'ĐẠT ' : 'HỎNG'} ${ten}${dung ? '' : '  → ' + chi}`); };
const gan = (a, b, e = 1e-3) => Math.abs(a - b) < e;
const vec = (a, b) => a.every((x, i) => gan(x, b[i]));

console.log('MẪU NTT 08/10 (cục 500×103×710, góc R50 20 đốt)');
const m = c.mau_ntt;
const ntt = 450 + 53 + 20 * 2 * 50 * Math.sin(Math.PI / 80); // tổng 20 đốt dây cung = cách NTT đo
kiem(`dài trải ${ntt.toFixed(4)} (NTT hiện 581,52)`, m.ok && gan(m.dai, ntt) && gan(m.dai, 581.52, 0.005), j(m));
kiem('cao 710', m.ok && gan(m.cao, 710), j(m));
kiem('đúng 1 vùng hạ nền, từ 450 tới 528,52 (bằng khúc bo, không lấn 13)', m.ok && m.vung.length === 1 && gan(m.vung[0][0], 450) && gan(m.vung[0][1], ntt - 53), j(m.vung));
kiem('vùng nằm mặt áp cục (góc lồi)', m.ok && m.vung[0][2] === true, j(m.vung));
kiem('khúc bo đo ra R50, góc 90° (để tự chọn dưỡng 81)', m.ok && gan(m.rg[0][0], 50) && gan(m.rg[0][1], 90), j(m.rg));
kiem('khung: trải theo trục đỏ, đứng theo trục xanh dương, mặt ngoài quay về xanh lá âm', m.ok && vec(m.x, [1, 0, 0]) && vec(m.y, [0, 0, 1]) && vec(m.z, [0, -1, 0]), j(m));
kiem('gốc tấm cách mặt trước 150, đáy cùng đáy cục', m.ok && vec(m.goc, [0, -150, 0]), j(m.goc));
kiem('vòng điểm đi ngược chiều → ra y hệt', j(c.mau_ntt_day_nguoc) === j(m), j(c.mau_ntt_day_nguoc));
for (const [a, r] of Object.entries(c.mau_ntt_xoay))
  kiem(`cục xoay ${a}°: dài + vùng y hệt`, r.ok && gan(r.dai, m.dai) && j(r.vung) === j(m.vung) && vec(r.y, [0, 0, 1]), j(r));
kiem('cục nằm ngang (trục đùn nằm): dài + vùng y hệt', c.mau_ntt_nam.ok && gan(c.mau_ntt_nam.dai, m.dai) && j(c.mau_ntt_nam.vung) === j(m.vung), j(c.mau_ntt_nam));
kiem('cung đã Explode: đoán ra y hệt + có cờ "đoán"', c.mau_ntt_explode.ok && gan(c.mau_ntt_explode.dai, m.dai) && j(c.mau_ntt_explode.vung) === j(m.vung) && c.mau_ntt_explode.doan === true, j(c.mau_ntt_explode));

console.log('\nHÌNH KHÁC');
const u = c.chu_u;
const w40 = 12 * 2 * 40 * Math.sin(Math.PI / 2 / 24), w60 = 16 * 2 * 60 * Math.sin(Math.PI / 2 / 32);
kiem('chữ U: 2 vùng đúng chỗ, cùng mặt áp cục', u.ok && u.vung.length === 2 && gan(u.vung[0][0], 300) && gan(u.vung[0][1], 300 + w40) && gan(u.vung[1][0], 800 + w40) && gan(u.vung[1][1], 800 + w40 + w60) && u.vung.every(v => v[2]), j(u));
kiem('chữ U: dài = 1000 + 2 cung', u.ok && gan(u.dai, 1000 + w40 + w60), j(u));
kiem('chữ U: khúc 1 R40, khúc 2 R60, đều 90°', u.ok && gan(u.rg[0][0], 40) && gan(u.rg[1][0], 60) && gan(u.rg[0][1], 90) && gan(u.rg[1][1], 90), j(u.rg));
const s = c.chu_s, w50 = 10 * 2 * 50 * Math.sin(Math.PI / 2 / 20);
kiem('chữ S: vùng 1 mặt áp cục, vùng 2 mặt NGOÀI (uốn ngược)', s.ok && s.vung.length === 2 && s.vung[0][2] === true && s.vung[1][2] === false && gan(s.vung[1][0], 400 + w50), j(s));

for (const [k, R, n] of [['bo_cuoi_chuoi', 50, 'cuối'], ['bo_dau_chuoi', 50, 'đầu'], ['bo_cuoi_r34', 34, 'cuối']])
  kiem(`khúc bo R${R} sát góc gãy ở ${n} chuỗi: vẫn đo ra R${R}, 90° (để tự chọn dưỡng)`, c[k].ok && gan(c[k].rg[0][0], R) && gan(c[k].rg[0][1], 90), j(c[k].rg));

console.log('\nKHÚC BO THEO DƯỠNG (đoạn thẳng giữ nguyên, tổng tấm đổi theo)');
kiem('dài = cung: y hệt tấm tự động', gan(c.rong_bang_cung.dai, m.dai) && j(c.rong_bang_cung.vung) === j(m.vung), j(c.rong_bang_cung));
kiem('dưỡng 54: 450 | 54 | 53 → tổng 557, vùng 450 → 504', gan(c.rong_54.dai, 557) && gan(c.rong_54.vung[0][0], 450) && gan(c.rong_54.vung[0][1], 504) && c.rong_54.vung[0][2] === true, j(c.rong_54));
kiem('dưỡng 81: 450 | 81 | 53 → tổng 584, vùng 450 → 531', gan(c.rong_81.dai, 584) && gan(c.rong_81.vung[0][0], 450) && gan(c.rong_81.vung[0][1], 531), j(c.rong_81));
kiem('dài 0: báo lỗi', typeof c.rong_0 === 'string', j(c.rong_0));
kiem('thiếu số cho khúc: báo lỗi', typeof c.rong_thieu_khuc === 'string', j(c.rong_thieu_khuc));
kiem('chữ U 54 + 81: 300 | 54 | 500 | 81 | 200 → tổng 1135', gan(c.u_54_81.dai, 1135) && gan(c.u_54_81.vung[0][0], 300) && gan(c.u_54_81.vung[0][1], 354) && gan(c.u_54_81.vung[1][0], 854) && gan(c.u_54_81.vung[1][1], 935), j(c.u_54_81));

console.log('\nKIỂU RÃNH LIỀN — 3 tấm NTT đo 08/10 (dao 6, thịt 5, biên 3)');
const NTT = { ranh_ntt1: [581.52, 8, 450.76, 527.76, 441.00, 537.52], ranh_ntt2: [852.07, 15, 524.53, 678.53, 514.00, 689.07], ranh_ntt3: [774.52, 8, 513.76, 590.76, 504.00, 600.52] };
for (const [k, [dai, n, r0, r1, b0, b1]] of Object.entries(NTT)) {
  const r = c[k], h = r.khuc && r.khuc[0];
  kiem(`${k}: tấm ${dai}, ${n} rãnh ${r0}→${r1}, bảo vệ ${b0}→${b1} (khớp NTT tới 0,01)`, h && gan(r.dai, dai, 0.01) && h.n === n && gan(h.r0, r0, 0.01) && gan(h.r1, r1, 0.01) && gan(h.b0, b0, 0.01) && gan(h.b1, b1, 0.01) && r.buoc === 11 && h.loi === true, j(r));
}
kiem('R34 (chưa có mẫu NTT): 5 rãnh, miệng còn hở ≈ 1,3 mm', c.ranh_r34.khuc && c.ranh_r34.khuc[0].n === 5 && gan(c.ranh_r34.khuc[0].ho, 6 - 15 * Math.PI / 2 / 5, 0.01), j(c.ranh_r34));
kiem('bù −4 (theo lý thuyết cách A): tấm 577,52, khúc 74,52 → 7 rãnh', c.ranh_bu_tru4.khuc && gan(c.ranh_bu_tru4.dai, 577.52, 0.01) && c.ranh_bu_tru4.khuc[0].n === 7, j(c.ranh_bu_tru4));
kiem('chữ U: 2 khúc, khúc 2 uốn ngược vẫn ra rãnh', c.ranh_chu_u.khuc && c.ranh_chu_u.khuc.length === 2 && c.ranh_chu_u.khuc.every(x => x.n >= 2), j(c.ranh_chu_u));
for (const k of ['ranh_dao0', 'ranh_thit_qua_day', 'ranh_ket', 'ranh_lo_dau_tam'])
  kiem(`${k}: báo lỗi — ${c[k]}`, typeof c[k] === 'string', j(c[k]));
const rn = c.ranh_ngau_nhien;
console.log('   ngẫu nhiên', j(rn.dem));
kiem('2000 cục rãnh liền ngẫu nhiên: 0 sai số / báo lỗi oan', rn.so_sai === 0, j(rn.sai));
kiem('ca ra số ≥ 1500', (rn.dem.ra_so || 0) >= 1500, j(rn.dem));

console.log('\nPHẢI BÁO LỖI, KHÔNG RA SỐ');
for (const k of ['hop_khong_bo', 'hai_chuoi_bo', 'khep_tron', 'khong_dun_thang', 'mat_bi_chia'])
  kiem(`${k}: ${c[k].loi || ''}`, c[k].ok === false, j(c[k]));

console.log('\nNGẪU NHIÊN 3000 cục (1–3 khúc 20–160°, R 5–300, 2–48 đốt, xoay, đảo chiều, 30% Explode hết, ~10% một phần)');
const n = c.ngau_nhien;
console.log('  ', j(n.dem));
kiem('0 ca sai số / báo lỗi oan', n.so_sai === 0, j(n.sai));
kiem('ca ra số ≥ 2000 (phần còn lại là ca PHẢI báo lỗi)', (n.dem.ra_so || 0) >= 2000, j(n.dem));

console.log(hong ? `\n${hong} HỎNG` : '\nTẤT CẢ ĐẠT');
process.exit(hong ? 1 : 0);
