// Thử Kiểm Mộng Xương Chó NGOÀI SketchUp (máy không có Ruby → Ruby 3.3 bản wasm):
//   node projects/lehai-tools/tests/kiem_tra_mong_xuong_cho.test.mjs [thư mục ruby.wasm]
// Hình thử dựng bằng CODE THẬT của tool Mộng (mong_xuong_cho/main.rb: plan_edge, chen_rang) trên SketchUp giả
// (mong_xuong_cho_gia.rb); lõi kiểm = kiem_tra_mong_xuong_cho/phan_tich.rb. Ca thử: kiem_tra_mong_xuong_cho_ca.rb.
// Lớp gom tấm (main.rb) cũng chạy trên cây group giả — giả KHÔNG chứng minh API thật, phải chạy trong SketchUp.
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
  ['mong_xuong_cho/main.rb', doc(path.join(LT, 'mong_xuong_cho/main.rb'))],
  ['kiem_tra_mong_xuong_cho/phan_tich.rb', doc(process.env.KMXC_LOI || path.join(LT, 'kiem_tra_mong_xuong_cho/phan_tich.rb'))],
  ['kiem_tra_mong_xuong_cho/main.rb', doc(path.join(LT, 'kiem_tra_mong_xuong_cho/main.rb'))],
  ['kiem_tra_mong_xuong_cho_ca.rb', doc(path.join(here, 'kiem_tra_mong_xuong_cho_ca.rb'))]];
const { vm } = await RubyVM.instantiateModule({ module: wasm, wasip1: new WASI({ version: 'preview1', returnOnExit: true }) });
const kq = JSON.parse(vm.eval(`require 'json'\n` + tep.map(([t, s]) => nap(t, bo(s))).join('\n')).toString());
let hong = 0;
for (const x of kq) {
  if (!x.dat) hong++;
  console.log(`  ${x.dat ? 'ĐẠT ' : 'HỎNG'} ${x.ten}  [${x.kq}]`);
}
console.log(`\nkiem_tra_mong_xuong_cho: ${kq.length - hong}/${kq.length} đạt`);
process.exit(hong ? 1 : 0);
