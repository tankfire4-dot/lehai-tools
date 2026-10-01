# encoding: UTF-8
# Ca thử Soi Nổi: mỗi tool dựng 1 lỗi giả trên tủ 600×600×300 (ván 18), activate + draw.
A = hop_segs([0, 0, 0], [18, 600, 300])        # hông trái
B = hop_segs([18, 0, 282], [582, 590, 300])    # nóc
P = ->(s) { s.map { |a, b| [a, b] } }
out = []

out << chay_tool('Tìm Tấm Lỗi (tấm tủ xanh + tấm nesting đỏ)') do
  m1 = TK::ABFFinder::Match.new(nil, [0, 1, 3, 2, 4, 5, 7, 6].map { |i| hop_goc([0, 0, 0], [18, 600, 300])[i] }, false, 'hông trái', 7)
  m2 = TK::ABFFinder::Match.new(nil, [0, 1, 3, 2, 4, 5, 7, 6].map { |i| hop_goc([3000, 0, 0], [3600, 300, 0])[i] }, true, 'hông trái', 7)
  TK::ABFFinder::HighlightTool.new([m1, m2], [7], [])
end

out << chay_tool('Trùng Tấm') do
  TK::DuplicateCheck::ReviewTool.new([TK::DuplicateCheck::Dup.new('hông trái', 'hông trái#2', A, A)])
end

out << chay_tool('Bản Lề Cánh') do
  TK::HingeCheck::ReviewTool.new([TK::HingeCheck::Violation.new('cánh trái', 1, 2, A, 'thiếu', 600)])
end

out << chay_tool('Dán Cạnh (3D: có hộp tấm)') do
  mat = [[[18 / 25.4, 0, 0], [18 / 25.4, 0, 300 / 25.4]], [[18 / 25.4, 0, 300 / 25.4], [0, 0, 300 / 25.4]]]
  TK::EdgeBandCheck::ReviewTool.new([TK::EdgeBandCheck::Mark.new('hông trái', false, mat, Geom::Point3d.new(9 / 25.4, 0, 150 / 25.4), 'chỉ đơn', 1, hop_goc([0, 0, 0], [18, 600, 300]))])
end

out << chay_tool('Dán Cạnh (dấu 2D nesting: hộp phẳng)') do
  TK::EdgeBandCheck::ReviewTool.new([TK::EdgeBandCheck::Mark.new('hông trái', true, hop_segs([3000, 0, 0], [3079, 39, 0]), Geom::Point3d.new(3040 / 25.4, 20 / 25.4, 0), nil, 1)])
end

out << chay_tool('Cung R100') do
  cung = (0..8).map { |i| g = i * Math::PI / 16; Geom::Point3d.new((100 - 100 * Math.cos(g)) / 25.4, 0, (100 * Math.sin(g)) / 25.4) }
  TK::RadiusCheck::ReviewTool.new([TK::RadiusCheck::Item.new('đợt', 100.0, cung, hop_goc([0, 0, 0], [400, 18, 300]))])
end

out << chay_tool('Khoảng Cách 7mm (nesting phẳng: chỉ mờ + nét)') do
  a = hop_segs([0, 0, 0], [300, 200, 0])
  b = hop_segs([305, 0, 0], [600, 200, 0])
  TK::SpacingCheck::ReviewTool.new([TK::SpacingCheck::Violation.new(:pair, 'tấm 1', 5.0, a, b, [300 / 25.4, 100 / 25.4, 0], [305 / 25.4, 100 / 25.4, 0], 'A ↔ B')])
end

out << chay_tool('Liên Kết (tấm A đỏ, tấm B xanh)') do
  TK::JointCheck::ReviewTool.new([TK::JointCheck::Vio.new(:ranhhau, 'nóc', 'hông trái', 9.0, B, A, hop_segs([9, 0, 282], [18, 590, 300]), nil)])
end

out << chay_tool('Đặt Tên') do
  TK::NameCheck::ReviewTool.new([TK::NameCheck::Item.new('(tấm không tên)', A)])
end

