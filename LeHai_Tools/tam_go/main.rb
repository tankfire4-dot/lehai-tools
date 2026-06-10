# encoding: UTF-8
# Lehai_TamGoGen/main.rb  v2.2.0
# Them nut xoay 90 do — dung dims() cho toan bo geometry

require 'sketchup.rb'
require 'json'

module Lehai
  module TamGoGen

    VERSION    = '2.2.0'
    PATH       = File.dirname(__FILE__).freeze
    MM_TO_INCH = 1.0 / 25.4

    @dialog      = nil
    @active_tool = nil

    def self.active_tool=(tool); @active_tool = tool; end
    def self.active_tool;        @active_tool;        end

    def self.show_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title:    'Tạo Tấm Gỗ Nhanh -- Le Hai Studio',
        preferences_key: 'com.lehai.tamgogen.v2',
        width:           420,
        height:          680,
        min_width:       340,
        min_height:      600,
        resizable:       true
      )

      html_path = File.join(PATH, 'ui', 'dialog.html')
      @dialog.set_url(html_path)

      @dialog.add_action_callback('tao_tam_go') do |_ctx, json_str|
        begin
          params = JSON.parse(json_str)
          UI.start_timer(0, false) { activate_place_tool(params) }
        rescue JSON::ParserError => e
          UI.messagebox("Loi nhan du lieu: #{e.message}")
        end
      end

      # R — toggle xoay (khi dialog co focus)
      @dialog.add_action_callback('toggle_rotate_from_dialog') do |_ctx|
        UI.start_timer(0, false) do
          tool = Lehai::TamGoGen.active_tool
          tool.toggle_rotated if tool
        end
      end

      # F — toggle nam/dung (khi dialog co focus)
      @dialog.add_action_callback('toggle_vertical_from_dialog') do |_ctx|
        UI.start_timer(0, false) do
          tool = Lehai::TamGoGen.active_tool
          tool.toggle_vertical if tool
        end
      end

      # S — swap length/width (khi dialog co focus)
      @dialog.add_action_callback('swap_dims_from_dialog') do |_ctx|
        UI.start_timer(0, false) do
          tool = Lehai::TamGoGen.active_tool
          tool.swap_dims_silent if tool
        end
      end

      # ESC — huy PlaceTool (khi dialog co focus)
      @dialog.add_action_callback('cancel_place_tool') do |_ctx|
        UI.start_timer(0, false) do
          Lehai::TamGoGen.active_tool = nil
          Sketchup.active_model.select_tool(nil)
        end
      end

      # Ve 2 diem — kich hoat DrawTool
      @dialog.add_action_callback('start_draw_tool') do |_ctx, json_str|
        begin
          params = JSON.parse(json_str)
          UI.start_timer(0, false) { activate_draw_tool(params) }
        rescue JSON::ParserError => e
          UI.messagebox("Loi: #{e.message}")
        end
      end

      @dialog.show
    end

    def self.activate_place_tool(params)
      length_mm = params['length'].to_f
      width_mm  = params['width'].to_f
      thick_mm  = params['thickness'].to_f
      name      = params['name'].to_s.strip
      vertical  = params['vertical'] == true
      rotated   = params['rotated']  == true

      name = 'Tam go' if name.empty?

      unless length_mm > 0 && width_mm > 0 && thick_mm > 0
        UI.messagebox('Kich thuoc phai lon hon 0mm!')
        return
      end

      tool = PlaceTool.new(
        length:   length_mm * MM_TO_INCH,
        width:    width_mm  * MM_TO_INCH,
        thick:    thick_mm  * MM_TO_INCH,
        name:     name,
        vertical: vertical,
        rotated:  rotated,
        dialog:   @dialog
      )
      Sketchup.active_model.select_tool(tool)
    end

    def self.activate_draw_tool(params)
      thick_mm = params['thickness'].to_f
      name     = params['name'].to_s.strip
      name     = 'Tam go' if name.empty?
      unless thick_mm > 0
        UI.messagebox('Do day phai lon hon 0mm!')
        return
      end
      tool = DrawTool.new(thick: thick_mm * MM_TO_INCH, name: name, dialog: @dialog)
      Sketchup.active_model.select_tool(tool)
    end

    class PlaceTool

      BOX_EDGES = [
        [0,1],[1,2],[2,3],[3,0],
        [4,5],[5,6],[6,7],[7,4],
        [0,4],[1,5],[2,6],[3,7]
      ].freeze

      def initialize(params)
        @length   = params[:length]
        @width    = params[:width]
        @thick    = params[:thick]
        @name     = params[:name]
        @vertical = params[:vertical]
        @rotated  = params[:rotated]
        @dialog   = params[:dialog]
        @ip       = Sketchup::InputPoint.new
        @pos      = ORIGIN
      end

      def activate
        Lehai::TamGoGen.active_tool = self
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        Lehai::TamGoGen.active_tool = nil
        view.invalidate
      end

      def resume(view); activate; end
      def suspend(view); view.invalidate; end

      # Goi duoc tu ca Ruby (onKeyDown) lan JS (dialog callback)
      def toggle_rotated
        @rotated = !@rotated
        update_status
        sync_dialog
        Sketchup.active_model.active_view.invalidate
      end

      def toggle_vertical
        @vertical = !@vertical
        update_status
        sync_dialog
        Sketchup.active_model.active_view.invalidate
      end

      def swap_dims
        @length, @width = @width, @length
        Sketchup.active_model.active_view.invalidate
        sync_dialog_swap
      end

      def swap_dims_silent
        @length, @width = @width, @length
        Sketchup.active_model.active_view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        @ip.pick(view, x, y)
        @pos = @ip.position
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        @pos = Sketchup::InputPoint.new(@ip.position).position
        place_board(view.model)
        view.model.select_tool(nil)
      end

      def onKeyDown(key, repeat, flags, view)
        return if repeat > 1
        case key
        when VK_ESCAPE
          view.model.select_tool(nil)
        when 82, 114   # R/r — toggle xoay 90 do
          toggle_rotated
        when 70, 102   # F/f — toggle nam ngang / dung thang
          toggle_vertical
        when 83, 115   # S/s — swap length/width
          swap_dims
        end
        false
      end

      def draw(view)
        return unless @pos
        pts = box_corners
        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(30, 144, 255, 220)
        BOX_EDGES.each { |i, j| view.draw(GL_LINES, [pts[i], pts[j]]) }
        @ip.draw(view) if @ip.valid?
      end

      def getExtents
        bb = Geom::BoundingBox.new
        box_corners.each { |pt| bb.add(pt) }
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      def getStatusText
        dir = @vertical ? 'Dung' : 'Nam'
        rot = @rotated  ? '[Xoay]' : ''
        "Click de dat  #{dir}#{rot}  |  R=Xoay  F=Nam/Dung  |  ESC=Huy"
      end

      private

      def update_status
        dir = @vertical ? 'Dung thang' : 'Nam ngang'
        rot = @rotated  ? '  [Xoay 90]' : ''
        Sketchup.set_status_text(
          "#{dir}#{rot}  |  Click=Dat  R=Xoay  F=Nam/Dung  ESC=Huy", SB_PROMPT
        )
      end

      def sync_dialog
        return unless @dialog && @dialog.visible?
        @dialog.execute_script(
          "typeof setRotateExternal==='function'   && setRotateExternal(#{@rotated});" +
          "typeof setVerticalExternal==='function' && setVerticalExternal(#{@vertical});"
        )
      rescue StandardError
        nil
      end

      def sync_dialog_swap
        return unless @dialog && @dialog.visible?
        @dialog.execute_script("typeof swapDimsExternal==='function' && swapDimsExternal();")
      rescue StandardError
        nil
      end

      def dims
        l, w, t = @length, @width, @thick
        if @vertical
          @rotated ? [t, w, l] : [w, t, l]
        else
          @rotated ? [w, l, t] : [l, w, t]
        end
      end

      def box_corners
        x, y, z    = @pos.x, @pos.y, @pos.z
        dx, dy, dz = dims
        [
          Geom::Point3d.new(x,    y,    z),
          Geom::Point3d.new(x+dx, y,    z),
          Geom::Point3d.new(x+dx, y+dy, z),
          Geom::Point3d.new(x,    y+dy, z),
          Geom::Point3d.new(x,    y,    z+dz),
          Geom::Point3d.new(x+dx, y,    z+dz),
          Geom::Point3d.new(x+dx, y+dy, z+dz),
          Geom::Point3d.new(x,    y+dy, z+dz)
        ]
      end

      def place_board(model)
        model.start_operation('Tao Tam Go', true)
        begin
          dx, dy, dz = dims
          grp        = model.active_entities.add_group
          grp.name   = @name

          face = grp.entities.add_face(
            Geom::Point3d.new(0,  0,  0),
            Geom::Point3d.new(dx, 0,  0),
            Geom::Point3d.new(dx, dy, 0),
            Geom::Point3d.new(0,  dy, 0)
          )
          push_dist = face.normal.z >= 0 ? dz : -dz
          face.pushpull(push_dist)
          grp.transform!(Geom::Transformation.translation(@pos))
          model.commit_operation
        rescue => e
          model.abort_operation
          UI.messagebox("Loi: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
        end
      end

    end # class PlaceTool

    class DrawTool
      FACE_CENTER_SNAP_PX = 12

      def initialize(params)
        @thick   = params[:thick]
        @name    = params[:name]
        @dialog  = params[:dialog]
        @ip1     = Sketchup::InputPoint.new
        @ip2     = Sketchup::InputPoint.new
        @state   = :pt1
        @pt1     = nil
        @normal  = nil
        @snap1   = nil
        @snap2   = nil
        @mouse_x = 0
        @mouse_y = 0
      end

      def activate
        Lehai::TamGoGen.active_tool = self
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        Lehai::TamGoGen.active_tool = nil
        view.invalidate
      end

      def resume(view); activate; end
      def suspend(view); view.invalidate; end

      def onMouseMove(flags, x, y, view)
        @mouse_x = x
        @mouse_y = y
        if @state == :pt1
          @ip1.pick(view, x, y)
          view.tooltip = @ip1.tooltip if @ip1.valid?
          @snap1 = face_center_snap(@ip1, x, y, view)
        else
          @ip2.pick(view, x, y, @ip1)
          view.tooltip = @ip2.tooltip if @ip2.valid?
          @snap2 = face_center_snap(@ip2, x, y, view)
        end
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        if @state == :pt1
          @ip1.pick(view, x, y)
          return unless @ip1.valid?
          @pt1    = @snap1 || @ip1.position
          @normal = @ip1.face ? @ip1.face.normal : Z_AXIS
          @snap1  = nil
          @state  = :pt2
          update_status
        else
          @ip2.pick(view, x, y, @ip1)
          return unless @ip2.valid?
          pt2    = @snap2 || @ip2.position
          @snap2 = nil
          corners = compute_rect(@pt1, pt2, @normal)
          place_panel(view.model, corners) if corners
          reset_to_pt1
        end
        view.invalidate
      end

      def onKeyDown(key, repeat, flags, view)
        return if repeat > 1
        case key
        when VK_ESCAPE
          @state == :pt2 ? reset_to_pt1 : view.model.select_tool(nil)
        end
        false
      end

      def draw(view)
        if @state == :pt1
          @ip1.draw(view) if @ip1.valid? && @ip1.display?
          draw_face_center_indicator(view, @snap1) if @snap1
          return
        end

        return unless @pt1

        view.draw_points([@pt1], 14, 2, Sketchup::Color.new(255, 150, 0))

        if @ip2.valid?
          pt2     = @snap2 || @ip2.position
          corners = compute_rect(@pt1, pt2, @normal)
          if corners
            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = Sketchup::Color.new(30, 144, 255, 220)
            view.draw_polyline(corners + [corners.first])
          end
          @ip2.draw(view) if @ip2.display? && !@snap2
        end
        draw_face_center_indicator(view, @snap2) if @snap2
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@pt1) if @pt1
        if @state == :pt2 && @ip2.valid?
          corners = compute_rect(@pt1, @ip2.position, @normal)
          corners&.each { |c| bb.add(c) }
        end
        bb
      rescue StandardError
        Geom::BoundingBox.new
      end

      # No-op: dialog callbacks từ PlaceTool mode không crash khi DrawTool đang active
      def toggle_rotated;   end
      def toggle_vertical;  end
      def swap_dims;        end
      def swap_dims_silent; end

      private

      def update_status
        text = @state == :pt1 \
          ? 'Click điểm 1 — góc đầu tiên tấm gỗ  |  ESC=Thoát' \
          : 'Click điểm 2 — góc đối diện  |  ESC=Huỷ'
        Sketchup.set_status_text(text, SB_PROMPT)
      end

      def reset_to_pt1
        @state  = :pt1
        @pt1    = nil
        @normal = nil
        @snap1  = nil
        @snap2  = nil
        @ip2.clear
        update_status
      end

      def face_center_snap(ip, x, y, view)
        face = ip.face
        return nil unless face
        center = face.bounds.center
        sc     = view.screen_coords(center)
        return nil unless sc
        dist = Math.sqrt((sc.x - x)**2 + (sc.y - y)**2)
        dist < FACE_CENTER_SNAP_PX ? center : nil
      end

      def draw_face_center_indicator(view, pt)
        sc = view.screen_coords(pt)
        return unless sc
        s = 8
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(255, 200, 0)
        view.line_stipple  = ''
        view.draw2d(GL_LINE_LOOP, [
          Geom::Point3d.new(sc.x,     sc.y - s, 0),
          Geom::Point3d.new(sc.x + s, sc.y,     0),
          Geom::Point3d.new(sc.x,     sc.y + s, 0),
          Geom::Point3d.new(sc.x - s, sc.y,     0)
        ])
      end

      def plane_axes(normal)
        n = normal.normalize
        return [X_AXIS, Y_AXIS] if n.parallel?(Z_AXIS)
        u = n.cross(Z_AXIS).normalize
        v = u.cross(n).normalize
        [u, v]
      end

      def compute_rect(pt1, pt2, normal)
        plane    = [pt1, normal]
        pt2_proj = pt2.project_to_plane(plane)
        vec      = pt2_proj - pt1
        return nil if vec.length < 1.mm

        u, v = plane_axes(normal)
        du   = vec.dot(u)
        dv   = vec.dot(v)
        return nil if du.abs < 1.mm || dv.abs < 1.mm

        [pt1, pt1 + u * du, pt1 + u * du + v * dv, pt1 + v * dv]
      end

      def place_panel(model, corners)
        model.start_operation('Tao Tam Go Ve', true)
        begin
          grp  = model.active_entities.add_group
          grp.name = @name
          face = grp.entities.add_face(corners)
          face.reverse! if face.normal.dot(@normal) < 0
          face.pushpull(@thick)
          model.commit_operation
        rescue => e
          model.abort_operation
          UI.messagebox("Loi: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
        end
      end

    end # class DrawTool

    def self.create_cmd
      cmd = UI::Command.new('Tao Tam Go Nhanh') { Lehai::TamGoGen.show_dialog }
      cmd.tooltip         = 'Tạo tấm gỗ nhanh với kích thước tùy chỉnh (mm)'
      cmd.status_bar_text = 'Mở hộp thoại Tạo Tấm Gỗ Nhanh -- Le Hai Studio'
      cmd.small_icon      = File.join(PATH, 'icons', 'tamgo_16.png')
      cmd.large_icon      = File.join(PATH, 'icons', 'tamgo_24.png')
      cmd
    end

  end
end
