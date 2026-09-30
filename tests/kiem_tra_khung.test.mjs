// Thử Soát Khung Tổng Thể NGOÀI SketchUp (máy không có Ruby → chạy Ruby 3.3 bản wasm):
//   node projects/lehai-tools/tests/kiem_tra_khung.test.mjs [thư mục ruby.wasm]
// Phần 1: LÕI (phan_tich.rb) — tủ sạch + từng lỗi cài sẵn (kiem_tra_khung_loi.rb).
// Phần 2: LỚP SketchUp (main.rb) trên SketchUp GIẢ (kiem_tra_khung_sketchup.rb) — gom tấm, quy về
//   hệ khung, tủ quay 4 hướng. SketchUp giả KHÔNG chứng minh API thật; phải chạy trong SketchUp.
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module';
import { WASI } from 'node:wasi';
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const LAB = path.resolve(here, '../../..');
const wasmDir = path.resolve(process.argv[2] || path.join(LAB, 'scratch/khao-sat-hien-truong/rubywasm'));
const { RubyVM } = createRequire(path.join(wasmDir, 'package.json'))('@ruby/wasm-wasi');
const wasm = await WebAssembly.compile(fs.readFileSync(path.join(wasmDir, 'node_modules/@ruby/3.3-wasm-wasi/dist/ruby+stdlib.wasm')));
const KT = path.join(here, '../LeHai_Tools/kiem_tra_khung');
const nap = (ten, s) => `eval('${Buffer.from(s, 'utf8').toString('base64')}'.unpack1('m0').force_encoding('UTF-8'), binding, '${ten}')`;
const doc = f => fs.readFileSync(f, 'utf8');
async function chay(...files) {
  const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
  const ma = files.map(([ten, s]) => nap(ten, s.replace(/^[ \t]*require .*$/gm, '# (bỏ) $&'))).join('\n');
  return JSON.parse(vm.eval(`require 'json'\n${ma}`).toString());
}

let hong = 0;
const kiem = (ten, dung, chi) => { if (!dung) hong++; console.log(`  ${dung ? 'ĐẠT ' : 'HỎNG'} ${ten}${dung ? '' : '  → ' + chi}`); };
const co = (arr, x) => arr.includes(x);
const dem = (arr, x) => arr.filter(y => y === x).length;

// ── Phần 1: lõi ──
console.log('LÕI (phan_tich.rb)');
const c = await chay(['phan_tich.rb', doc(path.join(KT, 'phan_tich.rb'))],
                     ['kiem_tra_khung_loi.rb', doc(path.join(here, 'kiem_tra_khung_loi.rb'))]);
