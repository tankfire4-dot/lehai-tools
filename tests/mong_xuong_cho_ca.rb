# encoding: UTF-8
# Ca thử dán lại mặt + lỗ xuyên khi DỰNG LẠI thân tấm (mong_xuong_cho dan_mat / dung_than) — SOÁT Codex 04/10
# (handoff/report-soat-lehai-1992.md). Chạy bằng tests/mong_xuong_cho.test.mjs. Hình giả: mặt chữ nhật.
M = TK::MongXuongCho
out = []
def ca(out, ten)
  r = yield
  out << { ten: ten, dat: r[0] ? true : false, kq: r[1].to_s }
rescue StandardError => e
  out << { ten: ten, dat: false, kq: "LỖI #{e.class}: #{e.message} #{(e.backtrace || []).first(2).join(' | ')}" }
end

Vertex = Struct.new(:position)
Loop = Struct.new(:vertices)
Mat = Struct.new(:name) { def texture; nil; end }
class Luoi # PolygonMesh giả: một tam giác đầu (mặt chữ nhật lồi → tam giác nằm trong mặt)
  def initialize(pts); @pts = pts; end
  def polygons; [[1, 2, 3]]; end
  def point_at(i); @pts[i - 1]; end
end
class TFace < Sketchup::Face
  attr_accessor :normal, :material, :back_material, :layer
  attr_reader :attrs
  # x0..x1 (mm) trên mép y 0..18, mặt phẳng z = 350mm; holes = các vòng lỗ (mảng điểm mm)
  def initialize(x0, x1, code: nil, mat: nil, back: nil, nz: 1, holes: [])
    @normal = Geom::Vector3d.new(0, 0, nz)
    @outer = [[x0, 0, 350], [x1, 0, 350], [x1, 18, 350], [x0, 18, 350]].map { |p| Geom::Point3d.new(p.map(&:mm)) }
    @holes = holes.map { |h| h.map { |p| Geom::Point3d.new(p.map(&:mm)) } }
    @attrs = code.nil? ? {} : { 'ABF' => { 'edge-band-id' => code } }
    @material = mat; @back_material = back; @layer = 'Layer0'
  end
  def vertices; @outer.map { |p| Vertex.new(p) }; end
  def loops; ([@outer] + @holes).map { |l| Loop.new(l.map { |p| Vertex.new(p) }) }; end
  def mesh; Luoi.new(@outer); end
  def attribute_dictionaries
    @attrs.map { |n, d| Struct.new(:name, :data) { def keys; data.keys; end; def [](k); data[k]; end }.new(n, d) }
  end
  def set_attribute(n, k, v); (@attrs[n] ||= {})[k] = v; end
  def id; @attrs.dig('ABF', 'edge-band-id'); end
  def valid?; true; end
  def reverse!; @normal = @normal.reverse; self; end
  def pushpull(_); end
  def erase!; end
end
A = Mat.new('A'); B = Mat.new('B')

ca(out, 'Mặt phẳng chỉ MỘT mặt cũ (mặt lớn, đầu không mộng) → chép id + vật liệu (y hệt cũ)') do
  cu = [TFace.new(0, 600, code: 3, mat: A)]
  moi = [TFace.new(0, 600)]
  bo = M.dan_mat(moi, M.nho_mat(cu, 1))
  [moi[0].id == 3 && moi[0].material.name == 'A' && bo == 0, [moi[0].id, bo].inspect]
end
ca(out, 'Đầu mọc mộng: một mặt cũ bị răng chia 2 mặt mới → bỏ dán cạnh đầu đó, giữ vật liệu (y hệt cũ)') do
  cu = [TFace.new(0, 600, code: 5, mat: A)]
  moi = [TFace.new(0, 200), TFace.new(400, 600)]
  bo = M.dan_mat(moi, M.nho_mat(cu, 1))
  [moi.map(&:id) == [nil, nil] && moi.map { |f| f.material.name } == %w[A A] && bo == 1, { id: moi.map(&:id), bo: bo }.inspect]
end
# GIỚI HẠN ĐÃ BIẾT (Khoa chấp nhận 04/10, bảng có dòng nhắc "dán chỉ SAU mộng"): khe chữ U hai mép đồng phẳng
# mất dán cạnh, mặt cũ lật không nhận lại — KHÔNG test ở đây. Ca dưới là CHỐT CHẶN cho ai sửa phần ghép sau này:
# bản ghép theo miền f607bca từng làm vách lỗ không bị đụng mất chỉ (Codex SOÁT lượt 2).
ca(out, 'Chốt chặn: vách lỗ mang chỉ 9 + sườn mộng mới đồng phẳng NGƯỢC hướng, rời miền → vách GIỮ chỉ 9, sườn không nhận') do
  cu = [TFace.new(0, 100, code: 9, mat: A)]
  moi = [TFace.new(0, 100), TFace.new(300, 340, nz: -1)]
  bo = M.dan_mat(moi, M.nho_mat(cu, 1))
  [moi[0].id == 9 && moi[1].id.nil? && bo == 0, { id: moi.map(&:id), bo: bo }.inspect]
end

