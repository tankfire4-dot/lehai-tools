# encoding: UTF-8
# Gỡ DC → Group: biến Component / Dynamic Component thành group lồng nhau,
# giữ nguyên cấu trúc từng tấm, rồi LÀM SẠCH:
#   - xóa màu/material (front + back)
#   - xóa toàn bộ attribute dictionaries (gồm dữ liệu ABF)
#   - quét toàn model xóa hết nhãn ABF (group tag 'ABF_Label' / tên '_ABF_Label')
# Chỉ chừa lại group thuần + tên (+ tag tấm). Dùng trước khi gắn nhãn ABF lại.
#
# Cách biến component→group AN TOÀN (tránh bugsplat): với mỗi component
#   1. tạo group rỗng trong parent
#   2. đặt 1 bản sao instance vào group rồi nổ bản sao đó BÊN TRONG group
#   3. xóa instance gốc
# Không dùng add_group(geometry-vừa-nổ) — đường API đó hay gây crash.

require 'sketchup.rb'

module TK
  module GoGroup

    PATH      = File.dirname(__FILE__).freeze
    MAX_DEPTH = 12

    # ABF đặt tên mọi object phụ (nhãn, phay rãnh, giao cắt...) theo quy luật:
    #   instance name bắt đầu '_ABF'  /  tag bắt đầu 'ABF_'
    ABF_NAME_PREFIX = '_ABF'.freeze
    ABF_TAG_PREFIX  = 'ABF_'.freeze

    # ── Entry point ────────────────────────────────────────────
    def self.run
      model = Sketchup.active_model
      targets = model.selection.reject(&:locked?).select do |e|
        e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      end

      if targets.empty?
        UI.messagebox(
          "Chưa chọn gì.\n\n" \
          "Hãy chọn component (hộc kéo, tủ...) cần biến thành group, " \
          "rồi bấm lại nút này."
        )
        return
      end

      result = convert_selection(model, targets)
      return if result.nil?

      comps, abf = result
      UI.messagebox(
        "✓ Xong.\n\n" \
        "Đã biến #{comps} component thành group, xóa #{abf} object ABF " \
        "(nhãn + phay rãnh + giao cắt...), và làm sạch màu + thuộc tính.\n\n" \
        "Trong model giờ chỉ còn group thuần lồng nhau, từng tấm là 1 group riêng " \
        "(giữ lại tên + tag)."
      )
    end

    # ── Logic ──────────────────────────────────────────────────
    def self.convert_selection(model, targets)
      @count = 0
      model.start_operation('Bien component thanh group + lam sach', true)
      begin
        targets.each do |e|
          result = convert_entity(e, root_entities(model, e), 0)
          clean(result, 0) if result.is_a?(Sketchup::Group)
        end
        abf = purge_abf_objects(model.entities, 0)
        model.commit_operation
        [@count, abf]
      rescue => err
        model.abort_operation
        UI.messagebox("Lỗi: #{err.message}\n\n#{err.backtrace.first(3).join("\n")}")
        nil
      end
    end
    private_class_method :convert_selection

    def self.root_entities(model, entity)
      parent = entity.parent
      parent.is_a?(Sketchup::Model) ? model.active_entities : parent.entities
    end
    private_class_method :root_entities

    # Component → group (đệ quy). Group thì giữ nguyên, chỉ xử lý con.
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

    # Tạo group rỗng → bỏ bản sao instance vào → nổ bản sao trong group → xóa gốc.
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

    # Duyệt các con trong group; con nào là component thì biến thành group.
    def self.convert_children(group, depth)
      group.entities.to_a.each do |child|
        next unless child.is_a?(Sketchup::ComponentInstance) ||
                    child.is_a?(Sketchup::Group)
        convert_entity(child, group.entities, depth + 1)
      end
    end
    private_class_method :convert_children

    # ── Làm sạch: xóa màu + mọi thuộc tính, giữ tên + tag + geometry ──
    def self.clean(entity, depth)
      return if depth > MAX_DEPTH || entity.deleted?

      strip_material(entity)
      strip_attributes(entity)

      return unless entity.respond_to?(:entities)
      entity.entities.to_a.each do |e|
        next if e.deleted?
        if e.is_a?(Sketchup::Group)
          clean(e, depth + 1)
        else
          strip_material(e)
          strip_attributes(e)
        end
      end
    end
    private_class_method :clean

    def self.strip_material(entity)
      entity.material      = nil if entity.respond_to?(:material=)
      entity.back_material = nil if entity.respond_to?(:back_material=)
    rescue StandardError
      nil
    end
    private_class_method :strip_material

    def self.strip_attributes(entity)
      dicts = entity.attribute_dictionaries
      return unless dicts
      dicts.map(&:name).each { |n| entity.delete_attribute(n) }
    rescue StandardError
      nil
    end
    private_class_method :strip_attributes

    # ── Quét toàn model xóa hết object ABF (nhãn, phay rãnh, giao cắt...) ──
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

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons_path = File.join(PATH, 'icons')
      cmd = UI::Command.new('Gỡ DC → Group') { TK::GoGroup.run }
      cmd.tooltip         = 'Biến Component/DC thành group thuần (xóa màu + thuộc tính + nhãn ABF)'
      cmd.status_bar_text = 'Chọn component → bấm: nổ thành group lồng nhau, xóa màu + ' \
                            'thuộc tính + nhãn ABF, giữ tên + tag.'
      cmd.small_icon      = File.join(icons_path, 'go_group_16.png')
      cmd.large_icon      = File.join(icons_path, 'go_group_24.png')
      cmd
    end

  end
end
