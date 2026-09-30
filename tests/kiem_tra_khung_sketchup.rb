# encoding: UTF-8
# Thử LỚP SketchUp của Soát Khung (kiem_tra_khung/main.rb) trên SketchUp GIẢ.
# Nền giả: projects/tao-modul-nhanh/thu_truc/sketchup_gia_tia.rb (tấm = group hộp + biến đổi cứng).
# Phần dưới bổ sung đúng thứ main.rb gọi mà nền giả chưa có. KHÔNG chứng minh API SketchUp thật.

module Sketchup
  class Entity
    def persistent_id; entityID; end
  end
  class ModelTam
    attr_accessor :selection
    def active_path; nil; end
  end
end

class Geom::Transformation
  class << self
    alias_method :new_goc, :new
    # SketchUp: Transformation.new(Point3d) = phép dời
    def new(*a)
      return new_goc([[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]], a[0].to_a) if a[0].is_a?(Geom::Point3d)
      new_goc(*a)
    end
  end
end

class DefKhungGia
  def initialize(k); @k = k; end
  def get_attribute(d, key, dv = nil)
    return dv unless d == 'LH_KHUNG'
    { 'dai' => @k[0], 'sau' => @k[1], 'cao' => @k[2] }.fetch(key, dv)
  end
  def entities; []; end
  def name; 'LH Khung kiem'; end
end

class KhungGia < Sketchup::ComponentInstance
  attr_accessor :transformation, :definition, :name
  def initialize(k, tr); @definition = DefKhungGia.new(k); @transformation = tr; @name = ''; end
  def deleted?; false; end
end

# Tấm có THÊM một mặt lạ (để thử méo / hình lạ): mặt vuông trục nằm ở toạ độ `o` (inch) theo trục `k`
class TamThemMat < Sketchup::Group
  def them_mat(k, o)
    n = [0.0, 0, 0]
    n[k] = 1.0
    a, b = [0, 1, 2] - [k]
    pts = [[0, 0], [1, 0], [1, 1], [0, 1]].map do |i, j|
      c = [0.0, 0, 0]
      c[k] = o
      c[a] = i.zero? ? lo[a] : hi[a]
      c[b] = j.zero? ? lo[b] : hi[b]
      Geom::Point3d.new(*c)
    end
    @them = Sketchup::Face.new(Geom::Vector3d.new(*n), pts)
    self
  end
  def entities; super + [@them].compact; end
end

# View / camera / selection giả cho XemTool (chỉ ghi lại lời gọi, không vẽ thật)
module Sketchup
  class CamGia
    attr_reader :eye, :target, :up
    attr_accessor :height
    def initialize; @eye = Geom::Point3d.new(-100, -100, 100); @target = Geom::Point3d.new(0, 0, 0); end
    def direction; (@target - @eye).normalize; end
    def perspective?; true; end
    def fov; 35.0; end
    def set(e, t, u); raise 'up song song huong nhin' if (t - e).normalize.cross(u).length < 1e-6; @eye = e; @target = t; @up = u; end
  end
  class ViewGia
    attr_reader :camera, :so_net, :tam_giac
    attr_writer :line_width, :drawing_color
    def initialize; @camera = CamGia.new; @so_net = 0; end
    def screen_coords(p); Geom::Point3d.new(p.x, p.y, 0); end
    def draw2d(_m, pts); raise 'draw2d lẻ điểm' if _m == GL_LINES && pts.size.odd?; @so_net += 1; (@tam_giac ||= []) << pts if pts.size == 3; end
    def draw(_m, pts); @so_net += 1; end
    def draw_text(*_a); end
    def invalidate; end
    def model; Sketchup.active_model; end
  end
  class SelGia
    attr_reader :ds
    def initialize; @ds = []; end
    def clear; @ds = []; end
    def add(e); @ds << e; end
  end
end
GL_LINES = 1
GL_POLYGON = 9
class ModelXem < Sketchup::ModelTam
  def initialize(e); super; @v = Sketchup::ViewGia.new; @sel = Sketchup::SelGia.new; end
  def active_view; @v; end
  def selection; @sel; end
  def raytest(*_a); nil; end   # không có vật che: mọi điểm đều THẤY
