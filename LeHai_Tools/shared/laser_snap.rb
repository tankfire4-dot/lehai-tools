# encoding: UTF-8
# LeHai_Tools/shared/laser_snap.rb
#
# Con trỏ "thước laser" dùng chung cho các tool vẽ:
# Tại vị trí chuột, bắn ray xuyên qua group/component tìm face đang hover,
# rồi chiếu 2 tia ngang/dọc trong mặt phẳng face → giao với biên face.
# Từ 2 đoạn giao đó suy ra đường giữa dọc, đường giữa ngang và tâm thật
# của face (giao 2 đường giữa) — hoạt động với mọi hình dạng face,
# kể cả face nằm sâu trong group lồng nhau.

module LeHai
  module LaserSnap

    SNAP_PX = 10  # ngưỡng hút vào đường giữa (pixel)

    module_function

    # Quét laser tại toạ độ chuột (x, y).
    # Trả về Hash hoặc nil nếu không hover lên face nào:
    #   :hit    — điểm chuột chạm face (world)
    #   :point  — điểm sau khi hút (world): đã kéo về đường giữa/tâm nếu đủ gần
    #   :normal — pháp tuyến face (world)
    #   :snap_u — true: đã hút vào đường giữa DỌC  (giữa trái-phải)
    #   :snap_v — true: đã hút vào đường giữa NGANG (giữa trên-dưới)
    #   :line_u — [trái, phải] 2 đầu tia ngang trên face
    #   :line_v — [dưới, trên] 2 đầu tia dọc trên face
    def scan(view, x, y)
      ray    = view.pickray(x, y)
      result = view.model.raytest(ray)
      return nil unless result

      hit, path = result
      face = path.last
      return nil unless face.is_a?(Sketchup::Face)

      xform = Geom::Transformation.new
      path[0..-2].each { |e| xform = xform * e.transformation if e.respond_to?(:transformation) }

      n    = world_normal(face, xform)
      u, v = plane_axes(n)

      pts2d = boundary_2d(face, xform, hit, u, v)
      return nil if pts2d.length < 3

      xs = crossings(pts2d, :u)   # giao tia ngang → offset theo u
      ys = crossings(pts2d, :v)   # giao tia dọc  → offset theo v

      left  = xs.select { |t| t <= 0 }.max
      right = xs.select { |t| t >= 0 }.min
      bot   = ys.select { |t| t <= 0 }.max
      top   = ys.select { |t| t >= 0 }.min
      return nil unless left && right && bot && top

      thr    = view.pixels_to_model(SNAP_PX, hit)
      mid_u  = (left + right) / 2.0   # offset từ chuột tới đường giữa dọc
      mid_v  = (bot + top)   / 2.0    # offset từ chuột tới đường giữa ngang
      snap_u = mid_u.abs < thr
      snap_v = mid_v.abs < thr

      du    = snap_u ? mid_u : 0.0
      dv    = snap_v ? mid_v : 0.0
      point = hit.offset(u, du).offset(v, dv)

      {
        hit:    hit,
        point:  point,
        normal: n,
        snap_u: snap_u,
        snap_v: snap_v,
        line_u: [point.offset(u, left - du), point.offset(u, right - du)],
        line_v: [point.offset(v, bot  - dv), point.offset(v, top   - dv)]
      }
    end

    # Vẽ tia laser + chỉ báo snap. Gọi từ Tool#draw.
    def draw(view, s)
      return unless s

      # 2 tia laser mờ chạy qua con trỏ, cắt hết bề mặt face
      view.line_width    = 1
      view.line_stipple  = '-'
      view.drawing_color = Sketchup::Color.new(0, 180, 255, 170)
      view.draw(GL_LINES, s[:line_u])
      view.draw(GL_LINES, s[:line_v])
      view.line_stipple  = ''

      # Khi hút vào đường giữa → tia tương ứng sáng vàng đậm
      if s[:snap_u]
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(255, 200, 0)
        view.draw(GL_LINES, s[:line_v])
      end
      if s[:snap_v]
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(255, 200, 0)
        view.draw(GL_LINES, s[:line_u])
      end

      # Chấm vàng: to khi đúng tâm, nhỏ khi mới hút 1 trục
      if s[:snap_u] && s[:snap_v]
        view.draw_points([s[:point]], 16, 4, Sketchup::Color.new(255, 200, 0))
      elsif s[:snap_u] || s[:snap_v]
        view.draw_points([s[:point]], 11, 4, Sketchup::Color.new(255, 200, 0))
      end
    end

    # Điểm đã hút nếu đang snap, nil nếu không
    def snapped_point(s)
      return nil unless s && (s[:snap_u] || s[:snap_v])
      s[:point]
    end

    # Thêm các điểm laser vào BoundingBox (cho Tool#getExtents)
    def add_extents(s, bb)
      return bb unless s
      bb.add(s[:line_u][0]); bb.add(s[:line_u][1])
      bb.add(s[:line_v][0]); bb.add(s[:line_v][1])
      bb
    end

    # --- nội bộ ---------------------------------------------------

    def world_normal(face, xform)
      (xform * face.normal).normalize
    rescue StandardError
      face.normal
    end

    # Trục u (ngang) / v (dọc) trong mặt phẳng có pháp tuyến n
    def plane_axes(n)
      return [X_AXIS, Y_AXIS] if n.parallel?(Z_AXIS)
      u = n.cross(Z_AXIS)
      return [X_AXIS, Y_AXIS] if u.length.zero?
      u.normalize!
      [u, u.cross(n).normalize]
    end

    # Đỉnh biên ngoài của face quy về toạ độ 2D (gốc = điểm chuột chạm face)
    def boundary_2d(face, xform, origin, u, v)
      face.outer_loop.vertices.map do |vert|
        d = (xform * vert.position) - origin
        [d.dot(u), d.dot(v)]
      end
    end

    # Giao của biên polygon với trục đi qua gốc:
    # axis == :u → tia ngang (v=0), trả về các offset theo u
    # axis == :v → tia dọc  (u=0), trả về các offset theo v
    def crossings(pts, axis)
      ai = axis == :u ? 0 : 1
      bi = axis == :u ? 1 : 0
      out = []
      pts.each_with_index do |p1, i|
        p2 = pts[(i + 1) % pts.length]
        b1 = p1[bi]
        b2 = p2[bi]
        next if (b1 > 0) == (b2 > 0)   # cạnh không cắt qua trục
        denom = b1 - b2
        next if denom.abs < 1.0e-12    # cạnh song song nằm trên trục
        t = b1 / denom.to_f
        out << p1[ai] + t * (p2[ai] - p1[ai])
      end
      out
    end

  end
end
