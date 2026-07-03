# encoding: UTF-8
# Kiểm Tra Rãnh Led (CẢNH BÁO, không phải lỗi cứng): ~80% căn có led nhưng KHÔNG
# xác định chắc căn nào có, nên đây là mức CẢNH BÁO vàng, không chặn xuất DXF.
#
# Dấu vết (2 plugin khác nhau tạo, dò từ dữ liệu thật):
#   - RÃNH PHAY led (ABF):  "_ABF_Intersect" tag "ABF_PHAYLED..." — thao tác gia
#     công, ĐI VÀO FILE DXF CẮT. Đây là BẰNG CHỨNG "đã làm led".
#   - Thanh đèn led (NTT):  group "ABF_LED" tag "NTT_led" — mô hình đèn mua sẵn,
#     KHÔNG cắt CNC. Chỉ là dấu hiệu "chỗ này cần led". File sản xuất hay bỏ nó.
#
# Luật (bám thực tế: rãnh phay mới là thứ đi cắt):
#   1. File CÓ rãnh phay led → đã làm led → ĐẠT (xanh). Xem = lướt các rãnh đã phay.
#   2. Có thanh đèn (NTT) mà chưa phay rãnh gần đó → cảnh báo, lướt tới thanh đó.
#   3. Cả file KHÔNG có rãnh phay LẪN thanh đèn → cảnh báo mức file: "80% căn có
#      led, kiểm tra căn này có cần led không".
#
# Rãnh phay coi là "của thanh đèn" nếu tâm rãnh nằm trong bbox thanh nới NEAR_MM.
# Dò AABB world, bỏ qua nhánh nesting. CHỈ ĐỌC, không sửa model.
#
# Toolbar do LeHai_Tools/main.rb quản lý — dashboard gọi qua audit/review.

require 'sketchup.rb'