end

# ── CA THỬ ──
FC = TK::FrameCheck
T = 18.0
DS = [
  ['Hông trái', [0, 18, 0], [T, 600, 1700]], ['Hông phải', [2282, 18, 0], [2300, 600, 1700]],
  ['Đáy', [T, 18, 0], [2282, 600, T]], ['Nóc', [T, 18, 1682], [2282, 600, 1700]],
  ['Vách', [1141, 18, T], [1159, 590, 1682]], ['Đợt', [T, 18, 800], [1141, 580, 818]],
  ['Hậu', [T, 590, T], [2282, 600, 1682]],
  ['Cánh trái', [0, 0, 0], [1148.5, T, 1700]], ['Cánh phải', [1151.5, 0, 0], [2300, T, 1700]]
].freeze

# Tủ đặt ở góc `do_` (xoay quanh trục lên) + dời; `gom`: tấm nằm trong group "Tủ"; `sua`: {tên => [lo, hi]}
def dung_tu(do_, gom: true, sua: {}, lop: nil)
  w = Geom::Transformation.xoay_z(do_, 1234, -567, 0)
  tams = DS.map do |ten, lo, hi|
    lo, hi = sua[ten] if sua[ten]
    k = lop && lop[0] == ten ? TamThemMat : Sketchup::Group
    g = k.new(lo.map(&:mm), hi.map(&:mm), gom ? Geom::Transformation.new : w, ten)
    g = g.them_mat(lop[1], lop[2].mm) if k == TamThemMat
    g
  end
  return [tams, w] unless gom
  vo = Sketchup::Group.new([0, 0, 0], [0, 0, 0], w, 'Tủ')   # vỏ tủ: hộp 0 → không phải tấm
  vo.con = tams
  [[vo], w]
end

def tom(x)
  ds = x[:kq]['ds']
  { do: ds.select { |f| f['muc'] == 'do' }.map { |f| f['loai'] }.sort,
    vang: ds.select { |f| f['muc'] == 'vang' }.map { |f| f['khoa'] }.sort, tam: x[:kq]['so_tam'],
    kich: x[:he][:kich].map { |v| v.round(3) } }
end

def ca(ten)
  kq = yield
  kq[:ten] = ten
  kq
rescue StandardError => e
  { ten: ten, dat: false, kq: "LỖI #{e.class}: #{e.message} #{e.backtrace.first(3).join(' | ')}" }
end

out = []
[0, 90, 180, 270].each do |g|
  out << ca("tủ sạch quay #{g}°, lồng trong group Tủ: 0 đỏ, 9 tấm, chỉ vàng khe cánh 3") do
    ents, w = dung_tu(g)
    Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
    r = tom(FC.quet.first)
    { dat: r[:do].empty? && r[:tam] == 9 && r[:vang] == ['nhom:khe:3'] && r[:kich] == [2300.0, 600.0, 1700.0], kq: r.to_s }
  end
end

out << ca('tủ quay 90° tấm rời (không group vỏ), nóc cao 0,5: gióng mặt trên chỉ ra nóc + hở với vách') do
  ents, w = dung_tu(90, gom: false, sua: { 'Nóc' => [[T, 18, 1682.5], [2282, 600, 1700.5]] })
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  r = tom(FC.quet.first)
  { dat: r[:do].include?('giong') && r[:do].include?('ho'), kq: r.to_s }
end

out << ca('tủ 270°, vách có mặt lệch 0,3 mm (méo): đỏ méo') do
  ents, w = dung_tu(270, lop: ['Vách', 0, 1159.3])
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  r = tom(FC.quet.first)
  { dat: r[:do] == ['meo'], kq: r.to_s }
end

out << ca('đợt có mặt khoét sâu 8 mm: vàng hình lạ, không đỏ') do
  ents, w = dung_tu(0, lop: ['Đợt', 2, 810])
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  r = tom(FC.quet.first)
  { dat: r[:do].empty? && r[:vang].include?('nhom:hinh:'), kq: r.to_s }
end

