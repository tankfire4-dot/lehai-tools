# encoding: UTF-8
# Kiểm Tra Bản Lề: luật xưởng Le Hai — group nào tên có "cánh"/"canh" là CÁNH
# TỦ, và cánh tủ dùng ABF thì BẮT BUỘC đã khoét cốc bản lề (component con tên
# "_ABF_hingeCup"), tối thiểu 2 cái/cánh. Cánh nào thiếu (đếm < 2, kể cả 0) →
# báo lỗi. "canh"/"cánh" là tên KHÔNG trùng nghĩa khác trong xưởng (dán cạnh
# không cần điền tên).
#
# HAI ngoại lệ theo luật xưởng:
#  - CHỈ soi mô hình 3D: BỎ QUA nhánh nesting (__ABF_Nesting) — trong đó cũng có
#    tấm tên "canh..." (phôi phẳng), quét vào sẽ báo nhầm.
#  - Tên có "hộc kéo" thì MIỄN bản lề ("cánh hộc kéo" = mặt hộc kéo, không gắn
#    bản lề) — dù có chữ "cánh".
# CHỈ ĐỌC, không sửa model.
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'

module TK
  module HingeCheck

    PATH        = File.dirname(__FILE__).freeze
    NEST_HINT   = '__ABF_Nesting'.freeze
    NAME_RE     = /c[aá]nh/i.freeze              # nhận diện group là "cánh" (co dau hoac khong)
    DRAWER_RE   = /h[oôộ]c\s*k[eé]o/i.freeze     # "hộc kéo" — miễn bản lề
    HINGE_RE    = /hingecup/i.freeze             # dau hieu da khoet cop ban le
    MIN_HINGES  = 2
    COLOR_BAD   = Sketchup::Color.new(255, 140, 0)   # cam — rieng cho ho "thieu lien ket"

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    Violation = Struct.new(:name, :found, :need, :segs)

    # =========================================================
    #  QUÉT
    # =========================================================
    def self.run
      vios, total = scan
      return UI.messagebox('Không tìm thấy cánh nào trong mô hình (tên chứa "cánh").') if total.zero?

      if vios.empty?
        UI.messagebox("✓ Tất cả #{total} cánh đã đủ bản lề (≥#{MIN_HINGES}).")
        return
      end
      Sketchup.active_model.select_tool(ReviewTool.new(vios))
    end

    # trả về [vios, tổng số cánh đã soi]
    def self.scan
      vios  = []
      total = 0
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, vios) { total += 1 }
      [vios, total]
    end

    # ── Adapter cho bộ "Soát Trước Xuất" (TK::PreExportCheck) ───
    def self.audit
      vios, total = scan
      return { status: :na, count: 0, message: 'Không tìm thấy cánh nào (tên chứa "cánh") để kiểm tra.' } if total.zero?
      return { status: :pass, count: 0, message: "Tất cả #{total} cánh đã đủ bản lề (≥#{MIN_HINGES})." } if vios.empty?
      { status: :fail, count: vios.size, message: "#{vios.size}/#{total} cánh thiếu bản lề (cần ≥#{MIN_HINGES})." }
    end

    def self.review
      run
    end

    # =========================================================
    #  DUYỆT MÔ HÌNH
    # =========================================================
    def self.walk(entities, t, depth, vios, &on_canh)
      return if depth > 40
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.name.to_s.include?(NEST_HINT)   # bỏ qua toàn nhánh nesting — chỉ soi 3D
        te   = t * e.transformation
        name = e.name.to_s
        if name =~ NAME_RE && name !~ DRAWER_RE   # là cánh, KHÔNG phải "hộc kéo"
          on_canh.call
          check_canh(e, te, vios)
        end
        ents = ents_of(e)
        walk(ents, te, depth + 1, vios, &on_canh) if ents
      end
    end

    def self.check_canh(e, te, vios)
      ents = ents_of(e)
      return unless ents
      count = count_hinges(ents, 0)
      return if count >= MIN_HINGES
      vios << Violation.new(label(e), count, MIN_HINGES, panel_box_segs(ents, te))
    end

    def self.count_hinges(entities, depth)
      return 0 if depth > 10
      n = 0
      entities.each do |c|
        next unless c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance)
        n += 1 if c.name.to_s =~ HINGE_RE
        sub = ents_of(c)
        n += count_hinges(sub, depth + 1) if sub
      end
      n
    end

    def self.label(e)
      n = e.name.to_s
      return n.sub(/\A__/, '') unless n.empty?
      if e.is_a?(Sketchup::ComponentInstance)
        dn = e.definition.name.to_s
        return dn unless dn.empty?
      end
      '(cánh không tên)'
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # hộp bao (world) của mặt tấm cánh — dùng để vẽ khung nổi bật, tránh vẽ hết
    # mọi nét khắc chữ/ABF bên trong (rối mắt, chậm).
    def self.panel_box_segs(ents, te)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return [] if bb.empty?
      mn = bb.min; mx = bb.max
      pts = CORNERS.map do |cx, cy, cz|
        p = Geom::Point3d.new(cx.zero? ? mn.x : mx.x,
                              cy.zero? ? mn.y : mx.y,
                              cz.zero? ? mn.z : mx.z)
        te * p
      end
      EDGES12.map { |a, b| [pts[a].to_a, pts[b].to_a] }
    end

    # =========================================================
    #  TOOL XEM TỪNG CÁNH THIẾU BẢN LỀ
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
        when 27 then quit(view)
        when 39, 38 then step(1, view)
        when 37, 40 then step(-1, view)
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
        return UI.messagebox("Chỉ có #{@vios.size} cánh lỗi (1–#{@vios.size}).") if i < 0 || i >= @vios.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_outline(view, @draw_pts)
        draw_banner(view)
      end

      def focus(i)
        @idx = i
        v = @vios[i]
        @draw_pts = flatten(v.segs)
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
        @draw_pts.each { |p| bb.add(p) }
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
        l1 = "Thiếu bản lề   (cánh #{@idx + 1}/#{@vios.size})"
        l2 = v.name
        l3 = "Đã có #{v.found} bản lề — cần ≥ #{v.need}"
        l4 = '← → đổi cánh  ·  gõ số để nhảy  ·  ESC thoát'
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
        Sketchup.set_status_text("Thiếu bản lề — cánh #{@idx + 1}/#{@vios.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số cánh', SB_VCB_LABEL)
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Kiểm tra bản lề') { TK::HingeCheck.run }
      cmd.tooltip         = 'Kiểm tra cánh tủ thiếu liên kết bản lề'
      cmd.status_bar_text = "Quét mọi cánh (tên có \"cánh\"): thiếu dưới #{MIN_HINGES} bản lề thì tô cam, nhảy tới xem."
      cmd.small_icon      = File.join(icons, 'hinge_16.png')
      cmd.large_icon      = File.join(icons, 'hinge_24.png')
      cmd
    end

  end
end
