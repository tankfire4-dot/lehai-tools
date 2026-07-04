# encoding: UTF-8
# MyStudio_AutoEdgeBand/main.rb — v1.1.3b (fix Ruby 2.7 compatibility)

module MyStudio
  module AutoEdgeBand

    VERSION              = '1.1.5'.freeze
    CAMERA_DOT_THRESHOLD = 0.0
    PERPENDICULAR_DOT    = 0.3
    AXIS_ALIGN_THRESHOLD = 0.92
    VERTICAL_EXCLUDE     = 0.65
    THIN_EXCLUDE_MM      = 12.0
    RAY_OFFSET_IN        = (1.0  / 25.4).freeze
    MAX_EDGE_FACE_IN     = (25.0 / 25.4).freeze

    ICONS_PATH = File.join(File.dirname(__FILE__), 'icons').freeze
    ICON_16    = File.join(ICONS_PATH, 'edge_band_16.png').freeze
    ICON_24    = File.join(ICONS_PATH, 'edge_band_24.png').freeze

    # ═══════════════════════════════════════════════════════
    #  EraserTool
    # ═══════════════════════════════════════════════════════
    class EraserTool
      def initialize
        @erasing        = false
        @highlight_face = nil
        @highlight_pts  = nil
      end

      def activate
        Sketchup.status_text = "🧹 Tẩy Dán Cạnh  |  Giữ chuột + rê qua cạnh cần xóa  |  ESC thoát"
      end

      def deactivate(view)
        @highlight_face = nil
        @highlight_pts  = nil
        view.invalidate
        Sketchup.status_text = ''
      end

      def resume(view)
        view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        pick_banded_face(x, y, view)
        erase_highlighted(view.model) if @erasing
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        @erasing = true
        erase_highlighted(view.model)
        view.invalidate
      end

      def onLButtonUp(flags, x, y, view)
        @erasing = false
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 27
          view.model.select_tool(nil)
          return true
        end
        false
      end

      def draw(view)
        return unless @highlight_pts && @highlight_pts.size >= 3
        view.drawing_color = Sketchup::Color.new(255, 60, 60, 140)
        view.draw(GL_POLYGON, @highlight_pts)
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(220, 30, 30)
        view.draw(GL_LINE_LOOP, @highlight_pts)
      end

      def onSetCursor
        UI.set_cursor(2)
      end

      private

      def pick_banded_face(x, y, view)
        @highlight_face = nil
        @highlight_pts  = nil
        ph = view.pick_helper
        ph.do_pick(x, y)
        ph.count.times do |i|
          path = ph.path_at(i)
          next unless path && !path.empty?
          face = path.last
          next unless face.is_a?(Sketchup::Face)
          next unless MyStudio::AutoEdgeBand.face_has_banding?(face)
          xform = Geom::Transformation.new
          path[0..-2].each { |e| xform = xform * e.transformation if e.respond_to?(:transformation) }
          @highlight_face = face
          @highlight_pts  = face.vertices.map { |v| v.position.transform(xform) }
          break
        end
      end

      def erase_highlighted(model)
        return unless @highlight_face && !@highlight_face.deleted?
        face = @highlight_face
        @highlight_face = nil
        @highlight_pts  = nil
        model.start_operation('Xóa Dán Cạnh Mặt', true)
        MyStudio::AutoEdgeBand.clear_band(face)
        model.commit_operation
      end
    end
    # ═══════════════════════════════════════════════════════

    # ═══════════════════════════════════════════════════════
    #  PainterTool
    # ═══════════════════════════════════════════════════════
    class PainterTool
      def initialize(band_type, mat)
        @band_type      = band_type
        @mat            = mat
        @painting       = false
        @highlight_face = nil
        @highlight_pts  = nil
      end

      def activate
        Sketchup.status_text = "🎨 Tô Dán Cạnh  |  Giữ chuột + rê qua cạnh cần dán  |  ESC thoát"
      end

      def deactivate(view)
        @highlight_face = nil
        @highlight_pts  = nil
        view.invalidate
        Sketchup.status_text = ''
      end

      def resume(view)
        view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        pick_edge_face(x, y, view)
        paint_highlighted(view.model) if @painting
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        @painting = true
        paint_highlighted(view.model)
        view.invalidate
      end

      def onLButtonUp(flags, x, y, view)
        @painting = false
      end

      def onKeyDown(key, repeat, flags, view)
        if key == 27
          view.model.select_tool(nil)
          return true
        end
        false
      end

      def draw(view)
        return unless @highlight_pts && @highlight_pts.size >= 3
        view.drawing_color = Sketchup::Color.new(60, 180, 255, 140)
        view.draw(GL_POLYGON, @highlight_pts)
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(30, 140, 255)
        view.draw(GL_LINE_LOOP, @highlight_pts)
      end

      def onSetCursor
        UI.set_cursor(2)
      end

      private

      def pick_edge_face(x, y, view)
        @highlight_face = nil
        @highlight_pts  = nil
        ph = view.pick_helper

        # Thử aperture tăng dần: 0 → 5 → 10px
        # Cạnh mỏng 18mm rất khó click chính xác, aperture lớn giúp pick được
        [0, 5, 10].each do |ap|
          ph.do_pick(x, y, ap)
          ph.count.times do |i|
            path = ph.path_at(i)
            next unless path && !path.empty?
            entity = path.last
            xform  = Geom::Transformation.new
            path[0..-2].each { |e| xform = xform * e.transformation if e.respond_to?(:transformation) }

            if entity.is_a?(Sketchup::Face)
              # Click trúng face trực tiếp — kiểm tra thin face
              if entity.edges.any? { |e| e.length <= MyStudio::AutoEdgeBand::MAX_EDGE_FACE_IN }
                @highlight_face = entity
                @highlight_pts  = entity.vertices.map { |v| v.position.transform(xform) }
                return
              end

            elsif entity.is_a?(Sketchup::Edge)
              # Click trúng đường edge — tìm face mỏng kề đó
              # Đây là trường hợp hay xảy ra với cạnh trong mỏng
              thin = entity.faces.find { |f|
                f.edges.any? { |e| e.length <= MyStudio::AutoEdgeBand::MAX_EDGE_FACE_IN }
              }
              if thin
                @highlight_face = thin
                @highlight_pts  = thin.vertices.map { |v| v.position.transform(xform) }
                return
              end
            end
          end

          break if @highlight_face
        end
      end

      def paint_highlighted(model)
        return unless @highlight_face && !@highlight_face.deleted?
        return if MyStudio::AutoEdgeBand.face_has_banding?(@highlight_face)
        face = @highlight_face
        @highlight_face = nil
        @highlight_pts  = nil
        model.start_operation('Dán Cạnh Mặt', true)
        MyStudio::AutoEdgeBand.apply_band(face, 0, @mat)
        model.commit_operation
      end
    end
    # ═══════════════════════════════════════════════════════

    @dialog = nil

    def self.show_panel
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title:    'Auto Dán Cạnh',
        preferences_key: 'MyStudio_AutoEdgeBand',
        scrollable:      false,
        width: 300, height: 420,
        min_width: 260, min_height: 380
      )
      @dialog.set_html(panel_html)
      register_callbacks(@dialog)
      # Đóng panel = thoát plugin → tự ẩn dấu (như ABF chỉ hiện khi bật).
      @dialog.set_on_closed { hide_all_bands rescue nil }
      @dialog.show
      refresh_band_types
      show_all_bands rescue nil   # mở panel → hiện lại dấu đã ẩn
    end

    def self.register_callbacks(dlg)
      dlg.add_action_callback('apply_band') do |_ctx, type_json, mode_str|
        begin
          band_type  = JSON.parse(type_json)
          mode       = mode_str == 'reset' ? :reset : :accumulate
          model      = Sketchup.active_model
          camera     = model.active_view.camera
          camera_dir = camera.direction
          camera_eye = camera.eye
          boards = []
          model.selection.each { |e| collect_boards(e, e.transformation, boards, 0) }
          if boards.empty?
            dlg.execute_script("setStatus('⚠️ Chưa chọn tấm gỗ nào', 'warn')")
            next
          end
          mat = ensure_display_material(model, band_type[3])
          model.start_operation('Auto Dán Cạnh Mặt Tiền', true)
          total = boards.sum { |inst, wxform|
            process_board(inst, wxform, band_type, mat, camera_dir, camera_eye, model, mode)
          }
          model.commit_operation
          mode_label = mode == :reset ? 'Reset' : 'Cộng dồn'
          dlg.execute_script("setStatus('✓ Dán #{total} cạnh mặt [#{mode_label}]', 'ok')")
        rescue => e
          model.abort_operation rescue nil
          dlg.execute_script("setStatus('❌ Lỗi: #{e.message.gsub("'","\\\\'")}', 'error')")
        end
      end

      dlg.add_action_callback('clear_band') do |_ctx|
        begin
          model  = Sketchup.active_model
          boards = []
          model.selection.each { |e| collect_boards(e, e.transformation, boards, 0) }
          if boards.empty?
            dlg.execute_script("setStatus('⚠️ Chưa chọn tấm gỗ nào', 'warn')")
            next
          end
          model.start_operation('Xóa Dán Cạnh', true)
          count = 0
          boards.each do |inst, _|
            raw_entities(inst).grep(Sketchup::Face).each do |face|
              next if face.deleted?
              next unless face_has_banding?(face)
              clear_band(face)
              count += 1
            end
          end
          model.commit_operation
          dlg.execute_script("setStatus('🗑 Đã xóa #{count} cạnh mặt', 'ok')")
        rescue => e
          model.abort_operation rescue nil
          dlg.execute_script("setStatus('❌ #{e.message.gsub("'","\\\\'")}', 'error')")
        end
      end

      dlg.add_action_callback('activate_eraser') do |_ctx|
        Sketchup.active_model.select_tool(EraserTool.new)
      end

      dlg.add_action_callback('activate_painter') do |_ctx, type_json|
        begin
          band_type = JSON.parse(type_json)
          model     = Sketchup.active_model
          mat       = ensure_display_material(model, band_type[3])
          model.select_tool(PainterTool.new(band_type, mat))
        rescue => e
          dlg.execute_script("setStatus('❌ #{e.message.gsub("'","\\\\'")}', 'error')")
        end
      end

      dlg.add_action_callback('refresh_types') { |_| refresh_band_types }
    end

    def self.refresh_band_types
      return unless @dialog && @dialog.visible?
      types = scan_all_band_types(Sketchup.active_model)
      json  = types.map { |t|
        "[#{t[0].to_i},#{t[1].to_s.inspect},#{t[2].to_f},#{t[3].to_s.inspect},#{t[4].to_i}]"
      }.join(',')
      @dialog.execute_script("setBandTypes([#{json}])")
    end

    def self.collect_boards(entity, world_xform, results, depth)
      return if depth > 6
      return unless entity.is_a?(Sketchup::ComponentInstance) ||
                    entity.is_a?(Sketchup::Group)
      ents = raw_entities(entity)
      if ents.grep(Sketchup::Face).size >= 2
        results << [entity, world_xform]
      else
        ents.each do |child|
          next unless child.is_a?(Sketchup::ComponentInstance) ||
                      child.is_a?(Sketchup::Group)
          collect_boards(child, world_xform * child.transformation, results, depth + 1)
        end
      end
    end

    def self.process_board(inst, world_xform, band_type, mat,
                           camera_dir, camera_eye, model, mode)
      inst.make_unique if inst.is_a?(Sketchup::ComponentInstance)
      ents = raw_entities(inst)
      inst.set_attribute('ABF', 'is-board',       true)
      inst.set_attribute('ABF', 'edge-band-types', band_type)
      if mode == :reset
        ents.grep(Sketchup::Face).each do |face|
          next if face.deleted?
          clear_band(face) if face_has_banding?(face)
        end
      end
      edge_faces = identify_straight_edge_faces(ents)

      # Tách mặt cong (thuộc cung tròn) ra xử lý theo nhóm
      curved, straight = edge_faces.partition { |f| f.edges.any? { |e| e.curve } }
      curve_groups     = group_arc_faces(curved)

      count = 0

      straight.each do |face|
        next if face.deleted?
        next if mode == :accumulate && face_has_banding?(face)
        if face_visible_from_camera?(face, world_xform, camera_dir, camera_eye, model)
          apply_band(face, 0, mat)
          count += 1
        end
      end

      # Nếu camera thấy BẤT KỲ mặt nào trong một cung → dán CẢ cung
      curve_groups.each do |group|
        next if group.all?(&:deleted?)
        next if mode == :accumulate && group.all? { |f| face_has_banding?(f) }
        visible = group.any? { |f|
          !f.deleted? && face_visible_from_camera?(f, world_xform, camera_dir, camera_eye, model)
        }
        next unless visible
        group.each do |face|
          next if face.deleted?
          next if mode == :accumulate && face_has_banding?(face)
          apply_band(face, 0, mat)
          count += 1
        end
      end

      count
    end

    # BFS qua curve.edges: từ mỗi mặt, lần theo các cạnh arc → tìm mặt kề cùng cung
    # Không dùng entityID của curve (không ổn định), mà dùng entityID của face
    def self.group_arc_faces(faces)
      id_to_face = {}
      faces.each { |f| id_to_face[f.entityID] = f }

      unvisited = faces.map(&:entityID)
      groups    = []

      until unvisited.empty?
        seed_id = unvisited.shift
        group   = [id_to_face[seed_id]]
        queue   = [id_to_face[seed_id]]

        while queue.any?
          current = queue.shift
          current.edges.each do |e|
            next unless e.curve
            e.curve.edges.each do |arc_edge|
              arc_edge.faces.each do |neighbor|
                n_id = neighbor.entityID
                idx  = unvisited.index(n_id)
                next if idx.nil?
                unvisited.delete_at(idx)
                group << neighbor
                queue << neighbor
              end
            end
          end
        end

        groups << group
      end
      groups
    end

    def self.identify_straight_edge_faces(ents)
      all_faces = ents.grep(Sketchup::Face)
      return [] if all_faces.size < 2
      large_face   = all_faces.max_by(&:area)
      large_normal = large_face.normal
      return [] if large_normal.length < 0.001
      all_faces.select do |face|
        next false if face == large_face
        fn = face.normal
        next false if fn.length < 0.001
        fn.dot(large_normal).abs < PERPENDICULAR_DOT
      end
    end

    def self.face_visible_from_camera?(face, world_xform, camera_dir, camera_eye, model)
      local_normal = face.normal
      return false if local_normal.length < 0.001
      world_normal = local_normal.transform(world_xform)
      return false if world_normal.length < 0.001
      world_normal.normalize!
      return false unless world_normal.dot(camera_dir) < CAMERA_DOT_THRESHOLD
      if world_normal.z.abs > VERTICAL_EXCLUDE
        max_edge = face.edges.map(&:length).max
        return false unless max_edge && max_edge > 0.001
        return false if (face.area / max_edge) * 25.4 < THIN_EXCLUDE_MM
      end
      center = world_center(face, world_xform)
      return false unless center
      to_camera   = camera_eye - center
      dist_to_cam = to_camera.length
      return true if dist_to_cam < 0.001
      dir      = to_camera.normalize
      start_pt = center.offset(dir, RAY_OFFSET_IN)
      result   = model.raytest([start_pt, dir])
      return true if result.nil?
      hit_dist = start_pt.distance(result[0])
      hit_dist >= (dist_to_cam - RAY_OFFSET_IN) * 0.98
    end

    def self.world_center(face, world_xform)
      pts = face.vertices.map { |v| v.position.transform(world_xform) }
      return nil if pts.empty?
      n = pts.size.to_f
      Geom::Point3d.new(
        pts.inject(0.0) { |s, p| s + p.x } / n,
        pts.inject(0.0) { |s, p| s + p.y } / n,
        pts.inject(0.0) { |s, p| s + p.z } / n
      )
    end

    def self.face_has_banding?(face)
      face.material&.name&.start_with?('Hung_Show_ABF_') ||
        !face.attribute_dictionary('Hung_EdgeBanding').nil? ||
        !face.get_attribute('ABF', 'edge-band-id').nil?
    end

    def self.raw_entities(inst)
      inst.respond_to?(:definition) ? inst.definition.entities : inst.entities
    end

    def self.apply_band(face, band_id, mat)
      orig = face.material ? face.material.name : 'nil'
      face.set_attribute('Hung_EdgeBanding', 'OriginalMat', orig)
      face.set_attribute('ABF', 'edge-band-id', band_id)
      face.material = mat
    end

    def self.clear_band(face)
      orig_name = face.get_attribute('Hung_EdgeBanding', 'OriginalMat')
      if orig_name && orig_name != 'nil'
        face.material = Sketchup.active_model.materials[orig_name]
      else
        face.material = nil
      end
      face.delete_attribute('ABF')
      face.delete_attribute('Hung_EdgeBanding')
    end

    def self.ensure_display_material(model, hex_color)
      name  = "Hung_Show_ABF_#{hex_color}"
      return model.materials[name] if model.materials[name]
      mat   = model.materials.add(name)
      clean = hex_color.to_s.delete('#')
      mat.color = Sketchup::Color.new(
        clean[0..1].to_i(16),
        clean[2..3].to_i(16),
        clean[4..5].to_i(16)
      )
      mat
    end

    # ═══════════════════════════════════════════════════════
    #  ẨN / HIỆN dấu dán cạnh toàn file (giống bật/tắt của ABF)
    #  Ẩn  = đổi màu tô về màu gỗ gốc (đã lưu ở OriginalMat), GIỮ dấu bền
    #        (attribute ABF/edge-band-id + dict Hung_EdgeBanding) → hết viền tím
    #        nhưng check & máy vẫn đọc được là "đã dán".
    #  Hiện = tô lại material đã lưu (ShowMat); tạo lại nếu material bị xoá.
    # ═══════════════════════════════════════════════════════
    def self.hide_all_bands
      model = Sketchup.active_model
      model.start_operation('An dau dan canh', true)
      n = 0
      each_banded_face_in_model(model) do |face|
        m = face.material
        next unless m && m.name.to_s.start_with?('Hung_Show_ABF_')
        face.set_attribute('Hung_EdgeBanding', 'ShowMat', m.name)   # nhớ để hiện lại
        orig = face.get_attribute('Hung_EdgeBanding', 'OriginalMat')
        face.material = (orig && orig != 'nil') ? model.materials[orig] : nil
        n += 1
      end
      n.positive? ? model.commit_operation : model.abort_operation
      n
    rescue => e
      model.abort_operation rescue nil
      raise e
    end

    def self.show_all_bands
      model = Sketchup.active_model
      model.start_operation('Hien dau dan canh', true)
      n = 0
      each_banded_face_in_model(model) do |face|
        m = face.material
        next if m && m.name.to_s.start_with?('Hung_Show_ABF_')     # đang hiện rồi
        smat = face.get_attribute('Hung_EdgeBanding', 'ShowMat')
        next unless smat
        mat = model.materials[smat] || recreate_show_mat(model, smat)
        face.material = mat if mat
        n += 1
      end
      n.positive? ? model.commit_operation : model.abort_operation
      n
    rescue => e
      model.abort_operation rescue nil
      raise e
    end

    def self.recreate_show_mat(model, name)
      hex = name.to_s.sub('Hung_Show_ABF_', '')
      return nil if hex.empty?
      ensure_display_material(model, hex)
    rescue StandardError
      nil
    end

    # duyệt MỌI face qua definitions (mỗi định nghĩa 1 lần → nhanh, không trùng)
    def self.each_banded_face_in_model(model)
      model.definitions.each do |d|
        next if d.image?
        d.entities.grep(Sketchup::Face).each { |f| yield f unless f.deleted? }
      end
    end

    def self.scan_all_band_types(model)
      seen = {}
      scan_for_types(model.active_entities, seen, 0)
      seen.values
    end

    def self.scan_for_types(entities, seen, depth)
      return if depth > 6
      entities.each do |e|
        next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
        raw = e.get_attribute('ABF', 'edge-band-types')
        seen[raw[1].to_s] ||= raw if raw.is_a?(Array) && raw.size >= 4
        scan_for_types(raw_entities(e), seen, depth + 1)
      end
    end

    def self.panel_html
      theme_css = File.join(File.dirname(__FILE__), '..', 'shared', 'lehai_theme.css')
      theme = File.exist?(theme_css) ? File.read(theme_css, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          *{box-sizing:border-box;margin:0;padding:0}
          body{font-size:13px;padding:12px;user-select:none}
          h3{font-size:14px;color:var(--lh-walnut);margin-bottom:12px}
          label{display:block;color:var(--lh-ink-soft);font-size:11px;margin-bottom:4px;font-weight:700}
          select{width:100%;padding:6px 8px;background:var(--lh-surface);color:var(--lh-ink);
                 border:1.5px solid var(--lh-line);border-radius:var(--lh-radius-sm);margin-bottom:10px;
                 font-size:12px;font-family:inherit}
          .modes{display:flex;gap:8px;margin-bottom:10px}
          .mode-btn{flex:1;padding:6px;border:1.5px solid var(--lh-line);border-radius:var(--lh-radius-sm);
                    background:var(--lh-surface);color:var(--lh-ink-soft);cursor:pointer;font-size:12px;text-align:center}
          .mode-btn.active{border-color:var(--lh-amber);color:var(--lh-amber-2);background:var(--lh-chip)}
          .btn{width:100%;padding:8px;border:none;border-radius:var(--lh-radius-sm);
               cursor:pointer;font-size:13px;font-weight:bold;margin-bottom:6px;font-family:inherit}
          .btn-primary{background:var(--lh-amber);color:#fff}
          .btn-primary:hover{filter:brightness(1.06)}
          .btn-painter{background:var(--lh-surface);color:var(--lh-walnut);border:1.5px solid var(--lh-line);font-size:12px}
          .btn-painter:hover{border-color:var(--lh-amber);color:var(--lh-amber)}
          .btn-eraser{background:var(--lh-surface);color:#b91c1c;border:1.5px solid var(--lh-line);font-size:12px}
          .btn-eraser:hover{border-color:#b91c1c}
          .btn-clear{background:var(--lh-fill);color:var(--lh-ink-soft);font-size:12px}
          .btn-clear:hover{background:var(--lh-fill-2)}
          .divider{border:none;border-top:1px solid var(--lh-line-2);margin:8px 0}
          .tool-row{display:flex;gap:6px;margin-bottom:6px}
          .tool-row .btn{margin-bottom:0}
          .status{margin-top:8px;padding:7px 10px;border-radius:var(--lh-radius-sm);
                  font-size:12px;background:var(--lh-fill);color:var(--lh-ink-soft);min-height:32px}
          .status.ok{color:#15803d}.status.warn{color:#b45309}.status.error{color:#b91c1c}
          .refresh-row{display:flex;justify-content:flex-end;margin-bottom:4px}
          .btn-refresh{background:none;border:none;color:var(--lh-muted);cursor:pointer;font-size:11px;padding:2px 4px;font-family:inherit}
          .btn-refresh:hover{color:var(--lh-amber)}
        </style></head><body class="lh">
          <div class="lh-eyebrow">LeHai's Decor Tools</div>
          <h3>▣ Auto Dán Cạnh_ LeHai</h3>
          <div class="refresh-row">
            <button class="btn-refresh" onclick="sketchup.refresh_types()">↺ Làm mới danh sách</button>
          </div>
          <label>Loại chỉ dán cạnh</label>
          <select id="bandType"></select>
          <label>Chế độ tự động</label>
          <div class="modes">
            <div class="mode-btn active" id="modeAccum" onclick="setMode('accumulate')">＋ Cộng dồn</div>
            <div class="mode-btn"        id="modeReset" onclick="setMode('reset')">↺ Reset</div>
          </div>
          <button class="btn btn-primary" onclick="applyBand()">⚡ Dán Cạnh Mặt Tiền</button>
          <hr class="divider">
          <label>Công cụ thủ công</label>
          <div class="tool-row">
            <button class="btn btn-painter" onclick="activatePainter()">🎨 Tô cạnh</button>
            <button class="btn btn-eraser"  onclick="activateEraser()">🧹 Tẩy cạnh</button>
          </div>
          <button class="btn btn-clear" onclick="clearBand()">🗑 Xóa toàn bộ dán cạnh</button>
          <div class="status" id="status">Chọn tấm gỗ → bấm Dán Cạnh</div>
          <script>
            var currentMode='accumulate';
            function setMode(m){
              currentMode=m;
              document.getElementById('modeAccum').className='mode-btn'+(m==='accumulate'?' active':'');
              document.getElementById('modeReset').className='mode-btn'+(m==='reset'?' active':'');
            }
            function applyBand(){
              var sel=document.getElementById('bandType');
              if(!sel.options.length){setStatus('⚠️ Chưa có loại chỉ. Bấm ↺ làm mới.','warn');return;}
              setStatus('⏳ Đang xử lý...','');
              sketchup.apply_band(sel.options[sel.selectedIndex].value,currentMode);
            }
            function activatePainter(){
              var sel=document.getElementById('bandType');
              if(!sel.options.length){setStatus('⚠️ Chưa có loại chỉ.','warn');return;}
              sketchup.activate_painter(sel.options[sel.selectedIndex].value);
              setStatus('🎨 Đang tô — giữ chuột + rê qua cạnh cần dán | ESC thoát','warn');
            }
            function activateEraser(){
              sketchup.activate_eraser();
              setStatus('🧹 Đang tẩy — giữ chuột + rê qua cạnh cần xóa | ESC thoát','warn');
            }
            function clearBand(){setStatus('⏳ Đang xóa...','');sketchup.clear_band();}
            function setStatus(msg,type){
              var el=document.getElementById('status');
              el.textContent=msg;el.className='status '+(type||'');
            }
            function setBandTypes(types){
              var sel=document.getElementById('bandType'),prev=sel.value;
              sel.innerHTML='';
              types.forEach(function(t){
                var opt=document.createElement('option');
                opt.value=JSON.stringify(t);
                opt.text=t[1]+'  ('+t[2]+'mm)';
                if(opt.value===prev)opt.selected=true;
                sel.appendChild(opt);
              });
              if(!types.length)setStatus('⚠️ Chưa có loại chỉ. Gắn nhãn 1 tấm bằng ABF trước.','warn');
            }
          </script>
        </body></html>
      HTML
    end

    def self.create_cmd
      cmd = UI::Command.new('Auto Dán Cạnh Mặt Tiền') { MyStudio::AutoEdgeBand.show_panel }
      cmd.tooltip         = 'Mở panel Dán Cạnh'
      cmd.status_bar_text = 'Mở panel → căn camera → chọn tấm gỗ → bấm Dán Cạnh'
      cmd.small_icon      = ICON_16
      cmd.large_icon      = ICON_24
      cmd
    end

  end
end