out << ca('khung đặt lệch 1 mm sang phải: gióng mặt trái khung + hụt mặt phải') do
  ents, w = dung_tu(180)
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w * Geom::Transformation.xoay_z(0, 1, 0, 0))])
  r = tom(FC.quet.first)
  { dat: r[:do].include?('hut') && r[:do].include?('giong'), kq: r.to_s }
end

out << ca('hộc trên ray: group cha "Hộc 1" chứa tấm tên "hông trái"/"đáy" → di động, không báo đỏ') do
  ents, w = dung_tu(90)
  hoc = [['hông trái', [30.5, 20, 100], [48.5, 570, 300]], ['hông phải', [1110.5, 20, 100], [1128.5, 570, 300]],
         ['đáy', [48.5, 20, 100], [1110.5, 570, 118]]].map { |n, lo, hi| Sketchup::Group.new(lo.map(&:mm), hi.map(&:mm), Geom::Transformation.new, n) }
  bo = Sketchup::Group.new([0, 0, 0], [0, 0, 0], Geom::Transformation.new, 'Hộc 1')
  bo.con = hoc
  ents[0].con = ents[0].instance_variable_get(:@con) + [bo]
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  r = tom(FC.quet.first)
  { dat: r[:do].empty? && r[:tam] == 12, kq: r.to_s }
end

out << ca('xem (tủ 180°, nóc lệch trước 0,5): 1 chỗ, mép đỏ cách mép xanh lá đúng 0,5 mm, nhãn "Nóc thụt vào 0.5 mm"') do
  ents, w = dung_tu(180, sua: { 'Nóc' => [[T, 18.5, 1682], [2282, 600, 1700]] })
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  x = FC.quet.first
  f = x[:kq]['ds'].find { |d| d['loai'] == 'giong' }
  cho = FC.ve_giong(x[:he], x[:tams], f['giong'])
  c = cho[0]
  d = c[:do][0].distance(c[:xanh][0]) * 25.4          # hai mép song song cách nhau đúng độ lệch
  song = (c[:do][1] - c[:do][0]).normalize.dot((c[:xanh][1] - c[:xanh][0]).normalize)
  { dat: cho.size == 1 && c[:nhan] == 'Nóc thụt vào 0.5 mm' && (d - 0.5).abs < 1e-6 && (song - 1).abs < 1e-9 && c[:hop].size == 8 && c[:hop_ban].size == 8,
    kq: "#{f['tieu_de']} | #{f['chi_tiet']} | cách #{d.round(4)} | #{c[:nhan]}" }
end

out << ca('XemTool chạy trên view giả: chọn sẵn tấm lệch, phủ mờ + vẽ khối 2 tấm, mũi tên đúng hướng mép đã đi, khung nhìn thấy khối mà mép vẫn tách, vẽ không lỗi, ← → không vỡ') do
  ents, w = dung_tu(90, sua: { 'Nóc' => [[T, 18.5, 1682], [2282, 600, 1700]], 'Vách' => [[1141, 20, T], [1159, 590, 1682]] })
  Sketchup.gia_model = ModelXem.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  x = FC.quet.first
  f = x[:kq]['ds'].find { |d| d['loai'] == 'giong' }
  cho = FC.ve_giong(x[:he], x[:tams], f['giong'])
  tool = FC::XemTool.new([], [], nil, nil, f, cho)
  tool.activate
  v = Sketchup.active_model.active_view
  tool.draw(v)
  tool.onKeyDown(39, 1, 0, v)
  tool.draw(v)
  # mũi tên (tam giác cuối cùng): đỉnh − giữa đáy phải cùng chiều hướng mép đã đi (u_k × dấu) chiếu lên màn
  t3 = v.tam_giac.last
  mui = [t3[0].x - (t3[1].x + t3[2].x) / 2, t3[0].y - (t3[1].y + t3[2].y) / 2]
  cc = cho[1]
  hg = [cc[:u_k].x * cc[:dau], cc[:u_k].y * cc[:dau]]
  dung_huong = mui[0] * hg[0] + mui[1] * hg[1] > 0
  cam = v.camera
  xa = cam.eye.distance(cam.target) * 25.4
  rong = 2 * xa * Math.tan(35.0 / 2 * Math::PI / 180)   # bề rộng khung nhìn tại chỗ lệch (mm)
  c = cho[1]
  lech = c[:do][0].distance(c[:xanh][0]) * 25.4
  chon = Sketchup.active_model.selection.ds
  # lệch chiếm ≥ 1/150 khung nhìn (màn 1000 px → ≥ 7 px: hai mép vẫn tách) nhưng khung đủ rộng thấy khối
  # (≥ 60 mm); đang chọn đúng tấm của chỗ 2; vẽ đủ lớp mờ + 2 khối × 6 mặt × (mặt + viền) + mép + nhãn
  { dat: lech / rong >= 1.0 / 150 && rong >= 60 && chon == [c[:e]] && v.so_net >= 1 + 24 + 2 && dung_huong,
    kq: "#{cho.size} chỗ · lệch #{lech.round(2)} mm / khung #{rong.round(1)} mm · chọn #{chon.map(&:name)} · #{v.so_net} lần vẽ" }
