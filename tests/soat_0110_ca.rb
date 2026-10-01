# encoding: UTF-8
# Ca thử đợt soát 01/10/2026 — chạy bằng tests/soat_0110.test.mjs. Mỗi ca: ĐÚNG khi bản sửa đúng VÀ ca cũ
# đang đúng (không scale / tấm chưa có loại chỉ) ra y hệt công thức cũ.
out = []
def ca(out, ten)
  r = yield
  out << { ten: ten, dat: r[0] ? true : false, kq: r[1].to_s }
rescue StandardError => e
  out << { ten: ten, dat: false, kq: "LỖI #{e.class}: #{e.message} #{(e.backtrace || []).first(2).join(' | ')}" }
end
I = Geom::Transformation.new
NM = TuDong::DienTen::Namer

# ── Điền Tên (A1): tên + khoá nhóm theo kích thước THẬT ──────────
g400   = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [400, 400, 18]))                       # không scale
g800   = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [400, 400, 18]), Geom::Transformation.scaling(2, 1, 1))  # kéo Scale ×2
g800x  = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [400, 400, 18]), Geom::Transformation.xoay_z_scale(90, 2))  # xoay 90° + giãn
cu_key = lambda do |e|   # công thức CŨ (bản gốc, không scale)
  b = e.definition.bounds
  "group_#{[b.width, b.height, b.depth].map { |d| (d * NM::DIM_PRECISION).round }.sort.join('_')}"
end
ca(out, 'Điền Tên: tấm KHÔNG scale → khoá y hệt công thức cũ') do
  ks = NM.build_groups([g400]).map { |x| x[:defId] }
  [ks == [cu_key.call(g400)], ks.inspect]
end
ca(out, 'Điền Tên: tấm kéo Scale ×2 → tên 800 × 400 × 18 (không còn 400 × 400)') do
  gr = NM.build_groups([g800])
  dims = gr[0][:defName].split(' x ').map { |s| (s.to_f * 25.4).round(3) }
  [dims == [800.0, 400.0, 18.0], gr[0][:defName] + ' → ' + dims.inspect]
end
ca(out, 'Điền Tên: tấm 400 và tấm Scale thành 800 (cùng bản gốc) → HAI dòng, không gộp chung tên') do
  gr = NM.build_groups([g400, g800])
  [gr.size == 2, gr.map { |x| x[:defId] }.inspect]
end
ca(out, 'Điền Tên: xoay 90° + giãn ×2 theo trục tấm → vẫn 800 (hệ số scale không lẫn với xoay)') do
  gr = NM.build_groups([g800x])
  dims = gr[0][:defName].split(' x ').map { |s| (s.to_f * 25.4).round(3) }
  [dims == [800.0, 400.0, 18.0], dims.inspect]
end
ca(out, 'Điền Tên: dùng transform WORLD do bảng đưa vào (tủ cha bị scale) → cỡ thật') do
  gr = NM.build_groups([g400], ->(_e) { Geom::Transformation.scaling(1, 1.5, 1) })
  dims = gr[0][:defName].split(' x ').map { |s| (s.to_f * 25.4).round(3) }
  [dims == [600.0, 400.0, 18.0], dims.inspect]
end
c1 = Sketchup::ComponentInstance.new(Sketchup.hop([0, 0, 0], [500, 300, 18]))
c1.definition.name = 'Hông'
c2 = Sketchup::ComponentInstance.new([]); c2.definition = c1.definition
c3 = Sketchup::ComponentInstance.new([]); c3.definition = c1.definition; c3.transformation = Geom::Transformation.scaling(1, 2, 1)
ca(out, 'Điền Tên: component cùng definition, không scale → MỘT dòng, khoá "comp_<id>" như cũ, tên = tên definition') do
  gr = NM.build_groups([c1, c2])
  [gr.size == 1 && gr[0][:defId] == "comp_#{c1.definition.entityID}" && gr[0][:defName] == 'Hông', gr.map { |x| [x[:defId], x[:defName]] }.inspect]
end
ca(out, 'Điền Tên: component cùng definition nhưng 1 cái bị scale → tách dòng, tên kèm cỡ thật') do
  gr = NM.build_groups([c1, c3])
  [gr.size == 2 && gr[1][:defName].start_with?('Hông ('), gr.map { |x| x[:defName] }.inspect]
end

# ── Kiểm Tra Độ Dày (A2) ─────────────────────────────────────
TD = TK::ThickCheck
ca(out, 'Độ Dày: tấm 18 không scale → 18.0 (y hệt cũ)') do
  v = TD.send(:own_thickness_mm, Sketchup.hop([0, 0, 0], [600, 300, 18]))
  [(v - 18.0).abs < 1e-9, v]
