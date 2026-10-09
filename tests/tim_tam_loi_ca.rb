# encoding: UTF-8
# Ca thử Tìm Tấm Lỗi → Tab sao ra gốc (tests/tim_tam_loi.test.mjs). SketchUp GIẢ trên nền
# thu_truc/sketchup_gia_tia.rb + soi_noi_gia.rb: group/component có definition, thuộc tính ABF,
# model.entities.add_instance. KHÔNG chứng minh API thật — Khoa phải chạy trong SketchUp.

module Geom
  class BoundingBox
    # thứ tự góc như SketchUp: bit 0 = x, bit 1 = y, bit 2 = z (0 = góc nhỏ nhất)
    def corner(i); Point3d.new(i & 1 == 0 ? @lo[0] : @hi[0], i & 2 == 0 ? @lo[1] : @hi[1], i & 4 == 0 ? @lo[2] : @hi[2]); end
  end
  class Transformation
    def self.xoay(truc, do_)   # xoay quanh trục 0/1/2 (độ), không dời
      g = do_ * Math::PI / 180
      c = Math.cos(g).round(12); s = Math.sin(g).round(12)
      r = case truc
          when 0 then [[1.0, 0, 0], [0, c, -s], [0, s, c]]
          when 1 then [[c, 0, s], [0, 1.0, 0], [-s, 0, c]]
          else [[c, -s, 0], [s, c, 0], [0, 0, 1.0]]
          end
      new(r, [0.0, 0, 0])
    end
  end
end

module Sketchup
  class DictGia
    attr_reader :name
    def initialize(name, h); @name = name; @h = h; end
    def [](k); @h[k]; end
    def keys; @h.keys; end
  end
  class Entity
    def attribute_dictionary(n)
      h = (@attr ||= {}).select { |(d, _), _| d == n }.map { |(_, k), v| [k, v] }.to_h
      h.empty? ? nil : DictGia.new(n, h)
    end
    def attribute_dictionaries
      ds = (@attr ||= {}).keys.map(&:first).uniq.map { |n| attribute_dictionary(n) }
      ds.empty? ? nil : ds
    end
  end
  class DefGia
    attr_reader :entities
    def initialize(lo_mm, hi_mm, con = [], group = true)
      @lo = lo_mm.map(&:mm); @hi = hi_mm.map(&:mm); @entities = con; @group = group
    end
    def group?; @group; end
    def bounds; Geom::BoundingBox.new.add(Geom::Point3d.new(*@lo), Geom::Point3d.new(*@hi)); end
  end
  module VoGia   # phần chung group/component giả: definition + transformation + thuộc tính vỏ
    attr_accessor :transformation, :name, :layer, :material
    attr_reader :definition
    def dung(defn, tr, name); @definition = defn; @transformation = tr; @name = name; @layer = 'Untagged'; @material = nil; self; end
    def entities; @definition.entities; end
    def bounds; Geom::BoundingBox.new.add((0..7).map { |i| transformation * @definition.bounds.corner(i) }); end
  end
  class GroupT < Group
    include VoGia
    def initialize(defn, tr, name = ''); dung(defn, tr, name); end
  end
  class CompT < ComponentInstance
    include VoGia
    def initialize(defn, tr, name = ''); dung(defn, tr, name); end
  end
  class EntsT < Array
    attr_accessor :hong_sau   # add_instance thứ n văng lỗi (thử đường abort)
    def add_instance(defn, tr)
      @dem = (@dem || 0) + 1
      raise 'add_instance giả hỏng' if hong_sau && @dem > hong_sau
      e = defn.group? ? GroupT.new(defn, tr) : CompT.new(defn, tr)
      self << e
      e
    end
  end
  class SelT < Array
    def add(e); self << e; end
  end
  class ViewSoi
    attr_reader :da_zoom
    def zoom(x); @da_zoom = x.to_a.size; end
  end
  class ModelT < ModelSoi
    attr_accessor :active_path
    attr_reader :ops, :tool
    def initialize(goc); super([]); @entities = goc; @selection = SelT.new; @ops = []; @tool = :cu; end
    def start_operation(*a); @ops << [:start, a.first]; end
    def commit_operation; @ops << [:commit]; end
    def abort_operation; @ops << [:abort]; end
    def select_tool(t); @tool = t; end
  end
end

module UI
  def self.messagebox(msg, *_a); (@hop ||= []) << msg.to_s; nil; end
  def self.hop; @hop ||= []; end
end

