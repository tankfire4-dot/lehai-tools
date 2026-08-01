# encoding: UTF-8
# Kiểm Tra Khoảng Cách: sau khi nesting bằng ABF, quét MỌI tấm ván, đo khoảng
# hở giữa các tấm chi tiết với nhau VÀ với mép tấm ván. Cặp nào < 7mm (dao CNC
# không lọt / nguy cơ phạm tấm bên) → tô ĐỎ + nhảy tới từng cặp để xem.
# Đo theo ĐƯỜNG VIỀN thật (tấm nesting chỉ có edges, phẳng) — không qua bounding box.
# CHỈ ĐỌC, không sửa model.
#
# ── NHẮC VÀNG cho chi tiết CHỐNG BAY (Khoa chốt 01/08) ────────────────
# Chi tiết đã được plugin Chống Bay gắn tag (tên tag khớp /chongbay/i) thường là
# chi tiết NHỎ — dễ bay khi CNC cắt. Loại này nên hở ≥ 12mm thay vì 7mm.
# Cặp nào có ÍT NHẤT MỘT bên là chi tiết chống bay và hở 7–12mm → NHẮC VÀNG.
#
# Vì sao VÀNG chứ không ĐỎ (Khoa nói rõ): "tuỳ chi tiết lớn thì để 7mm cũng được,
# chi tiết nhỏ thì cần cách 12mm". Máy KHÔNG biết thế nào là nhỏ — nó chỉ biết
# tấm đó có tag chống bay hay không. Nên nó nêu ra cho người quyết, KHÔNG chặn
# xuất DXF. Đỏ ở đây sẽ là báo động sai hàng loạt, mà báo động sai nhiều lần thì
# người ta bắt đầu bỏ qua cả báo động thật (xem SOAT_LOI.md mục G1).
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'

