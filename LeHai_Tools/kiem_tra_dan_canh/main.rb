# encoding: UTF-8
# Kiểm Tra Dán Cạnh (CẢNH BÁO vàng, mức THÔ — không chặn cứng):
#
# Dấu ABF để lại khi đã dán cạnh: group con "_ABF_edgeBanding" (mỗi cái = 1 cạnh
# đã dán). Dò từ file thật (dan_canh_probe): file ĐÃ dán có N dấu này (403 trong
# file mẫu, nằm bên trong nhánh __ABF_Nesting); file CHƯA dán thì KHÔNG có.
#
# Mức thô theo yêu cầu Khoa: chỉ xét "cả file đã có ai dán cạnh chưa" — vì quy
# tắc cạnh nào phải dán rất phức tạp (đế phải dán dù không lộ...), không suy từ
# hình học được. 0 dấu → cảnh báo; có dấu → coi như đã làm.
#
# Đếm dấu BẤT KỂ nằm đâu (dấu nằm ở bản nesting phẳng, không phải tủ 3D) → check
# ngầm hiểu file đã nesting, đúng bối cảnh "chốt trước khi xuất DXF".
#
# CHỈ ĐỌC. Dashboard (TK::PreExportCheck) gọi qua audit/review.

require 'sketchup.rb'