module TK
  module LedCheck

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    MM        = 25.4

    LED_RE       = /led/i.freeze          # tên có "led" = thanh led
    INTERSECT_RE = /intersect/i.freeze    # loại trừ rãnh (_ABF_Intersect)
    NEAR_MM      = 60.0                    # rãnh led coi là "của thanh này" nếu tâm nằm trong bbox thanh nới mức này

    COLOR_WARN = Sketchup::Color.new(230, 160, 0)     # vàng cam — cảnh báo (không phải đỏ lỗi)
    COLOR_OK   = Sketchup::Color.new(0, 170, 80)      # xanh lá — rãnh led đã phay

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    # item để lướt xem: kind :warn (thanh đèn thiếu rãnh) / :ok (rãnh đã phay)
    Item = Struct.new(:name, :aabb, :segs, :center)

    # =========================================================
    #  QUÉT
    # =========================================================
    def self.run
      leds, grooves = collect_all
      missing = leds.reject { |l| has_groove?(l, grooves) }

      # (3) không rãnh phay, không thanh đèn → cảnh báo mức file
      if grooves.empty? && leds.empty?
        UI.messagebox("⚠ Cảnh báo: không thấy rãnh led lẫn thanh đèn nào trong file.\n\n" \
                      "~80% căn có led — kiểm tra xem căn này có cần led không (chỉ là nhắc, không phải lỗi bắt buộc).")
        return
      end
      # (2) có thanh đèn chưa phay → cảnh báo, lướt thanh (vàng)
      unless missing.empty?
        Sketchup.active_model.select_tool(ReviewTool.new(missing, :warn))
        return
      end
      # (1) đã làm led → đạt, lướt các rãnh đã phay (xanh)
      if grooves.any?
        UI.messagebox("✓ Đã phay #{grooves.size} rãnh led — bấm OK để lướt xem.")
        Sketchup.active_model.select_tool(ReviewTool.new(grooves, :ok))
      else
        UI.messagebox("✓ #{leds.size} thanh đèn led đều đã phay rãnh.")
      end
    end

    # ── Adapter cho dashboard (TK::PreExportCheck) ─────────────
    def self.audit
      leds, grooves = collect_all
      missing = leds.reject { |l| has_groove?(l, grooves) }

      return { status: :warn, count: 0,
               message: '80% căn có led — không thấy rãnh led lẫn thanh đèn nào, kiểm tra căn này có cần led không.' } if grooves.empty? && leds.empty?
      return { status: :warn, count: missing.size,
               message: "#{missing.size} thanh đèn led chưa phay rãnh." } unless missing.empty?
      { status: :pass, count: 0, message: "Đã phay #{grooves.size} rãnh led." }
    end

    def self.review
      run
    end

    def self.has_groove?(led, grooves)
      near = NEAR_MM / MM
      a = led.aabb
      grooves.any? do |g|
        c = g.center
        c[0] >= a[0] - near && c[0] <= a[3] + near &&
          c[1] >= a[1] - near && c[1] <= a[4] + near &&
          c[2] >= a[2] - near && c[2] <= a[5] + near
      end
    end

    # =========================================================
    #  DUYỆT MÔ HÌNH — thu thanh led + tâm rãnh led
    # =========================================================
    def self.collect_all
      leds = []; grooves = []
      collect(Sketchup.active_model.entities, Geom::Transformation.new, 0, leds, grooves)
      [leds, grooves]
    end

    def self.collect(entities, t, depth, leds, grooves)
      return if depth > 40
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.name.to_s.include?(NEST_HINT)
        te   = t * e.transformation
        name = e.name.to_s
        tag  = (e.layer.name rescue '')

        if name =~ INTERSECT_RE && (tag =~ /phayled/i || tag =~ LED_RE)
          # rãnh phay led đã làm
          ab = world_aabb(ents_of(e), te)
          if ab
            c = [(ab[0] + ab[3]) / 2, (ab[1] + ab[4]) / 2, (ab[2] + ab[5]) / 2]
            grooves << Item.new('rãnh led', ab, aabb_box_segs(ab), c)
          end
        elsif (name =~ LED_RE || tag =~ LED_RE) && name !~ INTERSECT_RE
          # thanh đèn led (NTT)
          ab = world_aabb(ents_of(e), te)
          if ab
            c = [(ab[0] + ab[3]) / 2, (ab[1] + ab[4]) / 2, (ab[2] + ab[5]) / 2]
            leds << Item.new(label(e), ab, aabb_box_segs(ab), c)
          end
        end

        ents = ents_of(e)
        collect(ents, te, depth + 1, leds, grooves) if ents
      end
    end

    def self.world_aabb(ents, te)
      return nil unless ents
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
      '(thanh led không tên)'
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # =========================================================
    #  TOOL XEM TỪNG THANH LED THIẾU RÃNH
    # =========================================================
    class ReviewTool
      # mode = :warn (thanh đèn thiếu rãnh, vàng) / :ok (rãnh đã phay, xanh)
      def initialize(items, mode = :warn)
        @items = items
        @mode  = mode
        @color = mode == :ok ? COLOR_OK : COLOR_WARN
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
        return UI.messagebox("Chỉ có #{@items.size} thanh (1–#{@items.size}).") if i < 0 || i >= @items.size
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
        c = bb.center
        m = 200.0 / 25.4
        bb.add(c.offset(Geom::Vector3d.new(m, m, m)))
        bb.add(c.offset(Geom::Vector3d.new(-m, -m, -m)))
        bb
      end

      def draw_outline(view, pts)
        return if pts.empty?
        view.line_width = 3
        view.drawing_color = @color
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v = @items[@idx]
        if @mode == :ok
          l1 = "Rãnh led đã phay   (#{@idx + 1}/#{@items.size})"
          l3 = 'Đã làm led — đây là rãnh phay đi vào file cắt DXF'
          title_col = Sketchup::Color.new(120, 240, 160)
          info_col  = Sketchup::Color.new(150, 255, 190)
        else
          l1 = "⚠ Thanh đèn led chưa phay rãnh   (#{@idx + 1}/#{@items.size})"
          l3 = 'Cảnh báo (không bắt buộc) — kiểm tra thanh đèn này có cần phay rãnh không'
          title_col = Sketchup::Color.new(255, 205, 90)
          info_col  = Sketchup::Color.new(255, 225, 150)
        end
        l2 = v.name
        l4 = '← → đổi  ·  gõ số để nhảy  ·  ESC thoát'
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
        lbl = @mode == :ok ? 'Rãnh led đã phay' : 'Thanh đèn chưa phay rãnh'
        Sketchup.set_status_text("#{lbl} — #{@idx + 1}/#{@items.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số mục', SB_VCB_LABEL)
      end
    end

  end
end
