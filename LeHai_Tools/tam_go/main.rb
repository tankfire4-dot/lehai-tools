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
