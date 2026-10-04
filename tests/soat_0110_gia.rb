# encoding: UTF-8
# SketchUp GIẢ tối thiểu cho tests/soat_0110 — chỉ đủ cho các hàm THUẦN TÍNH của đợt soát 01/10:
# hệ số scale (Transformation * Vector), hộp bao (width/height/depth), definition.bounds, attribute.
# Chữ ký theo tài liệu Trimble; KHÔNG mô phỏng vẽ / chẻ mặt / dialog.

class Numeric
  def mm; self / 25.4; end
  def to_mm; self * 25.4; end
  def to_l; to_f; end
end

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def to_a; [x, y, z]; end
    def -(o); Vector3d.new(x - o.x, y - o.y, z - o.z); end
    def distance(o); (self - o).length; end
  end
  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def length; Math.sqrt(x * x + y * y + z * z); end
    def -(o); Vector3d.new(x - o.x, y - o.y, z - o.z); end
    def +(o); Vector3d.new(x + o.x, y + o.y, z + o.z); end
  end
  # r = ma trận 3×3 (xoay + scale), t = dời
  class Transformation
    attr_reader :r, :t
    def initialize(r = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]], t = [0.0, 0, 0]); @r = r; @t = t; end
    def self.scaling(sx, sy, sz); new([[sx.to_f, 0, 0], [0, sy.to_f, 0], [0, 0, sz.to_f]]); end
    def self.xoay_z_scale(do_, sx)   # xoay quanh trục lên rồi giãn theo trục x LOCAL
      c = Math.cos(do_ * Math::PI / 180); s = Math.sin(do_ * Math::PI / 180)
      new([[c * sx, -s, 0], [s * sx, c, 0], [0, 0, 1.0]])
    end
    def m(v); @r.map { |h| h[0] * v[0] + h[1] * v[1] + h[2] * v[2] }; end
    def *(o)
      case o
      when Vector3d then Vector3d.new(*m(o.to_a_v))
      when Point3d then Point3d.new(*m(o.to_a).zip(@t).map { |a, b| a + b })
      when Transformation
        r2 = (0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| @r[i][k] * o.r[k][j] } } }
        Transformation.new(r2, m(o.t).zip(@t).map { |a, b| a + b })
      end
    end
  end
  class Vector3d; def to_a_v; [x, y, z]; end; end
  class BoundingBox
    def initialize; @lo = nil; @hi = nil; end
    def add(*ps)
      ps.flatten.each do |p|
        if p.is_a?(BoundingBox) then add(p.min, p.max) unless p.empty?; next end
        a = p.to_a
        @lo = @lo ? @lo.zip(a).map(&:min) : a.dup
        @hi = @hi ? @hi.zip(a).map(&:max) : a.dup
      end
      self
    end
    def empty?; @lo.nil?; end
    def min; Point3d.new(*@lo); end
    def max; Point3d.new(*@hi); end
    def width; @hi[0] - @lo[0]; end
    def height; @hi[1] - @lo[1]; end
    def depth; @hi[2] - @lo[2]; end
    def center; Point3d.new(*(0..2).map { |i| (@lo[i] + @hi[i]) / 2.0 }); end
  end
end
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)

module Sketchup
  class Color; def initialize(*_a); end; end
  class Entity
    @@id = 0
    def entityID; @eid ||= (@@id += 1); end
    def deleted?; false; end
    def valid?; true; end
    def get_attribute(d, k, dv = nil); (@attr ||= {}).fetch([d, k], dv); end
    def set_attribute(d, k, v); (@attr ||= {})[[d, k]] = v; end
  end
  class Face < Entity
    def initialize(lo, hi); @bb = Geom::BoundingBox.new.add(Geom::Point3d.new(*lo), Geom::Point3d.new(*hi)); end
    def bounds; @bb; end
  end
  class Definition < Entity
    attr_accessor :name, :entities
    def initialize(name, ents); @name = name; @entities = ents; end
    def bounds; Geom::BoundingBox.new.add(@entities.map(&:bounds)); end
  end
  # tấm hộp lo..hi (mm) — 6 mặt quy về 1 hộp
  def self.hop(lo, hi)
    l = lo.map(&:mm); h = hi.map(&:mm)
    [Face.new(l, [h[0], h[1], l[2]]), Face.new([l[0], l[1], h[2]], h), Face.new(l, [h[0], l[1], h[2]]),
     Face.new([l[0], h[1], l[2]], h), Face.new(l, [l[0], h[1], h[2]]), Face.new([h[0], l[1], l[2]], h)]
  end
  class Group < Entity
    attr_accessor :name, :transformation, :definition
    def initialize(ents, tr = Geom::Transformation.new, name = '')
      @definition = Definition.new(name, ents); @transformation = tr; @name = name
    end
    def entities; @definition.entities; end
    def locked?; false; end
  end
  class ComponentInstance < Group; end

  # ── Thêm 04/10 cho Tô tay Dán Cạnh: đỉnh mặt, definition DÙNG CHUNG, make_unique ─────────────
  # make_unique theo tài liệu Trimble: đang dùng chung → definition riêng (chép ruột); vốn riêng → không làm gì.
  class Vertex
    attr_reader :position
    def initialize(p); @position = p; end
  end
  class Face
    attr_accessor :material
    def vertices
      lo = @bb.min.to_a; hi = @bb.max.to_a
      [lo[0], hi[0]].product([lo[1], hi[1]], [lo[2], hi[2]]).uniq.map { |p| Vertex.new(Geom::Point3d.new(*p)) }
    end
    def attribute_dictionary(d); (@attr || {}).keys.any? { |k| k[0] == d } ? d : nil; end
    def delete_attribute(d); (@attr || {}).delete_if { |k, _| k[0] == d }; end
    def ban_chep
      f = Face.new(@bb.min.to_a, @bb.max.to_a)
      f.instance_variable_set(:@attr, (@attr || {}).dup); f.material = material; f
    end
  end
  class Definition
    def instances; @instances ||= []; end
  end
  class Group
    alias_method :khoi_tao_cu, :initialize
    def initialize(*a); khoi_tao_cu(*a); @definition.instances << self; end
    def definition=(d); @definition.instances.delete(self); @definition = d; d.instances << self; end
    def make_unique
      return self if @definition.instances.size <= 1
      self.definition = Definition.new(@definition.name, @definition.entities.map { |e| e.respond_to?(:ban_chep) ? e.ban_chep : e })
      self
    end
  end
end
