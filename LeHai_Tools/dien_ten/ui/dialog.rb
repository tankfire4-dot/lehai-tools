# frozen_string_literal: true

require 'json'
require File.join(File.dirname(__FILE__), '..', '..', 'shared', 'soi_noi')

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

    # Vẽ các tấm đang chọn kiểu SOI NỔI (shared/soi_noi.rb) — Khoa 01/10: Điền Tên còn viền hồng cũ, chưa theo
    # kiểu đã chốt 30/09. Mờ phần còn lại của model + tấm thành khối sáng nhẹ (xanh = tấm tìm thấy); phần bị tấm
    # khác che: trong suốt + nét đứt nhạt. Chỉ vẽ (draw2d), không đổi model. Chạy nền khi bảng đặt tên mở.
    class HiliteTool
      def initialize
        @boxes = []   # mỗi tấm = 24 điểm world (12 cạnh hộp, nối cặp GL_LINES)
      end

      def set(boxes)
        @boxes = boxes || []
        invalidate
      end

      def clear
        @boxes = []
        invalidate
      end

      def activate; end
      def resume(view);     view.invalidate end
      def deactivate(view); view.invalidate end

      def draw(view)
        return if @boxes.empty?
        LeHai::SoiNoi.phu_mo(view)
        hop, le = @boxes.partition { |pts| LeHai::SoiNoi.khoi_tu_net(pts) }
        LeHai::SoiNoi.ve_nets(view, hop.map { |pts| [pts, :xanh] })
        le.each do |pts|   # tấm không dựng được hộp (dẹt lạ) → chỉ vẽ nét
          LeHai::SoiNoi.but(view, Sketchup::Color.new(*LeHai::SoiNoi::VIEN[:xanh]), 2)
          LeHai::SoiNoi.net2d(view, pts)
        end
      end

      private

      def invalidate
        v = Sketchup.active_model.active_view
        v.invalidate if v
      end
    end

    module Dialog
      @entity_map = {}
      @groups     = []
      @observer   = nil
      @parent     = nil   # module lớn được chọn; dùng để vào nested edit context
      @hilite     = nil   # công cụ vẽ khung tấm đang chọn (overlay)

      SUG_STORE = 'TK_DienTen_Sug'  # nơi nhớ giá trị đã dùng (theo máy)
      SUG_KEYS  = %w[room mod base].freeze

      # Danh sách mồi sẵn (chuẩn xưởng — Khoa cung cấp 2026-07-04).
      # KHÔNG dùng %w vì có giá trị chứa dấu cách ("WC Master", "Tủ TV"...).
      DEFAULT_SUG = {
        'room' => ['PK', 'Master', 'PN1', 'PN2', 'WC Master', 'WC1', 'WC2',
                   'WC Chung', 'Bếp', 'Logia'],
        'mod'  => ['Tủ TV', 'Tủ Áo', 'Bếp Trên', 'Bếp Dưới', 'Tủ Lạnh', 'Đảo Bếp',
                   'Giường', 'Bàn Học', 'Bàn Làm Việc', 'Kệ Trang Trí', 'Tủ Trang Trí',
                   'Khung Bao Giặt Sấy', 'Tủ Giày', 'Bàn Ăn', 'Bàn Trà', 'Tủ Tab'],
        'base' => ['hông', 'đáy', 'nóc', 'hậu', 'bạ', 'đợt', 'kệ', 'xương',
                   'cánh', 'vách', 'vạt']
      }.freeze

      # đọc gợi ý → (đã lưu theo máy khi bấm Áp dụng) + (danh sách chuẩn mồi sẵn)
      def self.suggestions
        out = {}
        SUG_KEYS.each do |k|
          raw   = Sketchup.read_default(SUG_STORE, k, nil)
          saved = raw ? (JSON.parse(raw) rescue []) : []
          out[k] = (saved + (DEFAULT_SUG[k] || [])).uniq
        end
        out
      end

      # lưu giá trị vừa nhập từ dialog
      def self.save_suggestions(json)
        data = JSON.parse(json) rescue {}
        add_sug('room', data['room'])
        add_sug('mod',  data['mod'])
        (data['bases'] || []).each { |b| add_sug('base', b) }
      end

      def self.add_sug(key, value)
        v = value.to_s.strip
        return if v.empty?
        list = (JSON.parse(Sketchup.read_default(SUG_STORE, key, '[]')) rescue [])
        return if list.include?(v)
        list << v
        list = list.last(50)  # giữ 50 giá trị gần nhất
        Sketchup.write_default(SUG_STORE, key, list.to_json)
      end

      def self.show(targets, parent = nil)
        @entity_map = targets.each_with_object({}) { |e, h| h[e.entityID] = e }
        @groups     = Namer.build_groups(targets)
        @parent     = parent

        id_to_row = {}
        @groups.each_with_index do |g, i|
          g[:instances].each { |inst| id_to_row[inst[:id]] = i }
        end

        model = Sketchup.active_model
        model.selection.clear   # bỏ viền xanh chọn sẵn — chỉ để lại lớp soi nổi của bộ vẽ

        dlg = UI::HtmlDialog.new(
          dialog_title:    'Ho Tro Dien Ten Nhanh',
          preferences_key: 'com.tudong.dien_ten',
          width:           760,
          height:          560,
          min_width:       600,
          min_height:      400,
          resizable:       true
        )
        # Đọc HTML NẰM CẠNH file này (không theo PATH) — để khi load bản dev qua
        # Ruby Console, HTML cũng lấy từ repo chứ không dính bản cài ở %AppData%.
        dlg.set_file(File.join(File.dirname(__FILE__), 'dialog.html'))

        dlg.add_action_callback('ready') do |_ctx|
          dlg.execute_script("loadGroups(#{@groups.to_json})")
          dlg.execute_script("setSuggestions(#{suggestions.to_json})")
          @observer = DienTenSelectionObserver.new(dlg, id_to_row)
          model.selection.add_observer(@observer)
          @hilite = HiliteTool.new           # bật bộ vẽ khung tấm (overlay)
          model.select_tool(@hilite)
        end

        # Nhớ giá trị vừa nhập (phòng / module / tên đặt) cho lần sau
        dlg.add_action_callback('save_suggestions') do |_ctx, json|
          save_suggestions(json)
        end

        # Click dòng cha → soi nổi TẤT CẢ tấm cùng loại + zoom tới.
        dlg.add_action_callback('highlight') do |_ctx, def_id|
          group = @groups.find { |g| g[:defId] == def_id }
          next unless group
          ents = group[:instances].map { |inst| @entity_map[inst[:id]] }
                                  .compact.reject(&:deleted?)
          hilite(ents)
        end

        # Click sub-row → vẽ khung đúng 1 tấm đó.
        dlg.add_action_callback('highlight_instance') do |_ctx, entity_id_str|
          entity = @entity_map[entity_id_str.to_i]
          next unless entity && !entity.deleted?
          hilite([entity])
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

      # Soi nổi các tấm (overlay) + zoom tới chúng.
      def self.hilite(ents)
        return if ents.empty? || @hilite.nil?
        Sketchup.active_model.selection.clear   # không lẫn viền xanh
        boxes = []
        bb    = Geom::BoundingBox.new
        ents.each do |e|
          segs = plank_box_segs(e)
          next if segs.empty?
          boxes << segs.flat_map { |a, b| [a, b] }
          segs.each { |a, b| bb.add(a); bb.add(b) }
        end
        @hilite.set(boxes)
        Sketchup.active_model.active_view.zoom(bb) unless bb.empty?
      end

      # 12 cạnh của hộp bao TẤM ở toạ độ WORLD.
      def self.plank_box_segs(entity)
        wtr = world_tr_of(entity)
        return [] unless wtr
        lb = entity.definition.bounds
        c  = (0..7).map { |i| wtr * lb.corner(i) }
        [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4],
         [0, 4], [1, 5], [2, 6], [3, 7]].map { |a, b| [c[a], c[b]] }
      rescue StandardError
        []   # tấm lạ (không có definition/bounds) → bỏ qua, không chặn
      end

      # Transform WORLD của tấm nằm sâu trong @parent (tích luỹ transformation
      # các cấp cha). Nếu không có parent → tấm là top-level, dùng luôn của nó.
      def self.world_tr_of(entity)
        if @parent && !@parent.deleted?
          r = find_wtr(@parent, @parent.transformation, entity.entityID)
          return r if r
        end
        entity.transformation
      end

      def self.find_wtr(container, tr, target_id)
        ents = container.is_a?(Sketchup::ComponentInstance) ? container.definition.entities : container.entities
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          wt = tr * e.transformation
          return wt if e.entityID == target_id
          r = find_wtr(e, wt, target_id)
          return r if r
        end
        nil
      end

      class << self
        private

        def cleanup(model)
          if @observer
            model.selection.remove_observer(@observer)
            @observer = nil
          end
          if @hilite
            model.select_tool(nil)   # trả về công cụ Chọn mặc định
            @hilite = nil
          end
          model.selection.clear
          model.active_path = nil if Sketchup.version.to_f >= 21.0
          @parent = nil
        end
      end
    end
  end
end
