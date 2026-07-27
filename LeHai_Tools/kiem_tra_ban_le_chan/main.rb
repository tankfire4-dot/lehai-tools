# encoding: UTF-8
# Kiểm Tra Đợt Chắn Bản Lề (LỖI ĐỎ — không lắp được, không phải nhắc nhở):
# cánh đã khoét cốc bản lề, nhưng bên trong thùng có TẤM ĐỢT nằm ngang cắt đúng
# chỗ đó → đế bản lề không bắt được vào hông, lắp không vào. Phát hiện lúc ra
# xưởng thì tấm đã cắt rồi.
#
# Luật (Khoa chốt 27/07): TÂM cốc bản lề phải cách MẶT tấm đợt ≥ 80mm.
# Gần hơn = lỗi đỏ.
#
# ── Dò bằng HÌNH HỌC, KHÔNG dò theo tên (Khoa chốt 27/07) ──────────────
# Vì sao: file thật đang mở lúc bàn việc có 17/17 tấm CHƯA ĐẶT TÊN. Bản Lề Cánh
# (`kiem_tra_ban_le`) dò theo tên chứa "cánh" nên trên file đó nó mù hoàn toàn.
# Ở đây mốc neo là cốc bản lề `_ABF_hingeCup` — do ABF sinh ra, LUÔN có tên —
# nên tool chạy được cả trên file chưa ai đặt tên tấm nào.
#
#   CÁNH   = group chứa cốc bản lề (không cần tên, cứ chứa cốc là cánh)
#   TẤM ĐỢT = tấm NẰM NGANG: hộp bao dày ≤ 30mm, hai cạnh còn lại ≥ 100mm
#
# ── Loại NÓC và ĐÁY tủ (nếu không sẽ báo nhầm gần như mọi tủ) ──────────
# Nóc/đáy cũng là tấm nằm ngang, nhưng chúng ở BIÊN khoang nên không cản đế bản
# lề bao giờ. Chỉ tính tấm nằm HẲN TRONG LÒNG cánh, cách mép trên lẫn mép dưới
# cánh ≥ BIEN_MM. Nóc/đáy trùng biên cánh → rơi ra.
#
# ⚠️ Ba con số BIEN_MM / GAN_XY_MM / DAY_MAX_MM là do tool tự đặt, KHÔNG phải
# luật xưởng Khoa đọc ra. Chạy thật thấy báo thừa/báo sót thì chỉnh ở đây trước
# khi nghi phần còn lại.
#
# CHỈ ĐỌC, không sửa model. Bỏ qua nhánh `__ABF_Nesting` (bản trải phẳng).
# Không có nút riêng — chạy trong dashboard Check Chốt Sản Xuất qua audit/review.

require 'sketchup.rb'