# ── Dựng cảnh: tủ xoay 90° + bản nesting nằm phẳng trên sheet ──
def tam(idx, lo, hi, tr, ten, comp: false)
  d = Sketchup::DefGia.new(lo, hi, [], !comp)
  e = comp ? Sketchup::CompT.new(d, tr, ten) : Sketchup::GroupT.new(d, tr, ten)
  e.set_attribute('ABF', 'is-board', true)
  e.set_attribute('ABF', 'board-index', idx)
  e.set_attribute('ABF', 'edge-band-types', [0, 'chi don KES 21417EV', 1, '#ec2525', 0])
  e.layer = "tag-#{idx}"
  e.material = "go-#{idx}"
  e
end

def mm_tr(dx, dy, dz, xoay = nil)
  t = Geom::Transformation.translation(Geom::Point3d.new(dx.mm, dy.mm, dz.mm))
  xoay ? t * xoay : t
end

def canh(comp_hong: false)
  # tủ: group xoay 90° quanh trục lên, đặt ở (5000, 2000, 0) mm
  hong   = tam(7, [0, 0, 0], [18, 560, 720], mm_tr(0, 0, 0), 'hông trái')                       # đứng
  day    = tam(9, [0, 0, 0], [800, 560, 18], mm_tr(18, 0, 0), 'đáy', comp: comp_hong)           # nằm
  xiendo = tam(11, [0, 0, 0], [400, 18, 300], mm_tr(100, 100, 100, Geom::Transformation.xoay(0, 30)), 'đợt xiên')
  khac   = tam(5, [0, 0, 0], [18, 560, 720], mm_tr(818, 0, 0), 'hông phải')
  tu = Sketchup::GroupT.new(Sketchup::DefGia.new([0, 0, 0], [836, 560, 720], [hong, day, xiendo, khac]),
                            mm_tr(5000, 2000, 0, Geom::Transformation.xoay(2, 90)), 'Tủ bếp')
  # nesting: __ABF_Nesting → sheet → chi tiết phẳng (dày theo z)
  p7 = tam(7, [0, 0, 0], [720, 560, 18], mm_tr(10, 10, 0), '__7 hông trái')
  p9 = tam(9, [0, 0, 0], [800, 560, 18], mm_tr(10, 600, 0), '__9 đáy')
  sheet = Sketchup::GroupT.new(Sketchup::DefGia.new([0, 0, 0], [1220, 2440, 18], [p7, p9]), mm_tr(0, 0, 0), '__MDF-sheet-1')
  nest = Sketchup::GroupT.new(Sketchup::DefGia.new([0, 0, 0], [1220, 2440, 18], [sheet]), mm_tr(-3000, 0, 0), '__ABF_Nesting')
  m = Sketchup::ModelT.new(Sketchup::EntsT.new([tu, nest]))
  Sketchup.gia_model = m
  m
end

def hop_mm(e, tr = e.transformation)
  bb = e.definition.bounds
  pts = (0..7).map { |i| (tr * bb.corner(i)).to_a.map { |v| v * 25.4 } }
  [(0..2).map { |k| pts.map { |p| p[k] }.min.round(3) }, (0..2).map { |k| pts.map { |p| p[k] }.max.round(3) }]
end

def ca(out, ten)
  r = yield
  out << { ten: ten, rieng: r[0], kq: r[1] }
rescue StandardError => e
  out << { ten: ten, loi: "#{e.class}: #{e.message} | #{(e.backtrace || []).first(3).join(' | ')}" }
end

out = []
F = TK::ABFFinder

ca(out, 'Tìm 7, 9: ra 4 tấm (2 tủ + 2 nesting), không lấy tấm 5') do
  canh
  hits, _w, miss = F.resolve(%w[7 9])
  [hits.size == 4 && hits.count(&:in_nesting) == 2 && miss.empty?, "#{hits.size} tấm · nesting #{hits.count(&:in_nesting)} · thiếu #{miss}"]
end

ca(out, 'Tab: sao 4 tấm ra gốc — 1 bậc Undo, chọn sẵn 4 bản sao, thoát tool, báo đúng số') do
  m = canh
  hits, w, miss = F.resolve(%w[7 9 99])
  tool = F::HighlightTool.new(hits, w, miss)
  an = tool.onKeyDown(9, 1, 0, m.active_view)
  sao = m.entities.select { |e| e.get_attribute(F::DICT_SAO, 'ban-sao') }
  msg = UI.hop.last.to_s
  ok = an == true && sao.size == 4 && m.ops == [[:start, 'Sao tam loi ra goc'], [:commit]] && m.selection.size == 4 &&
       m.tool.nil? && m.active_view.da_zoom == 4 && msg.include?('2 tấm tủ 3D + 2 tấm nesting') && msg.include?('99')
  [ok, "Tab trả #{an} · bản sao #{sao.size} · ops #{m.ops} · chọn #{m.selection.size} · tool #{m.tool.inspect} · zoom #{m.active_view.da_zoom} · báo: #{msg.tr("\n", ' ')}"]
