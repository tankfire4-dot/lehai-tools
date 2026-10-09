// Thử Tạo Cánh CNC (canh_cnc/main.rb › door_layout) NGOÀI SketchUp (Ruby 3.3 wasm, SketchUp giả của mong_xuong_cho):
//   node projects/lehai-tools/tests/canh_cnc.test.mjs [thư mục ruby.wasm]
// Chỉ thử công thức chia cánh (dùng chung cho xem trước + dựng). Hướng lòng tủ (shared/huong_tu) và dựng hình
// phải thử trong SketchUp thật.
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module';
import { WASI } from 'node:wasi';
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const LAB = path.resolve(here, '../../..');
const wasmDir = path.resolve(process.argv[2] || path.join(LAB, 'scratch/khao-sat-hien-truong/rubywasm'));
const { RubyVM } = createRequire(path.join(wasmDir, 'package.json'))('@ruby/wasm-wasi');
const wasm = await WebAssembly.compile(fs.readFileSync(path.join(wasmDir, 'node_modules/@ruby/3.3-wasm-wasi/dist/ruby+stdlib.wasm')));
const nap = (ten, s) => `eval('${Buffer.from(s, 'utf8').toString('base64')}'.unpack1('m0').force_encoding('UTF-8'), binding, '${ten}')`;
const doc = f => fs.readFileSync(f, 'utf8');
const bo = s => s.replace(/^[ \t]*require .*$/gm, '# (bỏ) $&');
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const c = JSON.parse(vm.eval(`require 'json'\n` + [
  ['mong_xuong_cho_gia.rb', doc(path.join(here, 'mong_xuong_cho_gia.rb'))],
  ['canh_cnc/main.rb', bo(doc(path.join(here, '../LeHai_Tools/canh_cnc/main.rb')))],
  ['canh_cnc_ca.rb', doc(path.join(here, 'canh_cnc_ca.rb'))]
].map(([t, s]) => nap(t, s)).join('\n')).toString());

let hong = 0;
const j = x => JSON.stringify(x);
const kiem = (ten, dung, chi) => { if (!dung) hong++; console.log(`  ${dung ? 'ĐẠT ' : 'HỎNG'} ${ten}${dung ? '' : '  → ' + chi}`); };
const gan = (a, b) => Math.abs(a - b) < 1e-3;

console.log('TẠO CÁNH CNC — door_layout');
const h = c.hai_canh_dung;
kiem('2 cánh đứng khoang 800×700: mặt trước, mỗi cánh 397 × 700, cánh 1 từ 2, cánh 2 từ 401', h.plane === 'xz' && h.doors.length === 2 && gan(h.doors[0][0], 2) && gan(h.doors[1][0], 401) && gan(h.doors[0][3], 397) && gan(h.doors[1][4], 700), j(h));
const n = c.ba_canh_ngang.doors;
kiem('3 cánh ngang: mỗi cánh 230,667 cao, đáy từ 1, khe 2', n.length === 3 && gan(n[0][4], 230.6667) && gan(n[0][1], 1) && gan(n[1][1], 1 + 230.6667 + 2) && gan(n[0][3], 796), j(n));
kiem('bấm 2 điểm ngược thứ tự: ra y hệt', c.bam_nguoc === true, j(c.bam_nguoc));
kiem('mặt hông (yz): 1 cánh 596 × 720', c.mat_hong.plane === 'yz' && gan(c.mat_hong.doors[0][3], 596) && gan(c.mat_hong.doors[0][4], 720), j(c.mat_hong));
kiem('khoang 5mm: báo quá nhỏ', c.qua_nho === 'too_small', c.qua_nho);
kiem('hở ngang vượt khoang: báo gap_w', c.ho_vuot_ngang === 'gap_w', c.ho_vuot_ngang);
kiem('hở dọc vượt khoang: báo gap_h', c.ho_vuot_doc === 'gap_h', c.ho_vuot_doc);
kiem('2 điểm cùng cao độ (mặt nằm): báo không phải mặt đứng', c.mat_nam === 'plane', c.mat_nam);
const r = c.ngau_nhien;
console.log('   ngẫu nhiên', j(r.dem));
kiem('3000 khoang ngẫu nhiên: 0 sai số / báo lỗi oan', r.so_sai === 0, j(r.sai));
console.log(hong ? `\n${hong} HỎNG` : '\nTẤT CẢ ĐẠT');
process.exit(hong ? 1 : 0);
