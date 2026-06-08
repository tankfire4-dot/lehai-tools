# encoding: UTF-8
# LeHai_HaNen — Tạo vùng hạ nền uốn cong đúng kích thước
# Cách dùng: bấm icon → rê chuột tới cục 3D uốn cong → click

require 'sketchup.rb'

module LeHaiDecor
  module HaNen

    OVERHANG_MM  = 3.0
    THICKNESS_MM = 17.5
    TAG_HN       = 'NTT_SoiHaNen'.freeze
    INST_HN      = 'ABF_hanenduong'.freeze

    # ── Tool class: hover highlight + click to run ─────────────
    class HaNenTool
      def initialize
        @hovered = nil
      end

      def activate
        update_status(nil)
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.model.selection.clear
        view.invalidate
      end

      def onCancel(_reason, view)
        view.model.selection.clear
        view.model.select_tool(nil)
      end

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked

        new_hov = (entity.is_a?(Sketchup::Group) ||
                   entity.is_a?(Sketchup::ComponentInstance)) ? entity : nil

        if new_hov != @hovered
          @hovered = new_hov
          sel = view.model.selection
          sel.clear
          sel.add(@hovered) if @hovered
          view.invalidate
        end
        update_status(@hovered)
      end

      def onLButtonDown(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked

        unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          Sketchup.set_status_text("Không phải group — rê chuột tới cục 3D uốn cong rồi click")
          return
        end

        view.model.selection.clear
        view.model.select_tool(nil)
        UI.start_timer(0, false) { LeHaiDecor::HaNen.run_on(entity) }
      end

      def getInstructorContentDirectory; nil; end

      private

      def update_status(hov)
        if hov
          Sketchup.set_status_text("✓ Sẵn sàng — click để tạo hạ nền | ESC: thoát")
        else
          Sketchup.set_status_text("Di chuột tới cục 3D uốn cong, click để tạo hạ nền | ESC: thoát")
        end
      end
    end

    # ── Entry point: bật tool ──────────────────────────────────
    def self.run
      Sketchup.active_model.select_tool(HaNenTool.new)
    end

    # ── Logic chính: đo + tạo tấm phẳng + vùng cam ────────────
    def self.run_on(entity)
      model = Sketchup.active_model

      info = measure(entity)
      unless info
        UI.messagebox(
          "Không tìm thấy đường cong trong group được chọn.\n" \
          "Đảm bảo ông click đúng cục tấm cong (click 1 lần, không double-click)."
        )
        return
      end

      arc_mm     = info[:arc_mm]
      panel_h_mm = info[:h_mm]
      hn_h_mm    = info[:h_mm] + OVERHANG_MM * 2
      left_mm    = info[:left_mm]
      right_mm   = info[:right_mm]
      total_mm   = left_mm + arc_mm + right_mm

      puts "==== LeHai HaNen ===="
      puts "Chiều dài cung: #{arc_mm.round(2)} mm"
      puts "Chiều cao tấm: #{panel_h_mm.round(0)} mm | vùng cam: #{hn_h_mm.round(0)} mm"
      puts "Tổng rộng: #{total_mm.round(1)} mm | Dày: #{THICKNESS_MM} mm"
      puts "===================="

      tag = model.layers.to_a.find { |l| l.name == TAG_HN } || model.layers.add(TAG_HN)

      mat_name = model.materials.unique_name('LeHai_HaNen_cam')
      mat      = model.materials.add(mat_name)
      mat.color = Sketchup::Color.new(210, 140, 70)

      bb         = entity.bounds
      ox         = bb.max.x + 10.mm
      oy         = bb.max.y
      oz         = bb.min.z

      arc_i      = arc_mm.mm
      panel_h_i  = panel_h_mm.mm
      left_i     = left_mm.mm
      total_i    = total_mm.mm
      thick_i    = THICKNESS_MM.mm
      overhang_i = OVERHANG_MM.mm

      model.start_operation('LeHai: Tao Tam Uon Cong + Ha Nen', true)
      begin
        outer      = model.active_entities.add_group
        outer.name = 'Tam Uon Cong'
        oe         = outer.entities

        fp = [
          Geom::Point3d.new(ox,           oy, oz),
          Geom::Point3d.new(ox + total_i, oy, oz),
          Geom::Point3d.new(ox + total_i, oy, oz + panel_h_i),
          Geom::Point3d.new(ox,           oy, oz + panel_h_i)
        ]
        panel_face = oe.add_face(fp)
        if panel_face
          panel_face.reverse! if panel_face.normal.y > 0
          panel_face.pushpull(thick_i)
        end

        oy_front = oy - thick_i
        hx0 = ox + left_i
        hx1 = hx0 + arc_i
        hz0 = oz - overhang_i
        hz1 = oz + panel_h_i + overhang_i

        hn_grp       = oe.add_group
        hn_grp.name  = INST_HN
        hn_grp.layer = tag

        hp = [
          Geom::Point3d.new(hx0, oy_front, hz0),
          Geom::Point3d.new(hx1, oy_front, hz0),
          Geom::Point3d.new(hx1, oy_front, hz1),
          Geom::Point3d.new(hx0, oy_front, hz1)
        ]
        hn_face = hn_grp.entities.add_face(hp)
        if hn_face
          hn_face.reverse! if hn_face.normal.y > 0
          hn_face.material      = mat
          hn_face.back_material = mat
        end

        model.commit_operation
        UI.messagebox(
          "✓ Tạo xong!\n\n" \
          "Tấm: #{total_mm.round(0)} × #{panel_h_mm.round(0)} × #{THICKNESS_MM} mm\n" \
          "Vùng hạ nền: #{arc_mm.round(1)} mm rộng × #{hn_h_mm.round(0)} mm cao\n" \
          "(lòi #{OVERHANG_MM.to_i} mm trên + dưới)"
        )
      rescue => e
        model.abort_operation
        UI.messagebox("Lỗi: #{e.message}\n\n#{e.backtrace.first(3).join("\n")}")
      end
    end

    # ── Đo đường cong + kích thước từ group 3D ─────────────────
    def self.measure(entity)
      tr = entity.transformation; curves = []; seen = {}

      scan = lambda do |ents, t|
        ents.each do |e|
          next if e.deleted?
          case e
          when Sketchup::Edge
            c = e.curve
            next unless c; next if seen[c.object_id]
            seen[c.object_id] = true
            len_mm = c.edges.sum { |ed|
              ed.start.position.transform(t).distance(ed.end.position.transform(t)).to_mm
            }
            curves << len_mm
          when Sketchup::Group
            scan.call(e.entities, t * e.transformation)
          when Sketchup::ComponentInstance
            scan.call(e.definition.entities, t * e.transformation)
          end
        end
      end

      ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
      scan.call(ents, tr)
      return nil if curves.empty?

      arc_mm   = curves.max
      bb       = entity.bounds
      h_mm     = bb.depth.to_mm
      radius   = arc_mm / (Math::PI / 2.0)
      left_mm  = [bb.width.to_mm  - radius, 0].max
      right_mm = [bb.height.to_mm - radius, 0].max

      { arc_mm: arc_mm, h_mm: h_mm, left_mm: left_mm, right_mm: right_mm }
    end

    def self.create_cmd
      icons_dir = File.dirname(__FILE__)
      cmd = UI::Command.new('Tạo Hạ Nền Uốn Cong') { LeHaiDecor::HaNen.run }
      cmd.tooltip         = 'Bấm → rê chuột → click vào cục 3D uốn cong'
      cmd.status_bar_text = 'Click vào cục 3D uốn cong để tạo hạ nền'
      cmd.small_icon      = File.join(icons_dir, 'LeHai_HaNen_16.png')
      cmd.large_icon      = File.join(icons_dir, 'LeHai_HaNen_24.png')
      cmd
    end

  end
end