end

ca(out, 'Vị trí: hàng 3D sát gốc, nối theo trục đỏ khe 10mm; hàng nesting lùi theo xanh lá khe 10mm; không chồng') do
  m = canh
  hits, = F.resolve(%w[7 9 11])
  bans = F.sao_ra_goc(hits)
  tu = bans.select { |b| b.get_attribute(F::DICT_SAO, 'ban-sao') == 'tu-3d' }.map { |b| hop_mm(b) }
  ne = bans.select { |b| b.get_attribute(F::DICT_SAO, 'ban-sao') == 'nesting' }.map { |b| hop_mm(b) }
  sau1 = tu.map { |lo, hi| hi[1] - lo[1] }.max
  ok = tu[0][0] == [0.0, 0.0, 0.0] &&
       (tu[1][0][0] - tu[0][1][0] - 10).abs < 1e-6 && (tu[2][0][0] - tu[1][1][0] - 10).abs < 1e-6 &&
       tu.all? { |lo, _| lo[1].abs < 1e-6 && lo[2].abs < 1e-6 } &&
       ne.all? { |lo, _| (lo[1] - sau1 - 10).abs < 1e-6 && lo[2].abs < 1e-6 } && ne[0][0][0].abs < 1e-6 &&
       (ne[1][0][0] - ne[0][1][0] - 10).abs < 1e-6
  [ok, "3D #{tu.inspect} · nesting #{ne.inspect}"]
end

ca(out, 'Y hệt: cùng definition, cùng hướng xoay (kể cả đợt xiên 30° trong tủ xoay 90°), kích thước giữ nguyên') do
  m = canh
  hits, = F.resolve(%w[7 9 11])
  bans = F.sao_ra_goc(hits)
  ok = hits.sort_by { |h| [h.in_nesting ? 1 : 0, h.board_index] }.zip(bans).all? do |h, b|
    goc = hop_mm(h.entity, h.world_t)
    moi = hop_mm(b)
    b.definition.equal?(h.entity.definition) && b.transformation.r == h.world_t.r &&
      (0..2).all? { |k| ((goc[1][k] - goc[0][k]) - (moi[1][k] - moi[0][k])).abs < 1e-6 }
  end
  [ok, bans.map { |b| "#{b.name}: #{b.transformation.r.map { |h| h.map { |v| v.round(3) } }}" }.join(' | ')]
end

ca(out, 'Chép vỏ tấm: tên, tag, vật liệu, toàn bộ thuộc tính ABF (cả mảng dán cạnh)') do
  m = canh
  hits, = F.resolve(%w[9])
  bans = F.sao_ra_goc(hits)
  ok = hits.zip(bans).all? do |h, b|
    e = h.entity
    b.name == e.name && b.layer == e.layer && b.material == e.material &&
      %w[is-board board-index edge-band-types].all? { |k| b.get_attribute('ABF', k) == e.get_attribute('ABF', k) }
  end
  [ok, bans.map { |b| [b.name, b.layer, b.material, b.attribute_dictionary('ABF').keys] }.inspect]
end

ca(out, 'Tìm lại sau khi sao: bản sao ở gốc bị bỏ qua (vẫn 4 tấm, không thành 8)') do
  m = canh
  hits, = F.resolve(%w[7 9])
  F.sao_ra_goc(hits)
  lai, = F.resolve(%w[7 9])
  [lai.size == 4 && m.entities.size == 6, "tìm lại #{lai.size} · gốc model có #{m.entities.size} thứ"]
end

ca(out, 'Đang mở group: không sao, báo ra ngoài cùng, không mở bậc Undo') do
  m = canh
  m.active_path = [m.entities.first]
  hits, = F.resolve(%w[7])
  r = F.sao_ra_goc(hits)
  [r.nil? && m.ops.empty? && m.entities.size == 2 && UI.hop.last.to_s.include?('ngoài cùng'), "kq #{r.inspect} · ops #{m.ops} · báo #{UI.hop.last}"]
