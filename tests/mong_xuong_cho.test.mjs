// Thử dán lại mặt + lỗ xuyên khi Mộng Xương Chó DỰNG LẠI thân tấm — NGOÀI SketchUp (Ruby 3.3 wasm), chạy ĐÚNG
// code thật mong_xuong_cho/main.rb:  node projects/lehai-tools/tests/mong_xuong_cho.test.mjs [thư mục ruby.wasm]
// Ca thử: tests/mong_xuong_cho_ca.rb · SketchUp giả: tests/mong_xuong_cho_gia.rb. Thêm 04/10 sau SOÁT Codex.
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
  ['mong_xuong_cho_gia.rb', doc(path.join(here, 'mong_xuong_cho_gia.rb'))],
  ['mong_xuong_cho/main.rb', doc(process.env.MXC_MAIN || path.join(LT, 'mong_xuong_cho/main.rb'))],
  ['mong_xuong_cho_ca.rb', doc(path.join(here, 'mong_xuong_cho_ca.rb'))]];
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const kq = JSON.parse(vm.eval(`require 'json'\n` + tep.map(([t, s]) => nap(t, bo(s))).join('\n')).toString());
let hong = 0;
for (const x of kq) {
  if (!x.dat) hong++;
  console.log(`  ${x.dat ? 'ĐẠT ' : 'HỎNG'} ${x.ten}  [${x.kq}]`);
}
console.log(`\nmong_xuong_cho: ${kq.length - hong}/${kq.length} đạt`);
process.exit(hong ? 1 : 0);
