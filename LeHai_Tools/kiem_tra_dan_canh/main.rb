# encoding: UTF-8
# Kiểm Tra Dán Cạnh (CẢNH BÁO vàng, mức THÔ — không chặn cứng):
#
# ── NGUỒN CHÍNH: attribute trên MÔ HÌNH 3D (đổi 27/07/2026) ───────────
# Khoa hỏi: "sao bấm Xem nó zoom tới bản 2D nesting, ABF biết đường đâu mà trải
# ra?". Đo lại bằng `probes/dan_canh_3d_probe.rb` + `abf_attr_full.rb` thì lòi ra:
#
#   FACE nào được dán cạnh mang attribute  ABF / edge-band-id
#   → face đó chính là MẶT CẠNH của tấm (kích thước luôn <dài> × 17,5 × 0)
#
# Đây mới là CÁI GỐC. Group "_ABF_edgeBanding" chỉ sinh ra lúc nesting (đo thật:
# **0 cái** ở khu 3D, 13 cái trong `__ABF_Nesting`) — nó là CÁI BÓNG. Đếm bóng thì
# file đã đánh dấu dán cạnh xong mà CHƯA nesting sẽ bị báo nhầm "chưa dán", và
# "Xem" không thể chỉ tới cạnh trên tủ.
#
# ⚠️ KHÔNG dùng `edge-band-types` làm bằng chứng đã dán. Nó là CẤU HÌNH loại chỉ
# của tấm, không phải dấu đã dán: đo thật 16 tấm mang key đó nhưng **4 tấm trong
# số đó không có face nào được dán**. Dùng nó là báo nhầm 4 tấm.
#
# Vẫn giữ hai nguồn phụ, xếp sau: dấu 2D `_ABF_edgeBanding` (file cũ chỉ còn bản
# nesting) và material "Hung_Show_ABF_..." của tool Auto Dán Cạnh nhà mình.
#
# Mức thô theo yêu cầu Khoa: chỉ xét "cả file đã có ai dán cạnh chưa" — vì quy
# tắc cạnh nào PHẢI dán rất phức tạp (đế phải dán dù không lộ...), không suy từ
# hình học được. Không thấy dấu nào → cảnh báo; có dấu → coi như đã làm.
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
    # chi = tên loại chỉ đọc từ `edge-band-types`; so_mat = mấy mặt gộp lại (cạnh
    # cong bị SketchUp chia thành hàng trăm mặt con — xem ghi chú ở collect_marks_3d)
    Mark = Struct.new(:owner, :in_nest, :segs, :center, :chi, :so_mat)

    # Đếm số group/comp mang dấu dán cạnh CỦA ABF trong toàn model.
    def self.count
      n = 0
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, '', false) do |e, _t, _own, _nest|
        n += 1 if e.name.to_s =~ EDGE_RE
      end
      n
    end

    # ── NGUỒN CHÍNH: cạnh đã dán trên MÔ HÌNH 3D ───────────────
    # Mỗi FACE mang attribute ABF/edge-band-id = một cạnh đã dán. Face đó là mặt
    # cạnh thật của tấm nên "Xem" chỉ đúng vào dải chỉ trên tủ, không phải bản 2D.
    def self.collect_marks_3d
      out = []
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, '', false) do |e, t, owner, nest|
        next if nest                       # khu 3D thôi — bản trải phẳng để nguồn phụ lo
        sub = ents_of(e)
        next unless sub
        te    = t * e.transformation
        ten   = ten_hoac(e, owner)
        types = band_types(e)

        # GOM theo (tấm, loại chỉ) — KHÔNG đếm từng face.
        # Đo thật 28/07 trên file sản xuất `CNC C.THUY`: **2099 face** mang
        # `edge-band-id`, vì tấm CONG bị SketchUp chia cạnh thành hàng trăm mặt
        # con (`18×7×0.1`, `18×6×3.2`…). Đếm face = con số vô nghĩa + bắt người
        # dùng lướt 2099 mục. File thử hôm trước toàn tấm phẳng nên không lộ —
        # đúng bẫy `sketchup-api.md` đã ghi: hình cong là ca thử bắt buộc.
        nhom = {}
        sub.grep(Sketchup::Face).each do |f|
          id = band_id(f)
          next if id.nil?
          pts = f.outer_loop.vertices.map { |v| te * v.position }   # khuôn chia_lam/main.rb:184
          next if pts.size < 3
          (nhom[id] ||= []) << pts
        end

        nhom.each do |id, loops|
          segs = []
          loops.each { |pts| segs.concat(loop_segs(pts)) }
          out << Mark.new(ten, false, segs, tam_diem(loops.first),
                          types[id] || "loại #{id}", loops.size)
        end
      end
      out
    end

    # `edge-band-types` là MẢNG NHIỀU BỘ 5: [id, tên chỉ, ?, màu, ?] lặp lại.
    # `edge-band-id` trên face là KHOÁ TRA vào bảng này của chính tấm đó — hôm
    # 27/07 tưởng id toàn 0 nên vô nghĩa, sai: file chỉ có MỘT loại chỉ thì mới
    # toàn 0. Tấm dùng hai loại có cả id 0 lẫn 1 (vd 3 cạnh "don 205 SH" + 1 cạnh
    # "Vat45" — Vat45 là VÁT 45°, không phải dán chỉ).
    def self.band_types(e)
      d = (e.attribute_dictionary('ABF') rescue nil)
      return {} if d.nil?
      arr = d['edge-band-types']
      return {} unless arr.is_a?(Array)
      h = {}
      i = 0
      while i + 1 < arr.size
        h[arr[i].to_i] = arr[i + 1].to_s
        i += 5
      end
      h
    rescue StandardError
      # nuốt được: helper thuần đọc, bảng đọc hỏng thì lùi về nhãn "loại N"
      {}
    end

    def self.band_id(f)
      d = f.attribute_dictionary('ABF')
      return nil if d.nil?
      v = d['edge-band-id']
      v.nil? ? nil : v.to_i
    rescue StandardError
      nil
    end

    # viền khép kín của mặt cạnh — dựng toạ độ thủ công, KHÔNG splat Point3d
    # (Point3d#to_a chưa có tiền lệ chạy thật nào trong repo)
    def self.loop_segs(pts)
      segs = []
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.size]
        segs << [[p.x, p.y, p.z], [q.x, q.y, q.z]]
      end
      segs
    end

    def self.tam_diem(pts)
      n = pts.size
      Geom::Point3d.new(pts.inject(0.0) { |s, p| s + p.x } / n,
                        pts.inject(0.0) { |s, p| s + p.y } / n,
                        pts.inject(0.0) { |s, p| s + p.z } / n)
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # ── NGUỒN PHỤ: dấu `_ABF_edgeBanding` (chỉ có ở bản trải phẳng) ──
    def self.collect_marks
      out = []
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, '', false) do |e, t, owner, nest|
        next unless e.name.to_s =~ EDGE_RE
        ab = world_aabb_of(e, t)
        next unless ab
        c = Geom::Point3d.new((ab[0] + ab[3]) / 2, (ab[1] + ab[4]) / 2, (ab[2] + ab[5]) / 2)
        out << Mark.new(owner.empty? ? '(tấm chưa đặt tên)' : owner, nest, aabb_box_segs(ab), c, nil, 1)
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
      m3 = collect_marks_3d
      unless m3.empty?
        n_tam = m3.map(&:owner).uniq.size
        chi   = m3.map(&:chi).compact.uniq
        return { status: :pass, count: n_tam,
                 message: "Đã dán cạnh trên #{n_tam} tấm — #{chi.size} loại chỉ (mô hình 3D)." }
      end
      n = count
      return { status: :pass, count: n,
               message: "Đã dán #{n} cạnh (dấu ở bản trải phẳng)." } if n.positive?
      return { status: :pass, count: 0, message: 'Đã dán cạnh (Auto Dán Cạnh).' } if auto_banded?
      { status: :warn, count: 0,
        message: 'Chưa thấy cạnh nào được dán — kiểm tra file đã chạy dán cạnh chưa.' }
    end

    def self.review
      # Ưu tiên cạnh trên TỦ 3D; hết cách mới lùi về dấu ở bản trải phẳng.
      marks = collect_marks_3d
      marks = collect_marks if marks.empty?
      if !marks.empty?
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
        l1 = "✓ Cạnh đã dán   (#{@idx + 1}/#{@items.size})" +
              (v.so_mat.to_i > 1 ? "   — gộp #{v.so_mat} mặt (cạnh cong)" : '')
        l2 = v.chi ? "#{v.owner}   ·   chỉ: #{v.chi}" : v.owner
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
