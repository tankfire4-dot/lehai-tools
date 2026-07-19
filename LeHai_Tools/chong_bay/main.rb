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
    DST_RE    = /chongbay/i.freeze           # tag đích do Khoa tạo bên ABF
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

    def self.pick_dst_tag(model)
      tags = model.layers.to_a.select { |l| l.name.to_s =~ DST_RE }
      if tags.empty?
        UI.messagebox(
          "Chưa có tag chống bay nào trong file này.\n\n" \
          "Tạo tag bên ABF trước (mục Layer → Tạo mới), đặt tên có chữ " \
          "CHONGBAY — ví dụ CHONGBAYTRAI — rồi chạy lại."
        )
        return nil
      end
      return tags.first if tags.size == 1

      names = tags.map { |l| l.name.to_s }.sort
      res = begin
        UI.inputbox(['Đổi sang tag:'], [names.first], [names.join('|')], 'Chống Bay')
      rescue => e
        # Bản SketchUp nào không nhận dạng danh sách thì hỏi trơn
        puts "[Chống Bay] inputbox dạng danh sách lỗi (#{e.message}) — hỏi dạng gõ tay."
        UI.inputbox(['Đổi sang tag:'], [names.first], 'Chống Bay')
      end
      return nil unless res
      tags.find { |l| l.name.to_s == res[0].to_s }
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

    Cand = Struct.new(:group, :segs, :done)

    def self.collect_cands(dst_name)
      out = []
      traverse(Sketchup.active_model.entities, Geom::Transformation.new) do |e, t|
        if src?(e)
          out << Cand.new(e, world_segments(e, t), false)
        elsif tag_name(e) == dst_name
          out << Cand.new(e, world_segments(e, t), true)
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
        done_pts = []
        todo_pts = []
        @cands.each do |c|
          next if (c.group.deleted? rescue true)
          bucket = c.done ? done_pts : todo_pts
          c.segs.each do |a, b|
            bucket << view.screen_coords(a) << view.screen_coords(b)
          end
        end
        unless todo_pts.empty?
          view.drawing_color = COL_TODO
          view.line_width    = 1
          view.draw2d(GL_LINES, todo_pts)
        end
        unless done_pts.empty?
          view.drawing_color = COL_DONE
          view.line_width    = 3
          view.draw2d(GL_LINES, done_pts)
        end
        if @drag
          draw_band(view)
        end
        draw_banner(view)
      end

      private

      COL_DONE = TK::ChongBay::COL_DONE
      COL_TODO = TK::ChongBay::COL_TODO
      COL_BAND = TK::ChongBay::COL_BAND

      def rescan
        # make_unique thay entity cũ bằng entity mới → danh sách cũ thành rác,
        # phải quét lại từ đầu sau mỗi lần đổi.
        @cands = TK::ChongBay.collect_cands(@dst_name)
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

        hits = @cands.reject(&:done).select do |c|
          next false if (c.group.deleted? rescue true)
          touches?(view, c.segs, rect)
        end
        return if hits.empty?

        stats = TK::ChongBay.retag(hits.map(&:group), TK::ChongBay.method(:src?), @dst)
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
        done  = @cands.count(&:done)
        line1 = "Chống Bay → #{@dst_name}   ·   đã đổi #{done}/#{@cands.size}"
        line2 = 'Kéo chuột quét qua chi tiết  ·  Ctrl+Z gỡ  ·  ESC thoát'
        x = 18
        y = 18
        w = 26 + [line1.length, line2.length].max * 8
        h = 58

        bg = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
             .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = Sketchup::Color.new(18, 22, 30, 210)
        view.draw2d(GL_POLYGON, bg)

        bar = [[x, y], [x + 6, y], [x + 6, y + h], [x, y + h]]
              .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = COL_DONE
        view.draw2d(GL_POLYGON, bar)

        view.draw_text(Geom::Point3d.new(x + 18, y + 10, 0), line1,
                       color: Sketchup::Color.new(255, 255, 255),
                       font: 'Arial', size: 12, bold: true)
        view.draw_text(Geom::Point3d.new(x + 18, y + 32, 0), line2,
                       color: Sketchup::Color.new(190, 195, 205),
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
