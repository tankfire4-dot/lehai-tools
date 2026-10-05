// Thử Tìm Tấm Lỗi → Tab sao các tấm đang sáng ra gốc toạ độ — NGOÀI SketchUp (Ruby 3.3 wasm):
//   node projects/lehai-tools/tests/tim_tam_loi.test.mjs [thư mục ruby.wasm]
// Cảnh giả: tủ xoay 90° (có đợt xiên 30°) + bản nesting phẳng. Đạt khi vị trí/hướng/thuộc tính bản sao
// đúng, một bậc Undo, lỗi thì abort. SketchUp giả KHÔNG chứng minh API thật — Khoa phải chạy SketchUp.
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
const tep = [
  ['sketchup_gia_tia.rb', doc(path.join(LAB, 'projects/tao-modul-nhanh/thu_truc/sketchup_gia_tia.rb'))],
  ['soi_noi_gia.rb', doc(path.join(here, 'soi_noi_gia.rb'))],
  ['tim_tam_loi/main.rb', doc(path.join(LT, 'tim_tam_loi/main.rb'))],
  ['tim_tam_loi_ca.rb', doc(path.join(here, 'tim_tam_loi_ca.rb'))]];
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const kq = JSON.parse(vm.eval(`require 'json'\n` + tep.map(([t, s]) => nap(t, bo(s))).join('\n')).toString());

let hong = 0;
for (const x of kq) {
  const dat = !x.loi && x.rieng;
  if (!dat) hong++;
  console.log(`  ${dat ? 'ĐẠT ' : 'HỎNG'} ${x.ten}  [${x.loi || x.kq}]`);
}
console.log(`\nKHÔNG ĐẠT: ${hong}`);
process.exit(hong ? 1 : 0);