out << chay_tool('Đợt Chắn Bản Lề (đợt đỏ, cốc xanh)') do
  TK::HingeBlockCheck::ReviewTool.new([TK::HingeBlockCheck::Vio.new('cánh', 'đợt', 3.0, hop_segs([30, 0, 90], [50, 10, 110]), hop_segs([18, 20, 90], [582, 570, 108]), Geom::Point3d.new(40 / 25.4, 5 / 25.4, 100 / 25.4))])
end

out << chay_tool('Rãnh Led') do
  TK::LedCheck::ReviewTool.new([TK::LedCheck::Item.new('thanh led', [0, 0, 0, 1, 1, 1], A, Geom::Point3d.new(9 / 25.4, 300 / 25.4, 150 / 25.4), nil)])
end

# khoi_tu_net: hộp XIÊN (xoay 30° + dời) vẫn dựng lại đúng 8 góc → 6 mặt
xoay = Geom::Transformation.xoay_z(30, 500, 200, 0)
xien = hop_segs([0, 0, 0], [18, 600, 300]).map { |a, b| [xoay * Geom::Point3d.new(*a), xoay * Geom::Point3d.new(*b)] }.flatten
g8 = LeHai::SoiNoi.khoi_tu_net(xien)
canh = g8 && [g8[1] - g8[0], g8[3] - g8[0], g8[4] - g8[0]].map { |v| (v.length * 25.4).round(3) }.sort
out << { ten: 'khoi_tu_net: hộp xiên 30° dựng lại đúng 18 × 300 × 600', rieng: canh == [18.0, 300.0, 600.0], kq: canh.inspect }
out << { ten: 'khoi_tu_net: nét không phải hộp (2 đoạn) → nil', rieng: LeHai::SoiNoi.khoi_tu_net([Geom::Point3d.new(0, 0, 0)] * 4).nil?, kq: '' }

# goc_tam: hộp tấm từ MẶT của group (tấm 18×600×300 xoay 30° + dời) → 8 góc thế giới đúng kích thước
g = Sketchup::Group.new([0, 0, 0], [18 / 25.4, 600 / 25.4, 300 / 25.4], xoay, 'hông')
gt = LeHai::SoiNoi.goc_tam(g.entities, xoay)
kt = gt && [gt[1] - gt[0], gt[3] - gt[0], gt[4] - gt[0]].map { |v| (v.length * 25.4).round(3) }.sort
out << { ten: 'goc_tam: tấm xoay 30° lấy từ mặt → đúng 18 × 300 × 600', rieng: kt == [18.0, 300.0, 600.0], kq: kt.inspect }
out << { ten: 'goc_tam: group không có mặt → nil', rieng: LeHai::SoiNoi.goc_tam([], xoay).nil?, kq: '' }

# THẤY / KHUẤT: nhìn từ phía −đỏ vào mặt x=0 của hông trái. Có vách chắn trước → khuất.
def xem_khuat(co_vach, nua = false, song_song = false)
  tam = Sketchup::Group.new([0, 0, 0], [18 / 25.4, 600 / 25.4, 300 / 25.4], Geom::Transformation.new, 'hông trái')
  ds = [tam]
  ds << Sketchup::Group.new([-200 / 25.4, -1000 / 25.4, -1000 / 25.4], [-180 / 25.4, (nua ? 280 : 1600) / 25.4, 1300 / 25.4], Geom::Transformation.new, 'vách') if co_vach
  m = Sketchup::ModelSoi.new(ds)
  Sketchup.gia_model = m
  v = m.active_view
  v.camera.song_song = song_song
  v.camera.set(Geom::Point3d.new(-2000 / 25.4, 250 / 25.4, 200 / 25.4), Geom::Point3d.new(9 / 25.4, 300 / 25.4, 150 / 25.4), Geom::Vector3d.new(0, 0, 1))
  LeHai::SoiNoi.phu_mo(v)
  LeHai::SoiNoi.ve_nets(v, [[TK::DuplicateCheck::ReviewTool.allocate.send(:flatten, A), :do]])
  dac = v.ghi.count { |k, gl, n, mau| k == :d2 && gl == GL_POLYGON && n == 4 && mau.rgba.size == 3 }
  trong = v.ghi.count { |k, gl, n, mau| k == :d2 && gl == GL_POLYGON && n == 4 && mau.rgba.size == 4 && mau.rgba[3] == 70 }
  nhan = v.ghi.any? { |k, s| k == :chu && s == 'khuất sau tấm khác' }
  [dac, trong, nhan]