end

ca(out, 'Lỗi giữa chừng (tấm thứ 2 hỏng): abort cả lượt, báo lỗi, không chọn gì') do
  m = canh
  m.entities.hong_sau = 1
  hits, w, miss = F.resolve(%w[7 9])
  tool = F::HighlightTool.new(hits, w, miss)
  tool.onKeyDown(9, 1, 0, m.active_view)
  [m.ops.last == [:abort] && m.selection.empty? && UI.hop.last.to_s.start_with?('Lỗi:') && m.tool == :cu,
   "ops #{m.ops} · chọn #{m.selection.size} · tool #{m.tool.inspect} · báo #{UI.hop.last}"]
end

ca(out, 'Tấm là component (không phải group): bản sao cũng là component cùng definition') do
  m = canh(comp_hong: true)
  hits, = F.resolve(%w[9])
  bans = F.sao_ra_goc(hits)
  c = bans.find { |b| b.get_attribute(F::DICT_SAO, 'ban-sao') == 'tu-3d' }
  [c.is_a?(Sketchup::ComponentInstance) && c.definition.equal?(hits.reject(&:in_nesting).first.entity.definition), c.class.to_s]
end

ca(out, 'Phím khác Tab/Esc: không làm gì, trả false') do
  m = canh
  hits, w, miss = F.resolve(%w[7])
  tool = F::HighlightTool.new(hits, w, miss)
  r = tool.onKeyDown(65, 1, 0, m.active_view)
  [r == false && m.ops.empty?, "trả #{r} · ops #{m.ops}"]
end

ca(out, 'Tab lần hai (soát P2-1): lượt mới lùi sau bản sao cũ 10mm theo xanh lá, không đè hộp nào') do
  m = canh
  hits, = F.resolve(%w[7 9])
  dot1 = F.sao_ra_goc(hits).map { |b| hop_mm(b) }
  hits2, = F.resolve(%w[7 9])
  dot2 = F.sao_ra_goc(hits2).map { |b| hop_mm(b) }
  chong = dot1.product(dot2).any? { |(a0, a1), (b0, b1)| (0..2).all? { |k| a0[k] < b1[k] - 1e-6 && b0[k] < a1[k] - 1e-6 } }
  y1 = dot1.map { |_, hi| hi[1] }.max
  [!chong && (dot2.map { |lo, _| lo[1] }.min - y1 - 10).abs < 1e-6 && dot2[0][0][0].abs < 1e-6 && m.entities.size == 10,
   "lượt 1 sâu tới y=#{y1} · lượt 2 #{dot2.inspect} · chồng #{chong}"]
end

ca(out, 'Vật liệu (soát P3): tấm không tô riêng → bản sao mang màu tủ; tấm tô riêng giữ màu mình') do
  m = canh
  tu = m.entities.first
  tu.material = 'go-tu'
  tu.entities.find { |e| e.name == 'hông trái' }.material = nil
  hits, = F.resolve(%w[7 9])
  bans = F.sao_ra_goc(hits).select { |b| b.get_attribute(F::DICT_SAO, 'ban-sao') == 'tu-3d' }
  [bans.map(&:material) == %w[go-tu go-9], bans.map { |b| [b.name, b.material] }.inspect]
end

ca(out, 'Hộp thoại báo xóa bản sao trước khi nesting lại / Check Chốt (soát P2-2)') do
  m = canh
  hits, w, miss = F.resolve(%w[7])
  F::HighlightTool.new(hits, w, miss).onKeyDown(9, 1, 0, m.active_view)
  msg = UI.hop.last.to_s
  [msg.include?('XÓA bản sao') && msg.include?('nesting lại') && msg.include?('Check Chốt'), msg.tr("\n", ' ')]
end

ca(out, 'xep_hang thuần: 2 hàng, khe 10') do
  d = F.xep_hang([[[[5, 5, 5], [7, 8, 9]], [[-1, 0, 0], [0, 1, 1]]], [[[0, 0, 0], [1, 1, 1]]]], 10)
  [d == [[[-5, -5, -5], [13, 0, 0]], [[0, 13, 0]]], d.inspect]
end

# ── Làm tiếp trên tấm đã tìm (Khoa 09/10): Delete xoá cả loạt, ESC chọn sẵn, N đổi phía ──
# SketchUp giả thêm: cha (parent) / definition.instances / locked? / erase! / active_path= văng khi khoá.
MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES = 6 unless defined?(IDYES)
module UI
  def self.tra_loi=(v); @tra_loi = v; end
  def self.messagebox(msg, *_a); (@hop ||= []) << msg.to_s; @tra_loi.nil? ? IDYES : @tra_loi; end
