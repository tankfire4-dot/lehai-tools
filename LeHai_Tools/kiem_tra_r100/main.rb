# encoding: UTF-8
# Kiểm Tra Cung R100 (CẢNH BÁO VÀNG, không phải lỗi cứng): trong file có cung tròn
# bán kính đúng 100mm thì KHÔNG ĐOÁN ĐƯỢC nó là gì — bo góc trang trí (R bo) hay
# đường cong của một tấm đợt thường. Hai thứ đó ra hai đường dao khác nhau, nên
# tool chỉ nhặt ra cho người nhìn rồi tự quyết, không chặn xuất DXF.
#
# Vì sao chỉ 100mm (Khoa chốt 27/07): các R khác đủ rõ nghĩa khi nhìn. Riêng 100
# lẫn giữa hai nghĩa nên mới cần một dòng nhắc.
#
# Luật nhặt:
#   1. Chỉ cung HỞ. Vòng tròn KÍN bỏ qua — đó là lỗ khoan, bên Dim Nhanh ghi nhãn
#      "D" (đường kính) chứ không phải "R", không dính gì tới bo góc.
#   2. Bán kính đo ở WORLD (đã nhân transform) nên tủ bị phóng/thu vẫn ra đúng số.
#   3. Bỏ qua nhánh "__ABF_Nesting" (bản trải phẳng) — cùng cung sẽ đếm hai lần.
#
# Cách đo bán kính chép ĐÚNG từ Dim Nhanh (`dim_nhanh/main.rb:248` radius_of,
# :263 full_circle?, :271 circumradius) để hai tool không bao giờ nói lệch số nhau.
# Chép chứ không gọi lại, vì bên đó là method của class DimTool (phải dựng tool mới
# gọi được), không phải hàm module.
#
# CHỈ ĐỌC, không sửa model. Không có nút riêng — chạy trong dashboard
# Check Chốt Sản Xuất qua adapter audit/review.

require 'sketchup.rb'