# ── dung_than: lỗ xuyên (P2) ─────────────────────────────────────────
class KhoiGia < Array # entities giả: add_face lần `hong` trả nil; mặt đáy/nắp mang `lo_moi` vòng lỗ
  def initialize(mat_cu, hong: nil, lo_moi: 1)
    super([mat_cu]); @hong = hong; @lo = lo_moi; @goi = 0
  end
  def erase_entities(_); clear; end
  def add_face(_)
    @goi += 1
    return nil if @goi == @hong
    if @goi == 1
      h = Array.new(@lo) { [[20, 5, 350], [40, 5, 350], [40, 10, 350]] }
      [TFace.new(0, 100, holes: h), TFace.new(0, 100, holes: h)].each { |f| self << f }
      return first
    end
    TFace.new(20, 40) # mặt lỗ tạm, bên gọi erase!
  end
end
TAM = Struct.new(:entities)
HOP = Geom::BoundingBox.new.add(ORIGIN, Geom::Point3d.new(100.mm, 18.mm, 350.mm))
PROF = { fd1: { frame: Geom::Transformation.new }, thin: 2, thickness: 18.mm,
         inner: [[[20.mm, 5.mm, 0], [40.mm, 5.mm, 0], [40.mm, 10.mm, 0]]] }
VIEN = [[0, 0, 0], [100.mm, 0, 0], [100.mm, 18.mm, 0]]
ca(out, 'Dựng lỗ hỏng (add_face trả nil) → BÁO LỖI để thao tác abort (trước: bỏ qua im lặng, tấm mất lỗ)') do
  M.dung_than(TAM.new(KhoiGia.new(TFace.new(0, 100), hong: 2)), HOP, PROF, VIEN)
  [false, 'không báo lỗi']
rescue RuntimeError => e
  [e.message.include?('lỗ xuyên'), e.message]
end
ca(out, 'Dựng xong mà đáy+nắp thiếu vòng lỗ → BÁO LỖI; đủ vòng lỗ (2 = đáy+nắp × 1 lỗ) → chạy bình thường') do
  thieu = begin
    M.dung_than(TAM.new(KhoiGia.new(TFace.new(0, 100), lo_moi: 0)), HOP, PROF, VIEN); 'không báo'
  rescue RuntimeError => e
    e.message
  end
  du = M.dung_than(TAM.new(KhoiGia.new(TFace.new(0, 100), lo_moi: 1)), HOP, PROF, VIEN)
  [thieu.include?('mất lỗ') && du.is_a?(Array), { thieu: thieu, du: du }.inspect]
end

# ── Layer phay theo dày sau phay (Khoa 04/10): _15 / _13; số khác không có layer → chặn ở đầu MỚI ──────
NguonPhay = Struct.new(:transformation)
HOP_NGAM = Geom::BoundingBox.new.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(600.mm, 17.5.mm, 300.mm))
def ke_phay(fit, side = 'A')
  spec = { 'edge' => 2, 'count' => 2, 'head' => 35, 'height' => 11, 'neck' => 6, 'bevel' => 1, 'inset' => 50,
           'side' => side, 'fit' => fit, 'slackT' => 0.2, 'slackL' => 0.2, 'cutter' => 6 }
  M.plan_edge(NguonPhay.new(Geom::Transformation.new), spec, nil, HOP_NGAM, '')
end
ca(out, 'Phay còn 15 → layer LEHAI_PHAYMONG_15 + LEHAI_PHAYVIENMONG_15') do
  pl = ke_phay(15)
  [pl[:narrow_mark] && pl[:tag_phay] == %w[LEHAI_PHAYMONG_15 LEHAI_PHAYVIENMONG_15], pl[:tag_phay].inspect]
end
ca(out, 'Phay còn 13 (phay mặt A lẫn B) → layer _13') do
  a = ke_phay(13, 'A'); b = ke_phay(13, 'B')
  [[a, b].all? { |pl| pl[:tag_phay] == %w[LEHAI_PHAYMONG_13 LEHAI_PHAYVIENMONG_13] }, [a[:tag_phay], b[:tag_phay]].inspect]
end
ca(out, 'Dày sau phay 14: plan_edge KHÔNG chặn (đầu cũ còn đóng dấu được), chỉ không có layer → apply chặn đầu mới') do
  pl = ke_phay(14)
  [pl[:narrow_mark] && pl[:tag_phay].nil?, pl[:tag_phay].inspect]
end
ca(out, 'Không phay / phay còn bằng bề dày ván → không sinh dấu phay, không cần layer') do
  a = ke_phay(15, 'none'); b = ke_phay(17.5, 'A')
  [!a[:narrow_mark] && !b[:narrow_mark] && a[:tag_phay].nil? && b[:tag_phay].nil?, [a[:tag_phay], b[:tag_phay]].inspect]
end
DauGia = Struct.new(:name, :layer, :attrs) do
  def is_a?(k); k == Sketchup::Group || super; end
  def get_attribute(d, k); (attrs[d] || {})[k]; end
end
Lop2 = Struct.new(:name)
ca(out, 'Gỡ mộng nhận đủ dấu phay: tên mới _15 / _13 + tên CŨ (file ≤ 1.9.94); không nhận dấu âm LEHAI_MONGAM') do
  d = ->(tag) { DauGia.new('_ABF_Intersect', Lop2.new(tag), {}) }
  nhan = %w[LEHAI_PHAYMONG_15 LEHAI_PHAYVIENMONG_15 LEHAI_PHAYMONG_13 LEHAI_PHAYVIENMONG_13 LEHAI_PHAYMONG LEHAI_PHAYVIENMONG].map { |t| M.dau_phay_cua_tool?(d.(t)) }
  [nhan.all? && !M.dau_phay_cua_tool?(d.('LEHAI_MONGAM')), nhan.inspect]
end

JSON.generate(out)
