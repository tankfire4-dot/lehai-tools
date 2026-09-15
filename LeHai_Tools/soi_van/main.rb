# encoding: UTF-8
# Soi Vân: đổ màu solid lên vật liệu thì MẤT dấu vân — không thấy tấm nào bị ngược.
# ABF đã gắn sẵn HƯỚNG VÂN cho mỗi tấm bằng cái nhãn "②→" (group con "_ABF_Label",
# 192×80, toàn nét vẽ). Vân chạy DỌC theo mũi tên đó, đúng cách ABF nesting.
#
# Tool này quét mọi tấm ván (dictionary "ABF" có key is-board), đọc chiều vân thật từ
# _ABF_Label, rồi phủ lên mặt tấm MỘT LỚP MÀU (theo trục vân: đứng/ngang/sâu) KÈM mấy
# SỌC VÂN mảnh chạy dọc theo chiều — nhìn dải màu là biết nó "chạy" hướng nào. Liếc cả
# cụm thấy ngay tấm nào lệch. Nền + sọc đều vẽ 3D có chiều sâu → tấm bị che thì che
# luôn, KHÔNG xuyên vật thể.
#
# ĐỌC CHIỀU VÂN THẬT, không suy từ cạnh dài: file "sạch" thì vân trùng cạnh dài, nhưng
# đúng tấm bị ngược mới là tấm vân KHÁC cạnh dài — suy theo cạnh dài là bỏ lọt đúng cái
# cần soi. (Đo 15/09: probes/van_go_probe3.rb đọc được chiều này.)
#
# CHỈ ĐỌC, không sửa model. Toolbar do LeHai_Tools/main.rb quản lý — file này chỉ
# expose create_cmd.

require 'sketchup.rb'

