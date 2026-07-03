# encoding: UTF-8
# Kiểm Tra Liên Kết (rãnh hậu + ngàm): trên MÔ HÌNH 3D, khi 2 tấm ăn/chồng vào
# nhau ở độ sâu đặc trưng thì người dựng đang MUỐN làm liên kết bằng ABF:
#   - ăn ~10mm  → rãnh hậu  → phải có group con "_ABF_Intersect" tag "...PHAYRANHHAU..."
#   - ăn ~17.5mm → ngàm     → phải có group con "_ABF_Intersect" tag "...NGAM..."
# Cặp ăn đúng độ sâu mà THIẾU group liên kết tương ứng → báo lỗi (phôi sẽ phế).
#
# Cách dò: mỗi tấm là hộp bao trục (AABB) ở tọa độ thế giới (tủ thẳng trục).
# Độ ăn sâu = chiều NHỎ NHẤT của khối giao. Chặn nhầm "chồng mặt lớn" (trùng
# tấm / ghép 2 lớp) bằng điều kiện vùng giao phải CỤC BỘ. Bỏ qua nhánh nesting.
# CHỈ ĐỌC, không sửa model.
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'

module TK
  module JointCheck

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    MM        = 25.4

    # ── Nhận diện tấm ván (mm) ──
    MIN_TH_MM   = 3.0
    MAX_TH_MM   = 40.0
    MIN_SIDE_MM = 40.0

    # ── Band độ ăn sâu đặc trưng (mm) ──
    RANHHAU_LO = 8.0
    RANHHAU_HI = 12.5
    NGAM_LO    = 15.0
    NGAM_HI    = 20.0

    MID_MAX_MM = 250.0    # chiều GIỮA của khối giao ≤ mức này = liên kết cục bộ
    NEAR_MM    = 25.0     # nới vùng giao khi dò điểm Intersect

    # ── Đo "đâm xuyên gỗ đặc" để tách KHẤU TAY (đã khoét) khỏi CHƯA LÀM ──
    # ABF chỉ dán nhãn (gỗ vẫn đâm xuyên) → dựa dấu ABF. Khấu tay cắt gỗ thật
    # (không đâm xuyên) → dựa hình học. Đã xử lý = có dấu ABF HOẶC đâm xuyên thấp.
    SAMPLE_N       = 3     # lưới N×N×N điểm mẫu trong vùng giao
    COLLIDE_THRESH = 0.4   # tỉ lệ điểm nằm trong CẢ 2 tấm ≥ mức này = còn đâm xuyên = chưa khoét

    COLOR_BAD  = Sketchup::Color.new(255, 140, 0)    # cam-đỏ — RÃNH HẬU thiếu (lỗi)
    COLOR_GAP  = Sketchup::Color.new(255, 60, 0)     # đỏ-cam — vùng giao (lỗi)
    COLOR_WARN = Sketchup::Color.new(230, 160, 0)    # vàng — NGÀM thiếu (cảnh báo, có thể khấu tay)
    COLOR_OK   = Sketchup::Color.new(0, 170, 80)     # xanh lá — mối ĐÃ làm liên kết
    COLOR_OKGAP= Sketchup::Color.new(0, 210, 110)    # xanh sáng — vùng giao (đã làm)

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    # made = true nếu mối ĐÃ có liên kết ABF (để xem lại chỗ làm đúng)
    Vio = Struct.new(:kind, :name_a, :name_b, :pen, :segs_a, :segs_b, :gap_segs, :made)

    # =========================================================
    #  QUÉT
    # =========================================================
    # ── Cache 1 lần quét (dashboard gọi audit 2 lần: rãnh hậu + ngàm) ──
    def self.clear_cache
      @cache = nil
    end

    def self.cached
      @cache ||= begin
        Sketchup.set_status_text('Đang quét liên kết (đo đâm xuyên)...', SB_PROMPT)
        planks, inters = collect_all
        joints = find_joints(planks, inters)
        Sketchup.set_status_text('', SB_PROMPT)
        { planks_n: planks.size, joints: joints }
      end
    end

    # kind = nil (cả 2) / :ranhhau / :ngam
    def self.run(kind = nil)
      clear_cache
      c = cached
      joints = kind ? c[:joints].select { |v| v.kind == kind } : c[:joints]

      return UI.messagebox('Không tìm thấy tấm ván nào để kiểm tra.') if c[:planks_n].zero?
      missing = joints.reject(&:made)
      if !missing.empty?
        Sketchup.active_model.select_tool(ReviewTool.new(missing, :loi))
      else
        made = joints.select(&:made)
        if made.empty?
          UI.messagebox("✓ Không thấy mối #{kind_label(kind)} nào (đã soi #{c[:planks_n]} tấm).")
        else
          Sketchup.active_model.select_tool(ReviewTool.new(made, :ok))
        end
      end
    end

    def self.scan
      cached[:joints].reject(&:made)
    end

    def self.kind_label(kind)
      case kind
      when :ranhhau then 'rãnh hậu'
      when :ngam    then 'ngàm'
      else 'rãnh hậu / ngàm'
      end
    end

    # ── Adapter cho bộ "Check Chốt Sản Xuất" (TK::PreExportCheck) ───
    def self.audit(kind = nil)
      c = cached
      return { status: :na, count: 0, message: 'Không tìm thấy tấm ván nào để kiểm tra.' } if c[:planks_n].zero?
      joints  = kind ? c[:joints].select { |v| v.kind == kind } : c[:joints]
      missing = joints.reject(&:made)
      made    = joints.size - missing.size
      return { status: :pass, count: 0, message: "Đã soi #{c[:planks_n]} tấm — #{made} mối #{kind_label(kind)} đã làm, không thiếu." } if missing.empty?
      # Giờ đã tách khấu-tay khỏi chưa-làm (đo đâm xuyên) → mối còn lại là LỖI thật (đỏ).
      { status: :fail, count: missing.size, message: "#{missing.size} mối #{kind_label(kind)}: 2 tấm đâm xuyên chưa khoét (chưa ABF, chưa khấu tay)." }
    end

    def self.review(kind = nil)
      run(kind)
    end

    # =========================================================
    #  TÌM MỌI MỐI LIÊN KẾT (đã làm + thiếu)
    # =========================================================
    def self.find_joints(planks, inters)
      rh = inters.select { |x| x[:kind] == :ranhhau }
      ng = inters.select { |x| x[:kind] == :ngam }
      planks = planks.sort_by { |p| p[:aabb][0] }   # sweep theo minX
      n = planks.size
      out  = []
      seen = {}                                      # khử trùng: mỗi cặp 1 mối
      i = 0
      while i < n
        a = planks[i]; ax_hi = a[:aabb][3]
        j = i + 1
        while j < n
          b = planks[j]
          break if b[:aabb][0] > ax_hi
          v = pair_joint(a, b, rh, ng)
          if v
            key = [v.name_a, v.name_b].sort.join(' || ')
            unless seen[key]
              seen[key] = true
              out << v
            end
          end
          j += 1
        end
        i += 1
      end
      out
    end

    # trả về Vio (kèm .made) nếu cặp là mối liên kết đặc trưng, ngược lại nil
    def self.pair_joint(a, b, rh, ng)
      ov = overlap_box(a[:aabb], b[:aabb])
      return nil unless ov
      dims = [ov[3] - ov[0], ov[4] - ov[1], ov[5] - ov[2]].sort  # inch tăng dần
      pen_mm = dims[0] * MM
      mid_mm = dims[1] * MM
      return nil if mid_mm > MID_MAX_MM              # chồng mặt lớn -> không phải mộng/rãnh

      kind = classify(pen_mm)
      return nil unless kind

      # Đã xử lý = có dấu ABF (sẽ phay khi xuất) HOẶC gỗ đã khoét thật (khấu tay).
      # Chỉ đo đâm xuyên (chậm) khi KHÔNG có dấu ABF — cặp có ABF khỏi cần đo.
      made = has_intersect?(kind == :ranhhau ? rh : ng, ov)
      unless made
        frac = collide_frac(ov, tris_of(a), tris_of(b))
        made = frac < COLLIDE_THRESH   # đâm xuyên thấp = đã khoét (khấu tay)
      end

      Vio.new(kind, a[:name], b[:name], pen_mm.round(1),
              aabb_box_segs(a[:aabb]), aabb_box_segs(b[:aabb]), aabb_box_segs(ov), made)
    end

    # =========================================================
    #  ĐO ĐÂM XUYÊN GỖ ĐẶC (point-in-solid bằng bắn tia +X)
    # =========================================================
    # tỉ lệ điểm mẫu nằm trong CẢ 2 khối tấm (0..1)
    def self.collide_frac(ov, ta, tb)
      n = SAMPLE_N
      dx = ov[3] - ov[0]; dy = ov[4] - ov[1]; dz = ov[5] - ov[2]
      both = 0; total = 0
      (0...n).each do |i|
        x = ov[0] + dx * (i + 0.5) / n
        (0...n).each do |j|
          y = ov[1] + dy * (j + 0.5) / n
          (0...n).each do |k|
            z = ov[2] + dz * (k + 0.5) / n
            total += 1
            both += 1 if point_inside?(x, y, z, ta) && point_inside?(x, y, z, tb)
          end
        end
      end
      total.zero? ? 0.0 : both.to_f / total
    end

    # điểm (x,y,z) nằm trong khối đặc? tia +X, đếm giao tam giác lẻ = trong.
    # tris đã kèm bbox Y-Z + xmax để lọc nhanh trước khi tính giao.
    def self.point_inside?(x, y, z, tris)
      cnt = 0
      tris.each do |tr|
        next if y < tr[3] || y > tr[4] || z < tr[5] || z > tr[6] || tr[7] < x
        cnt += 1 if ray_x_hit?(x, y, z, tr[0], tr[1], tr[2])
      end
      cnt.odd?
    end

    # tia (x,y,z)+X cắt tam giác (a,b,c)? (Möller–Trumbore, d = (1,0,0))
    def self.ray_x_hit?(px, py, pz, a, b, c)
      e1y = b[1] - a[1]; e1z = b[2] - a[2]; e1x = b[0] - a[0]
      e2y = c[1] - a[1]; e2z = c[2] - a[2]; e2x = c[0] - a[0]
      hy = -e2z; hz = e2y                 # h = d × e2 = (0, -e2z, e2y)
      aa = e1y * hy + e1z * hz            # e1 · h
      return false if aa.abs < 1e-12
      ff = 1.0 / aa
      sy = py - a[1]; sz = pz - a[2]; sx = px - a[0]
      u = ff * (sy * hy + sz * hz)
      return false if u < 0.0 || u > 1.0
      qx = sy * e1z - sz * e1y           # q = s × e1
      v = ff * qx                         # d · q = qx
      return false if v < 0.0 || (u + v) > 1.0
      t = ff * (e2x * qx + (sz * e1x - sx * e1z) * e2y + (sx * e1y - sy * e1x) * e2z)
      t > 1e-7
    end

    # tam giác world của tấm (lazy — chỉ dựng khi cần đo đâm xuyên)
    def self.tris_of(plank)
      plank[:tris] ||= build_tris(plank[:faces], plank[:te])
    end

    def self.build_tris(faces, te)
      out = []
      return out unless faces
      faces.each do |f|
        next if f.deleted?
        mesh = f.mesh
        mesh.polygons.each do |poly|
          idx = poly.map(&:abs)
          next if idx.size < 3
          a = te * mesh.point_at(idx[0])
          pa = [a.x, a.y, a.z]
          (1...(idx.size - 1)).each do |k|
            b = te * mesh.point_at(idx[k]); c = te * mesh.point_at(idx[k + 1])
            pb = [b.x, b.y, b.z]; pc = [c.x, c.y, c.z]
            ymin = pa[1] < pb[1] ? (pa[1] < pc[1] ? pa[1] : pc[1]) : (pb[1] < pc[1] ? pb[1] : pc[1])
            ymax = pa[1] > pb[1] ? (pa[1] > pc[1] ? pa[1] : pc[1]) : (pb[1] > pc[1] ? pb[1] : pc[1])
            zmin = pa[2] < pb[2] ? (pa[2] < pc[2] ? pa[2] : pc[2]) : (pb[2] < pc[2] ? pb[2] : pc[2])
            zmax = pa[2] > pb[2] ? (pa[2] > pc[2] ? pa[2] : pc[2]) : (pb[2] > pc[2] ? pb[2] : pc[2])
            xmax = pa[0] > pb[0] ? (pa[0] > pc[0] ? pa[0] : pc[0]) : (pb[0] > pc[0] ? pb[0] : pc[0])
            out << [pa, pb, pc, ymin, ymax, zmin, zmax, xmax]
          end
        end
      end
      out
    end

    def self.classify(pen_mm)
      return :ranhhau if pen_mm >= RANHHAU_LO && pen_mm <= RANHHAU_HI
      return :ngam    if pen_mm >= NGAM_LO && pen_mm <= NGAM_HI
      nil
    end

    # có điểm Intersect đúng loại nằm trong (vùng giao nới NEAR_MM)?
    def self.has_intersect?(list, ov)
      near = NEAR_MM / MM
      cx = (ov[0] + ov[3]) / 2; cy = (ov[1] + ov[4]) / 2; cz = (ov[2] + ov[5]) / 2
      list.any? do |ic|
        (ic[:c][0] - cx).abs < (ov[3] - ov[0]) / 2 + near &&
          (ic[:c][1] - cy).abs < (ov[4] - ov[1]) / 2 + near &&
          (ic[:c][2] - cz).abs < (ov[5] - ov[2]) / 2 + near
      end
    end

    # giao 2 AABB -> [minx,miny,minz,maxx,maxy,maxz] hoặc nil nếu không giao khối
    def self.overlap_box(a, b)
      lox = a[0] > b[0] ? a[0] : b[0]; hix = a[3] < b[3] ? a[3] : b[3]
      return nil if hix - lox <= 0
      loy = a[1] > b[1] ? a[1] : b[1]; hiy = a[4] < b[4] ? a[4] : b[4]
      return nil if hiy - loy <= 0
      loz = a[2] > b[2] ? a[2] : b[2]; hiz = a[5] < b[5] ? a[5] : b[5]
      return nil if hiz - loz <= 0
      [lox, loy, loz, hix, hiy, hiz]
    end

    # =========================================================
    #  DUYỆT MÔ HÌNH — thu tấm ván + điểm Intersect
    # =========================================================
    def self.collect_all
      planks = []; inters = []
      collect(Sketchup.active_model.entities, Geom::Transformation.new, 0, planks, inters, false)
      [planks, inters]
    end

    # in_plank = đang ở BÊN TRONG một tấm ván rồi → không lấy mảnh con làm tấm
    # nữa (tấm là lá), nhưng vẫn chui vào để nhặt _ABF_Intersect.
    def self.collect(entities, t, depth, planks, inters, in_plank)
      return if depth > 40
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.name.to_s.include?(NEST_HINT)
        te   = t * e.transformation
        ents = ents_of(e)
        next unless ents

        register_intersect(e, te, ents, inters)
        is_plank = in_plank ? false : register_plank(e, te, ents, planks)

        collect(ents, te, depth + 1, planks, inters, in_plank || is_plank)
      end
    end

    def self.register_intersect(e, te, ents, inters)
      return unless e.name.to_s =~ /intersect/i
      ab = world_aabb(ents, te)
      return unless ab
      tag  = (e.layer.name rescue '')
      kind = if tag =~ /phayranhhau/i then :ranhhau
             elsif tag =~ /ngam/i      then :ngam
             else :other end
      inters << { kind: kind, c: [(ab[0] + ab[3]) / 2, (ab[1] + ab[4]) / 2, (ab[2] + ab[5]) / 2] }
    end

    # trả về true nếu e đúng là 1 tấm ván (đã ghi vào planks)
    def self.register_plank(e, te, ents, planks)
      ab = world_aabb(ents, te)
      return false unless ab
      dims = [ab[3] - ab[0], ab[4] - ab[1], ab[5] - ab[2]].sort
      th = dims[0] * MM; mid = dims[1] * MM; big = dims[2] * MM
      return false unless th >= MIN_TH_MM && th <= MAX_TH_MM && mid >= MIN_SIDE_MM && big >= MIN_SIDE_MM
      # giữ faces + transform để LAZY dựng tam giác world khi cần đo đâm xuyên
      planks << { name: label(e), aabb: ab, faces: ents.grep(Sketchup::Face), te: te }
      true
    end

    # world AABB tu face rieng cua e -> [minx,miny,minz,maxx,maxy,maxz] (inch)
    def self.world_aabb(ents, te)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return nil if bb.empty?
      mn = bb.min; mx = bb.max
      wbb = Geom::BoundingBox.new
      CORNERS.each do |cx, cy, cz|
        p = Geom::Point3d.new(cx.zero? ? mn.x : mx.x, cy.zero? ? mn.y : mx.y, cz.zero? ? mn.z : mx.z)
        wbb.add(te * p)
      end
      [wbb.min.x, wbb.min.y, wbb.min.z, wbb.max.x, wbb.max.y, wbb.max.z]
    end

    def self.aabb_box_segs(ab)
      pts = CORNERS.map do |cx, cy, cz|
        [cx.zero? ? ab[0] : ab[3], cy.zero? ? ab[1] : ab[4], cz.zero? ? ab[2] : ab[5]]
      end
      EDGES12.map { |a, b| [pts[a], pts[b]] }
    end

    def self.label(e)
      n = e.name.to_s
      return n.sub(/\A__/, '') unless n.empty?
      if e.is_a?(Sketchup::ComponentInstance)
        dn = e.definition.name.to_s
        return dn unless dn.empty?
      end
      '(tấm không tên)'
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # =========================================================
    #  TOOL XEM TỪNG MỐI (thiếu = cam / đã làm = xanh)
    # =========================================================
    class ReviewTool
      # mode = :loi (thiếu) / :ok (đã làm). Màu tô quyết định THEO LOẠI mối:
      # rãnh hậu = cam-đỏ (lỗi), ngàm = vàng (cảnh báo), đã làm = xanh.
      def initialize(vios, mode = :loi)
        @vios = vios
        @mode = mode
        @idx  = 0
        pick_color(0)
      end

      def pick_color(_i)
        if @mode == :ok
          @color = COLOR_OK; @gapcol = COLOR_OKGAP
        else
          @color = COLOR_BAD; @gapcol = COLOR_GAP
        end
      end

      def activate; focus(0); end
      def deactivate(view); view.invalidate; end
      def resume(view); update_status; view.invalidate; end
      def getExtents; @bounds; end
      def onCancel(_r, view); quit(view); end

      def onKeyDown(key, _rep, _flags, view)
        case key
        when 27 then quit(view)
        when 39, 38 then step(1, view)
        when 37, 40 then step(-1, view)
        end
        false
      end

      def enableVCB?; true; end

      def onUserText(text, view)
        n = text.to_s.scan(/\d+/).first
        return unless n
        i = n.to_i - 1
        return UI.messagebox("Chỉ có #{@vios.size} mối (1–#{@vios.size}).") if i < 0 || i >= @vios.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_outline(view, @draw_a, 2)
        draw_outline(view, @draw_b, 2)
        draw_gap(view)
        draw_banner(view)
      end

      def focus(i)
        @idx = i
        pick_color(i)
        v = @vios[i]
        @draw_a = flatten(v.segs_a)
        @draw_b = flatten(v.segs_b)
        @draw_g = flatten(v.gap_segs)
        @bounds = focus_bounds
        frame(@bounds)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def step(dir, view)
        focus((@idx + dir) % @vios.size)
        view.invalidate
      end

      def flatten(segs)
        pts = []
        segs.each { |a, b| pts << Geom::Point3d.new(*a) << Geom::Point3d.new(*b) }
        pts
      end

      def focus_bounds
        bb = Geom::BoundingBox.new
        @draw_g.each { |p| bb.add(p) }
        # ôm gọn quanh vùng giao + lề 150mm để thấy ngữ cảnh 2 tấm (không ôm cả tấm dài)
        c = bb.center
        m = 150.0 / 25.4   # 150mm -> inch
        bb.add(c.offset(Geom::Vector3d.new(m, m, m)))
        bb.add(c.offset(Geom::Vector3d.new(-m, -m, -m)))
        bb
      end

      def draw_outline(view, pts, w)
        return if pts.empty?
        view.line_width = w
        view.drawing_color = @color
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end

      def draw_gap(view)
        return if @draw_g.empty?
        view.line_width = 4
        view.drawing_color = @gapcol
        view.draw(GL_LINES, @draw_g)
        view.draw2d(GL_LINES, @draw_g.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v = @vios[@idx]
        loai = v.kind == :ranhhau ? 'RÃNH HẬU' : 'NGÀM'
        if @mode == :ok
          l1 = "Đã làm #{loai}   (mối #{@idx + 1}/#{@vios.size})"
          l3 = "Hai tấm ăn nhau #{v.pen}mm — đã có liên kết ABF ✓"
          title_col = Sketchup::Color.new(120, 240, 160)
          info_col  = Sketchup::Color.new(150, 255, 190)
        else
          l1 = "Thiếu #{loai}   (mối #{@idx + 1}/#{@vios.size})"
          l3 = "Hai tấm đâm xuyên #{v.pen}mm — chưa khoét (chưa ABF, chưa khấu tay)"
          title_col = Sketchup::Color.new(255, 180, 90)
          info_col  = Sketchup::Color.new(255, 210, 60)
        end
        l2 = "#{v.name_a}  ↔  #{v.name_b}"
        l4 = '← → đổi mối  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, @color)
        txt(view, 34, 26, l1, title_col, 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, info_col, 12, false)
        txt(view, 34, 90, l4, Sketchup::Color.new(200, 200, 200), 11, false)
      end

      def draw_box2d(view, x, y, w, h, color)
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = color
        view.draw2d(GL_POLYGON, pts)
      end

      def txt(view, x, y, s, color, size, bold)
        view.draw_text(Geom::Point3d.new(x, y, 0), s, color: color, font: 'Arial', size: size, bold: bold)
      end

      def frame(bb)
        cam = Sketchup.active_model.active_view.camera
        ctr = bb.center
        diag = bb.diagonal
        diag = 100.0 if diag < 1.0
        if cam.perspective?
          fov = cam.fov * Math::PI / 180.0
          dist = (diag / 2.0) / Math.tan(fov / 2.0) * 1.5
          cam.set(ctr.offset(cam.direction.reverse, dist), ctr, cam.up)
        else
          cam.set(ctr.offset(cam.direction.reverse, diag * 3.0), ctr, cam.up)
          cam.height = diag * 1.5
        end
      end

      def quit(view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end

      def update_status
        v = @vios[@idx]
        loai = v.kind == :ranhhau ? 'rãnh hậu' : 'ngàm'
        lbl  = @mode == :ok ? 'Đã làm' : 'Thiếu'
        Sketchup.set_status_text("#{lbl} #{loai} — mối #{@idx + 1}/#{@vios.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số mối', SB_VCB_LABEL)
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Kiểm tra liên kết') { TK::JointCheck.run }
      cmd.tooltip         = 'Kiểm tra thiếu liên kết ABF (rãnh hậu / ngàm)'
      cmd.status_bar_text = 'Quét mô hình: 2 tấm ăn ~10mm cần rãnh hậu, ~17.5mm cần ngàm; thiếu thì tô cam.'
      cmd.small_icon      = File.join(icons, 'joint_16.png')
      cmd.large_icon      = File.join(icons, 'joint_24.png')
      cmd
    end

  end
end