rescue StandardError => e
  "LỖI #{e.class}: #{e.message} #{(e.backtrace || []).first(2).join(' | ')}"
end
a = xem_khuat(false)
b = xem_khuat(true)
out << { ten: 'Không bị che: mặt trước tô ĐẶC, không nhãn "khuất"', rieng: a.is_a?(Array) && a[0] >= 4 && !a[2], kq: a.inspect }
out << { ten: 'Bị vách che: mọi ô mặt trước TRONG SUỐT, 0 ô đặc, có nhãn "khuất sau tấm khác"', rieng: b.is_a?(Array) && b[0].zero? && b[1] >= 4 && b[2], kq: b.inspect }

c = xem_khuat(true, true)
out << { ten: 'Vách che MỘT NỬA: có ô đặc lẫn ô trong suốt, không nhãn "khuất" (tấm còn lộ)', rieng: c.is_a?(Array) && c[0] >= 1 && c[1] >= 1 && !c[2], kq: c.inspect }

d = xem_khuat(true, false, true)
e = xem_khuat(false, false, true)
out << { ten: 'Chiếu SONG SONG: bị vách che → trong suốt + nhãn; không che → đặc', rieng: d.is_a?(Array) && e.is_a?(Array) && d[0].zero? && d[2] && e[0] >= 4 && !e[2], kq: "#{d.inspect} / #{e.inspect}" }

# net2d: nét quá 60 đoạn (tấm cong) → vẽ liền, KHÔNG bắn tia
m = Sketchup::ModelSoi.new([])
Sketchup.gia_model = m
nhieu = (0...200).flat_map { |i| [Geom::Point3d.new(i, 0, 0), Geom::Point3d.new(i + 0.5, 0, 0)] }
LeHai::SoiNoi.net2d(m.active_view, nhieu)
it = (0...10).flat_map { |i| [Geom::Point3d.new(i, 0, 0), Geom::Point3d.new(i + 0.5, 0, 0)] }
LeHai::SoiNoi.net2d(m.active_view, it)
out << { ten: 'net2d: 200 đoạn → 0 tia (vẽ liền); 10 đoạn → có bắn tia', rieng: m.so_tia.between?(1, 20), kq: "#{m.so_tia} tia" }

# 01/10 Khoa: nét KHUẤT nhạt hơn nét THẤY — đục 45% (115/255) + mảnh một nửa; nhịp đứt giữ nguyên.
def canh_xem(nua)
  tam = Sketchup::Group.new([0, 0, 0], [18 / 25.4, 600 / 25.4, 300 / 25.4], Geom::Transformation.new, 'hông trái')
  vach = Sketchup::Group.new([-200 / 25.4, -1000 / 25.4, -1000 / 25.4], [-180 / 25.4, (nua ? 280 : 1600) / 25.4, 1300 / 25.4], Geom::Transformation.new, 'vách')
  m = Sketchup::ModelSoi.new([tam, vach])
  Sketchup.gia_model = m
  v = m.active_view
  v.camera.set(Geom::Point3d.new(-2000 / 25.4, 250 / 25.4, 200 / 25.4), Geom::Point3d.new(9 / 25.4, 300 / 25.4, 150 / 25.4), Geom::Vector3d.new(0, 0, 1))
  v
end
def nhom_net(v)
  l = v.ghi.select { |k, gl| k == :d2 && gl == GL_LINES }
  [l.select { |*_, mau, _w| mau.rgba.size == 3 }, l.select { |*_, mau, _w| mau.rgba.size == 4 && mau.rgba[3] == 115 }]