module TK
  module SoiVan

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    LABEL_RE  = /_ABF_Label/i.freeze

    # màu theo TRỤC VÂN trong không gian — tấm cùng chiều vân thì cùng màu,
    # tấm ngược sẽ lệch màu so với hàng xóm.
    COL_X    = Sketchup::Color.new(40, 150, 255)   # vân theo X (ngang) — xanh dương
    COL_Y    = Sketchup::Color.new(255, 150, 30)   # vân theo Y (sâu)   — cam
    COL_Z    = Sketchup::Color.new(40, 200, 110)   # vân theo Z (đứng)  — xanh lá
    FILL_A     = 70                                 # độ mờ lớp nền (0..255)
    FILL_EPS   = 0.03                               # đẩy nền ra khỏi mặt (inch) tránh z-fighting
    STREAK_EPS = 0.05                               # sọc vân nổi trên lớp nền (inch)
    STREAK_GAP = 0.8                                # khoảng cách sọc (inch, ~20mm)
    STREAK_MIN = 3                                  # số sọc tối thiểu / tối đa mỗi tấm
    STREAK_MAX = 16

    Panel = Struct.new(:center, :fill, :fill_color, :streaks, :line_color)

    # =========================================================
    #  VÀO
    # =========================================================
    def self.run
      panels, no_label = scan
      if panels.empty?
        msg = no_label.zero? ? 'Không thấy tấm ván ABF nào (dictionary "ABF"/is-board). File đã nest chưa?' \
                             : "Thấy #{no_label} tấm nhưng không tấm nào có nhãn _ABF_Label để đọc hướng vân."
        return UI.messagebox(msg)
      end
      Sketchup.active_model.select_tool(ShowTool.new(panels, no_label))
    end

    def self.show
      run
    end

    # =========================================================
    #  QUÉT
    # =========================================================
    def self.scan
      panels = []; no_label = 0
      walk(Sketchup.active_model.entities, Geom::Transformation.new, 0) do |board, te|
        pan = build_panel(board, te)
        pan ? panels << pan : no_label += 1
      end
      [panels, no_label]
    end

    # duyệt, gọi block cho MỖI tấm is-board (không chui vào trong tấm nữa)
    def self.walk(entities, t, depth, &blk)
      return if depth > 40 || entities.nil?
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if hidden_ent?(e)                           # bỏ tấm/nhánh Khoa đã Hide hoặc tag tắt
        next if e.name.to_s.include?(NEST_HINT)          # chỉ soi 3D, bỏ phôi phẳng
        te = t * e.transformation
        d  = (e.attribute_dictionary('ABF') rescue nil)
        if d && d.keys.include?('is-board')
          blk.call(e, te)
          next
        end
        walk(ents_of(e), te, depth + 1, &blk)
      end
    end

    # dựng lớp phủ 1 tấm; nil nếu không tìm được nhãn (không biết chiều vân)
    def self.build_panel(board, te)
      lbl = find_label(board)
      return nil unless lbl

      bb     = board.definition.bounds
      center = te * bb.center
      dir    = axis_world(te * lbl.transformation, longest_axis(lbl.definition.bounds))  # chiều VÂN thật
      normal = axis_world(te, shortest_axis(bb))          # pháp tuyến mặt tấm (trục mỏng nhất)

      col     = color_for(dir)
      fill    = fill_tris(broad_faces(board, te, normal), te)
      fcol    = Sketchup::Color.new(col.red, col.green, col.blue, FILL_A)
      streaks = streak_lines(bb, te, center, dir, normal)
      Panel.new(center, fill, fcol, streaks, col)
    end

    # SỌC VÂN: mấy đoạn thẳng song song chạy DỌC chiều vân, rải ngang mặt tấm, đặt sát
    # cả hai mặt. Đo bề rộng tấm bằng cách chiếu 8 đỉnh hộp bao lên dir & perp.
    def self.streak_lines(bb, te, center, dir, normal)
      perp = normal.cross(dir)
      return [] if perp.length < 1e-9
      perp.normalize!
      cs   = corners_world(bb, te)
      ld   = cs.map { |c| (c - center).dot(dir).abs }.max * 0.85    # nửa chiều dọc vân
      lp   = cs.map { |c| (c - center).dot(perp).abs }.max * 0.85   # nửa chiều ngang vân
      half = shortest_dim(bb) / 2.0
      return [] if ld < 1e-6 || lp < 1e-6

      n   = [[(2 * lp / STREAK_GAP).round, STREAK_MIN].max, STREAK_MAX].min
      pts = []
      (0...n).each do |i|
        o    = n == 1 ? 0.0 : (-lp + 2 * lp * i / (n - 1).to_f)
        base = center + vscale(perp, o)
        [half + STREAK_EPS, -(half + STREAK_EPS)].each do |off|          # hai mặt tấm
          mid = base + vscale(normal, off)
          pts << (mid + vscale(dir, -ld)) << (mid + vscale(dir, ld))
        end
      end
      pts
    end

    # hai mặt RỘNG của tấm (pháp tuyến ~ trục mỏng) — để tô, khỏi dính mặt cạnh mỏng.
    def self.broad_faces(board, te, normal)
      ents = ents_of(board)
      return [] unless ents
      out = []
      ents.each do |f|
        next unless f.is_a?(Sketchup::Face)
        wn = te * f.normal                       # Transformation * Vector = xoay pháp tuyến (tấm không scale)
        next if wn.length < 1e-9
        wn.normalize!
        out << [f, wn] if wn.dot(normal).abs > 0.8
      end
      out
    end

    # tam giác hoá mặt bằng Face#mesh (tấm cong ra hàng trăm mặt con vẫn đúng, không lệm
    # như GL_POLYGON lồi). Đẩy mỗi điểm ra theo pháp tuyến mặt để tránh z-fighting.
    def self.fill_tris(faces_wn, te)
      pts = []
      faces_wn.each do |f, wn|
        push = vscale(wn, FILL_EPS)
        mesh = f.mesh
        mesh.polygons.each do |poly|
          idx = poly.map { |i| i.abs }
          next if idx.size < 3
          (1..idx.size - 2).each do |k|
            [idx[0], idx[k], idx[k + 1]].each do |ii|
              pts << (te * mesh.point_at(ii)) + push
            end
          end
        end
      end
      pts
    end

    def self.find_label(board)
      stack = ents_of(board).to_a
      guard = 0
      while (e = stack.shift)
        guard += 1
        break if guard > 20000
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        return e if e.name.to_s =~ LABEL_RE
        sub = ents_of(e)
        stack.concat(sub.to_a) if sub
      end
      nil
    end

    # ---- hình học ----
    def self.corners_world(bb, te)
      mn = bb.min; mx = bb.max
      pts = []
      [mn.x, mx.x].each { |x| [mn.y, mx.y].each { |y| [mn.z, mx.z].each { |z| pts << (te * Geom::Point3d.new(x, y, z)) } } }
      pts
    end

    def self.longest_axis(bb)
      [bb.width.to_f.abs, bb.height.to_f.abs, bb.depth.to_f.abs].each_with_index.max_by { |v, _| v }[1]
    end

    def self.shortest_axis(bb)
      [bb.width.to_f.abs, bb.height.to_f.abs, bb.depth.to_f.abs].each_with_index.min_by { |v, _| v }[1]
    end

    def self.shortest_dim(bb)
      [bb.width.to_f.abs, bb.height.to_f.abs, bb.depth.to_f.abs].min
    end

    def self.vscale(v, s)
      Geom::Vector3d.new(v.x * s, v.y * s, v.z * s)
    end

    # vector đơn vị (world) của trục local i (0=X,1=Y,2=Z) qua transform world
    def self.axis_world(world_tr, i)
      v = [world_tr.xaxis, world_tr.yaxis, world_tr.zaxis][i].clone
      return Geom::Vector3d.new(1, 0, 0) if v.length < 1e-9
      v.normalize!
      v
    end

    def self.color_for(dir)
      case dominant(dir)
      when 0 then COL_X
      when 1 then COL_Y
      else        COL_Z
      end
    end

    def self.dominant(v)
      [v.x.abs, v.y.abs, v.z.abs].each_with_index.max_by { |m, _| m }[1]
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # bỏ qua entity bị Hide (e.hidden?) hoặc nằm trên tag/layer đang tắt
    def self.hidden_ent?(e)
      return true if e.hidden?
      lay = e.layer
      lay ? !lay.visible? : false
    end

    # =========================================================
    #  TOOL PHỦ MÀU + SỌC VÂN
    # =========================================================
    class ShowTool
      def initialize(panels, no_label)
        @panels   = panels
        @no_label = no_label
      end

      def activate
        Sketchup.set_status_text("Soi Vân — #{@panels.size} tấm · màu + sọc = chiều vân · ESC thoát", SB_PROMPT)
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view) view.invalidate end

      # quay lại tool sau một lệnh (vd Hide/Unhide) → quét lại cho khớp hiện trạng ẩn/hiện.
      # scan chỉ ĐỌC nên an toàn; bọc rescue để lỗi không làm chết tool.
      def resume(view)
        begin
          @panels, @no_label = TK::SoiVan.scan
        rescue => e
          puts "Soi Vân quét lại lỗi: #{e.message}"
        end
        view.invalidate
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @panels.each { |p| bb.add(p.center) }
        bb
      end

      def onCancel(_r, view) quit(view) end
      def onKeyDown(key, _rep, _flags, view)
        quit(view) if key == 27
        false
      end

      def draw(view)
        begin
          @panels.each { |p| draw_fill(view, p) }      # lớp nền mờ
          @panels.each { |p| draw_streaks(view, p) }   # sọc vân nổi trên
          draw_legend(view)
        rescue => e
          puts "Soi Vân lỗi draw: #{e.class}: #{e.message}"
          puts e.backtrace.first(5).join("\n") if e.backtrace
        end
      end

      # đều vẽ bằng draw 3D (có chiều sâu) → tấm bị che thì che luôn, không xuyên.
      def draw_fill(view, p)
        return if p.fill.nil? || p.fill.empty?
        view.drawing_color = p.fill_color
        view.draw(GL_TRIANGLES, p.fill)
      end

      def draw_streaks(view, p)
        return if p.streaks.nil? || p.streaks.empty?
        view.line_width = 2
        view.drawing_color = p.line_color
        view.draw(GL_LINES, p.streaks)
      end

      def draw_legend(view)
        lines = [
          "Soi Vân — #{@panels.size} tấm  (màu + sọc = chiều vân theo ABF)",
          'xanh dương = vân ngang (X)   ·   cam = vân sâu (Y)   ·   xanh lá = vân đứng (Z)',
          @no_label.zero? ? 'ESC thoát' : "#{@no_label} tấm không đọc được nhãn (bỏ qua)  ·  ESC thoát"
        ]
        w = 26 + lines.map(&:length).max * 7
        box(view, 18, 18, w, 78, Sketchup::Color.new(18, 22, 30, 215))
        box(view, 18, 18, 6, 78, Sketchup::Color.new(120, 200, 255))
        txt(view, 34, 26, lines[0], Sketchup::Color.new(150, 220, 255), 14, true)
        txt(view, 34, 48, lines[1], Sketchup::Color.new(230, 230, 230), 11, false)
        txt(view, 34, 68, lines[2], Sketchup::Color.new(200, 200, 200), 11, false)
      end

      def box(view, x, y, w, h, color)
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = color
        view.draw2d(GL_POLYGON, pts)
      end

      def txt(view, x, y, s, color, size, bold)
        view.draw_text(Geom::Point3d.new(x, y, 0), s, color: color, font: 'Arial', size: size, bold: bold)
      end

      def quit(view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Soi Vân') { TK::SoiVan.run }
      cmd.tooltip         = 'Soi chiều vân từng tấm (màu + sọc theo mũi tên ABF)'
      cmd.status_bar_text = 'Phủ màu + sọc vân lên mặt tấm theo trục vân — soi tấm ngược khi đổ màu solid mất dấu vân.'
      s16 = File.join(icons, 'soi_van_16.png')
      s24 = File.join(icons, 'soi_van_24.png')
      cmd.small_icon = s16 if File.exist?(s16)
      cmd.large_icon = s24 if File.exist?(s24)
      cmd
    end

  end
end
