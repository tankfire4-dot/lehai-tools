// Thử các bản sửa đợt SOÁT 01/10/2026 — NGOÀI SketchUp (Ruby 3.3 wasm), chạy ĐÚNG code thật của tool:
//   node projects/lehai-tools/tests/soat_0110.test.mjs [thư mục ruby.wasm]
// Ca thử: tests/soat_0110_ca.rb · SketchUp giả: tests/soat_0110_gia.rb (chỉ phần thuần tính, không vẽ).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { WASI } from 'node:wasi';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const LT = path.join(here, '..', 'LeHai_Tools');
const LAB = path.join(here, '..', '..', '..');
const wasmDir = path.resolve(process.argv[2] || path.join(LAB, 'scratch/khao-sat-hien-truong/rubywasm'));
const { RubyVM } = createRequire(path.join(wasmDir, 'package.json'))('@ruby/wasm-wasi');
const wasm = await WebAssembly.compile(fs.readFileSync(path.join(wasmDir, 'node_modules/@ruby/3.3-wasm-wasi/dist/ruby+stdlib.wasm')));
const nap = (ten, s) => `eval('${Buffer.from(s, 'utf8').toString('base64')}'.unpack1('m0').force_encoding('UTF-8'), binding, '${ten}')`;
const doc = f => fs.readFileSync(f, 'utf8');
const bo = s => s.replace(/^[ \t]*require .*$/gm, '# (bỏ) $&');
const tep = [
  ['soat_0110_gia.rb', doc(path.join(here, 'soat_0110_gia.rb'))],
  ['dien_ten/core/namer.rb', doc(path.join(LT, 'dien_ten/core/namer.rb'))],
  ['kiem_tra_do_day/main.rb', doc(path.join(LT, 'kiem_tra_do_day/main.rb'))],
  ['trung_tam/main.rb', doc(path.join(LT, 'trung_tam/main.rb'))],
  ['auto_dan_canh/main.rb', doc(path.join(LT, 'auto_dan_canh/main.rb'))],
  ['kiem_tra_khoang_cach/main.rb', doc(path.join(LT, 'kiem_tra_khoang_cach/main.rb'))],
  ['kiem_tra_lien_ket/main.rb', doc(path.join(LT, 'kiem_tra_lien_ket/main.rb'))],
  ['soat_0110_ca.rb', doc(path.join(here, 'soat_0110_ca.rb'))]];
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const kq = JSON.parse(vm.eval(`require 'json'\n` + tep.map(([t, s]) => nap(t, bo(s))).join('\n')).toString());
let hong = 0;
for (const x of kq) {
  if (!x.dat) hong++;
  console.log(`  ${x.dat ? 'ĐẠT ' : 'HỎNG'} ${x.ten}  [${x.kq}]`);
}
console.log(`\nsoat_0110: ${kq.length - hong}/${kq.length} đạt`);
process.exit(hong ? 1 : 0);
