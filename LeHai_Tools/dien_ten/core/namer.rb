# frozen_string_literal: true

module TuDong
  module DienTen
    module Namer
      MAX_DEPTH      = 8
      DIM_PRECISION  = 100  # làm tròn đến 0.01 inch (~0.25mm) khi so khớp kích thước

      def self.filter_top_level(selection)
        selection.select { |e|
          (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)) &&
            !e.deleted? && !e.locked?
        }
      end

      def self.collect_all_nested(top_level_list)
        results = []
        top_level_list.each { |e| collect_nested(e, results, 0) }
        results.empty? ? top_level_list : results
      end

      # Nhóm các entity theo loại:
      #   ComponentInstance → nhóm theo definition.entityID (chính xác)
      #   Group             → nhóm theo kích thước bounding box (thực tế cho furniture)
      def self.build_groups(targets)
        groups_map = {}
        targets.each do |e|
          key   = group_key(e)
          label = groups_map[key] ? groups_map[key][:defName] : group_label(e)
          groups_map[key] ||= { defId: key, defName: label, instances: [] }
          groups_map[key][:instances] << { id: e.entityID, current: e.name.to_s }
        end
        groups_map.values
      end

      def self.apply_names(assignments, entity_map)
        model = Sketchup.active_model
        model.start_operation('Tu Dong Dien Ten', true)
        begin
          assignments.each do |a|
            entity = entity_map[a['id']]
            next if entity.nil? || entity.deleted?
            entity.name = a['name']
          end
          model.commit_operation
        rescue => e
          model.abort_operation
          raise e
        end
      end

      class << self
        private

        def collect_nested(entity, results, depth)
          return if depth > MAX_DEPTH
          child_entities = case entity
                           when Sketchup::ComponentInstance then entity.definition.entities
                           when Sketchup::Group             then entity.entities
                           end
          return unless child_entities

          child_entities.each do |e|
            next if e.deleted?
            next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            results << e unless e.locked?
            collect_nested(e, results, depth + 1)
          end
        end

        def group_key(entity)
          case entity
          when Sketchup::ComponentInstance
            # Chính xác: các instance cùng definition có cùng key
            "comp_#{entity.definition.entityID}"
          when Sketchup::Group
            # Nhóm theo kích thước local (trong hệ toạ độ của group)
            b    = entity.definition.bounds
            dims = [b.width, b.height, b.depth]
                   .map { |d| (d * DIM_PRECISION).round }
                   .sort
            "group_#{dims.join('_')}"
          end
        end

        def group_label(entity)
          case entity
          when Sketchup::ComponentInstance
            entity.definition.name
          when Sketchup::Group
            b    = entity.definition.bounds
            dims = [b.width, b.height, b.depth]
                   .map { |d| d.to_l }
                   .sort_by { |d| -d.to_f }
            "#{dims[0]} x #{dims[1]} x #{dims[2]}"
          end
        end
      end
    end
  end
end
