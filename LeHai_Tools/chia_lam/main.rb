# encoding: UTF-8
# Chia Lam — chia mặt phẳng thành hệ nan/lam gỗ ôm khít biên dạng.
#   • Rê chuột lên mặt → xem trước hệ lam (đường xanh), bấm chuột trái để tạo.
#   • Phím tắt trong lúc rê:  [A] đổi kiểu căn lề · [TAB]/[Space] đổi hướng dọc↔ngang
#                             [←][→] chỉnh rộng nan · [↑][↓] chỉnh khe hở.
# Port từ plugin rời "Chia Nan Auto" (NGUYEN KHANH) vào bộ LeHai_Tools:
# giữ nguyên thuật toán, bỏ toolbar/menu riêng — chỉ expose create_cmd (luật nhà).

require 'sketchup.rb'
require 'json'

module TK
  module ChiaLam
    PATH = File.dirname(__FILE__).freeze
    @dialog = nil

    # Thông số mặc định (nhớ giữa các lần gọi trong 1 phiên)
    @slat_width      = 50.0
    @slat_gap        = 20.0
    @slat_thick      = 17.5
    @align_mode      = "Can deu theo Le (Auto Gap)"
    @margin_both_mm  = 50.0
    @margin_single_mm = 0.0

    # ── Tool tương tác: rê xem trước + bấm để sinh lam ─────────────
    class SlatTool
      def initialize(width_mm, gap_mm, thick_mm, align_mode, margin_both_mm, margin_single_mm)
        @width = width_mm.to_f.mm
        @gap = gap_mm.to_f.mm
        @thick = thick_mm.to_f.mm
        @align_mode = align_mode.to_s
        @margin_both = margin_both_mm.to_f.mm
        @margin_single = margin_single_mm.to_f.mm
        @vertical = true

        @ip = Sketchup::InputPoint.new
        @picked_face = nil
        @preview_polygons = []
        @transformation = Geom::Transformation.new
      end

      def activate
        puts ">>> [Chia Lam - Khit Bien Dang] Tool da kich hoat!"
        update_status_bar
      end

      def onSetCursor
        UI.set_cursor(632)
      end

      def deactivate(view)
        view.invalidate
      end

      def update_status_bar
        orient = @vertical ? "Doc" : "Ngang"
        w_mm = @width.to_mm.round(1)
        g_mm = @calculated_gap ? @calculated_gap.to_mm.round(1) : @gap.to_mm.round(1)

        margin_info = if @align_mode.include?("Trai") || @align_mode.include?("Phai")
                        "Le dau: #{@margin_single.to_mm.round(1)}mm"
                      else
                        "Le 2 dau: #{@margin_both.to_mm.round(1)}mm"
                      end

        Sketchup.status_text = "Huong: #{orient} | Can: #{@align_mode} | Rong: #{w_mm}mm | Ho: #{g_mm}mm | #{margin_info} | [A]: Doi Can Le | [TAB/Space]: Doi huong"
      end

      def onMouseMove(flags, x, y, view)
        begin
          @ip.pick(view, x, y)
          ph = view.pick_helper
          ph.do_pick(x, y)

          face = ph.picked_face
          trans = Geom::Transformation.new

          if ph.count > 0
            path = ph.path_at(0)
            if path
              trans = ph.transformation_at(0)
              unless face
                path.reverse_each do |elem|
                  if elem.is_a?(Sketchup::Face)
                    face = elem
                    break
                  end
                end
              end
            end
          end

          if face && face.is_a?(Sketchup::Face) && face.valid?
            if face != @picked_face || trans != @transformation
              @picked_face = face
              @transformation = trans
              calculate_preview
              update_status_bar
            end
          else
            @picked_face = nil
            @preview_polygons = []
          end
        rescue => e
        end

        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        if [9, 32].include?(key)
          @vertical = !@vertical
          calculate_preview if @picked_face && @picked_face.valid?
          update_status_bar
          view.invalidate
          return true
        elsif key == 65 || key == 97
          modes = [
            "Can deu theo Le (Auto Gap)",
            "Trai qua (Left)",
            "Phai qua (Right)"
          ]
          idx = modes.index(@align_mode) || 0
          @align_mode = modes[(idx + 1) % modes.length]
          calculate_preview if @picked_face && @picked_face.valid?
          update_status_bar
          view.invalidate
          return true
        elsif key == 38
          @gap += 5.0.mm
          calculate_preview if @picked_face && @picked_face.valid?
          update_status_bar
          view.invalidate
          return true
        elsif key == 40
          @gap = [@gap - 5.0.mm, 1.0.mm].max
          calculate_preview if @picked_face && @picked_face.valid?
          update_status_bar
          view.invalidate
          return true
        elsif key == 39
          @width += 5.0.mm
          calculate_preview if @picked_face && @picked_face.valid?
          update_status_bar
          view.invalidate
          return true
        elsif key == 37
          @width = [@width - 5.0.mm, 5.0.mm].max
          calculate_preview if @picked_face && @picked_face.valid?
          update_status_bar
          view.invalidate
          return true
        end
        false
      end

      def onLButtonDown(flags, x, y, view)
        if @picked_face && @picked_face.valid? && !@preview_polygons.empty?
          generate_slats_perfect
          view.invalidate
        end
      end

      def draw(view)
        @ip.draw(view) if @ip.valid?

        if @preview_polygons && !@preview_polygons.empty?
          view.drawing_color = Sketchup::Color.new(30, 200, 30)
          view.line_width = 2
          @preview_polygons.each do |poly|
            view.draw(GL_LINE_LOOP, poly) if poly.length >= 3
          end
        end
      end

      private

      def calculate_preview
        return unless @picked_face && @picked_face.valid?

        @preview_polygons = []

        normal_world = @picked_face.normal.transform(@transformation).normalize
        outer_verts = @picked_face.outer_loop.vertices.map { |v| v.position.transform(@transformation) }
        origin_world = outer_verts.first

        axes = normal_world.axes
        u_vec = axes[0].normalize
        v_vec = axes[1].normalize
        u_vec, v_vec = v_vec, u_vec unless @vertical

        all_loops = [@picked_face.outer_loop] + @picked_face.loops.select { |l| l != @picked_face.outer_loop }

        edges_2d = []
        all_pts_2d = []

        all_loops.each do |loop|
          loop_pts_3d = loop.vertices.map { |v| v.position.transform(@transformation) }
          loop_pts_2d = loop_pts_3d.map do |pt|
            vec = pt - origin_world
            [vec.dot(u_vec), vec.dot(v_vec)]
          end

          all_pts_2d.concat(loop_pts_2d)
          n = loop_pts_2d.length
          n.times { |i| edges_2d << [loop_pts_2d[i], loop_pts_2d[(i + 1) % n]] }
        end

        u_coords = all_pts_2d.map { |p| p[0] }
        u_min, u_max = u_coords.min, u_coords.max
        total_span = u_max - u_min

        start_u = u_min
        count_slats = 0
        actual_gap = @gap

        if @align_mode.include?("Auto Gap")
          effective_span = total_span - (2 * @margin_both)
          if effective_span > @width
            count_slats = ((effective_span + @gap) / (@width + @gap)).round
            count_slats = 1 if count_slats < 1

            if count_slats == 1
              start_u = u_min + (total_span - @width) / 2.0
              actual_gap = 0
            else
              actual_gap = (effective_span - (count_slats * @width)) / (count_slats - 1)
              start_u = u_min + @margin_both
            end
          end
        elsif @align_mode.include?("Trai")
          start_u = u_min + @margin_single
          effective_span = total_span - @margin_single
          if effective_span >= @width
            count_slats = ((effective_span + @gap) / (@width + @gap)).floor + 1
            if start_u + (count_slats * @width) + ((count_slats - 1) * @gap) > u_max + 1e-4
              count_slats -= 1
            end
          end
        elsif @align_mode.include?("Phai")
          effective_span = total_span - @margin_single
          if effective_span >= @width
            count_slats = ((effective_span + @gap) / (@width + @gap)).floor + 1
            if (count_slats * @width) + ((count_slats - 1) * @gap) > effective_span + 1e-4
              count_slats -= 1
            end
            slats_total_width = (count_slats * @width) + ((count_slats - 1) * @gap)
            start_u = (u_max - @margin_single) - slats_total_width
          end
        end

        @calculated_gap = actual_gap
        return if count_slats <= 0

        current_u = start_u
        step = @width + actual_gap
        lift_origin = origin_world.offset(normal_world, 0.5.mm)

        count_slats.times do
          u1 = current_u
          u2 = current_u + @width
          current_u += step

          poly_3d = generate_clipped_slat_polygon(u1, u2, edges_2d, origin_world, u_vec, v_vec, lift_origin)
          @preview_polygons << poly_3d if poly_3d && poly_3d.length >= 3
        end
      end

      def generate_clipped_slat_polygon(u1, u2, edges_2d, origin_world, u_vec, v_vec, lift_origin)
        samples = 20
        left_pts = []
        right_pts = []

        samples.times do |i|
          t = i.to_f / (samples - 1)
          u_curr = u1 + t * (u2 - u1)
          v_list = find_v_intersections_2d(u_curr, edges_2d)

          if v_list.length >= 2
            v_min_val = v_list.min
            v_max_val = v_list.max
            left_pts << lift_origin.offset(u_vec, u_curr).offset(v_vec, v_min_val)
            right_pts.unshift(lift_origin.offset(u_vec, u_curr).offset(v_vec, v_max_val))
          end
        end

        return nil if left_pts.empty? || right_pts.empty?
        left_pts + right_pts
      end

      def find_v_intersections_2d(u_target, edges_2d)
        v_list = []
        eps = 1e-4

        edges_2d.each do |p1, p2|
          u1, v1 = p1
          u2, v2 = p2

          next if (u1 < u_target - eps && u2 < u_target - eps) || (u1 > u_target + eps && u2 > u_target + eps)
          next if (u1 - u2).abs < 1e-6

          t = (u_target - u1) / (u2 - u1)
          if t >= -eps && t <= 1 + eps
            v_inter = v1 + t * (v2 - v1)
            v_list << v_inter
          end
        end

        v_list.sort!
        filtered_v = []
        v_list.each do |v|
          filtered_v << v if filtered_v.empty? || (v - filtered_v.last).abs > 1e-3
        end
        filtered_v
      end

      def generate_slats_perfect
        return unless @picked_face && @picked_face.valid?

        model = Sketchup.active_model
        model.start_operation("Chia Lam Khit Bien Dang", true)

        active_ents = model.active_entities
        normal_world = @picked_face.normal.transform(@transformation).normalize

        count = 0
        main_group = active_ents.add_group
        main_group.name = "He_Lam_Om_Khit"

        @preview_polygons.each do |poly_pts|
          next if poly_pts.length < 3

          slat_group = main_group.entities.add_group
          slat_group.name = "Lam_#{count + 1}"

          real_pts = poly_pts.map { |pt| pt.offset(normal_world, -0.5.mm) }

          face = slat_group.entities.add_face(real_pts)
          if face
            face.reverse! if face.normal.dot(normal_world) < 0
            face.pushpull(@thick) if @thick > 0

            # Tự động ẩn và làm mềm các cạnh phân đoạn bên trong mặt phẳng
            slat_group.entities.each do |ent|
              if ent.is_a?(Sketchup::Edge)
                # Cạnh nằm giữa 2 mặt (không phải cạnh biên ngoài) → làm mềm/ẩn
                if ent.faces.length > 1
                  f1, f2 = ent.faces
                  if f1.normal.parallel?(f2.normal)
                    ent.hidden = true
                    ent.smooth = true
                  end
                end
              end
            end

            count += 1
          else
            slat_group.erase! if slat_group.valid?
          end
        end

        model.commit_operation
      end
    end

    # ── Bảng nhập thông số (HtmlDialog theo theme nhà) ─────────────
    def self.show_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title:    'Chia Lam',
        preferences_key: 'tk.chialam',
        width:           320, height: 430,
        min_width:       300, min_height: 400,
        resizable:       false,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      @dialog.add_action_callback('start') do |_ctx, json_str|
        begin
          params = JSON.parse(json_str)
          UI.start_timer(0, false) { activate_tool(params) }
        rescue JSON::ParserError => e
          UI.messagebox("Loi nhan du lieu: #{e.message}")
        end
      end
      @dialog.show
    end

    # Giữ tên cũ để load thử trong Ruby Console vẫn chạy
    def self.start; show_dialog; end

    def self.activate_tool(params)
      @slat_width       = params['width'].to_f
      @slat_gap         = params['gap'].to_f
      @slat_thick       = params['thick'].to_f
      @align_mode       = params['align'].to_s
      @margin_both_mm   = params['margin_both'].to_f
      @margin_single_mm = params['margin_single'].to_f

      unless @slat_width > 0 && @slat_thick > 0
        UI.messagebox('Chieu rong va do day lam phai lon hon 0mm!')
        return
      end

      tool = SlatTool.new(@slat_width, @slat_gap, @slat_thick, @align_mode,
                          @margin_both_mm, @margin_single_mm)
      Sketchup.active_model.select_tool(tool)
    end

    def self.html
      theme_css = File.join(PATH, '..', 'shared', 'lehai_theme.css')
      theme = File.exist?(theme_css) ? File.read(theme_css, encoding: 'UTF-8') : ''
      w  = @slat_width;      g  = @slat_gap;      t  = @slat_thick
      mb = @margin_both_mm;  ms = @margin_single_mm
      # Cờ chọn kiểu căn để đặt "selected" đúng option lúc mở lại
      sel = ->(v) { @align_mode == v ? ' selected' : '' }
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          body{margin:0;padding:16px}
          h3{margin:0 0 12px;font-size:15px;color:var(--lh-walnut)}
          .fld{margin-bottom:11px}
          .fld label{display:block;font-size:11px;color:var(--lh-muted);margin-bottom:4px}
          .fld input,.fld select{width:100%;box-sizing:border-box;padding:8px 9px;
            border:1px solid #e0d3c2;border-radius:var(--lh-radius-sm);
            font-family:inherit;font-size:13px;color:var(--lh-ink);background:var(--lh-surface)}
          .fld input:focus,.fld select:focus{outline:none;border-color:var(--lh-amber)}
          .row{display:flex;gap:10px}.row .fld{flex:1}
          .go{width:100%;margin-top:6px;padding:11px;border:0;border-radius:var(--lh-radius);
            background:var(--lh-amber);color:#fff;font-size:14px;font-weight:700;
            cursor:pointer;font-family:inherit}
          .go:hover{filter:brightness(1.08)}
          .hint{margin-top:11px;font-size:11px;color:var(--lh-muted);line-height:1.5}
        </style></head><body class="lh">
        <div class="lh-eyebrow">LeHai's Decor Tools</div>
        <h3>Chia Lam — ôm khít biên dạng</h3>
        <div class="row">
          <div class="fld"><label>Rộng lam (mm)</label>
            <input id="width" type="number" step="1" min="1" value="#{w}"></div>
          <div class="fld"><label>Khoảng hở (mm)</label>
            <input id="gap" type="number" step="1" min="0" value="#{g}"></div>
        </div>
        <div class="fld"><label>Dày lam (mm)</label>
          <input id="thick" type="number" step="0.5" min="0" value="#{t}"></div>
        <div class="fld"><label>Kiểu căn chỉnh</label>
          <select id="align">
            <option value="Can deu theo Le (Auto Gap)"#{sel.call('Can deu theo Le (Auto Gap)')}>Căn đều theo lề (Auto Gap)</option>
            <option value="Trai qua (Left)"#{sel.call('Trai qua (Left)')}>Trái qua (Left)</option>
            <option value="Phai qua (Right)"#{sel.call('Phai qua (Right)')}>Phải qua (Right)</option>
          </select></div>
        <div class="fld" id="fld_both"><label>Lề 2 đầu — Căn giữa/Auto (mm)</label>
          <input id="margin_both" type="number" step="1" min="0" value="#{mb}"></div>
        <div class="fld" id="fld_single"><label>Lề đầu xuất phát — Trái/Phải (mm)</label>
          <input id="margin_single" type="number" step="1" min="0" value="#{ms}"></div>
        <button class="go" onclick="go()">Bắt đầu chia →</button>
        <div class="hint">Rê chuột lên mặt để xem trước, bấm chuột trái để tạo.<br>
          [A] đổi căn lề · [Tab]/[Space] đổi hướng · [←→] rộng · [↑↓] khe hở.</div>
        <script>
          var alignEl = document.getElementById('align');
          function toggleMargins(){
            var v = alignEl.value;
            var auto = v.indexOf('Auto') >= 0;
            document.getElementById('fld_both').style.display   = auto ? '' : 'none';
            document.getElementById('fld_single').style.display = auto ? 'none' : '';
          }
          alignEl.addEventListener('change', toggleMargins);
          toggleMargins();
          function num(id){ return document.getElementById(id).value; }
          function go(){
            var p = {
              width: num('width'), gap: num('gap'), thick: num('thick'),
              align: alignEl.value,
              margin_both: num('margin_both'), margin_single: num('margin_single')
            };
            sketchup.start(JSON.stringify(p));
          }
        </script></body></html>
      HTML
    end
    private_class_method :html

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──────
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Chia Lam') { TK::ChiaLam.show_dialog }
      cmd.tooltip         = 'Chia Lam: chia mặt phẳng thành hệ nan/lam gỗ ôm khít biên dạng'
      cmd.status_bar_text = 'Rê chuột lên mặt để xem trước hệ lam, bấm chuột trái để tạo. [A] đổi căn lề · [TAB] đổi hướng.'
      cmd.small_icon      = File.join(icons, 'chia_lam_16.png')
      cmd.large_icon      = File.join(icons, 'chia_lam_24.png')
      cmd
    end

  end
end