const j = x => JSON.stringify(x);
kiem('tủ sạch: 0 đỏ', c.sach.do.length === 0, j(c.sach));
kiem('tủ sạch: vàng chỉ có khe cánh 3 mm', j(c.sach.vang) === j(['nhom:khe:3']), j(c.sach.vang));
kiem('nóc cao 0,5: gióng mặt trên khung chỉ ra NÓC + hở với vách', co(c.noc_cao_0_5.do, 'giong') && co(c.noc_cao_0_5.do, 'ho') && j(c.noc_cao_0_5.giong.map(g => g[0])) === '[[4]]', j(c.noc_cao_0_5));
kiem('đợt hụt 0,5 hai đầu: tấm bay + 2 khe hở đỏ (mép trước chạm lưng cánh vẫn là bay)',co(c.dot_bay.do, 'bay') && dem(c.dot_bay.do, 'ho') === 2, j(c.dot_bay));
kiem('hông phải lùi 1: chồng lẹm + gióng mặt phải khung chỉ ra hông phải', co(c.hong_phai_lui_1.do, 'lem') && c.hong_phai_lui_1.giong.some(g => j(g[0]) === '[2]'), j(c.hong_phai_lui_1));
kiem('khung cao 1701: hụt khung mặt trên', j(c.khung_cao_hon.do) === j(['hut']) && c.khung_cao_hon.tieu_de[0].includes('trên'), j(c.khung_cao_hon));
kiem('đợt xéo 0,5°: đỏ xéo, không kêu tấm bay', co(c.dot_xeo.do, 'xeo') && !co(c.dot_xeo.do, 'bay'), j(c.dot_xeo));
kiem('đợt xiên 30°: vàng, không đỏ', c.dot_xien_30.do.length === 0 && co(c.dot_xien_30.vang, 'nhom:xien:'), j(c.dot_xien_30));
kiem('vách méo 0,3: đỏ méo', j(c.vach_meo.do) === j(['meo']), j(c.vach_meo));
kiem('đợt ngàm 9 mm vào hông: vàng ăn 9, không đỏ', c.dot_ngam_9.do.length === 0 && co(c.dot_ngam_9.vang, 'nhom:an:9'), j(c.dot_ngam_9));
kiem('nóc lệch mép trước 0,5: đúng MỘT dòng, chỉ ra nóc "mép trước thụt vào 0.5 so với Hông…"', j(c.noc_lech_mep.do) === '["giong"]' && j(c.noc_lech_mep.giong[0][0]) === '[4]' && c.noc_lech_mep.giong[0][1].includes('Nóc: mép trước thụt vào 0.5 mm so với Hông'), j(c.noc_lech_mep));
kiem('vách thụt 2 (số đông 18): một dòng chỉ vách "mép trước thụt vào 2"', j(c.vach_thut_2.do) === '["giong"]' && j(c.vach_thut_2.giong[0][0]) === '[5]' && c.vach_thut_2.giong[0][1].includes('Vách: mép trước thụt vào 2 mm so với'), j(c.vach_thut_2));
kiem('cánh chừa khe 2 mm trên/dưới so với khung: không đỏ, vàng "cánh/hộc lệch mép"', c.canh_ho_2.do.length === 0 && co(c.canh_ho_2.vang, 'nhom:giong_cua:'), j(c.canh_ho_2));
kiem('hộc trên ray hở 12,5 với hông: không báo đỏ', c.hoc_tren_ray.do.length === 0, j(c.hoc_tren_ray));
kiem('hộc lơ lửng giữa khoang: đỏ "không bám thân tủ"', dem(c.hoc_lo_lung.do, 'cum') === 1 && c.hoc_lo_lung.tieu_de.some(t => t.includes('không bám')), j(c.hoc_lo_lung));
kiem('tấm chỉ chạm theo góc: vàng chạm đường (+ lồi khung)', co(c.cham_duong.vang, 'nhom:canh:') && co(c.cham_duong.do, 'loi'), j(c.cham_duong));
kiem('2 tấm dính nhau nhưng rời tủ: tủ đứt 1 cụm', dem(c.cum_roi.do, 'cum') === 1 && !co(c.cum_roi.do, 'bay'), j(c.cum_roi));
kiem('bỏ qua dòng gióng: hết đỏ, đếm 1', c.bo_qua.do.length === 0 && c.bo_qua.so_bo_qua === 1, j(c.bo_qua));
kiem('bỏ qua nhóm khe cánh: hết vàng, đếm 1', c.bo_qua_nhom.vang.length === 0 && c.bo_qua_nhom.so_bo_qua === 1, j(c.bo_qua_nhom));
kiem(`400 tấm: ${c.toc_do_400_ms} ms (wasm) < 3000`, c.toc_do_400_ms < 3000, c.toc_do_400_ms);

// ── Phần 2: lớp SketchUp trên SketchUp giả ──
const suFile = path.join(here, 'kiem_tra_khung_sketchup.rb');
if (fs.existsSync(suFile)) {
  console.log('\nLỚP SKETCHUP (main.rb trên SketchUp giả)');
  // Nền SketchUp giả dùng chung với bộ thử luật trục (chỉ đọc, không sửa)
  const gia = path.join(LAB, 'projects/tao-modul-nhanh/thu_truc/sketchup_gia_tia.rb');
  const s = await chay(['phan_tich.rb', doc(path.join(KT, 'phan_tich.rb'))],
                       ['sketchup_gia_tia.rb', doc(gia)],
                       ['kiem_tra_khung_sketchup.rb', doc(suFile).split('# ── CA THỬ ──')[0]],
                       ['soi_noi.rb', doc(path.join(here, '../LeHai_Tools/shared/soi_noi.rb'))],
                       ['main.rb', doc(path.join(KT, 'main.rb'))],
                       ['ca', doc(suFile).split('# ── CA THỬ ──')[1]]);
  for (const x of s) kiem(x.ten + (x.dat ? "  [" + x.kq + "]" : ""), x.dat, x.kq);
}

console.log(`\nKHÔNG ĐẠT: ${hong}`);
process.exit(hong ? 1 : 0);
