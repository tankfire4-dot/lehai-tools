# encoding: UTF-8
# LeHai_Tools/shared/laser_snap.rb
#
# Con trỏ "thước laser" dùng chung cho các tool vẽ:
# Tại vị trí chuột, bắn ray xuyên qua group/component tìm face đang hover,
# rồi chiếu 2 tia ngang/dọc trong mặt phẳng face → giao với biên face.
# Từ 2 đoạn giao đó suy ra đường giữa dọc, đường giữa ngang và tâm thật.
#
# Ngoài face đang hover, laser còn quét các FACE ĐỒNG PHẲNG lân cận
# (kể cả nằm trong group/component khác): nếu đường giữa của tấm khác
# chạy qua gần con trỏ thì hút vào đó — ví dụ rê trên dải mặt của tấm
# ngang vẫn bắt được đường tim của tấm đứng bên dưới.

module LeHai
  module LaserSnap

    SNAP_PX   = 10     # ngưỡng hút vào đường giữa (pixel)
    NEAR_2D   = 79.0   # chỉ xét face đồng phẳng có tâm cách con trỏ < ~2m
    PLANE_TOL = 0.04   # lệch mặt phẳng cho phép ~1mm (inch)
    BAND_TOL  = 0.2    # chế độ khoá mặt: nhận face lệch tới ~5mm (mép thụt 2mm)
    CLIP_LEN  = 24.0   # chế độ khoá mặt: tia vẽ tối đa ~600mm quanh con trỏ
    MAX_FACES = 300    # chặn quét model quá lớn
    MAX_DEPTH = 3      # độ sâu group lồng nhau khi quét

    @plane_cache = nil

    module_function

    # Gọi sau khi tạo/sửa geometry để laser quét lại các face đồng phẳng
    def clear_cache!
      @plane_cache = nil
    end

    # Quét laser tại toạ độ chuột (x, y).
    # Trả về Hash hoặc nil nếu không hover lên face nào:
    #   :hit    — điểm chuột chạm face (world)
    #   :point  — điểm sau khi hút (world)
    #   :normal — pháp tuyến face (world)
    #   :snap_u — true: đã hút vào đường giữa DỌC  (giữa trái-phải)
    #   :snap_v — true: đã hút vào đường giữa NGANG (giữa trên-dưới)
    #   :line_u — [trái, phải] 2 đầu tia ngang
    #   :line_v — [dưới, trên] 2 đầu tia dọc
    #
    # plane (tuỳ chọn) = [origin, normal]: KHOÁ laser theo mặt phẳng vẽ —
    # mọi tia/điểm hút nằm trên mặt đó, tham chiếu lấy từ các face song song
    # trong dải ±BAND_TOL rồi chiếu phẳng về. Không truyền = hành vi cũ.
    def scan(view, x, y, plane = nil)
      return scan_locked(view, x, y, plane) if plane

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

      xs = crossings(pts2d, :u)
      ys = crossings(pts2d, :v)

      left  = xs.select { |t| t <= 0 }.max
      right = xs.select { |t| t >= 0 }.min
      bot   = ys.select { |t| t <= 0 }.max
      top   = ys.select { |t| t >= 0 }.min
      return nil unless left && right && bot && top

      thr   = view.pixels_to_model(SNAP_PX, hit)
      mid_u = (left + right) / 2.0   # offset tới đường giữa dọc của face hover
      mid_v = (bot + top)   / 2.0    # offset tới đường giữa ngang của face hover

      # Đường giữa của các tấm đồng phẳng lân cận (khi face hover không hút được)
      ext_u = ext_v = nil
      if mid_u.abs >= thr || mid_v.abs >= thr
        ext_u, ext_v = neighbor_centerlines(view.model, face, hit, n, u, v, thr)
      end

      du = dv = 0.0
      snap_u = snap_v = false
      lo_u, hi_u = left, right
      lo_v, hi_v = bot, top

      if mid_u.abs < thr
        du = mid_u
        snap_u = true
      elsif ext_u
        du     = ext_u[0]
        snap_u = true
        lo_v   = [lo_v, ext_u[1]].min   # kéo dài tia dọc phủ cả tấm nguồn
        hi_v   = [hi_v, ext_u[2]].max
      end

      if mid_v.abs < thr
        dv = mid_v
        snap_v = true
      elsif ext_v
        dv     = ext_v[0]
        snap_v = true
        lo_u   = [lo_u, ext_v[1]].min
        hi_u   = [hi_u, ext_v[2]].max
      end

      point = hit.offset(u, du).offset(v, dv)

      {
        hit:    hit,
        point:  point,
        normal: n,
        snap_u: snap_u,
        snap_v: snap_v,
        line_u: [point.offset(u, lo_u - du), point.offset(u, hi_u - du)],
        line_v: [point.offset(v, lo_v - dv), point.offset(v, hi_v - dv)]
      }
    end

    # Vẽ tia laser + chỉ báo snap. Gọi từ Tool#draw.
    def draw(view, s)
      return unless s

      # 2 tia laser mờ chạy qua con trỏ
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

    # Quét laser KHOÁ theo mặt phẳng vẽ (bước chọn điểm 2 của tool vẽ).
    # Con trỏ được chiếu thẳng lên mặt phẳng; biên/tim của các face song song
    # trong dải ±BAND_TOL (mép ván thụt 1-5mm vẫn tính) được chiếu phẳng về
    # mặt vẽ rồi mới tính giao và hút — cái thấy luôn nằm đúng mặt đang vẽ.
    def scan_locked(view, x, y, plane)
      origin = plane[0]
      n      = plane[1].normalize
      ray    = view.pickray(x, y)
      hit    = Geom.intersect_line_plane(ray, [origin, n])
      return nil unless hit

      u, v = plane_axes(n)
      thr  = view.pixels_to_model(SNAP_PX, hit)

      xs = []
      ys = []
      cands_u = []
      cands_v = []

      banded_faces(view.model, n, origin).each do |f, xf|
        next if f.deleted?
        pts = f.outer_loop.vertices.map do |vert|
          d = (xf * vert.position) - hit
          [d.dot(u), d.dot(v)]
        end
        next if pts.length < 3

        xs.concat(crossings(pts, :u))
        ys.concat(crossings(pts, :v))

        umin, umax = pts.map { |p| p[0] }.minmax
        vmin, vmax = pts.map { |p| p[1] }.minmax
        cu = (umin + umax) / 2.0
        cv = (vmin + vmax) / 2.0
        next if cu.abs > NEAR_2D || cv.abs > NEAR_2D
        cands_u << [cu, vmin, vmax] if cu.abs < thr
        cands_v << [cv, umin, umax] if cv.abs < thr
      end

      left  = xs.select { |t| t <= 0 }.max
      right = xs.select { |t| t >= 0 }.min
      bot   = ys.select { |t| t <= 0 }.max
      top   = ys.select { |t| t >= 0 }.min

      du = dv = 0.0
      snap_u = snap_v = false
      lo_u = left  || -CLIP_LEN
      hi_u = right ||  CLIP_LEN
      lo_v = bot   || -CLIP_LEN
      hi_v = top   ||  CLIP_LEN

      # Tâm cục bộ giữa 2 biên thật gần nhất: tim ván hoặc tim khoang trống
      if left && right && ((left + right) / 2.0).abs < thr
        du     = (left + right) / 2.0
        snap_u = true
      elsif (best = cands_u.min_by { |c| c[0].abs })
        du     = best[0]
        snap_u = true
        lo_v   = [lo_v, best[1]].min
        hi_v   = [hi_v, best[2]].max
      end

      if bot && top && ((bot + top) / 2.0).abs < thr
        dv     = (bot + top) / 2.0
        snap_v = true
      elsif (best = cands_v.min_by { |c| c[0].abs })
        dv     = best[0]
        snap_v = true
        lo_u   = [lo_u, best[1]].min
        hi_u   = [hi_u, best[2]].max
      end

      # Cắt tia quanh con trỏ — không kéo dài xuyên qua module khác
      lo_u = -CLIP_LEN if lo_u < -CLIP_LEN
      hi_u =  CLIP_LEN if hi_u >  CLIP_LEN
      lo_v = -CLIP_LEN if lo_v < -CLIP_LEN
      hi_v =  CLIP_LEN if hi_v >  CLIP_LEN

      point = hit.offset(u, du).offset(v, dv)

      {
        hit:    hit,
        point:  point,
        normal: n,
        snap_u: snap_u,
        snap_v: snap_v,
        line_u: [point.offset(u, lo_u - du), point.offset(u, hi_u - du)],
        line_v: [point.offset(v, lo_v - dv), point.offset(v, hi_v - dv)]
      }
    end

    # Danh sách [face, xform] song song và nằm trong dải ±BAND_TOL quanh
    # mặt phẳng khoá. Cache riêng theo key :band.
    def banded_faces(model, n, origin)
      key = [:band] + plane_key(n, origin)
      if @plane_cache && @plane_cache[:key] == key
        @plane_cache[:faces].delete_if { |f, _| f.deleted? }
        return @plane_cache[:faces]
      end

      faces = []
      collect_coplanar(model.active_entities, Geom::Transformation.new, n, origin, faces, 0, BAND_TOL)
      @plane_cache = { key: key, faces: faces }
      faces
    end

    # Tìm đường giữa của các face đồng phẳng khác đủ gần con trỏ.
    # Trả về [ext_u, ext_v]:
    #   ext_u = [offset_u tới đường giữa dọc,  vmin, vmax của tấm nguồn]
    #   ext_v = [offset_v tới đường giữa ngang, umin, umax của tấm nguồn]
    def neighbor_centerlines(model, hit_face, hit, n, u, v, thr)
      cands_u = []
      cands_v = []

      coplanar_faces(model, n, hit).each do |f, xf|
        next if f.deleted? || f == hit_face

        us = []
        vs = []
        f.outer_loop.vertices.each do |vert|
          d = (xf * vert.position) - hit
          us << d.dot(u)
          vs << d.dot(v)
        end
        umin, umax = us.minmax
        vmin, vmax = vs.minmax

        cu = (umin + umax) / 2.0
        cv = (vmin + vmax) / 2.0
        next if cu.abs > NEAR_2D || cv.abs > NEAR_2D   # tấm quá xa

        cands_u << [cu, vmin, vmax] if cu.abs < thr
        cands_v << [cv, umin, umax] if cv.abs < thr
      end

      [
        cands_u.min_by { |c| c[0].abs },
        cands_v.min_by { |c| c[0].abs }
      ]
    end

    # Danh sách [face, xform] đồng phẳng với mặt đang hover.
    # Cache theo mặt phẳng — rê chuột trên cùng một mặt không quét lại model.
    def coplanar_faces(model, n, hit)
      key = plane_key(n, hit)
      if @plane_cache && @plane_cache[:key] == key
        @plane_cache[:faces].delete_if { |f, _| f.deleted? }
        return @plane_cache[:faces]
      end

      faces = []
      collect_coplanar(model.active_entities, Geom::Transformation.new, n, hit, faces, 0)
      @plane_cache = { key: key, faces: faces }
      faces
    end

    def plane_key(n, pt)
      d = Geom::Vector3d.new(pt.x.to_f, pt.y.to_f, pt.z.to_f).dot(n)
      [n.x.round(4), n.y.round(4), n.z.round(4), d.round(2)]
    end

    def collect_coplanar(ents, xf, n, hit, out, depth, tol = PLANE_TOL)
      return if depth > MAX_DEPTH || out.length >= MAX_FACES
      ents.each do |e|
        return if out.length >= MAX_FACES
        case e
        when Sketchup::Face
          fn = xf * e.normal
          next if fn.length.zero?
          next unless fn.parallel?(n)
          p0 = xf * e.vertices.first.position
          next if ((p0 - hit).dot(n)).abs > tol
          out << [e, xf]
        when Sketchup::Group
          collect_coplanar(e.entities, xf * e.transformation, n, hit, out, depth + 1, tol)
        when Sketchup::ComponentInstance
          collect_coplanar(e.definition.entities, xf * e.transformation, n, hit, out, depth + 1, tol)
        end
      end
    end

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