end
module Sketchup
  class DefGia
    def instances; @instances ||= []; end
  end
  module VoGia
    attr_accessor :parent
    attr_writer :locked
    def locked?; !!@locked; end
    def deleted?; !!@xoa; end
    def erase!
      raise 'xoá tấm đã xoá' if @xoa
      raise 'xoá trong ngữ cảnh lạ' unless parent.entities.delete(self)
      @xoa = true
    end
  end
  class ModelT
    def active_path=(p)
      raise ArgumentError, 'instance path chứa group khoá' if (p || []).any?(&:locked?)
      @active_path = p
    end
  end
end

# nối cha/con như SketchUp thật: tấm nằm trong definition của group cha, definition biết các bản dùng nó
def noi_cha(m, ents = m.entities, cha = m)
  ents.each do |e|
    next unless e.respond_to?(:definition)
    e.parent = cha
    e.definition.instances << e unless e.definition.instances.include?(e)
    noi_cha(m, e.definition.entities, e.definition)
  end
  m
end

def tool_cho(so)
  hits, w, miss = F.resolve(so)
  F::HighlightTool.new(hits, w, miss)
end

ca(out, 'Mặc định nhắm tấm tủ 3D; N đổi sang nesting, N lần nữa về 3D') do
  canh
  t = tool_cho(%w[7 9])
  a = t.send(:nham).map(&:in_nesting).uniq
  t.onKeyDown(78, 1, 0, Sketchup.active_model.active_view)
  b = t.send(:nham).map(&:in_nesting).uniq
  t.onKeyDown(110, 1, 0, Sketchup.active_model.active_view)
  c = t.send(:nham).map(&:in_nesting).uniq
  [a == [false] && b == [true] && c == [false], "đầu #{a} · N #{b} · n #{c}"]
end

ca(out, 'Chỉ tìm thấy tấm nesting: tự nhắm nesting') do
  canh
  t = tool_cho(%w[7])
  hits, = F.resolve(%w[7])
  t2 = F::HighlightTool.new(hits.select(&:in_nesting), [7], [])
  [t2.send(:nham).size == 1 && t2.send(:nham).first.in_nesting, t2.send(:ten_phia)]
end

ca(out, 'Delete: hỏi rồi xoá cả 2 tấm tủ 3D (7, 9) một bậc Undo; nesting còn nguyên; tool còn mở') do
  m = noi_cha(canh)
  UI.tra_loi = nil
  t = tool_cho(%w[7 9])
  an = t.onKeyDown(46, 1, 0, m.active_view)
  tu = m.entities.first.entities.map(&:name)
  con, = F.resolve(%w[7 9])
  hoi = UI.hop[-2].to_s
  ok = an == true && m.ops == [[:start, 'Xoa tam tim thay'], [:commit]] && tu == ['đợt xiên', 'hông phải'] &&
       con.size == 2 && con.all?(&:in_nesting) && hoi.include?('Xoá 2 tấm tủ 3D (số 7, 9)') && m.tool == :cu
  [ok, "trả #{an} · ops #{m.ops} · tủ còn #{tu} · tìm lại #{con.size} · hỏi: #{hoi.tr("\n", ' ')}"]
end

ca(out, 'Delete mà bấm Không: không xoá, không mở bậc Undo') do
  m = noi_cha(canh)
  UI.tra_loi = 7
  tool_cho(%w[7 9]).onKeyDown(46, 1, 0, m.active_view)
  UI.tra_loi = nil
  [m.ops.empty? && m.entities.first.entities.size == 4, "ops #{m.ops} · tủ còn #{m.entities.first.entities.size}"]
end

ca(out, 'Delete khi tủ là bản COPY dùng chung (2 bản): KHÔNG xoá, báo lý do — xoá là mất ở cả 2 tủ') do
  m = noi_cha(canh)
  tu = m.entities.first
  ban2 = Sketchup::GroupT.new(tu.definition, mm_tr(9000, 0, 0), 'Tủ bếp copy')
  m.entities << ban2
  noi_cha(m)
  xoa, bo = F.xoa_tam(F.resolve(%w[9]).first.reject(&:in_nesting))
  [xoa.empty? && bo.size == 1 && bo[0][1].include?('2 bản copy') && m.ops.empty? && tu.entities.size == 4,
   "xoá #{xoa.size} · bỏ #{bo.map { |b| b[1] }} · ops #{m.ops}"]
