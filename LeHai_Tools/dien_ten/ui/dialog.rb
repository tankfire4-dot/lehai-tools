# frozen_string_literal: true

require 'json'

module TuDong
  module DienTen

    # Lắng nghe selection thay đổi bên SketchUp → đồng bộ sang dialog
    class DienTenSelectionObserver < Sketchup::SelectionObserver
      def initialize(dlg, id_to_row)
        @dlg       = dlg
        @id_to_row = id_to_row  # { entityID => group_index }
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
        return if row_index == @last_row   # tránh gọi thừa
        @last_row = row_index
        # execute_script không sửa model → an toàn gọi trong observer
        @dlg.execute_script("highlightRow(#{row_index})")
      end
    end

    module Dialog
      @entity_map = {}
      @groups     = []
      @observer   = nil

      def self.show(targets, parent = nil)
        @entity_map = targets.each_with_object({}) { |e, h| h[e.entityID] = e }
        @groups     = Namer.build_groups(targets)

        # Bảng tra ngược: entityID → index dòng trong bảng
        id_to_row = {}
        @groups.each_with_index do |g, i|
          g[:instances].each { |inst| id_to_row[inst[:id]] = i }
        end

        model = Sketchup.active_model

        # Enter edit context (SU 2021+) để child entity có thể được select/highlight
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

        # Trang load xong → gửi dữ liệu nhóm; gắn SelectionObserver
        dlg.add_action_callback('ready') do |_ctx|
          dlg.execute_script("loadGroups(#{@groups.to_json})")
          # Gắn observer SAU khi dialog đã sẵn sàng nhận execute_script
          @observer = DienTenSelectionObserver.new(dlg, id_to_row)
          model.selection.add_observer(@observer)
        end

        # Dialog → SketchUp: click dòng → chọn (highlight) entity tương ứng
        dlg.add_action_callback('highlight') do |_ctx, def_id|
          group = @groups.find { |g| g[:defId] == def_id }
          next unless group
          ids      = group[:instances].map { |inst| inst[:id] }
          entities = ids.map { |id| @entity_map[id] }.compact.reject(&:deleted?)
          model.selection.clear
          model.selection.add(entities)
        end

        # Sub-row click → highlight single instance in viewport
        dlg.add_action_callback('highlight_instance') do |_ctx, entity_id_str|
          entity = @entity_map[entity_id_str.to_i]
          next unless entity && !entity.deleted?
          model.selection.clear
          model.selection.add(entity)
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

        def cleanup(model)
          # Tháo observer trước khi đóng
          if @observer
            model.selection.remove_observer(@observer)
            @observer = nil
          end
          model.selection.clear
          model.active_path = nil if Sketchup.version.to_f >= 21.0
        end
      end
    end
  end
end
