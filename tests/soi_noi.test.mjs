// Thử SOI NỔI (shared/soi_noi.rb) trên 10 tool kiểm/tìm tấm — NGOÀI SketchUp (Ruby 3.3 wasm):
//   node projects/lehai-tools/tests/soi_noi.test.mjs [thư mục ruby.wasm]
// Mỗi tool: dựng lỗi giả → activate (tự phóng camera) → draw. Đạt khi: không lỗi Ruby, lớp mờ là
// lời vẽ 2D ĐẦU TIÊN, có khối đặc (tool có hộp tấm) hoặc có nét (tool không phải hộp), camera đã đặt.
// SketchUp giả KHÔNG chứng minh API thật — phải bấm Xem trong SketchUp (checklist cho Khoa).
import fs from 'node:fs'; import path from 'node:path'; import { createRequire } from 'node:module';
import { WASI } from 'node:wasi';
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const LAB = path.resolve(here, '../../..');
const LT = path.join(here, '../LeHai_Tools');
const wasmDir = path.resolve(process.argv[2] || path.join(LAB, 'scratch/khao-sat-hien-truong/rubywasm'));
const { RubyVM } = createRequire(path.join(wasmDir, 'package.json'))('@ruby/wasm-wasi');
const wasm = await WebAssembly.compile(fs.readFileSync(path.join(wasmDir, 'node_modules/@ruby/3.3-wasm-wasi/dist/ruby+stdlib.wasm')));
const nap = (ten, s) => `eval('${Buffer.from(s, 'utf8').toString('base64')}'.unpack1('m0').force_encoding('UTF-8'), binding, '${ten}')`;
const doc = f => fs.readFileSync(f, 'utf8');
const bo = s => s.replace(/^[ \t]*require .*$/gm, '# (bỏ) $&');
const TOOL = ['tim_tam_loi', 'trung_tam', 'kiem_tra_ban_le', 'kiem_tra_dan_canh', 'kiem_tra_r100', 'kiem_tra_khoang_cach',
              'kiem_tra_lien_ket', 'kiem_tra_ten', 'kiem_tra_ban_le_chan', 'kiem_tra_led'];
const tep = [
  ['sketchup_gia_tia.rb', doc(path.join(LAB, 'projects/tao-modul-nhanh/thu_truc/sketchup_gia_tia.rb'))],
  ['soi_noi_gia.rb', doc(path.join(here, 'soi_noi_gia.rb'))],
  ['huong_tu.rb', doc(path.join(LT, 'shared/huong_tu.rb'))],
  ['soi_noi.rb', doc(path.join(LT, 'shared/soi_noi.rb'))],
  ...TOOL.map(t => [t + '/main.rb', doc(path.join(LT, t, 'main.rb'))]),
  ['soi_noi_ca.rb', doc(path.join(here, 'soi_noi_ca.rb'))]];
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const kq = JSON.parse(vm.eval(`require 'json'\n` + tep.map(([t, s]) => nap(t, bo(s))).join('\n')).toString());

let hong = 0;
for (const x of kq) {
  let dat, chi;
  if (x.loi) { dat = false; chi = x.loi; }
  else if ('rieng' in x) { dat = x.rieng; chi = x.kq; }
  else {
    const khong_hop = /Khoảng Cách/.test(x.ten);          // chi tiết nesting là nét phẳng, không phải hộp
    dat = x.mo === 1 && x.mo_truoc && (khong_hop ? x.net > 0 : x.khoi >= 6) && x.net > 0 && x.cam > 0;
    chi = `mờ ${x.mo} (đầu tiên: ${x.mo_truoc}) · mặt khối ${x.khoi} · nét ${x.net} · đặt camera ${x.cam}`;
  }
  if (!dat) hong++;
  console.log(`  ${dat ? 'ĐẠT ' : 'HỎNG'} ${x.ten}  [${chi}]`);
}
console.log(`\nKHÔNG ĐẠT: ${hong}`);
process.exit(hong ? 1 : 0);
