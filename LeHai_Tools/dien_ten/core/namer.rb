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
      #   ComponentInstance → nhóm theo definition.entityID (chính xác); scale khác nhau thì tách dòng
      #   Group             → nhóm theo kích thước bounding box (thực tế cho furniture)
      # tr_of = hàm trả transform WORLD của tấm (dialog biết cây cha). Soát 01/10 (SOAT_LOI A1): kích thước
      # phải NHÂN hệ số scale — thợ kéo Scale tool thì definition.bounds vẫn là BẢN GỐC, tên ra cỡ gốc và hai tấm
      # khác cỡ cùng bản gốc bị gán CÙNG tên. Tấm không scale: hệ số 1 → khoá + tên y hệt bản cũ.
      def self.build_groups(targets, tr_of = nil)
        groups_map = {}
        targets.each do |e|
          k     = scale_of(tr_of ? tr_of.call(e) : e.transformation)
          key   = group_key(e, k)
          label = groups_map[key] ? groups_map[key][:defName] : group_label(e, k)
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

        # Hệ số scale từng trục = độ dài (tr * trục) — sketchup-api.md "Lấy hệ số scale" (đúng cả khi có xoay).
        def scale_of(tr)
          [X_AXIS, Y_AXIS, Z_AXIS].map { |a| (tr * a).length.to_f }
        rescue StandardError
          [1.0, 1.0, 1.0]   # helper thuần đọc: không đọc được transform → coi như không scale (hành vi cũ)
        end

        def scaled?(k)
          k.any? { |x| (x - 1.0).abs > 1e-6 }
        end

        # Kích thước THẬT của tấm (inch): hộp bản gốc × hệ số scale từng trục.
        def real_dims(entity, k)
          b = entity.definition.bounds
          [b.width * k[0], b.height * k[1], b.depth * k[2]]
        end

        def group_key(entity, k = [1.0, 1.0, 1.0])
          case entity
          when Sketchup::ComponentInstance
            # Cùng definition = cùng key; instance bị scale khác thì kèm cỡ thật để không gộp nhầm
            base = "comp_#{entity.definition.entityID}"
            scaled?(k) ? "#{base}_#{real_dims(entity, k).map { |d| (d * DIM_PRECISION).round }.sort.join('_')}" : base
          when Sketchup::Group
            # Nhóm theo kích thước THẬT (bản gốc × scale)
            dims = real_dims(entity, k)
                   .map { |d| (d * DIM_PRECISION).round }
                   .sort
            "group_#{dims.join('_')}"
          end
        end

        def group_label(entity, k = [1.0, 1.0, 1.0])
          dims = real_dims(entity, k).map { |d| d.to_l }.sort_by { |d| -d.to_f }
          case entity
          when Sketchup::ComponentInstance
            scaled?(k) ? "#{entity.definition.name} (#{dims[0]} x #{dims[1]} x #{dims[2]})" : entity.definition.name
          when Sketchup::Group
            "#{dims[0]} x #{dims[1]} x #{dims[2]}"
          end
        end
      end
    end
  end
end