module TK
  module HingeBlockCheck

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    HINGE_RE  = /hingecup/i.freeze     # cùng dấu hiệu với kiem_tra_ban_le/main.rb:32
    MM        = 25.4
    MAX_DEPTH = 40

    HO_MM       = 80.0    # Khoa chốt: tâm cốc cách mặt tấm đợt tối thiểu ngần này
    BIEN_MM     = 20.0    # tấm phải lùi vào trong lòng cánh ngần này mới tính (loại nóc/đáy)
    GAN_XY_MM   = 40.0    # cốc coi là "nằm trên/dưới tấm" nếu hình chiếu lọt bbox tấm nới ngần này
    DAY_MAX_MM  = 30.0    # dày hơn ngần này thì không phải ván nằm ngang
    CANH_MIN_MM = 100.0   # hai cạnh còn lại phải rộng ngần này (loại nhãn/dấu ABF vụn)

    COLOR_CUP  = Sketchup::Color.new(220, 38, 38)    # đỏ — cốc bản lề bị chắn
    COLOR_SHELF = Sketchup::Color.new(230, 160, 0)   # cam — tấm đợt đang chắn

    CORNERS = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
               [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    EDGES12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
               [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    Panel = Struct.new(:name, :ab)                        # ab = [xmin,ymin,zmin,xmax,ymax,zmax] world
    Cup   = Struct.new(:center, :door)                    # tâm cốc + cánh chứa nó
    Vio   = Struct.new(:door_name, :shelf_name, :gap_mm, :cup_segs, :shelf_segs, :center)

    # =========================================================
    #  Adapter cho dashboard (TK::PreExportCheck)
    # =========================================================
    def self.audit
      cups, shelves = collect_all
      return { status: :na, count: 0,
               message: 'Không thấy cốc bản lề nào để kiểm tra.' } if cups.empty?
      vios = find_blocked(cups, shelves)
      return { status: :pass, count: 0,
               message: "Đã soi #{cups.size} cốc bản lề — không cái nào bị tấm đợt chắn." } if vios.empty?
      { status: :fail, count: vios.size,
        message: "#{vios.size} cốc bản lề bị tấm đợt chắn (gần hơn #{fmt(HO_MM)}mm) — lắp không vào." }
    end

    def self.review
      run
    end

    def self.run
      cups, shelves = collect_all
      return UI.messagebox('Không thấy cốc bản lề nào trong mô hình (group tên "_ABF_hingeCup").') if cups.empty?
      vios = find_blocked(cups, shelves)
      if vios.empty?
        UI.messagebox("Đã soi #{cups.size} cốc bản lề trên #{shelves.size} tấm nằm ngang.\n\n" \
                      "Không cốc nào bị tấm đợt chắn (đều cách ≥ #{fmt(HO_MM)}mm).")
        return
      end
      Sketchup.active_model.select_tool(ReviewTool.new(vios))
    end

    # =========================================================
    #  GHÉP — cốc nào bị tấm đợt nào chắn
    # =========================================================
    def self.find_blocked(cups, shelves)
      vios = []
      cups.each do |cup|
        d = cup.door.ab
        shelves.each do |s|
          a = s.ab
          next if s.equal?(cup.door)
          # 1. tấm phải nằm HẲN TRONG LÒNG cánh theo chiều đứng — loại nóc/đáy ở biên
          next unless a[2] >= d[2] + BIEN_MM / MM && a[5] <= d[5] - BIEN_MM / MM
          # 2. hình chiếu bằng của cốc phải lọt vào bóng tấm (nới GAN_XY_MM)
          near = GAN_XY_MM / MM
          c = cup.center
          next unless c.x >= a[0] - near && c.x <= a[3] + near
          next unless c.y >= a[1] - near && c.y <= a[4] + near
          # 3. khoảng cách đứng từ tâm cốc tới KHỐI tấm (nằm trong khối = 0)
          gap = if c.z >= a[2] && c.z <= a[5] then 0.0
                else [(c.z - a[2]).abs, (c.z - a[5]).abs].min
                end
          gap_mm = gap * MM
          next if gap_mm >= HO_MM
          vios << Vio.new(cup.door.name, s.name, gap_mm,
                          cup_box_segs(c), aabb_box_segs(a), c)
        end
      end
      vios.sort_by(&:gap_mm)
    end

    # =========================================================
    #  QUÉT MÔ HÌNH
    #  Group có FACE trực tiếp = một TẤM. Group chứa cốc bản lề = CÁNH.
    # =========================================================
    def self.collect_all
      cups = []; shelves = []
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, cups, shelves)
      [cups, shelves]
    end

    def self.walk(entities, t, depth, cups, shelves)
      return if depth > MAX_DEPTH || entities.nil?
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.name.to_s.include?(NEST_HINT)
        te   = t * e.transformation
        ents = ents_of(e)
        next unless ents

        ab = world_aabb(ents, te)     # nil nếu group không có face trực tiếp (vd cốc, nhãn)
        if ab
          panel = Panel.new(label(e), ab)
          shelves << panel if nam_ngang?(ab)
          # cốc nằm trong tấm nào thì tấm đó là CÁNH — không cần tên
          centers = []
          collect_cups(ents, te, 0, centers)
          centers.each { |c| cups << Cup.new(c, panel) }
        end

        walk(ents, te, depth + 1, cups, shelves)
      end
    end

    # tâm world từng cốc — cốc CHỈ CÓ EDGE, không có face, phải lấy bounds.center
    # (sketchup-api.md: "_ABF_hingeCup chỉ có EDGES"). Khuôn: kiem_tra_ban_le/main.rb:128
    def self.collect_cups(entities, te, depth, out)
      return if depth > 10
      entities.each do |c|
        next unless c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance)
        if c.name.to_s =~ HINGE_RE
          out << (te * c.bounds.center)
          next
        end
        sub = ents_of(c)
        next unless sub
        # Nhóm con nào TỰ CÓ mặt phẳng thì nó là một TẤM riêng — `walk` sẽ nhận nó
        # làm cánh của mình. Không chui xuống nữa, kẻo một cốc bị đếm hai lần
        # (một lần cho tấm ngoài, một lần cho tấm trong).
        next if co_face?(sub)
        collect_cups(sub, te * c.transformation, depth + 1, out)
      end
    end

    def self.co_face?(ents)
      ents.each { |c| return true if c.is_a?(Sketchup::Face) }
      false
    end

    def self.nam_ngang?(ab)
      dz = (ab[5] - ab[2]) * MM
      dx = (ab[3] - ab[0]) * MM
      dy = (ab[4] - ab[1]) * MM
      dz <= DAY_MAX_MM && dx >= CANH_MIN_MM && dy >= CANH_MIN_MM
    end

    # hộp bao WORLD từ các face TRỰC TIẾP trong group (khuôn kiem_tra_led/main.rb:136)
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

    # hộp nhỏ quanh tâm cốc để nhìn thấy nó giữa rừng nét
    def self.cup_box_segs(c)
      r = 40.0 / MM
      ab = [c.x - r, c.y - r, c.z - r, c.x + r, c.y + r, c.z + r]
      aabb_box_segs(ab)
    end

    def self.label(e)
      n = e.name.to_s.strip
      return n.sub(/\A__/, '') unless n.empty?
      if e.is_a?(Sketchup::ComponentInstance)
        dn = e.definition.name.to_s.strip
        return dn unless dn.empty?
      end
      '(tấm chưa đặt tên)'
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
    #  TOOL LƯỚT XEM — khuôn kiem_tra_led/main.rb:172
    # =========================================================
    class ReviewTool
      def initialize(vios)
        @items = vios
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
        return UI.messagebox("Chỉ có #{@items.size} chỗ (1–#{@items.size}).") if i < 0 || i >= @items.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        draw_segs(view, @cup_pts,   COLOR_CUP)
        draw_segs(view, @shelf_pts, COLOR_SHELF)
        draw_banner(view)
      end

      def focus(i)
        @idx       = i
        @cup_pts   = flatten(@items[i].cup_segs)
        @shelf_pts = flatten(@items[i].shelf_segs)
        @bounds    = focus_bounds
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
        @cup_pts.each { |p| bb.add(p) }
        c = @items[@idx].center
        m = 400.0 / 25.4
        bb.add(c.offset(Geom::Vector3d.new(m, m, m)))
        bb.add(c.offset(Geom::Vector3d.new(-m, -m, -m)))
        bb
      end

      def draw_segs(view, pts, color)
        return if pts.nil? || pts.empty?
        view.line_width = 3
        view.drawing_color = color
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end

      def draw_banner(view)
        v  = @items[@idx]
        l1 = "⚠ Đợt chắn bản lề — hở #{TK::HingeBlockCheck.fmt(v.gap_mm)}mm   (#{@idx + 1}/#{@items.size})"
        l2 = "Cánh: #{v.door_name}   ·   Tấm chắn: #{v.shelf_name}"
        l3 = "Đỏ = cốc bản lề, cam = tấm đang chắn. Cần ≥ #{TK::HingeBlockCheck.fmt(HO_MM)}mm mới lắp được."
        l4 = '← → đổi  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, COLOR_CUP)
        txt(view, 34, 26, l1, Sketchup::Color.new(255, 150, 150), 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, Sketchup::Color.new(255, 210, 150), 12, false)
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
        Sketchup.set_status_text("Đợt chắn bản lề — #{@idx + 1}/#{@items.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số mục', SB_VCB_LABEL)
      end
    end

  end
end