end

ca(out, 'Delete gặp tấm khoá: xoá tấm còn lại, báo tấm khoá') do
  m = noi_cha(canh)
  hits, = F.resolve(%w[7 9])
  tu = hits.reject(&:in_nesting)
  tu.find { |h| h.board_index == 7 }.entity.locked = true
  xoa, bo = F.xoa_tam(tu)
  [xoa.map(&:board_index) == [9] && bo.map { |b, l| [b.board_index, l] } == [[7, 'đang khoá']], "xoá #{xoa.map(&:board_index)} · bỏ #{bo.map { |b, l| [b.board_index, l] }}"]
end

ca(out, 'ESC: tấm 3D chung một tủ → mở tủ đó + chọn sẵn 2 tấm, tool thoát') do
  m = noi_cha(canh)
  t = tool_cho(%w[7 9])
  an = t.onKeyDown(27, 1, 0, m.active_view)
  ok = an == true && m.tool.nil? && m.active_path == [m.entities.first] && m.selection.map(&:name).sort == ['hông trái', 'đáy'].sort
  [ok, "trả #{an} · tool #{m.tool.inspect} · mở #{(m.active_path || []).map(&:name)} · chọn #{m.selection.map(&:name)}"]
end

ca(out, 'ESC sau N: chọn sẵn 2 tấm nesting, mở đúng sheet (__ABF_Nesting › sheet)') do
  m = noi_cha(canh)
  t = tool_cho(%w[7 9])
  t.onKeyDown(78, 1, 0, m.active_view)
  t.onCancel(0, m.active_view)
  [m.active_path.map(&:name) == ['__ABF_Nesting', '__MDF-sheet-1'] && m.selection.size == 2,
   "mở #{(m.active_path || []).map(&:name)} · chọn #{m.selection.map(&:name)}"]
end

ca(out, 'ESC khi tấm ở 2 group khác nhau: không chọn, báo vì sao + chỉ Delete') do
  m = noi_cha(canh)
  hits, = F.resolve(%w[7 5])
  ms = hits.reject(&:in_nesting)
  ms.find { |h| h.board_index == 5 }.duong = []   # giả: tấm 5 nằm ngay gốc model
  bao = F.chon_san(m, ms)
  [bao.to_s.include?('2 group khác nhau') && bao.include?('Delete') && m.selection.empty?, bao.to_s]
end

ca(out, 'ESC khi group cha đang khoá: không văng, báo lý do') do
  m = noi_cha(canh)
  m.entities.first.locked = true
  bao = F.chon_san(m, F.resolve(%w[7]).first.reject(&:in_nesting))
  [bao.to_s.include?('đang khoá') && m.selection.empty?, bao.to_s]
end

ca(out, 'Undo khi tool đang mở (onCancel lý do 2): chỉ thoát, không mở group, không chọn') do
  m = noi_cha(canh)
  tool_cho(%w[7 9]).onCancel(2, m.active_view)
  [m.tool.nil? && m.active_path.nil? && m.selection.empty?, "mở #{m.active_path.inspect} · chọn #{m.selection.size}"]
end

ca(out, 'Đường thứ hai (phím tắt SketchUp giành phím): gõ "n" Enter đổi phía, "x" Enter xoá; Backspace cũng xoá') do
  m = noi_cha(canh)
  t = tool_cho(%w[7 9])
  t.onUserText('n', m.active_view)
  a = t.send(:nham).map(&:in_nesting).uniq
  t.onUserText(' N ', m.active_view)
  t.onUserText('x', m.active_view)
  xoa1 = m.entities.first.entities.size
  m2 = noi_cha(canh)
  tool_cho(%w[9]).onKeyDown(8, 1, 0, m2.active_view)
  xoa2 = m2.entities.first.entities.size
  [a == [true] && xoa1 == 2 && xoa2 == 3, "sau n: nesting? #{a} · x xoá còn #{xoa1}/4 · Backspace còn #{xoa2}/4"]
end

ca(out, 'Bấm nút lần sau: ô nhập điền sẵn số lần trước') do
  canh
  goi = []
  UI.define_singleton_method(:inputbox) { |_a, mac_dinh, _t| goi << mac_dinh.first; ['7, 9, 9'] }
  F.prompt
  F.prompt
  [goi == ['', '7, 9'], "lần 1 #{goi[0].inspect} · lần 2 #{goi[1].inspect}"]
end

JSON.generate(out)
