# frozen_string_literal: true

require 'json'

module TuDong
  module DienTen

    # Lắng nghe selection thay đổi bên SketchUp → đồng bộ sang dialog
    class DienTenSelectionObserver < Sketchup::SelectionObserver
      def initialize(dlg, id_to_row)
        @dlg       = dlg
        @id_to_row = id_to_row
        @last_row  = nil
      end

      def onSelectionBulkChange(selection)
        sync(selection)
      end

      def onSelectedAdded(selection, _entity)
        sync(selection)
      end

      private

      def sync(selection)
        row_index = nil
        selection.each do |e|
          idx = @id_to_row[e.entityID]
          if idx
            row_index = idx
            break
          end
        end
        return if row_index.nil?
        return if row_index == @last_row
        @last_row = row_index
        @dlg.execute_script("highlightRow(#{row_index})")
      end
    end

    module Dialog
      @entity_map         = {}
      @groups             = []
      @observer           = nil
      @pre_isolate_hidden = {}
      @isolated_key       = nil

      def self.show(targets, parent = nil)
        @entity_map = targets.each_with_object({}) { |e, h| h[e.entityID] = e }
        @groups     = Namer.build_groups(targets)

        # Lưu trạng thái hidden gốc để khôi phục chính xác khi đóng dialog
        @pre_isolate_hidden = {}
        @entity_map.each do |id, entity|
          @pre_isolate_hidden[id] = entity.hidden? rescue false
        end
        @isolated_key = nil

        id_to_row = {}
        @groups.each_with_index do |g, i|
          g[:instances].each { |inst| id_to_row[inst[:id]] = i }
        end

        model = Sketchup.active_model

        if parent && Sketchup.version.to_f >= 21.0
          model.active_path = [parent]
        end

        dlg = UI::HtmlDialog.new(
          dialog_title:    'Ho Tro Dien Ten Nhanh',
          preferences_key: 'com.tudong.dien_ten',
          width:           760,
          height:          560,
          min_width:       600,
          min_height:      400,
          resizable:       true
        )
        dlg.set_file(File.join(PATH, 'ui', 'dialog.html'))

        dlg.add_action_callback('ready') do |_ctx|
          dlg.execute_script("loadGroups(#{@groups.to_json})")
          @observer = DienTenSelectionObserver.new(dlg, id_to_row)
          model.selection.add_observer(@observer)
        end

        # Isolate: ẩn mọi entity trong danh sách NGOẠI TRỪ instances của group này.
        # Gọi lại với cùng def_id → toggle: khôi phục tất cả.
        dlg.add_action_callback('isolate') do |_ctx, def_id|
          group = @groups.find { |g| g[:defId] == def_id }
          next unless group

          if @isolated_key == def_id
            restore_visibility
            @isolated_key = nil
            model.selection.clear
          else
            ids_to_show      = group[:instances].map { |inst| inst[:id] }.to_set
            entities_to_show = @entity_map
                                 .select  { |id, _| ids_to_show.include?(id) }
                                 .values
                                 .reject(&:deleted?)
            isolate_entities(entities_to_show)
            @isolated_key = def_id
            model.selection.clear
            model.selection.add(entities_to_show)
          end
        end

        # Isolate đúng 1 instance khi click sub-row.
        # Gọi lại với cùng entity_id → toggle: khôi phục tất cả.
        dlg.add_action_callback('isolate_instance') do |_ctx, entity_id_str|
          entity_id = entity_id_str.to_i
          entity    = @entity_map[entity_id]
          next unless entity && !entity.deleted?

          key = "inst_#{entity_id}"
          if @isolated_key == key
            restore_visibility
            @isolated_key = nil
            model.selection.clear
          else
            isolate_entities([entity])
            @isolated_key = key
            model.selection.clear
            model.selection.add(entity)
          end
        end

        dlg.add_action_callback('apply_names') do |_ctx, json|
          assignments = JSON.parse(json)
          Namer.apply_names(assignments, @entity_map)
          cleanup(model)
          dlg.close
        end

        dlg.add_action_callback('cancel') do |_ctx|
          cleanup(model)
          dlg.close
        end

        dlg.set_on_closed { cleanup(model) }

        dlg.show
      end

      class << self
        private

        # Ẩn tất cả entity trong @entity_map trừ những cái trong show_set
        def isolate_entities(entities_to_show)
          show_set = entities_to_show.map(&:entityID).to_set
          @entity_map.each do |id, entity|
            next if entity.deleted?
            entity.hidden = !show_set.include?(id)
          end
        end

        # Khôi phục trạng thái hidden như trước khi mở dialog
        def restore_visibility
          @entity_map.each do |id, entity|
            next if entity.deleted?
            entity.hidden = @pre_isolate_hidden[id] || false
          end
        end

        def cleanup(model)
          restore_visibility
          if @observer
            model.selection.remove_observer(@observer)
            @observer = nil
          end
          model.selection.clear
          model.active_path = nil if Sketchup.version.to_f >= 21.0
          @isolated_key = nil
        end
      end
    end
  end
end
