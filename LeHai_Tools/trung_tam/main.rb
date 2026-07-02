# encoding: UTF-8
# Kiểm Tra Trùng Tấm: trên MÔ HÌNH TỦ 3D (dựng tay), đôi khi copy 1 tấm rồi
# quên di chuyển / dán đè → 2 tấm chồng khít cùng góc tọa độ, nhìn như 1 tấm
# nhưng thực ra 2. Khi nesting bằng ABF sẽ đếm dư phôi → phế. Tool quét TOÀN
# mô hình (BỎ QUA vùng nesting vì nesting không bao giờ trùng), nhận diện "tấm
# ván" theo hình học (mỏng 1 chiều, lớn 2 chiều), so tâm + kích thước ở tọa độ
# THẾ GIỚI — trùng khít = báo. CHỈ ĐỌC, không sửa model.
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'

module TK
  module DuplicateCheck

    PATH      = File.dirname(__FILE__).freeze
    DICT      = 'ABF'.freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    MM        = 25.4

    # ── Ngưỡng nhận diện "tấm ván" (mm) ──
    MIN_TH_MM   = 3.0     # chiều mỏng nhất (độ dày) tối thiểu
    MAX_TH_MM   = 40.0    # dày hơn mức này coi là khối, không phải tấm
    MIN_SIDE_MM = 40.0    # 2 chiều lớn phải ≥ mức này (loại chi tiết vụn, ke, vít)

    # ── Dung sai coi là "trùng khít" ──
    CENTER_MM  = 1.0
    CENTER_TOL = CENTER_MM / MM   # inch (so tâm world)
    EDGE_TOL   = 1.0 / MM         # inch (~1mm) — sai số khi so vector cạnh

    COLOR_BAD  = Sketchup::Color.new(255, 0, 200)   # hồng cánh sen — đồng bộ SpacingCheck

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    Dup = Struct.new(:name_a, :name_b, :segs_a, :segs_b)

    # =========================================================
    #  QUÉT
    # =========================================================
    def self.run
      Sketchup.set_status_text('Đang quét tấm trùng lặp...', SB_PROMPT)
      boards = collect_all
      vios   = find_dups(boards)
      Sketchup.set_status_text('', SB_PROMPT)

      if boards.empty?
        UI.messagebox('Không tìm thấy tấm ván nào trên mô hình để kiểm tra.')
        return
      end
      if vios.empty?
        UI.messagebox("✓ Không thấy tấm nào trùng lặp (đã soi #{boards.size} tấm).")
        return
      end
      Sketchup.active_model.select_tool(ReviewTool.new(vios))
    end

    def self.scan
      find_dups(collect_all)
    end

    # ── Adapter cho bộ "Soát Trước Xuất" (TK::PreExportCheck) ───
    def self.audit
      boards = collect_all
      return { status: :na, count: 0, message: 'Không tìm thấy tấm ván nào để kiểm tra.' } if boards.empty?
      vios = find_dups(boards)
      return { status: :pass, count: 0, message: "Không thấy tấm trùng lặp (đã soi #{boards.size} tấm)." } if vios.empty?
      { status: :fail, count: vios.size, message: "#{vios.size} tấm bị trùng lặp (chồng khít lên nhau)." }
    end

    def self.review
      run
    end

    # ── So từng cặp trong cùng nhóm kích thước (nhanh) ──
    # Trùng khít THẬT = cùng tâm + 3 vector cạnh khớp (cùng hướng). Hai tấm cắt
    # mộng (xoay 90°) tuy cùng tâm + cùng bao nhưng cạnh lệch hướng → bị loại.
    def self.find_dups(boards)
      buckets = Hash.new { |h, k| h[k] = [] }
      boards.each { |b| buckets[b[:key]] << b }
      vios = []
      buckets.each_value do |grp|
        next if grp.size < 2
        grp.each_with_index do |a, i|
          ((i + 1)...grp.size).each do |j|
            b = grp[j]
            next if a[:wc].distance(b[:wc]) > CENTER_TOL
            next unless edges_match?(a[:edges], b[:edges])
            vios << Dup.new(a[:name], b[:name], a[:segs], b[:segs])
          end
        end
      end
      vios
    end

    # 3 vector cạnh của tấm A có khớp 1-1 với của tấm B không (bỏ qua thứ tự &
    # chiều)? Khớp = cùng phương + cùng độ dài trong EDGE_TOL.
    def self.edges_match?(va, vb)
      used = [false, false, false]
      va.each do |a|
        hit = false
        vb.each_with_index do |b, i|
          next if used[i]
          if (a - b).length <= EDGE_TOL || (a + b).length <= EDGE_TOL
            used[i] = true
            hit = true
            break
          end
        end
        return false unless hit
      end
      true
    end

    # =========================================================
    #  DUYỆT MÔ HÌNH — thu mọi "tấm ván" kèm world bbox
    # =========================================================
    def self.collect_all
      out = []
      collect(Sketchup.active_model.entities, Geom::Transformation.new, 0, out)
      out
    end

    def self.collect(entities, t, depth, out)
      return if depth > 40
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if skip?(e)
        te   = t * e.transformation
        ents = ents_of(e)
        next unless ents
        register_board(e, te, ents, out)
        if ents.any? { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
          collect(ents, te, depth + 1, out)
        end
      end
    end

    # nếu e có mặt phẳng riêng đạt tiêu chuẩn tấm ván -> ghi vào out
    def self.register_board(e, te, ents, out)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return if bb.empty?
      dims   = [bb.width.to_f, bb.height.to_f, bb.depth.to_f].sort  # inch, tăng dần
      th_mm  = dims[0] * MM
      mid_mm = dims[1] * MM
      big_mm = dims[2] * MM
      return unless th_mm  >= MIN_TH_MM && th_mm <= MAX_TH_MM
      return unless mid_mm >= MIN_SIDE_MM && big_mm >= MIN_SIDE_MM
      size = [th_mm, mid_mm, big_mm]
      pts  = box_corners(bb, te)
      out << {
        name:  label(e),
        wc:    te * bb.center,
        size:  size,
        key:   size.map(&:round),         # nhóm sơ bộ theo kích thước làm tròn 1mm
        edges: [pts[1] - pts[0], pts[3] - pts[0], pts[4] - pts[0]], # 3 vector cạnh world
        segs:  segs_from_corners(pts)
      }
    end

    def self.skip?(e)
      n = e.name.to_s
      return true if n.include?(NEST_HINT) || n.include?('_ABF_Label')
      d = e.attribute_dictionary(DICT)
      return true if d && (d['is-label'] == true || d['is-sheet-border'] == true)
      false
    end

    # 8 góc hộp bao (world) — thứ tự theo CORNERS
    def self.box_corners(bb, te)
      mn = bb.min; mx = bb.max
      CORNERS.map do |cx, cy, cz|
        p = Geom::Point3d.new(cx.zero? ? mn.x : mx.x,
                              cy.zero? ? mn.y : mx.y,
                              cz.zero? ? mn.z : mx.z)
        te * p
      end
    end

    def self.segs_from_corners(pts)
      EDGES12.map { |a, b| [pts[a].to_a, pts[b].to_a] }
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
    #  TOOL XEM TỪNG CẶP TRÙNG LẶP
    # =========================================================
    class ReviewTool
      def initialize(vios)
        @vios = vios
        @idx  = 0
      end

      def activate
        focus(0)
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def getExtents
        @bounds
      end

      def onCancel(_r, view) quit(view) end

      def onKeyDown(key, _rep, _flags, view)
        case key
        when 27 then quit(view)            # Esc
        when 39, 38 then step(1, view)     # Right / Up -> cặp sau
        when 37, 40 then step(-1, view)    # Left / Down -> cặp trước
        end
        false
      end

      def enableVCB?
        true
      end

      def onUserText(text, view)
        n = text.to_s.scan(/\d+/).first
        return unless n
        i = n.to_i - 1
        return UI.messagebox("Chỉ có #{@vios.size} cặp (1–#{@vios.size}).") if i < 0 || i >= @vios.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_outline(view, @draw_a)
        draw_outline(view, @draw_b)
        draw_banner(view)
      end

      def focus(i)
        @idx = i
        v = @vios[i]
        @draw_a = flatten(v.segs_a)
        @draw_b = flatten(v.segs_b)
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
        @draw_a.each { |p| bb.add(p) }
        @draw_b.each { |p| bb.add(p) }
        bb
      end

      def draw_outline(view, pts)
        return if pts.empty?
        view.line_width = 3
        view.drawing_color = COLOR_BAD
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v = @vios[@idx]
        l1 = "Trùng lặp   (cặp #{@idx + 1}/#{@vios.size})"
        l2 = "#{v.name_a}  ↔  #{v.name_b}"
        l3 = '← → đổi cặp  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 80, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 80, COLOR_BAD)
        txt(view, 34, 26, l1, Sketchup::Color.new(255, 140, 220), 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 70, l3, Sketchup::Color.new(255, 210, 60), 11, false)
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
          dist = (diag / 2.0) / Math.tan(fov / 2.0) * 1.6
          cam.set(ctr.offset(cam.direction.reverse, dist), ctr, cam.up)
        else
          cam.set(ctr.offset(cam.direction.reverse, diag * 3.0), ctr, cam.up)
          cam.height = diag * 1.6
        end
      end

      def quit(view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end

      def update_status
        Sketchup.set_status_text("Trùng lặp — cặp #{@idx + 1}/#{@vios.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số cặp', SB_VCB_LABEL)
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Kiểm tra trùng tấm') { TK::DuplicateCheck.run }
      cmd.tooltip         = 'Kiểm tra tấm bị trùng lặp (chồng khít) trên mô hình 3D'
      cmd.status_bar_text = 'Quét mô hình: tấm nào chồng khít lên tấm khác thì tô hồng, nhảy tới xem.'
      cmd.small_icon      = File.join(icons, 'dup_16.png')
      cmd.large_icon      = File.join(icons, 'dup_24.png')
      cmd
    end

  end
end