end
ca(out, 'Độ Dày: tấm 18 bị kéo Scale ×2 theo bề dày → 36 (trước đây vẫn báo 18)') do
  v = TD.send(:own_thickness_mm, Sketchup.hop([0, 0, 0], [600, 300, 18]), Geom::Transformation.scaling(1, 1, 2))
  [(v - 36.0).abs < 1e-9, v]
end
ca(out, 'Độ Dày: walk mang transform cha xuống tấm con (tủ cha scale bề dày ×0.5 → 9)') do
  tam = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [600, 300, 18]))
  tu  = Sketchup::Group.new([tam], Geom::Transformation.scaling(1, 1, 0.5))
  leaves = []
  TD.send(:walk, [tu], 0, leaves, I)
  [leaves.size == 1 && (leaves[0][1] - 9.0).abs < 1e-9, leaves.map { |_e, t| t }.inspect]
end

# ── Trùng Tấm (A3) ───────────────────────────────────────────
TT = TK::DuplicateCheck
ca(out, 'Trùng Tấm: tấm 600×300×18 không scale → size y hệt cũ') do
  e = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [600, 300, 18]), I, 'a')
  o = []; TT.register_board(e, I, e.entities, o)
  [o.size == 1 && o[0][:size].map { |x| x.round(6) } == [18.0, 300.0, 600.0], o.map { |x| x[:size] }.inspect]
end
ca(out, 'Trùng Tấm: tấm 18 scale bề dày ×3 = 54 → bị LOẠI (dày > 40), không còn lọt vào như tấm 18') do
  e = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [600, 300, 18]), I, 'b')
  o = []; TT.register_board(e, Geom::Transformation.scaling(1, 1, 3), e.entities, o)
  [o.empty?, o.map { |x| x[:size] }.inspect]
end
ca(out, 'Trùng Tấm: tấm 300 scale dài ×2 → size 600 (nhóm đúng với tấm 600 thật)') do
  e = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [600, 300, 18]), I, 'c')
  o = []; TT.register_board(e, Geom::Transformation.scaling(1, 2, 1), e.entities, o)
  [o.size == 1 && o[0][:size].map { |x| x.round(6) } == [18.0, 600.0, 600.0], o.map { |x| x[:size] }.inspect]
end

# ── Auto Dán Cạnh (AD1): GỘP loại chỉ, không ghi đè ─────────────
AE = MyStudio::AutoEdgeBand
A  = [0, 'don 221 T', 1.0, '#e99450', 0]
B  = [0, 'don 205 SH', 1.0, '#c79ef9', 0]
V  = [1, 'Vat45', 1.0, '#e53535', 0]
ca(out, 'Dán Cạnh: tấm CHƯA có loại → ghi 1 bộ, id 0 (y hệt cũ)') do
  t = Sketchup::Group.new([])
  id = AE.ensure_band_type(t, A)
  [id == 0 && t.get_attribute('ABF', 'edge-band-types') == A, [id, t.get_attribute('ABF', 'edge-band-types')].inspect]
end
ca(out, 'Dán Cạnh: tấm đã có CÙNG loại → dùng lại id, mảng không đổi') do
  t = Sketchup::Group.new([]); t.set_attribute('ABF', 'edge-band-types', A.dup)
  id = AE.ensure_band_type(t, A)
  [id == 0 && t.get_attribute('ABF', 'edge-band-types') == A, id]
end
ca(out, 'Dán Cạnh: tấm có [chỉ A + Vát45], dán thêm chỉ A → GIỮ Vát45 (trước đây mất)') do
  t = Sketchup::Group.new([]); t.set_attribute('ABF', 'edge-band-types', A + V)
  id = AE.ensure_band_type(t, A)
  [id == 0 && t.get_attribute('ABF', 'edge-band-types') == A + V, t.get_attribute('ABF', 'edge-band-types').inspect]
end
ca(out, 'Dán Cạnh: tấm đang chỉ A, dán chỉ B → THÊM bộ B id 1, cạnh A cũ vẫn là A (trước đây đổi thành B)') do
  t = Sketchup::Group.new([]); t.set_attribute('ABF', 'edge-band-types', A.dup)
  id = AE.ensure_band_type(t, B)
  [id == 1 && t.get_attribute('ABF', 'edge-band-types') == A + [1, 'don 205 SH', 1.0, '#c79ef9', 0], t.get_attribute('ABF', 'edge-band-types').inspect]
end
ca(out, 'Dán Cạnh: danh sách loại quét ĐỦ cả bộ thứ 2 (Vát45) — trước đây chỉ bộ đầu') do
  t = Sketchup::Group.new([]); t.set_attribute('ABF', 'edge-band-types', A + V)
  seen = {}; AE.scan_for_types([t], seen, 0)
  [seen.keys.sort == ['Vat45', 'don 221 T'], seen.keys.inspect]
end

JSON.generate(out)
