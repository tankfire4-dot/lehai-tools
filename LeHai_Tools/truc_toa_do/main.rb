# encoding: UTF-8
# Trục Tọa Độ — 1 icon mở bảng nhỏ, gồm:
#   • Reset về Global : đưa trục group/component thẳng theo global + dời GỐC trục
#                       về góc thấp nhất của hình (sửa Position lệch âm kiểu -2.5cm).
#   • Xoay X / Y / Z  : xoay vật thể 90° quanh trục X/Y/Z (quanh gốc đối tượng).
# Kết quả báo ngay trong bảng (không popup). Mọi thao tác undo được.
# (Bản gộp vào LeHai_Tools — chỉ expose create_cmd, không tự đăng ký toolbar/menu.)

require 'sketchup.rb'

module TK
  module AxisFix

    PATH      = File.dirname(__FILE__).freeze
    CLEAN_TOL = 0.001   # inch: nhỏ hơn mức này coi như 0 (khử "-0" do sai số)

    ROT = {
      'x' => Geom::Vector3d.new(1.0, 0.0, 0.0),
      'y' => Geom::Vector3d.new(0.0, 1.0, 0.0),
      'z' => Geom::Vector3d.new(0.0, 0.0, 1.0)
    }.freeze
    QUARTER = Math::PI / 2.0   # 90°

    # ── Bảng điều khiển ────────────────────────────────────────
    def self.show
      if @dlg&.visible?
        @dlg.bring_to_front
        return
      end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Trục Tọa Độ',
        preferences_key: 'tk.tructoado',
        width:           240, height: 250,
        min_width:       220, min_height: 230,
        resizable:       false,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @dlg.set_html(html)
      @dlg.add_action_callback('reset')  { reset_axes }
      @dlg.add_action_callback('rotate') { |_c, axis| rotate(axis) }
      @dlg.show
    end

    def self.status(msg)
      @dlg&.execute_script("setStatus(#{msg.to_json});")
    end
    private_class_method :status

    # ── Reset trục về global + gốc về góc tấm ──────────────────
    def self.reset_axes
      targets = picked
      return unless targets

      dcs   = targets.select { |e| dynamic?(e) }
      plain = targets - dcs

      # Toàn bộ là DC còn sống → Reset không ăn (engine DC kéo trục về chỗ cũ).
      if plain.empty?
        status("⚠ #{dcs.size} đối tượng là Dynamic Component — Reset KHÔNG ăn " \
               "trên DC. Hãy bấm \"Dọn Component → Biến component→group\" để gỡ DC " \
               "trước, rồi Reset lại.")
        return
      end

      model = Sketchup.active_model
      n = 0
      model.start_operation('Reset truc ve global', true)
      begin
        plain.each { |e| n += 1 if reset_one(e) }
        model.commit_operation
      rescue => err
        model.abort_operation
        status("Lỗi: #{err.message}")
        return
      end

      msg = "✓ Đã reset trục #{n} đối tượng về global (gốc về góc hình)."
      msg += " ⚠ Bỏ qua #{dcs.size} DC — gỡ DC trước rồi reset." unless dcs.empty?
      status(msg)
    end
    private_class_method :reset_axes

    # DC còn sống = có dictionary 'dynamic_attributes'
    def self.dynamic?(entity)
      !entity.attribute_dictionary('dynamic_attributes').nil?
    rescue StandardError
      false
    end
    private_class_method :dynamic?

    def self.reset_one(entity)
      entity.make_unique
      t  = entity.transformation
      o  = clean_point(entity.definition.bounds.min.transform(t))  # góc hình (đã khử -0)
      t2 = Geom::Transformation.new(o)                    # tịnh tiến thuần, trục = global
      ents = entity.definition.entities
      ents.transform_entities(t2.inverse * t, ents.to_a)  # giữ hình đứng yên
      entity.transformation = t2
      true
    rescue StandardError
      false
    end
    private_class_method :reset_one

    # Ép các thành phần gần 0 về 0 chẵn (tránh hiển thị "-0 cm")
    def self.clean_point(p)
      Geom::Point3d.new(*p.to_a.map { |v| v.abs < CLEAN_TOL ? 0.0 : v })
    end
    private_class_method :clean_point

    # ── Xoay vật thể 90° quanh X / Y / Z ───────────────────────
    def self.rotate(axis)
      vec = ROT[axis.to_s]
      return status('Trục không hợp lệ.') unless vec

      targets = picked
      return unless targets

      model = Sketchup.active_model
      n = 0
      model.start_operation("Xoay #{axis}", true)
      begin
        targets.each { |e| rotate_one(e, vec); n += 1 }
        model.commit_operation
      rescue => err
        model.abort_operation
        status("Lỗi xoay: #{err.message}")
        return
      end
      status("✓ Đã xoay #{n} đối tượng 90° quanh trục #{axis.to_s.upcase}.")
    end
    private_class_method :rotate

    def self.rotate_one(entity, axis_vec)
      t = entity.transformation
      r = Geom::Transformation.rotation(t.origin, axis_vec, QUARTER)
      entity.transformation = r * t
    end
    private_class_method :rotate_one

    # ── Helper ─────────────────────────────────────────────────
    def self.picked
      sel = Sketchup.active_model.selection.reject(&:locked?).select do |e|
        e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      end
      if sel.empty?
        status('Hãy chọn group/component rồi bấm lại.')
        return nil
      end
      sel
    end
    private_class_method :picked

    # ── HTML ───────────────────────────────────────────────────
    def self.html
      theme_css = File.join(PATH, '..', 'shared', 'lehai_theme.css')
      theme = File.exist?(theme_css) ? File.read(theme_css, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          body{margin:0;padding:14px}
          h3{margin:0 0 10px;font-size:14px;color:var(--lh-walnut)}
          .reset{width:100%;padding:11px;border:0;border-radius:var(--lh-radius);margin-bottom:12px;
                 background:var(--lh-walnut);color:#fff;font-size:13px;font-weight:700;cursor:pointer;font-family:inherit}
          .reset:hover{filter:brightness(1.1)}
          .lbl{font-size:11px;color:var(--lh-muted);margin-bottom:5px}
          .row{display:flex;gap:8px}
          /* X/Y/Z giữ màu trục chuẩn SketchUp — ngữ nghĩa, không đổi theo theme */
          .ax{flex:1;padding:14px 0;border:0;border-radius:var(--lh-radius-sm);color:#fff;
              font-size:16px;font-weight:700;cursor:pointer;font-family:inherit}
          .x{background:#d0394a}.x:hover{filter:brightness(1.08)}
          .y{background:#3a9d4f}.y:hover{filter:brightness(1.08)}
          .z{background:#2f6fd0}.z:hover{filter:brightness(1.08)}
          #status{margin-top:13px;font-size:12px;color:#15803d;min-height:30px;line-height:1.4}
        </style></head><body class="lh">
        <div class="lh-eyebrow">LeHai Decor Tools</div>
        <h3>Trục Tọa Độ</h3>
        <button class="reset" onclick="sketchup.reset()">Reset trục về Global</button>
        <div class="lbl">Xoay vật thể 90° quanh trục</div>
        <div class="row">
          <button class="ax x" onclick="rot('x')">X</button>
          <button class="ax y" onclick="rot('y')">Y</button>
          <button class="ax z" onclick="rot('z')">Z</button>
        </div>
        <div id="status"></div>
        <script>
          function setStatus(m){ document.getElementById('status').textContent=m; }
          function rot(a){ sketchup.rotate(a); }
        </script></body></html>
      HTML
    end
    private_class_method :html

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Trục Tọa Độ') { TK::AxisFix.show }
      cmd.tooltip         = 'Trục Tọa Độ: reset trục về global / xoay vật thể 90° quanh X·Y·Z'
      cmd.status_bar_text = 'Mở bảng: reset trục + xoay 90° quanh X/Y/Z. Chọn group/component trước.'
      cmd.small_icon      = File.join(icons, 'reset_16.png')
      cmd.large_icon      = File.join(icons, 'reset_24.png')
      cmd
    end

  end
end
