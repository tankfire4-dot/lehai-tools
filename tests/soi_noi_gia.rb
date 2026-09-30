# encoding: UTF-8
# SketchUp GIẢ cho bộ thử Soi Nổi (tests/soi_noi.test.mjs): bổ sung trên nền
# projects/tao-modul-nhanh/thu_truc/sketchup_gia_tia.rb đúng những gì các ReviewTool gọi khi
# activate + draw. Ghi lại lời vẽ để kiểm: có lớp mờ, có khối đặc, có nét. KHÔNG phải SketchUp thật.

GL_LINES = 1 unless defined?(GL_LINES)
GL_LINE_STRIP = 3 unless defined?(GL_LINE_STRIP)
GL_LINE_LOOP = 2 unless defined?(GL_LINE_LOOP)
GL_QUADS = 7 unless defined?(GL_QUADS)
GL_POLYGON = 9 unless defined?(GL_POLYGON)
SB_VCB_LABEL = 1 unless defined?(SB_VCB_LABEL)

module Geom
  class Point3d
    def self.linear_combination(w1, p1, w2, p2)
      new(p1.x * w1 + p2.x * w2, p1.y * w1 + p2.y * w2, p1.z * w1 + p2.z * w2)
    end
    def +(v); Point3d.new(x + v.x, y + v.y, z + v.z); end
    def ==(o); o.respond_to?(:x) && (x - o.x).abs < 1e-9 && (y - o.y).abs < 1e-9 && (z - o.z).abs < 1e-9; end
  end
  class Vector3d
    def *(k); k.is_a?(Numeric) ? Vector3d.new(x * k, y * k, z * k) : cross(k); end
    def +(o); Vector3d.new(x + o.x, y + o.y, z + o.z); end
    def -(o); Vector3d.new(x - o.x, y - o.y, z - o.z); end
    def normalize!; l = length; @x /= l; @y /= l; @z /= l; self; end
    def reverse!; @x = -@x; @y = -@y; @z = -@z; self; end
    def valid?; length > 1e-12; end
    def parallel?(o); cross(o).length < 1e-9; end
  end
  class BoundingBox
    def center; Point3d.new(*(0..2).map { |i| (@lo[i] + @hi[i]) / 2.0 }); end
    def diagonal; Math.sqrt((0..2).sum { |i| (@hi[i] - @lo[i])**2 }); end
    def width; @hi[0] - @lo[0]; end
    def height; @hi[1] - @lo[1]; end
    def depth; @hi[2] - @lo[2]; end
    def valid?; !empty?; end
  end
end