module TK
  module EdgeBandCheck

    PATH      = File.dirname(__FILE__).freeze
    EDGE_RE   = /edgeband/i.freeze          # dấu ABF: group "_ABF_edgeBanding"
    AUTO_RE   = /\AHung_Show_ABF_/.freeze    # dấu Auto Dán Cạnh: material tô lên mặt
    NEST_HINT = '__ABF_Nesting'.freeze

    COLOR_OK = Sketchup::Color.new(0, 170, 80)   # xanh lá — cạnh ĐÃ dán (không phải lỗi)

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    # một cạnh đã dán, đủ dữ liệu để lướt tới xem
    Mark = Struct.new(:owner, :in_nest, :segs, :center)

    # Đếm số group/comp mang dấu dán cạnh CỦA ABF trong toàn model.
    def self.count
      n = 0
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, '', false) do |e, _t, _own, _nest|
        n += 1 if e.name.to_s =~ EDGE_RE
      end
      n
    end

    # Thu vị trí từng dấu để "Xem" lướt được — trước 27/07 dòng này chỉ hiện
    # messagebox rồi thôi, là dòng DUY NHẤT trong dashboard không dẫn đi đâu.
    def self.collect_marks
      out = []
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, '', false) do |e, t, owner, nest|
        next unless e.name.to_s =~ EDGE_RE
        ab = world_aabb_of(e, t)
        next unless ab
        c = Geom::Point3d.new((ab[0] + ab[3]) / 2, (ab[1] + ab[4]) / 2, (ab[2] + ab[5]) / 2)
        out << Mark.new(owner.empty? ? '(tấm chưa đặt tên)' : owner, nest, aabb_box_segs(ab), c)
      end
      out
    end

    # Hộp bao WORLD của chính entity e. `e.bounds` nằm ở hệ toạ độ của CHA (đã
    # gộp sẵn e.transformation) nên nhân transform của CHA, không nhân te —
    # cùng cách kiem_tra_ban_le/main.rb:128 lấy tâm cốc bản lề.
    def self.world_aabb_of(e, t)
      bb = e.bounds
      return nil if bb.nil? || bb.empty?
      mn = bb.min; mx = bb.max
      w = Geom::BoundingBox.new
      CORNERS.each do |cx, cy, cz|
        w.add(t * Geom::Point3d.new(cx.zero? ? mn.x : mx.x, cy.zero? ? mn.y : mx.y, cz.zero? ? mn.z : mx.z))
      end
      [w.min.x, w.min.y, w.min.z, w.max.x, w.max.y, w.max.z]
    end

    def self.aabb_box_segs(ab)
      pts = CORNERS.map do |cx, cy, cz|
        [cx.zero? ? ab[0] : ab[3], cy.zero? ? ab[1] : ab[4], cz.zero? ? ab[2] : ab[5]]
      end
      EDGES12.map { |a, b| [pts[a], pts[b]] }
    end

    # Auto Dán Cạnh (MyStudio::AutoEdgeBand) KHÔNG tạo group — nó tô material
    # "Hung_Show_ABF_..." lên mặt cạnh dán. Chỉ cần material đó có trong file là
    # dấu hiệu đã có dùng dán cạnh (mức thô — không đếm chính xác từng cạnh).
    def self.auto_banded?
      Sketchup.active_model.materials.any? { |m| m.name.to_s =~ AUTO_RE }
    rescue StandardError
      false
    end

    # owner = tên tấm gần nhất có tên (để banner nói được cạnh của tấm nào)
    # nest  = đang ở trong nhánh trải phẳng __ABF_Nesting hay chưa
    def self.walk(entities, t, depth, owner, nest, &blk)
      return if depth > 40 || entities.nil?
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        blk.call(e, t, owner, nest)
        next if e.name.to_s =~ EDGE_RE   # là dấu dán cạnh → không đi sâu thêm
        sub = e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities
        walk(sub, t * e.transformation, depth + 1, ten_hoac(e, owner),
             nest || e.name.to_s.include?(NEST_HINT), &blk) if sub
      end
    end

    def self.ten_hoac(e, thua_ke)
      n = e.name.to_s.strip
      return thua_ke if n.empty? || n.include?(NEST_HINT)
      n.sub(/\A__/, '')
    end

    # ── Adapter cho dashboard ──────────────────────────────────
    def self.audit
      n = count
      return { status: :pass, count: n, message: "Đã dán #{n} cạnh (ABF)." } if n.positive?
      return { status: :pass, count: 0, message: 'Đã dán cạnh (Auto Dán Cạnh).' } if auto_banded?
      { status: :warn, count: 0,
        message: 'Chưa thấy cạnh nào được dán — kiểm tra file đã chạy dán cạnh chưa.' }
    end

    def self.review
      marks = collect_marks
      if !marks.empty?
        # Lướt tới từng cạnh đã dán — trước đây chỉ báo con số, không xem được.
        Sketchup.active_model.select_tool(ReviewTool.new(marks))
      elsif count.positive?
        # Có dấu nhưng không đo được vị trí (bounds rỗng) — vẫn phải nói ra.
        UI.messagebox("✓ File đã dán cạnh (ABF): #{count} dấu \"_ABF_edgeBanding\".\n\n" \
                      'Nhưng không đo được vị trí của dấu nào để lướt xem.')
      elsif auto_banded?
        UI.messagebox("✓ File đã dán cạnh (Auto Dán Cạnh_LeHai).\n\n" \
                      "Có dấu material \"Hung_Show_ABF_...\" — cạnh đã được tô dán.")
      else
        UI.messagebox("⚠ Cảnh báo (không bắt buộc): chưa thấy cạnh nào được dán trong file.\n\n" \
                      "Kiểm tra xem file này đã chạy DÁN CẠNH chưa (ABF hoặc Auto Dán Cạnh) trước khi xuất DXF.")
      end
    end

    def self.run
      review
    end

    # =========================================================
    #  TOOL LƯỚT XEM TỪNG CẠNH ĐÃ DÁN — khuôn kiem_tra_led/main.rb:172
    # =========================================================
    class ReviewTool
      def initialize(marks)
        @items = marks
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
        return UI.messagebox("Chỉ có #{@items.size} cạnh (1–#{@items.size}).") if i < 0 || i >= @items.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_outline(view)
        draw_banner(view)
      end

      def focus(i)
        @idx    = i
        @draw   = flatten(@items[i].segs)
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
        m = 150.0 / 25.4
        bb.add(c.offset(Geom::Vector3d.new(m, m, m)))
        bb.add(c.offset(Geom::Vector3d.new(-m, -m, -m)))
        bb
      end

      def draw_outline(view)
        return if @draw.nil? || @draw.empty?
        view.line_width = 3
        view.drawing_color = COLOR_OK
        view.draw(GL_LINES, @draw)
        view.draw2d(GL_LINES, @draw.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v  = @items[@idx]
        l1 = "✓ Cạnh đã dán   (#{@idx + 1}/#{@items.size})"
        l2 = v.owner
        # Dấu _ABF_edgeBanding nằm trong bản TRẢI PHẲNG, không phải tủ 3D — nói
        # thẳng ra, kẻo nhìn màn hình tưởng tool zoom nhầm chỗ.
        l3 = v.in_nest ? 'Đang xem trên BẢN TRẢI PHẲNG (nesting), không phải tủ 3D' \
                       : 'Đang xem trên mô hình 3D'
        l4 = '← → đổi  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, COLOR_OK)
        txt(view, 34, 26, l1, Sketchup::Color.new(120, 240, 160), 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, Sketchup::Color.new(150, 255, 190), 12, false)
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
        cam  = Sketchup.active_model.active_view.camera
        ctr  = bb.center
        diag = bb.diagonal
        diag = 100.0 if diag < 1.0
        if cam.perspective?
          fov  = cam.fov * Math::PI / 180.0
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
        Sketchup.set_status_text("Cạnh đã dán — #{@idx + 1}/#{@items.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số mục', SB_VCB_LABEL)
      end
    end

  end
end
