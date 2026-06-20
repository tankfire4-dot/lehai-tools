# encoding: UTF-8
# Gỡ DC / Dọn Component — bấm icon hiện bảng chọn, tích thao tác cần làm:
#   - Biến component → group (nổ DC/component thành group lồng nhau, an toàn)
#   - Xóa màu (material front + back)
#   - Xóa tag
#   - Xóa thuộc tính (attribute dictionaries, gồm dữ liệu ABF)
#   - Xóa object ABF (nhãn _ABF_Label, rãnh phay _ABF_Intersect... tag ABF_*)
# Áp dụng trên các đối tượng đang chọn (ABF quét toàn model).

require 'sketchup.rb'
require 'json'

module TK
  module GoGroup

    PATH      = File.dirname(__FILE__).freeze
    MAX_DEPTH = 12

    ABF_NAME_PREFIX = '_ABF'.freeze
    ABF_TAG_PREFIX  = 'ABF_'.freeze

    OPTS = %w[convert makecomp color tag attr abf].freeze

    # ── Dialog ─────────────────────────────────────────────────
    def self.show
      if @dlg&.visible?
        @dlg.bring_to_front
        return
      end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Dọn Component',
        preferences_key: 'tk.gogroup',
        width:           320, height: 380,
        min_width:       280, min_height: 320,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @dlg.set_html(html)
      @dlg.add_action_callback('run') { |_c, json| run(JSON.parse(json)) }
      @dlg.show
    end

    def self.status(msg)
      @dlg&.execute_script("setStatus(#{msg.to_json});")
    end
    private_class_method :status

    # ── Thực thi ───────────────────────────────────────────────
    def self.run(opts)
      unless OPTS.any? { |k| opts[k] }
        status('Chưa tích thao tác nào.')
        return
      end

      model   = Sketchup.active_model
      targets = model.selection.reject(&:locked?).select do |e|
        e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      end
      if targets.empty?
        status('Chưa chọn component/group nào trong model.')
        return
      end

      model.start_operation('Don component', true)
      begin
        @count      = 0
        @comp_count = 0
        roots = targets

        if opts['convert']
          roots = targets.map { |e| convert_entity(e, root_entities(model, e), 0) }.compact
        end

        if opts['makecomp']
          roots = roots.map do |e|
            next nil if e.deleted?
            if e.is_a?(Sketchup::Group)
              @comp_count += 1
              group_to_component(e)
            else
              e
            end
          end.compact
        end

        abf = opts['abf'] ? purge_abf_objects(model.entities, 0) : 0

        if opts['color'] || opts['tag'] || opts['attr']
          flags = { color: opts['color'], tag: opts['tag'], attr: opts['attr'] }
          roots.each { |r| clean(r, 0, flags) if r && !r.deleted? }
        end
        model.commit_operation
      rescue => err
        model.abort_operation
        status("Lỗi: #{err.message}")
        return
      end

      status(summary(opts, @count, @comp_count, abf))
    end
    private_class_method :run

    def self.summary(opts, conv, comp, abf)
      parts = []
      parts << "biến #{conv} component→group" if opts['convert']
      parts << "biến #{comp} group→component" if opts['makecomp']
      parts << "xóa #{abf} object ABF"        if opts['abf']
      done = []
      done << 'màu'        if opts['color']
      done << 'tag'        if opts['tag']
      done << 'thuộc tính' if opts['attr']
      parts << "xóa #{done.join(' + ')}" unless done.empty?
      "✓ Xong: #{parts.join(' · ')}."
    end
    private_class_method :summary

    # ── Component → group ──────────────────────────────────────
    def self.root_entities(model, entity)
      parent = entity.parent
      parent.is_a?(Sketchup::Model) ? model.active_entities : parent.entities
    end
    private_class_method :root_entities

    def self.convert_entity(entity, parent_entities, depth)
      return nil if depth > MAX_DEPTH || entity.deleted?
      if entity.is_a?(Sketchup::ComponentInstance)
        group = instance_to_group(entity, parent_entities)
        @count += 1
        convert_children(group, depth)
        group
      elsif entity.is_a?(Sketchup::Group)
        convert_children(entity, depth)
        entity
      end
    end
    private_class_method :convert_entity

    def self.instance_to_group(instance, parent_entities)
      defn  = instance.definition
      trans = instance.transformation
      name  = instance.name.to_s
      name  = defn.name.to_s if name.empty?
      layer = instance.layer

      group = parent_entities.add_group
      group.name  = name unless name.empty?
      group.layer = layer if layer

      copy = group.entities.add_instance(defn, trans)
      instance.erase!
      copy.explode
      group
    end
    private_class_method :instance_to_group

    # ── Group → component ──────────────────────────────────────
    def self.group_to_component(group)
      name     = group.name.to_s
      instance = group.to_component
      unless name.empty?
        instance.name = name
        instance.definition.name = name rescue nil
      end
      instance
    rescue StandardError
      nil
    end
    private_class_method :group_to_component

    def self.convert_children(group, depth)
      group.entities.to_a.each do |child|
        next unless child.is_a?(Sketchup::ComponentInstance) ||
                    child.is_a?(Sketchup::Group)
        convert_entity(child, group.entities, depth + 1)
      end
    end
    private_class_method :convert_children

    # ── Làm sạch (màu / tag / thuộc tính) ──────────────────────
    def self.clean(entity, depth, f)
      return if depth > MAX_DEPTH || entity.deleted?
      apply_flags(entity, f)
      ents = ents_of(entity)
      return unless ents
      ents.to_a.each do |e|
        next if e.deleted?
        if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          clean(e, depth + 1, f)
        else
          apply_flags(e, f)
        end
      end
    end
    private_class_method :clean

    def self.apply_flags(e, f)
      strip_material(e)   if f[:color]
      strip_attributes(e) if f[:attr]
      strip_tag(e)        if f[:tag]
    end
    private_class_method :apply_flags

    def self.strip_material(entity)
      entity.material      = nil if entity.respond_to?(:material=)
      entity.back_material = nil if entity.respond_to?(:back_material=)
    rescue StandardError
      nil
    end
    private_class_method :strip_material

    def self.strip_tag(entity)
      entity.layer = nil if entity.respond_to?(:layer=)
    rescue StandardError
      nil
    end
    private_class_method :strip_tag

    def self.strip_attributes(entity)
      dicts = entity.attribute_dictionaries
      return unless dicts
      dicts.map(&:name).each { |n| entity.delete_attribute(n) }
    rescue StandardError
      nil
    end
    private_class_method :strip_attributes

    # ── Quét toàn model xóa object ABF ─────────────────────────
    def self.purge_abf_objects(entities, depth)
      return 0 if depth > MAX_DEPTH
      removed = 0
      entities.to_a.each do |e|
        next if e.deleted?
        if abf_object?(e)
          e.erase!
          removed += 1
          next
        end
        if e.is_a?(Sketchup::Group)
          removed += purge_abf_objects(e.entities, depth + 1)
        elsif e.is_a?(Sketchup::ComponentInstance)
          removed += purge_abf_objects(e.definition.entities, depth + 1)
        end
      end
      removed
    end
    private_class_method :purge_abf_objects

    def self.abf_object?(entity)
      return false unless entity.is_a?(Sketchup::Group) ||
                          entity.is_a?(Sketchup::ComponentInstance)
      return true if entity.name.to_s.start_with?(ABF_NAME_PREFIX)
      tag = entity.layer
      tag && tag.name.to_s.start_with?(ABF_TAG_PREFIX)
    rescue StandardError
      false
    end
    private_class_method :abf_object?

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end
    private_class_method :ents_of

    # ── HTML ───────────────────────────────────────────────────
    def self.html
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:14px;background:#fafafa;color:#222}
          h3{margin:0 0 4px;font-size:15px}
          .sub{font-size:11px;color:#999;margin-bottom:12px}
          label{display:flex;align-items:center;gap:9px;padding:9px 10px;margin-bottom:6px;
                 background:#fff;border:1px solid #e3e3e3;border-radius:7px;cursor:pointer;font-size:13px}
          label:hover{border-color:#2962a8;background:#f3f8ff}
          input{width:16px;height:16px;cursor:pointer}
          .run{width:100%;margin-top:8px;padding:11px;border:0;border-radius:7px;
               background:#2962a8;color:#fff;font-size:13px;font-weight:600;cursor:pointer}
          .run:hover{background:#1f5294}
          #status{margin-top:11px;font-size:12px;color:#2a845c;min-height:16px;line-height:1.4}
        </style></head><body>
        <h3>Dọn Component</h3>
        <div class="sub">Tích thao tác cần làm trên đối tượng đang chọn.</div>
        <label><input type="checkbox" id="convert"> Biến component → group</label>
        <label><input type="checkbox" id="makecomp"> Biến group → component</label>
        <label><input type="checkbox" id="color"> Xóa màu</label>
        <label><input type="checkbox" id="tag"> Xóa tag</label>
        <label><input type="checkbox" id="attr"> Xóa thuộc tính</label>
        <label><input type="checkbox" id="abf"> Xóa object ABF (nhãn, rãnh phay)</label>
        <button class="run" onclick="runIt()">Thực hiện</button>
        <div id="status"></div>
        <script>
          var KEYS=['convert','makecomp','color','tag','attr','abf'];
          function setStatus(m){ document.getElementById('status').textContent=m; }
          function runIt(){
            var o={}; KEYS.forEach(function(k){ o[k]=document.getElementById(k).checked; });
            setStatus('Đang xử lý...');
            sketchup.run(JSON.stringify(o));
          }
        </script></body></html>
      HTML
    end
    private_class_method :html

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons_path = File.join(PATH, 'icons')
      cmd = UI::Command.new('Dọn Component') { TK::GoGroup.show }
      cmd.tooltip         = 'Dọn component: chọn thao tác (group hóa / xóa màu / tag / thuộc tính / ABF)'
      cmd.status_bar_text = 'Mở bảng chọn: biến component→group, xóa màu/tag/thuộc tính/object ABF tùy ý.'
      cmd.small_icon      = File.join(icons_path, 'go_group_16.png')
      cmd.large_icon      = File.join(icons_path, 'go_group_24.png')
      cmd
    end

  end
end
