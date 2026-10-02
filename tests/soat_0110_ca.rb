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

# ── Lượt 2 (soát kỹ tối 01/10) ───────────────────────────────
# Sai số máy khi tấm xoay: hệ số scale 0.9999999999999999 phải ép về đúng 1 → số y hệt tấm không xoay.
GAN1 = Geom::Transformation.new([[0.9999999999999999, 0, 0], [0, 1.0000000000000002, 0], [0, 0, 0.9999999999999999]])
ca(out, 'Sai số máy: hệ số 0.9999999999999999 ép về 1 — Độ Dày ra ĐÚNG số của tấm không xoay') do
  a = TD.send(:own_thickness_mm, Sketchup.hop([0, 0, 0], [600, 300, 17.5]))
  b = TD.send(:own_thickness_mm, Sketchup.hop([0, 0, 0], [600, 300, 17.5]), GAN1)
  [a == b, "#{a.inspect} vs #{b.inspect}"]
end
ca(out, 'Sai số máy: Điền Tên 2 tấm giống hệt (1 tấm lệch sai số) → MỘT dòng, không tách') do
  g1 = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [600, 300, 17.5]))
  g2 = Sketchup::Group.new(Sketchup.hop([0, 0, 0], [600, 300, 17.5]), GAN1)
  gr = NM.build_groups([g1, g2])
  [gr.size == 1, gr.map { |x| x[:defId] }.inspect]
end

# Trùng Tấm: 2 tấm 17,5 trùng khít, một tấm lệch sai số máy (17.499999999999996) → vẫn phải bắt
def tam_tt(ten, day, x0 = 0.0)
  { name: ten, wc: Geom::Point3d.new(x0 + 300 / 25.4, 150 / 25.4, day / 2 / 25.4), size: [day, 300.0, 600.0],
    key: [day, 300.0, 600.0].map(&:round), segs: [],
    edges: [Geom::Vector3d.new(600 / 25.4, 0, 0), Geom::Vector3d.new(0, 300 / 25.4, 0), Geom::Vector3d.new(0, 0, day / 25.4)] }
end
ca(out, 'Trùng Tấm: 17,5 vs 17,499999999999996 (sai số máy) → VẪN bắt trùng (trước đây khác ngăn 18 / 17 → sót)') do
  v = TT.find_dups([tam_tt('a', 17.5), tam_tt('b', 17.499999999999996)])
  [v.size == 1, "#{v.size} cặp · khoá cũ #{tam_tt('a', 17.5)[:key]} vs #{tam_tt('b', 17.499999999999996)[:key]}"]
end
ca(out, 'Trùng Tấm: hai tấm cách nhau 5mm → KHÔNG báo trùng') do
  v = TT.find_dups([tam_tt('a', 17.5), tam_tt('b', 17.5, 5 / 25.4)])
  [v.empty?, "#{v.size} cặp"]
end
ca(out, 'Trùng Tấm: ba tấm chồng khít → 3 cặp (như cũ: mỗi cặp một dòng)') do
  v = TT.find_dups([tam_tt('a', 18.0), tam_tt('b', 18.0), tam_tt('c', 18.0)])
  [v.size == 3, "#{v.size} cặp"]
end

# Khoảng Cách: cặp có chi tiết chống bay hở 10mm (7–12) → phải NHẮC; cặp thường 10mm → không; 5mm → lỗi
KC = TK::SpacingCheck
def chu_nhat(x0, x1, y0, y1)
  p = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |x, y| [x / 25.4, y / 25.4, 0.0] }
  (0..3).map { |i| [p[i], p[(i + 1) % 4]] }
end
def tam_kc(ten, segs, cb)
  { name: ten, segs: segs, bbox: KC.bbox_of(segs), cb: cb }
end
ca(out, 'Khoảng Cách: chi tiết chống bay hở 10mm → NHẮC (trước đây lọt vì lọc nhanh cứng 7mm)') do
  v = []; KC.check_pairs('sheet-1', [tam_kc('lớn', chu_nhat(0, 500, 0, 300), false), tam_kc('nhỏ', chu_nhat(510, 560, 0, 40), true)], v)
  [v.size == 1 && v[0].kind == :pair_cb && (v[0].gap_mm - 10.0).abs < 0.05, v.map { |x| [x.kind, x.gap_mm] }.inspect]
end
ca(out, 'Khoảng Cách: cặp thường hở 10mm → không báo gì (y hệt cũ)') do
  v = []; KC.check_pairs('sheet-1', [tam_kc('a', chu_nhat(0, 500, 0, 300), false), tam_kc('b', chu_nhat(510, 900, 0, 300), false)], v)
  [v.empty?, v.map { |x| [x.kind, x.gap_mm] }.inspect]
end
ca(out, 'Khoảng Cách: cặp hở 5mm → LỖI 5mm (y hệt cũ, kể cả khi có chống bay)') do
  v = []; KC.check_pairs('sheet-1', [tam_kc('a', chu_nhat(0, 500, 0, 300), false), tam_kc('b', chu_nhat(505, 560, 0, 40), true)], v)
  [v.size == 1 && v[0].kind == :pair && (v[0].gap_mm - 5.0).abs < 0.05, v.map { |x| [x.kind, x.gap_mm] }.inspect]
end

# Liên Kết: 2 tủ giống nhau, cùng cặp tên "hông ↔ hậu" — tủ 1 đã khoét, tủ 2 CHƯA → mối thiếu phải hiện
JC = TK::JointCheck
def ca_lien_ket(jc, ket)   # ket = [[tên a, tên b, đã làm?]...] theo thứ tự quét
  planks = ket.each_with_index.flat_map { |(na, nb, _m), i| [{ name: na, aabb: [i * 10.0, 0, 0, i * 10.0 + 5, 1, 1], k: i }, { name: nb, aabb: [i * 10.0 + 1, 0, 0, i * 10.0 + 4, 1, 1], k: i }] }
  jc.define_singleton_method(:pair_joint) do |a, b, _rh, _ng|
    next nil unless a[:k] == b[:k]
    na, nb, m = ket[a[:k]]
    TK::JointCheck::Vio.new(:ranhhau, na, nb, 9.0, [], [], [], m)
  end
  jc.find_joints(planks, [])
end
ca(out, 'Liên Kết: tủ 1 đã khoét, tủ 2 CHƯA (cùng tên hông ↔ hậu) → mối thiếu VẪN hiện (trước đây bị gộp mất)') do
  j = ca_lien_ket(JC, [['hông', 'hậu', true], ['hông', 'hậu', false]])
  [j.count { |v| !v.made } == 1, j.map { |v| [v.name_a, v.name_b, v.made] }.inspect]
end
ca(out, 'Liên Kết: 3 tủ đều thiếu cùng cặp tên → 3 mối thiếu, không gộp') do
  j = ca_lien_ket(JC, [['hông', 'hậu', false], ['hông', 'hậu', false], ['hông', 'hậu', false]])
  [j.count { |v| !v.made } == 3, j.size]
end
ca(out, 'Liên Kết: 3 tủ đều ĐÃ khoét → vẫn gộp 1 dòng "đã làm" như cũ') do
  j = ca_lien_ket(JC, [['hông', 'hậu', true], ['hông', 'hậu', true], ['hông', 'hậu', true]])
  [j.size == 1 && j[0].made, j.size]
end

JSON.generate(out)