module TK
  module RadiusCheck

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze

    TARGET_MM = 100.0    # bán kính cần soi
    TOL_MM    = 0.5      # sai số cho phép quanh 100mm
    MAX_DEPTH = 40

    COLOR_WARN = Sketchup::Color.new(230, 160, 0)   # vàng cam — cảnh báo, không phải đỏ lỗi

    # một cung R100 tìm được: tên tấm chứa nó, số đo, các điểm world để vẽ
    Item = Struct.new(:name, :radius_mm, :pts)

    # =========================================================
    #  Adapter cho dashboard (TK::PreExportCheck)
    # =========================================================
    def self.audit
      items = collect_all
      return { status: :pass, count: 0,
               message: 'Không thấy cung R100 nào.' } if items.empty?
      { status: :warn, count: items.size,
        message: "#{items.size} cung R100 — chưa rõ là bo góc hay R tấm đợt thường, xác nhận trước khi xuất DXF." }
    end

    def self.review
      run
    end

    def self.run
      items = collect_all
      if items.empty?
        UI.messagebox("Không thấy cung R100 nào trong file.\n\n" \
                      "(Chỉ soi cung HỞ bán kính 100mm ±#{TOL_MM}mm. Vòng tròn kín là lỗ khoan, không tính.)")
        return
      end
      Sketchup.active_model.select_tool(ReviewTool.new(items))
    end

    # =========================================================
    #  QUÉT — duyệt cây, nhặt cung hở bán kính ≈ 100mm
    # =========================================================
    def self.collect_all
      items = []
      collect(Sketchup.active_model.entities, Geom::Transformation.new, 0, '(ngoài cùng model)', items)
      items
    end

    def self.collect(entities, t, depth, owner, items)
      return if depth > MAX_DEPTH || entities.nil?
      seen = {}   # entityID của EDGE đã xét (entityID của curve không ổn định — auto_dan_canh/main.rb:407)
      entities.each do |e|
        next if e.deleted?
        if e.is_a?(Sketchup::Edge)
          c = e.curve
          next unless c.is_a?(Sketchup::Curve)
          next if seen[e.entityID]
          c.edges.each { |ce| seen[ce.entityID] = true }
          next if full_circle?(c)
          r = radius_of(c, t)
          next if (r - TARGET_MM).abs > TOL_MM
          pts = world_points(c, t)
          items << Item.new(owner, r, pts) if pts.size >= 2
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          next if e.name.to_s.include?(NEST_HINT)
          collect(ents_of(e), t * e.transformation, depth + 1, label(e, owner), items)
        end
      end
    end

    def self.world_points(curve, t)
      curve.vertices.map { |v| t * v.position }
    end

    # bán kính (mm) đo ở WORLD — chép từ dim_nhanh/main.rb:248
    def self.radius_of(curve, tr)
      if curve.is_a?(Sketchup::ArcCurve)
        c = tr * curve.center
        p = tr * curve.vertices.first.position
        return (p - c).length.to_mm
      end
      vs = curve.vertices
      n = vs.size
      return 0 if n < 3
      r = circumradius(tr * vs[0].position, tr * vs[n / 3].position, tr * vs[2 * n / 3].position)
      r ? r * 25.4 : 0
    end

    # vòng tròn LIỀN (kín) hay cung HỞ? — chép từ dim_nhanh/main.rb:263
    def self.full_circle?(curve)
      if curve.is_a?(Sketchup::ArcCurve)
        return (curve.end_angle - curve.start_angle).abs >= (2 * Math::PI - 0.05)
      end
      vs = curve.vertices
      vs.size > 2 && vs.first.position.distance(vs.last.position) < 1e-4
    end

    # bán kính vòng tròn ngoại tiếp tam giác ABC (inch) — chép từ dim_nhanh/main.rb:271
    def self.circumradius(a, b, c)
      ab = a.distance(b); bc = b.distance(c); ca = c.distance(a)
      area2 = (b - a).cross(c - a).length
      return nil if area2 < 1e-9
      (ab * bc * ca) / (2.0 * area2)
    end

    # tên tấm chứa cung: lấy tên gần nhất có nghĩa, không có thì kế thừa của cha
    def self.label(e, inherited)
      n = e.name.to_s.strip
      n = e.definition.name.to_s.strip if n.empty? && e.respond_to?(:definition)
      n.empty? ? inherited : n.sub(/\A__/, '')
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    def self.fmt(v)
      r = v.round(1)
      (r == r.to_i ? r.to_i : r).to_s
    end

    # =========================================================
    #  TOOL LƯỚT XEM TỪNG CUNG — khuôn kiem_tra_led/main.rb:172
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
        return UI.messagebox("Chỉ có #{@items.size} cung (1–#{@items.size}).") if i < 0 || i >= @items.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_arc(view)
        draw_banner(view)
      end

      def focus(i)
        @idx    = i
        @draw   = @items[i].pts
        @bounds = focus_bounds
        frame(@bounds)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def step(dir, view)
        focus((@idx + dir) % @items.size)
        view.invalidate
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

      def draw_arc(view)
        return if @draw.nil? || @draw.empty?
        view.line_width = 3
        view.drawing_color = COLOR_WARN
        view.draw(GL_LINE_STRIP, @draw)
        view.draw2d(GL_LINE_STRIP, @draw.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v  = @items[@idx]
        l1 = "⚠ Cung R#{TK::RadiusCheck.fmt(v.radius_mm)}   (#{@idx + 1}/#{@items.size})"
        l2 = v.name
        l3 = 'Chưa rõ bo góc hay R tấm đợt thường — xác nhận trước khi xuất DXF'
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
        Sketchup.set_status_text("Cung R100 — #{@idx + 1}/#{@items.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số mục', SB_VCB_LABEL)
      end
    end

  end
end
