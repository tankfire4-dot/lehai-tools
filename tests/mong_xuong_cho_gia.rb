# encoding: UTF-8
# SketchUp GIẢ cho tests/mong_xuong_cho — chép từ scratch/mong-xuong-cho/thu_vien_that.rb (02/10) để test
# không phụ thuộc đồ tạm. Chữ ký theo tài liệu Trimble; KHÔNG mô phỏng kernel dựng hình.
class Numeric
  def mm; self / 25.4; end
  def to_mm; self * 25.4; end
end
module Geom
  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); x, y, z = x if x.is_a?(Array); @x, @y, @z = x.to_f, y.to_f, z.to_f; end
    def to_a; [x, y, z]; end
    def length; Math.sqrt(x * x + y * y + z * z); end
    def dot(o); x * o.x + y * o.y + z * o.z; end
    def reverse; Vector3d.new(-x, -y, -z); end
    def *(o); Vector3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x); end
  end
  class Point3d < Vector3d
    def -(o); Vector3d.new(x - o.x, y - o.y, z - o.z); end
    def distance(o); (self - o).length; end
    def ==(o); o.respond_to?(:x) && distance(o) < 1e-9; end
  end
  class Transformation
    attr_reader :r, :t
    def initialize(r = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]], t = [0.0, 0, 0]); @r, @t = r, t; end
    # cột = trục: T * e_i = axis_i
    def self.axes(o, x, y, z)
      c = [x, y, z].map(&:to_a)
      new((0..2).map { |i| (0..2).map { |j| c[j][i] } }, o.to_a)
    end
    def m(v); @r.map { |h| h[0] * v[0] + h[1] * v[1] + h[2] * v[2] }; end
    def inverse
      rt = (0..2).map { |i| (0..2).map { |j| @r[j][i] } }
      tt = Transformation.new(rt).m(@t).map(&:-@)
      Transformation.new(rt, tt)
    end
    def *(o)
      case o
      when Transformation then Transformation.new((0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| @r[i][k] * o.r[k][j] } } }, m(o.t).zip(@t).map { |a, b| a + b })
      when Point3d then Point3d.new(m(o.to_a).zip(@t).map { |a, b| a + b })
      when Vector3d then Vector3d.new(m(o.to_a))
      end
    end
  end
  class BoundingBox
    def initialize; @lo = nil; @hi = nil; end
    def add(*ps)
      ps.flatten.each { |p| a = p.to_a; @lo = @lo ? @lo.zip(a).map(&:min) : a.dup; @hi = @hi ? @hi.zip(a).map(&:max) : a.dup }
      self
    end
    def min; Geom::Point3d.new(@lo); end
    def max; Geom::Point3d.new(@hi); end
    def width; @hi[0] - @lo[0]; end
    def height; @hi[1] - @lo[1]; end
    def depth; @hi[2] - @lo[2]; end
  end
end
ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)
module Sketchup
  class Color; def initialize(*_a); end; end
  class Group; end
  class Face; PointInside = 1; PointOnEdge = 2; PointOnVertex = 4; end
end
module Sketchup; class Edge; end; end