end

out << ca('hai tủ dùng CHUNG tấm (một component đặt 2 lần) trong một khung: 18 mã tấm riêng, không trùng') do
  _, w = dung_tu(0)
  tams = DS.map { |ten, lo, hi| Sketchup::Group.new(lo.map(&:mm), hi.map(&:mm), Geom::Transformation.new, ten) }
  v1 = Sketchup::Group.new([0, 0, 0], [0, 0, 0], w, 'Tủ A')
  v2 = Sketchup::Group.new([0, 0, 0], [0, 0, 0], w * Geom::Transformation.xoay_z(0, 2300, 0, 0), 'Tủ B')
  v1.con = tams
  v2.con = tams                                       # CÙNG các entity tấm → persistent_id trùng
  Sketchup.gia_model = Sketchup::ModelTam.new([v1, v2, KhungGia.new([4600, 600, 1700], w)])
  x = FC.quet.first
  { dat: x[:tams].size == 18 && x[:kq]['so_tam'] == 18, kq: "#{x[:tams].size} mã / #{x[:kq]['so_tam']} tấm" }
end

out << ca('tủ bên cạnh (ngoài khung) không bị soát') do
  ents, w = dung_tu(0)
  ben, = dung_tu(0)
  ben[0].transformation = Geom::Transformation.xoay_z(0, 1234 + 2300, -567, 0)
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + ben + [KhungGia.new([2300, 600, 1700], w)])
  r = tom(FC.quet.first)
  { dat: r[:tam] == 9 && r[:do].empty?, kq: r.to_s }
end

[0, 90].each do |g|
  out << ca("tự đặt khung theo vùng chọn (tủ quay #{g}°): soát ra 0 đỏ") do
    ents, = dung_tu(g)
    m = Sketchup::ModelTam.new(ents)
    m.selection = ents
    Sketchup.gia_model = m
    tr = FC.vi_tri_tu_chon(m, [2300, 600, 1700])
    raise 'không đặt được' unless tr
    Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], tr)])
    r = tom(FC.quet.first)
    { dat: r[:do].empty? && r[:tam] == 9, kq: r.to_s }
  end
end

out << ca('audit: chưa có khung → na; tủ sạch → warn (khe cánh)') do
  ents, w = dung_tu(0)
  Sketchup.gia_model = Sketchup::ModelTam.new(ents)
  a = FC.audit
  Sketchup.gia_model = Sketchup::ModelTam.new(ents + [KhungGia.new([2300, 600, 1700], w)])
  b = FC.audit
  { dat: a[:status] == :na && b[:status] == :warn, kq: "#{a} | #{b}" }
end

out << ca('xem: đổi điểm lỗi hệ khung → thế giới khớp góc tủ (quay 90°)') do
  _, w = dung_tu(90)
  h = FC.he_khung(e: KhungGia.new([2300, 600, 1700], w), te: w)
  p = FC.ra_the_gioi(h, [2300, 600, 1700])
  q = w * Geom::Point3d.new(2300.mm, 600.mm, 1700.mm)
  back = FC.vao_khung(h, p)
  { dat: p.distance(q) < 1e-9 && back.zip([2300, 600, 1700]).all? { |a, b| (a - b).abs < 1e-6 }, kq: "#{p.to_a} vs #{q.to_a}" }
end

JSON.generate(out)