end
begin
  v = canh_xem(true)
  hop_a = TK::DuplicateCheck::ReviewTool.allocate.send(:flatten, A)
  LeHai::SoiNoi.ve_nets(v, [[hop_a, :do]])
  lien, dut = nhom_net(v)
  out << { ten: 'Nét KHUẤT nhạt + mảnh: đoạn thấy liền 2px màu đặc, đoạn khuất đục 115 dày 1px',
           rieng: !lien.empty? && !dut.empty? && lien.map(&:last).uniq == [2] && dut.map(&:last).uniq == [1],
           kq: "liền #{lien.size} (dày #{lien.map(&:last).uniq}) · khuất #{dut.size} (dày #{dut.map(&:last).uniq})" }
  # Bút chỉ dùng cho MỘT lần net2d: tool đặt màu kiểu cũ rồi gọi net2d → nét khuất cùng màu tool, không mang màu cũ sang
  v.ghi.clear
  v.drawing_color = Sketchup::Color.new(1, 2, 3)
  v.line_width = 3
  LeHai::SoiNoi.net2d(v, hop_a)
  l2 = v.ghi.select { |k, gl| k == :d2 && gl == GL_LINES }
  out << { ten: 'Bút không dính sang lần sau: net2d không qua but → mọi nét đúng màu tool (1,2,3), dày 3',
           rieng: !l2.empty? && l2.all? { |*_, mau, w| mau.rgba == [1, 2, 3] && w == 3 }, kq: l2.map { |*_, mau, w| [mau.rgba, w] }.uniq.inspect }
rescue StandardError => e
  out << { ten: 'Nét KHUẤT nhạt', loi: "#{e.class}: #{e.message} #{(e.backtrace || []).first(2).join(' | ')}" }
end

# Điền Tên (01/10): chọn tấm → SOI NỔI (mờ + khối xanh), KHÔNG còn viền hồng cũ (255,20,200)
begin
  v = canh_xem(false)
  ht = TuDong::DienTen::HiliteTool.new
  ht.set([TK::DuplicateCheck::ReviewTool.allocate.send(:flatten, A)])
  ht.draw(v)
  mo = v.ghi.count { |k, gl, _n, mau| k == :d2 && gl == GL_POLYGON && mau.rgba == [246, 245, 241, 185] }
  khoi = v.ghi.count { |k, gl, n| k == :d2 && gl == GL_POLYGON && n == 4 }
  hong = v.ghi.any? { |*_, mau, _w| mau.respond_to?(:rgba) && mau.rgba[0, 3] == [255, 20, 200] }
  xanh = v.ghi.any? { |k, gl, _n, mau| k == :d2 && gl == GL_LINES && mau.rgba[0, 3] == [30, 110, 230] }
  out << { ten: 'Điền Tên: chọn tấm → mờ 1 lớp + khối + viền xanh, không còn hồng', rieng: mo == 1 && khoi >= 6 && xanh && !hong,
           kq: "mờ #{mo} · mặt khối #{khoi} · viền xanh #{xanh} · hồng #{hong}" }
  v.ghi.clear
  ht.set([TK::DuplicateCheck::ReviewTool.allocate.send(:flatten, hop_segs([0, 0, 0], [100, 0, 0]))])   # hộp bẹp thành 1 đoạn: không dựng được khối → chỉ vẽ nét, không văng
  ht.draw(v)
  out << { ten: 'Điền Tên: tấm không dựng được hộp → vẫn vẽ nét, không văng', rieng: LeHai::SoiNoi.khoi_tu_net(TK::DuplicateCheck::ReviewTool.allocate.send(:flatten, hop_segs([0, 0, 0], [100, 0, 0]))).nil? && v.ghi.any? { |k, gl| k == :d2 && gl == GL_LINES }, kq: v.ghi.map { |k, gl| [k, gl] }.inspect }
rescue StandardError => e
  out << { ten: 'Điền Tên soi nổi', loi: "#{e.class}: #{e.message} #{(e.backtrace || []).first(2).join(' | ')}" }
end

JSON.generate(out)