module TK
  module SpacingCheck

    PATH      = File.dirname(__FILE__).freeze
    DICT      = 'ABF'.freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    GAP_MM    = 7.0          # khoang cach toi thieu can co (mm)
    TOL_MM    = 0.1          # dung sai do dac, tranh bao nham o dung 7mm
    MM        = 25.4
    GAP_INCH  = GAP_MM / MM
    TOL_INCH  = TOL_MM / MM

    # ── NHAC VANG cho chi tiet CHONG BAY (Khoa chot 01/08) ──────────────
    # Chi tiet da duoc plugin Chong Bay gan tag thi thuong la chi tiet NHO —
    # de bay khi CNC cat. Loai nay nen ho >= 12mm chu khong phai 7mm.
    # NHUNG day la NHAC (vang), KHONG phai loi (do): Khoa noi ro "tuy chi tiet
    # lon thi 7mm cung duoc, chi tiet nho thi can 12mm" — may khong biet the nao
    # la nho, nen chi neu ra cho nguoi quyet, khong chan xuat DXF.
    GAP_CB_MM   = 12.0
    GAP_CB_INCH = GAP_CB_MM / MM
    CB_RE       = /chongbay/i.freeze   # cung dau hieu voi chong_bay/main.rb:26 (DST_RE)

    COLOR_BAD  = Sketchup::Color.new(255, 40, 40)    # do = tam vi pham
    COLOR_WARN = Sketchup::Color.new(230, 160, 0)    # vang-cam = nhac chong bay
    COLOR_GAP  = Sketchup::Color.new(255, 0, 200)    # hong canh sen = vach khoang ho (noi tren nen xam)

    Violation = Struct.new(:kind, :sheet, :gap_mm, :segs_a, :segs_b, :ca, :cb, :label)

    # nhac vang thi khong phai loi do
    def self.nhac?(v)
      v.kind == :pair_cb
    end

    # Tam nay co phai chi tiet CHONG BAY khong?
    #
    # ⚠️ BAY DA MAC 01/08 (do live tren file that): tag chong bay KHONG nam o group
    # tam. `chong_bay/main.rb:588-594` gan tag cho entity nao co tag `ABF_cuttingLines`
    # — tuc la ĐƯỜNG CẮT NẰM BÊN TRONG tam. Ban dau doan sai o day chi hoi
    # `board.layer.name` -> LUC NAO CUNG false -> nhac vang khong bao gio bat, ma
    # dashboard van xanh nen KHONG AI BIET. Do live moi lo: file co 200 tag chong bay
    # va 446 cap trong dai 7-12mm ma khong cap nao dinh tag — con so khong the co that.
    #
    # Nen phai soi CA CAY CON, dung ngay khi thay tag dau tien.
    def self.chong_bay?(e, depth = 0)
      return false if depth > 8
      return true if tag_cb?(e)
      ents = ents_of(e)
      return false unless ents
      ents.each do |c|
        if c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance)
          return true if chong_bay?(c, depth + 1)
        elsif tag_cb?(c)
          return true
        end
      end
      false
    end

    def self.tag_cb?(e)
      (e.layer.name.to_s rescue '') =~ CB_RE ? true : false
    end

    # =========================================================
    #  QUET — tra ve mang Violation
    # =========================================================
    def self.run
      Sketchup.set_status_text('Đang quét khoảng cách...', SB_PROMPT)
      vios = scan
      Sketchup.set_status_text('', SB_PROMPT)
      return UI.messagebox("Không thấy nesting (#{NEST_HINT}).") if vios.nil?

      if vios.empty?
        UI.messagebox("✓ Tất cả các tấm cách nhau & cách mép ≥ #{GAP_MM}mm. Không có vi phạm.")
        return
      end
      # Gần nhất (nguy hiểm nhất) lên đầu. Không cần xếp riêng đỏ/vàng: mọi lỗi đỏ
      # đều < 7mm còn mọi nhắc vàng đều 7–12mm, nên xếp theo gap_mm là đỏ tự lên trước.
      vios.sort_by!(&:gap_mm)
      nhac = vios.count { |v| nhac?(v) }
      if nhac > 0 && nhac == vios.size
        UI.messagebox("Không cặp nào dưới #{GAP_MM}mm — về khoảng cách là ĐẠT.\n\n" \
                      "Chỉ nhắc: có chi tiết chống bay chỉ hở #{GAP_MM}–#{GAP_CB_MM}mm " \
                      "(#{nhac} cặp). Loại nhỏ nên để ≥ #{GAP_CB_MM}mm.\n\n" \
                      "Máy không biết tấm nào là nhỏ — chỉ nhắc, không chặn xuất DXF.\n" \
                      'Muốn soi từng cặp thì bấm OK; không cần thì ESC.')
      end
      Sketchup.active_model.select_tool(ReviewTool.new(vios))
    end

    # ── Adapter cho bộ "Soát Trước Xuất" (TK::PreExportCheck) ───
    def self.audit
      vios = scan
      return { status: :na, count: 0, message: "Không tìm thấy nesting (#{NEST_HINT})." } if vios.nil?
      return { status: :pass, count: 0, message: "Tất cả cách nhau & cách mép ≥ #{GAP_MM}mm." } if vios.empty?

      nhac = vios.count { |v| nhac?(v) }
      loi  = vios.size - nhac

      # Co loi do thi bao do. Nhac vang di kem mot ve cau, khong lam mo trong tam.
      if loi > 0
        # Ve nhac PHAI co con so, khong thi no troi tuot ben canh con so cua ve do.
        # (Khoa 01/08 nhin file that: "ua co thay nhac toi 12mm nao dau" — chu co that
        #  nhung khong co so nen mat khong bat duoc.)
        msg = "#{loi} cặp hở dưới #{GAP_MM}mm."
        msg += " ⚠ Kèm nhắc: #{nhac} cặp chi tiết chống bay hở #{GAP_MM}–#{GAP_CB_MM}mm (nên ≥ #{GAP_CB_MM}mm)." if nhac > 0
        return { status: :fail, count: loi, message: msg }
      end

      # Chi con nhac vang. Doc ky cau chu duoi day truoc khi sua:
      # day la NHAC, khong phai dem loi. Khoa chot 01/08: "chi can co dong chu mau
      # vang chu yeu la nhac nho thoi, chu chung ta lam sao tinh duoc no co nho hay
      # khong". Nen KHONG dua con so len dau cau — dua con so len dau la bien nhac
      # thanh phan xet, ma may khong du tu cach phan xet o day.
      { status: :warn, count: nhac,
        message: "Tất cả cách nhau & cách mép ≥ #{GAP_MM}mm. Nhắc: có chi tiết chống bay chỉ hở " \
                 "#{GAP_MM}–#{GAP_CB_MM}mm (#{nhac} cặp) — loại nhỏ nên để ≥ #{GAP_CB_MM}mm." }
    end

    def self.review
      run
    end

    def self.scan
      found = find_nest(Sketchup.active_model.entities, Geom::Transformation.new)
      return nil unless found
      nest, t_nest = found
      vios = []
      kids(nest).each do |sheet|
        process_sheet(sheet, t_nest * sheet.transformation, vios)
      end
      vios
    end

    def self.process_sheet(sheet, t_sheet, vios)
      data = boards_of(sheet).map do |b|
        segs = []
        walk_edges(b, t_sheet * b.transformation, segs)
        { name: board_label(b), segs: segs, bbox: bbox_of(segs), cb: chong_bay?(b) }
      end
      check_pairs(sheet.name.to_s, data, vios)
      check_border(sheet, t_sheet, data, vios)
    end

    # ── tam <-> tam (cung sheet) ──
    def self.check_pairs(sheet_name, data, vios)
      data.each_with_index do |a, i|
        ((i + 1)...data.size).each do |j|
          b = data[j]
          # Cap co CHI MOT ben la chi tiet chong bay cung phai xet o nguong 12mm:
          # cai de bay la chi tiet nho, hang xom to hay nho khong doi duoc dieu do.
          co_cb    = a[:cb] || b[:cb]
          nguong   = co_cb ? GAP_CB_INCH : GAP_INCH
          next if aabb_far?(a[:bbox], b[:bbox], nguong)
          dist, ca, cpb = min_dist(a[:segs], b[:segs])
          next if dist.nil?
          nhan = "#{a[:name]}  ↔  #{b[:name]}"
          if dist < GAP_INCH - TOL_INCH
            # duoi 7mm — LOI DO, khong lien quan chong bay
            vios << Violation.new(:pair, sheet_name, (dist * MM).round(1),
                                  a[:segs], b[:segs], ca, cpb, nhan)
          elsif co_cb && dist < GAP_CB_INCH - TOL_INCH
            # 7-12mm VA co chi tiet chong bay — NHAC VANG, khong chan xuat
            vios << Violation.new(:pair_cb, sheet_name, (dist * MM).round(1),
                                  a[:segs], b[:segs], ca, cpb,
                                  "#{nhan}   [chống bay]")
          end
        end
      end
    end

    # ── tam <-> mep tam van ──
    def self.check_border(sheet, t_sheet, data, vios)
      border = border_of(sheet)
      return unless border
      bsegs = []
      walk_edges(border, t_sheet * border.transformation, bsegs)
      return if bsegs.empty?
      data.each do |a|
        dist, ca, cb = min_dist(a[:segs], bsegs)
        next if dist.nil? || dist >= GAP_INCH - TOL_INCH
        vios << Violation.new(:border, sheet.name.to_s, (dist * MM).round(1),
                              a[:segs], bsegs, ca, cb,
                              "#{a[:name]}  ↔  mép tấm ván")
      end
    end

    # =========================================================
    #  DUYET / GOM HINH HOC
    # =========================================================
    def self.find_nest(entities, accum, depth = 0)
      return nil if depth > 4
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        t = accum * e.transformation
        return [e, t] if e.name.to_s.include?(NEST_HINT)
        r = find_nest(ents_of(e), t, depth + 1)
        return r if r
      end
      nil
    end

    # gom moi edge (the gioi) trong group, BO QUA sub-group nhan
    def self.walk_edges(grp, t, segs, depth = 0)
      return if depth > 8
      ents = ents_of(grp)
      return unless ents
      ents.each do |c|
        if c.is_a?(Sketchup::Edge)
          segs << [(t * c.start.position).to_a, (t * c.end.position).to_a]
        elsif c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance)
          next if label?(c)
          walk_edges(c, t * c.transformation, segs, depth + 1)
        end
      end
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    def self.kids(e)
      (ents_of(e) || []).select { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
    end

    def self.label?(c)
      d = c.attribute_dictionary(DICT)
      (d && d['is-label'] == true) || c.name.to_s.include?('_ABF_Label')
    end

    def self.boards_of(sheet)
      kids(sheet).select do |c|
        d = c.attribute_dictionary(DICT)
        d && d['is-board'] == true
      end
    end

    def self.border_of(sheet)
      kids(sheet).find do |c|
        d = c.attribute_dictionary(DICT)
        d && d['is-sheet-border'] == true
      end
    end

    def self.board_label(b)
      b.name.to_s.sub(/\A__/, '')
    end

    # =========================================================
    #  TOAN HINH HOC (lam tren mang [x,y,z], don vi inch)
    # =========================================================
    def self.bbox_of(segs)
      bb = Geom::BoundingBox.new
      segs.each { |a, b| bb.add(Geom::Point3d.new(*a)); bb.add(Geom::Point3d.new(*b)) }
      bb
    end

    # AABB cach nhau hon gap? (loc tho cho nhanh)
    def self.aabb_far?(bb1, bb2, gap)
      return true if bb1.empty? || bb2.empty?
      dx = axis_gap(bb1.min.x, bb1.max.x, bb2.min.x, bb2.max.x)
      dy = axis_gap(bb1.min.y, bb1.max.y, bb2.min.y, bb2.max.y)
      dz = axis_gap(bb1.min.z, bb1.max.z, bb2.min.z, bb2.max.z)
      (dx * dx + dy * dy + dz * dz) > gap * gap
    end

    def self.axis_gap(min1, max1, min2, max2)
      return min2 - max1 if max1 < min2
      return min1 - max2 if max2 < min1
      0.0
    end

    # khoang cach nho nhat giua 2 tap doan thang -> [dist, ca, cb] (inch)
    # Toi uu: bo qua cap canh co AABB cach xa hon GAP (khong the la min < 7mm)
    # -> chi tinh seg_seg cho cac cap canh THUC SU gan -> nhanh hon nhieu.
    def self.min_dist(segs_a, segs_b)
      best = nil; bca = nil; bcb = nil
      g2 = GAP_INCH * GAP_INCH
      baabb = segs_b.map { |b1, b2| edge_aabb(b1, b2) }
      segs_a.each do |a1, a2|
        aab = edge_aabb(a1, a2)
        segs_b.each_with_index do |(b1, b2), k|
          next if edge_far?(aab, baabb[k], g2)
          d, ca, cb = seg_seg(a1, a2, b1, b2)
          next if best && d >= best
          best = d; bca = ca; bcb = cb
        end
      end
      [best, bca, bcb]
    end

    # AABB cua 1 doan thang -> [minx,miny,minz, maxx,maxy,maxz]
    def self.edge_aabb(p, q)
      [p[0] < q[0] ? p[0] : q[0], p[1] < q[1] ? p[1] : q[1], p[2] < q[2] ? p[2] : q[2],
       p[0] > q[0] ? p[0] : q[0], p[1] > q[1] ? p[1] : q[1], p[2] > q[2] ? p[2] : q[2]]
    end

    # 2 AABB canh cach xa hon GAP? (so binh phuong cho nhanh)
    def self.edge_far?(ea, eb, gap2)
      dx = axis_gap(ea[0], ea[3], eb[0], eb[3])
      dy = axis_gap(ea[1], ea[4], eb[1], eb[4])
      dz = axis_gap(ea[2], ea[5], eb[2], eb[5])
      (dx * dx + dy * dy + dz * dz) > gap2
    end

    # khoang cach 2 doan thang 3D (Ericson) -> [dist, closestA, closestB]
    def self.seg_seg(p1, p2, q1, q2)
      d1 = vsub(p2, p1); d2 = vsub(q2, q1); r = vsub(p1, q1)
      a = vdot(d1, d1); e = vdot(d2, d2); f = vdot(d2, r)
      eps = 1e-14
      s, t = seg_seg_params(d1, d2, r, a, e, f, eps)
      ca = vadd(p1, vscale(d1, s)); cb = vadd(q1, vscale(d2, t))
      [vlen(vsub(ca, cb)), ca, cb]
    end

    def self.seg_seg_params(d1, d2, r, a, e, f, eps)
      return [0.0, clamp(f / e)] if a <= eps && e > eps
      return [clamp(-vdot(d1, r) / a), 0.0] if e <= eps && a > eps
      return [0.0, 0.0] if a <= eps && e <= eps
      b = vdot(d1, d2); c = vdot(d1, r); denom = a * e - b * b
      s = denom > eps ? clamp((b * f - c * e) / denom) : 0.0
      t = (b * s + f) / e
      return [clamp(-c / a), 0.0] if t < 0.0
      return [clamp((b - c) / a), 1.0] if t > 1.0
      [s, t]
    end

    def self.clamp(v) [[v, 0.0].max, 1.0].min end
    def self.vsub(a, b) [a[0] - b[0], a[1] - b[1], a[2] - b[2]] end
    def self.vadd(a, b) [a[0] + b[0], a[1] + b[1], a[2] + b[2]] end
    def self.vscale(a, s) [a[0] * s, a[1] * s, a[2] * s] end
    def self.vdot(a, b) a[0] * b[0] + a[1] * b[1] + a[2] * b[2] end
    def self.vlen(a) Math.sqrt(vdot(a, a)) end

    # =========================================================
    #  TOOL XEM TUNG CAP VI PHAM
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
        when 39, 38 then step(1, view)     # Right / Up -> cap sau
        when 37, 40 then step(-1, view)    # Left / Down -> cap truoc
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
        draw_gap(view)
        draw_banner(view)
      end

      # ── focus 1 cap ──
      def focus(i)
        @idx = i
        v = @vios[i]
        @draw_a = flatten(v.segs_a)
        @draw_b = flatten(v.segs_b)
        @gap_a  = Geom::Point3d.new(*v.ca)
        @gap_b  = Geom::Point3d.new(*v.cb)
        @bounds = focus_bounds(v)
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

      # vung zoom: tam A + khoang ho (+ tam B neu la cap tam-tam, khong lay ca mep van)
      def focus_bounds(v)
        bb = Geom::BoundingBox.new
        @draw_a.each { |p| bb.add(p) }
        bb.add(@gap_a); bb.add(@gap_b)
        @draw_b.each { |p| bb.add(p) } if v.kind == :pair || v.kind == :pair_cb
        bb
      end

      # ── ve ──
      # mau vien theo loai: nhac chong bay = vang, loi that = do
      def mau_hien_tai
        TK::SpacingCheck.nhac?(@vios[@idx]) ? COLOR_WARN : COLOR_BAD
      end

      def draw_outline(view, pts)
        return if pts.empty?
        view.line_width = 3
        view.drawing_color = mau_hien_tai
        view.draw(GL_LINES, pts)
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) }) # noi tren cung
      end

      def draw_gap(view)
        a = view.screen_coords(@gap_a)
        b = view.screen_coords(@gap_b)
        view.line_width = 6
        view.drawing_color = COLOR_GAP
        view.draw(GL_LINES, [@gap_a, @gap_b])  # 3D
        view.draw2d(GL_LINES, [a, b])          # 2D noi tren cung
        draw_gap_ticks(view, a, b)
        draw_gap_label(view, a, b)
      end

      # vach vuong goc 2 dau cho ro nhu duong kich thuoc
      def draw_gap_ticks(view, a, b)
        dx = b.x - a.x; dy = b.y - a.y
        len = Math.sqrt(dx * dx + dy * dy)
        return if len < 1.0
        px = -dy / len * 7.0; py = dx / len * 7.0
        view.line_width = 3
        view.drawing_color = COLOR_GAP
        view.draw2d(GL_LINES, [tick(a, px, py), tick(a, -px, -py),
                               tick(b, px, py), tick(b, -px, -py)])
      end

      def tick(p, dx, dy)
        Geom::Point3d.new(p.x + dx, p.y + dy, 0)
      end

      # so mm tren chip toi -> luon doc duoc du nen gi
      def draw_gap_label(view, a, b)
        cx = (a.x + b.x) / 2.0
        cy = (a.y + b.y) / 2.0 - 24
        s  = "#{@vios[@idx].gap_mm}mm"
        w  = 16 + s.length * 9
        draw_box2d(view, cx - w / 2.0, cy - 13, w, 26, Sketchup::Color.new(18, 22, 30, 235))
        draw_box2d(view, cx - w / 2.0, cy - 13, 4, 26, COLOR_GAP)
        txt(view, cx - w / 2.0 + 10, cy - 8, s, Sketchup::Color.new(255, 255, 255), 14, true)
      end

      def draw_banner(view)
        v     = @vios[@idx]
        nhac  = TK::SpacingCheck.nhac?(v)
        l1 = if nhac
               "⚠ Chống bay — hở #{v.gap_mm}mm, nên ≥ #{TK::SpacingCheck::GAP_CB_MM}mm   " \
               "(cặp #{@idx + 1}/#{@vios.size})"
             else
               "Hở #{v.gap_mm}mm < #{TK::SpacingCheck::GAP_MM}mm   (cặp #{@idx + 1}/#{@vios.size})"
             end
        l2 = "#{v.label}   ·   #{v.sheet}"
        l3 = if nhac
               'Chi tiết NHỎ cần ≥ 12mm; chi tiết LỚN thì 7mm vẫn được — người soát quyết.'
             else
               '← → đổi cặp  ·  gõ số để nhảy  ·  ESC thoát'
             end
        l4 = nhac ? '← → đổi cặp  ·  gõ số để nhảy  ·  ESC thoát' : nil
        rows = [l1, l2, l3, l4].compact
        bg_h = 22 * rows.size + 14
        bg_w = 26 + rows.map(&:length).max * 8
        draw_box2d(view, 18, 18, bg_w, bg_h, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, bg_h, nhac ? COLOR_WARN : COLOR_BAD)
        txt(view, 34, 26, l1, nhac ? Sketchup::Color.new(255, 200, 90) : Sketchup::Color.new(255, 120, 120), 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 70, l3, Sketchup::Color.new(255, 210, 60), 11, false)
        txt(view, 34, 92, l4, Sketchup::Color.new(255, 210, 60), 11, false) if l4
      end

      def draw_box2d(view, x, y, w, h, color)
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = color
        view.draw2d(GL_POLYGON, pts)
      end

      def txt(view, x, y, s, color, size, bold)
        view.draw_text(Geom::Point3d.new(x, y, 0), s, color: color, font: 'Arial', size: size, bold: bold)
      end

      # ── camera frame (giu huong hien tai) ──
      def frame(bb)
        cam = Sketchup.active_model.active_view.camera
        ctr = bb.center
        diag = bb.diagonal
        diag = 100.0 if diag < 1.0
        if cam.perspective?
          fov = cam.fov * Math::PI / 180.0
          dist = (diag / 2.0) / Math.tan(fov / 2.0) * 1.4
          cam.set(ctr.offset(cam.direction.reverse, dist), ctr, cam.up)
        else
          cam.set(ctr.offset(cam.direction.reverse, diag * 3.0), ctr, cam.up)
          cam.height = diag * 1.4
        end
      end

      def quit(view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end

      def update_status
        v = @vios[@idx]
        Sketchup.set_status_text("Hở #{v.gap_mm}mm — cặp #{@idx + 1}/#{@vios.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số cặp', SB_VCB_LABEL)
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Kiểm tra khoảng cách') { TK::SpacingCheck.run }
      cmd.tooltip         = 'Kiểm khoảng cách 7mm sau nesting'
      cmd.status_bar_text = "Quét nesting: tấm nào cách tấm/mép < #{GAP_MM}mm thì tô đỏ, nhảy tới xem."
      cmd.small_icon      = File.join(icons, 'spacing_16.png')
      cmd.large_icon      = File.join(icons, 'spacing_24.png')
      cmd
    end

  end
end
