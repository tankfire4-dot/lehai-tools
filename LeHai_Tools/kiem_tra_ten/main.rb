# encoding: UTF-8
# Kiểm Tra Đặt Tên (CẢNH BÁO vàng): tấm ván nào CHƯA đặt tên có ý nghĩa thì
# nhắc — vì nhiều check khác (vd Bản Lề) dựa vào tên, và tên là thông tin cần
# cho sản xuất. "Chưa đặt tên" = tên RỖNG hoặc chỉ là SỐ TRƠN (vd "31", "608"
# — SketchUp/tool tự đặt, không phải người đặt).
#
# Nhận diện "tấm ván" bằng hình học (mỏng 1 chiều, lớn 2 chiều) như các check
# khác; bỏ qua nhánh nesting. CHỈ ĐỌC, không sửa model.
#
# Toolbar do LeHai_Tools/main.rb quản lý — dashboard gọi qua audit/review.

require 'sketchup.rb'

module TK
  module NameCheck

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    MM        = 25.4

    MIN_TH_MM   = 3.0
    MAX_TH_MM   = 40.0
    MIN_SIDE_MM = 40.0

    COLOR_WARN = Sketchup::Color.new(230, 160, 0)    # vàng cam — cảnh báo

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    Item = Struct.new(:name, :segs)

    # =========================================================
    #  QUÉT
    # =========================================================
    def self.run
      unnamed, total = scan
      return UI.messagebox('Không tìm thấy tấm ván nào để kiểm tra.') if total.zero?
      if unnamed.empty?
        UI.messagebox("✓ Cả #{total} tấm đều đã đặt tên.")
        return
      end
      Sketchup.active_model.select_tool(ReviewTool.new(unnamed))
    end

    # trả về [mảng tấm chưa tên, tổng số tấm]
    def self.scan
      unnamed = []; total = [0]
      collect(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, unnamed, total)
      [unnamed, total[0]]
    end

    # ── Adapter cho dashboard (TK::PreExportCheck) ─────────────
    def self.audit
      unnamed, total = scan
      return { status: :na, count: 0, message: 'Không tìm thấy tấm ván nào để kiểm tra.' } if total.zero?
      return { status: :pass, count: 0, message: "Cả #{total} tấm đều đã đặt tên." } if unnamed.empty?
      { status: :warn, count: unnamed.size, message: "#{unnamed.size}/#{total} tấm chưa đặt tên (rỗng hoặc số trơn)." }
    end

    def self.review
      run
    end

    # "chưa đặt tên" = rỗng hoặc chỉ toàn số (bỏ tiền tố __ và khoảng trắng)
    def self.unnamed?(name)
      s = name.to_s.sub(/\A__/, '').strip
      s.empty? || s =~ /\A\d+\z/
    end

    # =========================================================
    #  DUYỆT MÔ HÌNH
    # =========================================================
    def self.collect(entities, t, depth, in_plank, unnamed, total)
      return if depth > 40
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.name.to_s.include?(NEST_HINT)
        te   = t * e.transformation
        ents = ents_of(e)
        next unless ents

        is_plank = in_plank ? false : register(e, te, ents, unnamed, total)
        collect(ents, te, depth + 1, in_plank || is_plank, unnamed, total)
      end
    end

    # true nếu e là tấm ván (dù có tên hay không). Ghi vào unnamed nếu chưa đặt tên.
    def self.register(e, te, ents, unnamed, total)
      ab = world_aabb(ents, te)
      return false unless ab
      dims = [ab[3] - ab[0], ab[4] - ab[1], ab[5] - ab[2]].sort
      th = dims[0] * MM; mid = dims[1] * MM; big = dims[2] * MM
      return false unless th >= MIN_TH_MM && th <= MAX_TH_MM && mid >= MIN_SIDE_MM && big >= MIN_SIDE_MM
      total[0] += 1
      unnamed << Item.new(e.name.to_s.empty? ? '(trống)' : e.name.to_s, aabb_box_segs(ab)) if unnamed?(e.name)
      true
    end

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

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # =========================================================
    #  TOOL XEM TỪNG TẤM CHƯA TÊN
    # =========================================================
    class ReviewTool
      def initialize(items)
        @items = items
        @idx   = 0
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
        return UI.messagebox("Chỉ có #{@items.size} tấm (1–#{@items.size}).") if i < 0 || i >= @items.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_outline(view, @draw)
        draw_banner(view)
      end

      def focus(i)
        @idx = i
        @draw = flatten(@items[i].segs)
        @bounds = focus_bounds
        frame(@bounds)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def step(dir, view)
        focus((@idx + dir) % @items.size)
        view.invalidate
      end

      def flatten(segs)
        pts = []
        segs.each { |a, b| pts << Geom::Point3d.new(*a) << Geom::Point3d.new(*b) }
        pts
      end

      def focus_bounds
        bb = Geom::BoundingBox.new
        @draw.each { |p| bb.add(p) }
        bb
      end

      def draw_outline(view, pts)
        return if pts.empty?
        view.line_width = 3
        view.drawing_color = COLOR_WARN
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v = @items[@idx]
        l1 = "⚠ Tấm chưa đặt tên   (#{@idx + 1}/#{@items.size})"
        l2 = "Tên hiện tại: #{v.name}"
        l3 = 'Cảnh báo — đặt tên có ý nghĩa (dùng tool Điền Tên Nhanh cho tiện)'
        l4 = '← → đổi  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, COLOR_WARN)
        txt(view, 34, 26, l1, Sketchup::Color.new(255, 205, 90), 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, Sketchup::Color.new(255, 225, 150), 12, false)
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
        Sketchup.set_status_text("Tấm chưa đặt tên — #{@idx + 1}/#{@items.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số tấm', SB_VCB_LABEL)
      end
    end

  end
end
