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

    COLOR_BAD  = Sketchup::Color.new(255, 140, 0)    # cam — họ "thiếu liên kết"
    COLOR_GAP  = Sketchup::Color.new(255, 60, 0)     # đỏ-cam — vùng giao

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    Vio = Struct.new(:kind, :name_a, :name_b, :pen, :segs_a, :segs_b, :gap_segs)

    # =========================================================
    #  QUÉT
    # =========================================================
    def self.run
      Sketchup.set_status_text('Đang quét liên kết (rãnh hậu / ngàm)...', SB_PROMPT)
      planks, inters = collect_all
      vios = find_missing(planks, inters)
      Sketchup.set_status_text('', SB_PROMPT)

      return UI.messagebox('Không tìm thấy tấm ván nào để kiểm tra.') if planks.empty?
      if vios.empty?
        UI.messagebox("✓ Không thấy mối liên kết nào bị thiếu (đã soi #{planks.size} tấm).")
        return
      end
      Sketchup.active_model.select_tool(ReviewTool.new(vios))
    end

    def self.scan
      planks, inters = collect_all
      find_missing(planks, inters)
    end

    # ── Adapter cho bộ "Soát Trước Xuất" (TK::PreExportCheck) ───
    def self.audit
      planks, inters = collect_all
      return { status: :na, count: 0, message: 'Không tìm thấy tấm ván nào để kiểm tra.' } if planks.empty?
      vios = find_missing(planks, inters)
      return { status: :pass, count: 0, message: "Các mối rãnh hậu / ngàm đều đủ (đã soi #{planks.size} tấm)." } if vios.empty?
      nr = vios.count { |v| v.kind == :ranhhau }
      ng = vios.count { |v| v.kind == :ngam }
      parts = []
      parts << "#{nr} mối thiếu rãnh hậu" if nr > 0
      parts << "#{ng} mối thiếu ngàm"     if ng > 0
      { status: :fail, count: vios.size, message: parts.join(', ') + '.' }
    end

    def self.review
      run
    end

    # =========================================================
    #  TÌM MỐI THIẾU LIÊN KẾT
    # =========================================================
    def self.find_missing(planks, inters)
      rh = inters.select { |x| x[:kind] == :ranhhau }
      ng = inters.select { |x| x[:kind] == :ngam }
      planks = planks.sort_by { |p| p[:aabb][0] }   # sweep theo minX
      n = planks.size
      vios = []
      seen = {}                                      # khử trùng: mỗi cặp tên 1 lỗi
      i = 0
      while i < n
        a = planks[i]; ax_hi = a[:aabb][3]
        j = i + 1
        while j < n
          b = planks[j]
          break if b[:aabb][0] > ax_hi
          v = pair_vio(a, b, rh, ng)
          if v
            key = [v.name_a, v.name_b].sort.join(' || ')
            unless seen[key]
              seen[key] = true
              vios << v
            end
          end
          j += 1
        end
        i += 1
      end
      vios
    end

    def self.pair_vio(a, b, rh, ng)
      ov = overlap_box(a[:aabb], b[:aabb])
      return nil unless ov
      dims = [ov[3] - ov[0], ov[4] - ov[1], ov[5] - ov[2]].sort  # inch tăng dần
      pen_mm = dims[0] * MM
      mid_mm = dims[1] * MM
      return nil if mid_mm > MID_MAX_MM              # chồng mặt lớn -> không phải mộng/rãnh

      kind = classify(pen_mm)
      return nil unless kind
      return nil if has_intersect?(kind == :ranhhau ? rh : ng, ov)

      Vio.new(kind, a[:name], b[:name], pen_mm.round(1),
              aabb_box_segs(a[:aabb]), aabb_box_segs(b[:aabb]), aabb_box_segs(ov))
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
      planks << { name: label(e), aabb: ab }
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
    #  TOOL XEM TỪNG MỐI THIẾU
    # =========================================================
    class ReviewTool
      def initialize(vios)
        @vios = vios
        @idx  = 0
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
        view.drawing_color = COLOR_BAD
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end

      def draw_gap(view)
        return if @draw_g.empty?
        view.line_width = 4
        view.drawing_color = COLOR_GAP
        view.draw(GL_LINES, @draw_g)
        view.draw2d(GL_LINES, @draw_g.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v = @vios[@idx]
        loai = v.kind == :ranhhau ? 'RÃNH HẬU' : 'NGÀM'
        l1 = "Thiếu #{loai}   (mối #{@idx + 1}/#{@vios.size})"
        l2 = "#{v.name_a}  ↔  #{v.name_b}"
        l3 = "Hai tấm ăn nhau #{v.pen}mm — chưa thấy liên kết ABF"
        l4 = '← → đổi mối  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, COLOR_BAD)
        txt(view, 34, 26, l1, Sketchup::Color.new(255, 180, 90), 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, Sketchup::Color.new(255, 210, 60), 12, false)
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
        Sketchup.set_status_text("Thiếu #{loai} — mối #{@idx + 1}/#{@vios.size} (← → đổi, ESC thoát)", SB_PROMPT)
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
