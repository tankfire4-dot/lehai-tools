# encoding: UTF-8
#
# Chống Bay — quét đổi tag chi tiết từ ABF_cuttingLines sang tag chống bay.
#
# Vì sao phải tự viết bộ quét thay vì dùng selection của SketchUp:
#   Chi tiết nesting nằm sâu trong group __ABF_Nesting. Quét bằng công cụ Select
#   ở ngoài group thì không chạm được chi tiết bên trong (Entity Info báo
#   "No Selection"). Bộ quét này không đụng tới selection — nó chiếu toạ độ thật
#   của từng cạnh lên màn hình rồi so với khung quét.
#
# Hai điều đã trả giá bằng lần chạy thật 19/07/2026 (probe trên file đã nest):
#   1. Tag ABF nằm ở EDGE, không nằm ở GROUP vỏ (group vỏ đeo Layer0). Đổi tag
#      phải đổi cả hai cấp, đổi mỗi group thì DXF ra layer rỗng.
#   2. Chi tiết nesting DÙNG CHUNG group — lần chạy thật báo "tách 18 container".
#      Không make_unique trước khi sửa thì đổi 1 cái là đổi lây sang tấm khác,
#      mà nhìn màn hình không thấy gì bất thường cho tới lúc ra máy cắt.

module TK
  module ChongBay

    PATH      = File.dirname(__FILE__).freeze

    SRC_TAG   = 'ABF_cuttingLines'.freeze
    SRC_RE    = /cutting.?lines/i.freeze     # phòng tên viết hoa/thường khác nhau
    DST_RE      = /chongbay/i.freeze         # tag đích do Khoa tạo bên ABF
    DEFAULT_DST = 'CHONGBAYTRAI'.freeze      # tên gợi ý sẵn khi phải tạo tag
    NEW_LABEL   = '— Tạo tag mới —'.freeze   # dòng cuối trong hộp sổ xuống

    # Hai tag này tạo sẵn cho mọi file — đỡ phải khai tay từng lần.
    # Vẫn phải khai ĐÚNG tên bên ABF thì hai bên mới khớp.
    DEFAULT_TAGS = ['CHONGBAYTRAI', 'CHONGBAYPHAI'].freeze

    # Mỗi tag một màu để nhìn phát biết cái nào trái cái nào phải.
    TAG_COLORS = {
      'CHONGBAYTRAI' => Sketchup::Color.new(0, 190, 80),     # xanh lá
      'CHONGBAYPHAI' => Sketchup::Color.new(255, 130, 0)     # cam
    }.freeze

    # Tag chống bay tự đặt thêm thì lấy màu theo thứ tự trong bảng này
    PALETTE = [
      Sketchup::Color.new(60, 130, 255),    # xanh dương
      Sketchup::Color.new(200, 60, 220),    # tím
      Sketchup::Color.new(220, 200, 0),     # vàng
      Sketchup::Color.new(0, 200, 200)      # xanh ngọc
    ].freeze
    MAX_DEPTH = 12

    COL_DONE  = Sketchup::Color.new(0, 190, 80)      # xanh lá = đã đổi
    COL_TODO  = Sketchup::Color.new(150, 150, 150)   # xám    = chưa đổi
    COL_BAND  = Sketchup::Color.new(255, 20, 200)    # hồng   = khung đang quét

    # ── Helper đọc ───────────────────────────────────────────────

    def self.tag_name(e)
      # nuốt được: entity không phải Drawingelement thì coi như không có tag
      e.layer.name.to_s rescue ''
    end

    def self.container?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end

    def self.kids_of(e)
      e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    end

    def self.src?(e)
      n = tag_name(e)
      n == SRC_TAG || !!(n =~ SRC_RE)
    end

    # ── Chọn tag đích ────────────────────────────────────────────
    # Không hardcode một tên: quét các tag có chữ CHONGBAY trong model.
    # 1 cái  → dùng luôn, không hỏi (đỡ vướng tay).
    # nhiều  → cho chọn.  0 cái → bảo Khoa tạo bên ABF trước.

    # Danh sách Layer bên ABF KHÔNG phải tag SketchUp — đó là danh sách riêng của
    # ABF (đo thật 19/07: model có 8 tag, hộp thoại ABF liệt kê 31 layer). ABF chỉ
    # đẻ tag SketchUp thật khi có hình được gán vào. Nên tag tạo ở đây phải đặt
    # ĐÚNG tên đã khai bên ABF thì hai bên mới khớp — lệch tên là ABF không nhận
    # mà chẳng báo lỗi gì.
    # Tạo sẵn CHONGBAYTRAI + CHONGBAYPHAI nếu file chưa có. layers.add trả về cái
    # cũ nếu đã tồn tại nên gọi nhiều lần vô hại.
    def self.ensure_default_tags(model)
      thieu = DEFAULT_TAGS.reject { |n| model.layers.to_a.any? { |l| l.name.to_s == n } }
      return if thieu.empty?
      model.start_operation('Tao tag chong bay', true)
      begin
        thieu.each { |n| model.layers.add(n) }
        model.commit_operation
      rescue => e
        model.abort_operation
        UI.messagebox("Lỗi: #{e.message}")
      end
    end

    # Màu overlay của một tag. Tag không tên (chưa đổi) → xám.
    def self.color_for(tag_name)
      return COL_TODO if tag_name.nil?
      TAG_COLORS[tag_name] || PALETTE[tag_name.hash.abs % PALETTE.size]
    end

    def self.pick_dst_tag(model)
      ensure_default_tags(model)
      tags = model.layers.to_a
                  .select { |l| l.name.to_s =~ DST_RE }
                  .sort_by { |l| l.name.to_s }
      return create_dst_tag(model) if tags.empty?

      names   = tags.map { |l| l.name.to_s }
      choices = names + [NEW_LABEL]
      pick    = ask_from_list('Quét sang tag:', choices)
      return nil if pick.nil?
      return create_dst_tag(model) if pick == NEW_LABEL

      tags.find { |l| l.name.to_s == pick }
    end

    # Hộp sổ xuống. Bản SketchUp nào không nhận dạng danh sách thì rớt về gõ tay
    # — nuốt được vì đã báo ra Console và vẫn hỏi lại bằng đường khác.
    def self.ask_from_list(prompt, choices)
      res = begin
        UI.inputbox([prompt], [choices.first], [choices.join('|')], 'Chống Bay')
      rescue => e
        puts "[Chống Bay] hộp sổ xuống lỗi (#{e.message}) — chuyển sang gõ tay."
        UI.inputbox([prompt], [choices.first], 'Chống Bay')
      end
      return nil unless res
      res[0].to_s.strip
    end

    def self.create_dst_tag(model)
      res = UI.inputbox(
        ["Tên tag mới — gõ ĐÚNG tên đã tạo bên ABF:"],
        [DEFAULT_DST],
        'Chống Bay — tạo tag'
      )
      return nil unless res
      name = res[0].to_s.strip
      if name.empty?
        UI.messagebox('Chưa nhập tên tag.')
        return nil
      end
      unless name =~ DST_RE
        ok = UI.messagebox(
          "Tên \"#{name}\" không có chữ CHONGBAY.\n\n" \
          "Lần sau tool sẽ không tự thấy tag này trong danh sách.\n\nVẫn tạo?",
          MB_YESNO
        )
        return nil if ok != IDYES
      end
      model.layers.add(name)      # có sẵn thì trả về cái cũ, chưa có thì tạo
    end

    # ── Duyệt (khuôn tim_tam_loi/main.rb:36) ─────────────────────

    def self.traverse(entities, accum_t, depth = 0, &blk)
      return if depth > MAX_DEPTH
      entities.each do |e|
        next unless container?(e)
        blk.call(e, accum_t)
        traverse(kids_of(e), accum_t * e.transformation, depth + 1, &blk)
      end
    end

    # Đoạn thẳng THẬT của chi tiết ở toạ độ thế giới → viền bám sát hình.
    # Dùng hộp bao thì chi tiết nằm xiên sẽ phình ra, vừa xấu vừa quét lẹm
    # sang cái bên cạnh. Khuôn: kiem_tra_khoang_cach/main.rb:131
    def self.world_segments(grp, accum_t)
      segs = []
      collect_edges(kids_of(grp), accum_t * grp.transformation, 0, segs)
      segs
    end

    def self.collect_edges(entities, t, depth, segs)
      return if depth > MAX_DEPTH
      entities.each do |e|
        if e.is_a?(Sketchup::Edge)
          segs << [t * e.start.position, t * e.end.position]
        elsif container?(e)
          collect_edges(kids_of(e), t * e.transformation, depth + 1, segs)
        end
      end
    end

    # ── Ứng viên để quét ─────────────────────────────────────────

    # tag = nil nếu chưa đổi (còn ABF_cuttingLines), ngược lại là tên tag chống bay
    # đang đeo. Gom CẢ chi tiết đã đổi sang tag chống bay KHÁC — nếu chỉ gom tag
    # đích thì mấy cái đã gắn tag khác biến mất khỏi màn hình, không nhìn thấy,
    # không sửa lại được (lỗi này đã xảy ra: quét sang PHAI thì 6 cái TRAI mất tăm).
    Cand = Struct.new(:group, :segs, :tag)

    def self.collect_cands
      out = []
      traverse(Sketchup.active_model.entities, Geom::Transformation.new) do |e, t|
        n = tag_name(e)
        if src?(e)
          out << Cand.new(e, world_segments(e, t), nil)
        elsif n =~ DST_RE
          out << Cand.new(e, world_segments(e, t), n)
        end
      end
      out
    end

    # ── Đổi tag ──────────────────────────────────────────────────

    def self.has_match?(entities, match, depth = 0)
      return false if depth > MAX_DEPTH
      entities.each do |e|
        return true if match.call(e)
        return true if container?(e) && has_match?(kids_of(e), match, depth + 1)
      end
      false
    end

    def self.apply(entities, match, dst, depth, stats)
      return if depth > MAX_DEPTH
      entities.each do |e|
        if container?(e)
          if match.call(e) || has_match?(kids_of(e), match)
            if e.respond_to?(:make_unique)
              begin
                e.make_unique
                stats[:unique] += 1
              rescue => err
                stats[:unique_fail] += 1
                puts "[Chống Bay] không make_unique được một container: #{err.message}"
              end
            end
          end
          if match.call(e)
            e.layer = dst
            stats[:groups] += 1
          end
          apply(kids_of(e), match, dst, depth + 1, stats)   # gọi SAU make_unique
        elsif match.call(e)
          e.layer = dst
          stats[:leaves] += 1
        end
      end
    end

    # Trả về stats, hoặc nil nếu không có gì để đổi
    def self.retag(items, match, dst)
      model = Sketchup.active_model
      stats = { :groups => 0, :leaves => 0, :unique => 0, :unique_fail => 0 }

      model.start_operation('Doi tag chong bay', true)
      begin
        apply(items, match, dst, 0, stats)
        if stats[:groups] + stats[:leaves] == 0
          model.abort_operation                 # không đổi gì → khỏi bậc undo rỗng
          return nil
        end
        model.commit_operation
      rescue => e
        model.abort_operation
        UI.messagebox("Lỗi: #{e.message}")
        return nil
      end
      stats
    end

    # ── Bộ quét ──────────────────────────────────────────────────

    class SweepTool

      def initialize(dst_tag)
        @dst      = dst_tag
        @dst_name = dst_tag.name.to_s
      end

      def activate
        rescan
        @drag = false
        @x0 = @y0 = @x1 = @y1 = 0
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        view.invalidate
      end

      def onCancel(_reason, view)
        view.model.select_tool(nil)
      end

      def onKeyDown(key, _rep, _flags, view)
        view.model.select_tool(nil) if key == 27   # Esc
        false
      end

      def onLButtonDown(_flags, x, y, view)
        @drag = true
        @x0 = x; @y0 = y; @x1 = x; @y1 = y
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        return unless @drag
        @x1 = x; @y1 = y
        view.invalidate
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @drag
        @drag = false
        @x1 = x; @y1 = y
        apply_rect(view)
        view.invalidate
      end

      def draw(view)
        # Gom điểm theo TAG rồi vẽ mỗi tag một lệnh — mỗi tag một màu, và 50 chi
        # tiết vẫn chỉ vài lệnh vẽ chứ không phải 50.
        by_tag = Hash.new { |h, k| h[k] = [] }
        @cands.each do |c|
          next if (c.group.deleted? rescue true)
          pts = by_tag[c.tag]
          c.segs.each do |a, b|
            pts << view.screen_coords(a) << view.screen_coords(b)
          end
        end

        # chưa đổi vẽ trước (mảnh, xám) để mấy cái đã đổi nổi lên trên
        todo = by_tag.delete(nil)
        if todo && !todo.empty?
          view.drawing_color = COL_TODO
          view.line_width    = 1
          view.draw2d(GL_LINES, todo)
        end
        by_tag.each do |tag, pts|
          next if pts.empty?
          view.drawing_color = TK::ChongBay.color_for(tag)
          view.line_width    = 3
          view.draw2d(GL_LINES, pts)
        end

        draw_band(view) if @drag
        draw_banner(view)
      end

      private

      COL_DONE = TK::ChongBay::COL_DONE
      COL_TODO = TK::ChongBay::COL_TODO
      COL_BAND = TK::ChongBay::COL_BAND

      def rescan
        # make_unique thay entity cũ bằng entity mới → danh sách cũ thành rác,
        # phải quét lại từ đầu sau mỗi lần đổi.
        @cands = TK::ChongBay.collect_cands
      end

      # ---- va chạm: khung quét vs CẠNH THẬT của chi tiết ----

      def in_rect?(p, r)
        p.x >= r[0] && p.x <= r[2] && p.y >= r[1] && p.y <= r[3]
      end

      def ccw(ax, ay, bx, by, cx, cy)
        (cy - ay) * (bx - ax) > (by - ay) * (cx - ax)
      end

      def seg_cross?(p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
        ccw(p1x, p1y, p3x, p3y, p4x, p4y) != ccw(p2x, p2y, p3x, p3y, p4x, p4y) &&
          ccw(p1x, p1y, p2x, p2y, p3x, p3y) != ccw(p1x, p1y, p2x, p2y, p4x, p4y)
      end

      def touches?(view, segs, r)
        x0, y0, x1, y1 = r
        edges = [[x0, y0, x1, y0], [x1, y0, x1, y1],
                 [x1, y1, x0, y1], [x0, y1, x0, y0]]
        segs.each do |a, b|
          pa = view.screen_coords(a)
          pb = view.screen_coords(b)
          return true if in_rect?(pa, r) || in_rect?(pb, r)
          edges.each do |e|
            return true if seg_cross?(pa.x, pa.y, pb.x, pb.y, e[0], e[1], e[2], e[3])
          end
        end
        false
      end

      def apply_rect(view)
        rect = [[@x0, @x1].min, [@y0, @y1].min, [@x0, @x1].max, [@y0, @y1].max]

        # khung quá nhỏ = lỡ tay click, bỏ qua để khỏi đổi oan một chi tiết
        return if (rect[2] - rect[0]).abs < 4 && (rect[3] - rect[1]).abs < 4

        # Quét trúng cái đang đeo tag khác thì ĐỔI SANG tag đích — cho phép chuyển
        # trái ↔ phải. Chỉ bỏ qua cái đã đúng tag đích rồi.
        hits = @cands.select do |c|
          next false if c.tag == @dst_name
          next false if (c.group.deleted? rescue true)
          touches?(view, c.segs, rect)
        end
        return if hits.empty?

        dst_name = @dst_name
        match = lambda do |e|
          n = TK::ChongBay.tag_name(e)
          next false if n == dst_name
          TK::ChongBay.src?(e) || !!(n =~ TK::ChongBay::DST_RE)
        end

        stats = TK::ChongBay.retag(hits.map(&:group), match, @dst)
        if stats && stats[:unique_fail] > 0
          UI.messagebox(
            "Cảnh báo: #{stats[:unique_fail]} nhóm không tách riêng được.\n\n" \
            "Những chi tiết này có thể dùng chung với tấm khác — kiểm lại các tấm " \
            "còn lại xem có bị đổi lây không."
          )
        end
        rescan
      end

      # ---- Bảng nhắc góc trên-trái (khuôn tim_tam_loi/main.rb:266) ----

      def draw_band(view)
        r = [[@x0, @x1].min, [@y0, @y1].min, [@x0, @x1].max, [@y0, @y1].max]
        pts = [[r[0], r[1]], [r[2], r[1]], [r[2], r[1]], [r[2], r[3]],
               [r[2], r[3]], [r[0], r[3]], [r[0], r[3]], [r[0], r[1]]]
              .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = COL_BAND
        view.line_width    = 2
        view.draw2d(GL_LINES, pts)
      end

      def draw_banner(view)
        chua  = @cands.count { |c| c.tag.nil? }
        theo  = Hash.new(0)
        @cands.each { |c| theo[c.tag] += 1 if c.tag }

        line1 = "Chống Bay → #{@dst_name}"
        line2 = theo.keys.sort.map { |t| "#{t} #{theo[t]}" }.join('   ·   ')
        line2 = line2.empty? ? "chưa đổi #{chua}" : "#{line2}   ·   chưa đổi #{chua}"
        line3 = 'Kéo chuột quét qua chi tiết  ·  Ctrl+Z gỡ  ·  ESC thoát'

        # Thông số bám đúng bảng nhắc của bộ (tim_tam_loi/main.rb:277): góc 18/18,
        # bề rộng = 26 + ký_tự*9, nền (18,22,30,210), vạch màu 6px bên trái, chữ
        # thụt x+16, dòng đầu trắng đậm 13, dòng nhắc vàng 11. Khác một điểm: bảng
        # này 3 dòng (thêm dòng đếm theo tag) nên cao 80 thay vì 58.
        x = 18
        y = 18
        w = 26 + [line1.length, line2.length, line3.length].max * 9
        h = 80

        bg = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
             .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = Sketchup::Color.new(18, 22, 30, 210)
        view.draw2d(GL_POLYGON, bg)

        # vạch màu bên trái = màu của tag đang quét sang (bộ dùng màu trạng thái
        # của chính tool ở chỗ này)
        bar = [[x, y], [x + 6, y], [x + 6, y + h], [x, y + h]]
              .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = TK::ChongBay.color_for(@dst_name)
        view.draw2d(GL_POLYGON, bar)

        view.draw_text(Geom::Point3d.new(x + 16, y + 8, 0), line1,
                       color: Sketchup::Color.new(255, 255, 255),
                       font: 'Arial', size: 13, bold: true)
        view.draw_text(Geom::Point3d.new(x + 16, y + 32, 0), line2,
                       color: Sketchup::Color.new(255, 255, 255),
                       font: 'Arial', size: 11)
        view.draw_text(Geom::Point3d.new(x + 16, y + 54, 0), line3,
                       color: Sketchup::Color.new(255, 210, 60),
                       font: 'Arial', size: 11)
      end
    end

    # ── Cổng vào ─────────────────────────────────────────────────

    def self.start
      model = Sketchup.active_model
      dst   = pick_dst_tag(model)
      return unless dst
      model.select_tool(SweepTool.new(dst))
    end

    # Gỡ ngược trên vùng đang chọn (dùng khi lỡ quét nhầm cả mảng)
    def self.revert_selection
      model = Sketchup.active_model
      if model.selection.empty?
        UI.messagebox("Chưa chọn gì.\n\nChọn vùng cần gỡ rồi chạy lại.")
        return
      end
      src = model.layers.to_a.find { |l| l.name.to_s == SRC_TAG }
      if src.nil?
        UI.messagebox("Không tìm thấy tag \"#{SRC_TAG}\" trong file này.")
        return
      end
      match = lambda { |e| tag_name(e) =~ DST_RE ? true : false }
      stats = retag(model.selection.to_a, match, src)
      if stats.nil?
        UI.messagebox('Không có chi tiết chống bay nào trong vùng đang chọn.')
      else
        UI.messagebox("Đã gỡ #{stats[:groups]} nhóm về \"#{SRC_TAG}\".")
      end
    end

    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Chống Bay') { TK::ChongBay.start }
      cmd.tooltip         = 'Chống Bay — quét đổi chi tiết sang tag chống bay'
      cmd.status_bar_text = 'Kéo chuột quét qua chi tiết nhỏ để đổi sang tag chống bay. ESC thoát.'
      cmd.small_icon      = File.join(icons, 'chong_bay_16.png')
      cmd.large_icon      = File.join(icons, 'chong_bay_24.png')
      cmd
    end
  end
end