module Sketchup
  class CamSoi
    attr_reader :eye, :target, :up
    attr_accessor :height
    def initialize
      @eye = Geom::Point3d.new(-2000.0 / 25.4, -3000.0 / 25.4, 2500.0 / 25.4)
      @target = Geom::Point3d.new(0, 0, 0)
      @up = Geom::Vector3d.new(0, 0, 1)
      @dat = 0
    end
    def direction; (@target - @eye).normalize; end
    attr_writer :song_song
    def perspective?; !@song_song; end
    def fov; 35.0; end
    def xaxis; direction.cross(@up).normalize; end
    def yaxis; xaxis.cross(direction).normalize; end
    def zaxis; direction; end
    def set(e, t, u); @eye = e; @target = t; @up = u; @dat += 1; self; end
    def so_lan_dat; @dat; end
  end
  # Chiếu phối cảnh thật (để phép "bỏ mặt sau camera" và sắp xa→gần có nghĩa)
  class ViewSoi
    attr_reader :camera, :ghi
    attr_writer :line_width, :drawing_color, :line_stipple
    def initialize; @camera = CamSoi.new; @ghi = []; @mau = nil; end
    def drawing_color=(c); @mau = c; end
    def screen_coords(p)
      c = @camera
      d = p - c.eye
      z = d.dot(c.direction)
      z = 1e-6 if z.abs < 1e-6
      f = 500.0 / z
      Geom::Point3d.new(500 + d.dot(c.xaxis) * f, 400 - d.dot(c.yaxis) * f, 0)
    end
    def draw2d(m, pts)
      raise "draw2d GL_LINES lẻ điểm (#{pts.size})" if m == GL_LINES && pts.size.odd?
      raise 'draw2d điểm không phải Point3d' unless pts.all? { |p| p.is_a?(Geom::Point3d) }
      @ghi << [:d2, m, pts.size, @mau]
    end
    def draw(m, pts); @ghi << [:d3, m, pts.size, @mau]; end
    def draw_polyline(*pts); @ghi << [:d3, :poly, pts.flatten.size, @mau]; end
    def draw_line(*pts); @ghi << [:d3, :line, pts.flatten.size, @mau]; end
    def draw_points(*a); end
    def draw_text(_p, s, *_a); @ghi << [:chu, s.to_s]; end
    def invalidate; end
    def refresh; end
    def model; Sketchup.active_model; end
    def vpwidth; 1000; end
    def vpheight; 800; end
  end
  class Color
    attr_reader :rgba
    def initialize(*a); @rgba = a; end
    def alpha; @rgba[3] || 255; end
    def red; @rgba[0]; end
    def green; @rgba[1]; end
    def blue; @rgba[2]; end
  end
  # raytest thật trên các hộp trong @tam (Group giả của nền thu_truc): tia chạm hộp gần nhất
  class ModelSoi < Model
    attr_reader :entities, :selection
    attr_reader :so_tia
    def initialize(tam = []); super(tam); @v = ViewSoi.new; @entities = []; @selection = []; @so_tia = 0; end
    def raytest(*a); @so_tia += 1; super; end
    def active_view; @v; end
    def select_tool(_t); end
    def active_path; nil; end
  end
end

module UI
  def self.messagebox(*_a); end
  def self.beep; end
end

# Hộp tấm (mm) → 12 cạnh dạng [[x,y,z],[x,y,z]] (inch) — đúng khuôn segs các tool đang giữ
def hop_segs(lo, hi)
  g = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].map do |a, b, c|
    [(a.zero? ? lo[0] : hi[0]) / 25.4, (b.zero? ? lo[1] : hi[1]) / 25.4, (c.zero? ? lo[2] : hi[2]) / 25.4]
  end
  [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].map { |a, b| [g[a], g[b]] }
end

def hop_goc(lo, hi)
  [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].map do |a, b, c|
    Geom::Point3d.new((a.zero? ? lo[0] : hi[0]) / 25.4, (b.zero? ? lo[1] : hi[1]) / 25.4, (c.zero? ? lo[2] : hi[2]) / 25.4)
  end
end

# Chạy một tool Xem như lúc bấm: activate → draw; tóm tắt những gì đã vẽ
def chay_tool(ten)
  m = Sketchup::ModelSoi.new
  Sketchup.gia_model = m
  tool = yield
  tool.activate
  v = m.active_view
  tool.draw(v)
  mo = v.ghi.count { |k, gl, _n, mau| k == :d2 && gl == GL_POLYGON && mau && mau.rgba == [246, 245, 241, 185] }
  khoi = v.ghi.count { |k, gl, n, mau| k == :d2 && gl == GL_POLYGON && n == 4 && mau && mau.rgba.size == 3 }
  net = v.ghi.count { |k, gl, _n, _m| k == :d2 && [GL_LINES, GL_LINE_STRIP].include?(gl) }
  # lớp mờ phải là lời vẽ 2D ĐẦU TIÊN (thứ vẽ sau nằm trên) — vẽ sau nét đỏ là che mất lỗi
  dau = v.ghi.find { |k, *_| k == :d2 }
  { ten: ten, mo: mo, khoi: khoi, net: net, mo_truoc: !dau.nil? && dau[3] && dau[3].rgba == [246, 245, 241, 185],
    cam: v.camera.so_lan_dat }
rescue StandardError => e
  { ten: ten, loi: "#{e.class}: #{e.message} | #{(e.backtrace || []).first(3).join(' | ')}" }
end
