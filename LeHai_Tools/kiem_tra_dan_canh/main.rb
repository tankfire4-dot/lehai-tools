# encoding: UTF-8
# Kiểm Tra Dán Cạnh (CẢNH BÁO vàng, mức THÔ — không chặn cứng):
#
# Dấu ABF để lại khi đã dán cạnh: group con "_ABF_edgeBanding" (mỗi cái = 1 cạnh
# đã dán). Dò từ file thật (dan_canh_probe): file ĐÃ dán có N dấu này (403 trong
# file mẫu, nằm bên trong nhánh __ABF_Nesting); file CHƯA dán thì KHÔNG có.
#
# Mức thô theo yêu cầu Khoa: chỉ xét "cả file đã có ai dán cạnh chưa" — vì quy
# tắc cạnh nào phải dán rất phức tạp (đế phải dán dù không lộ...), không suy từ
# hình học được. 0 dấu → cảnh báo; có dấu → coi như đã làm.
#
# Đếm dấu BẤT KỂ nằm đâu (dấu nằm ở bản nesting phẳng, không phải tủ 3D) → check
# ngầm hiểu file đã nesting, đúng bối cảnh "chốt trước khi xuất DXF".
#
# CHỈ ĐỌC. Dashboard (TK::PreExportCheck) gọi qua audit/review.

require 'sketchup.rb'

module TK
  module EdgeBandCheck

    PATH    = File.dirname(__FILE__).freeze
    EDGE_RE = /edgeband/i.freeze   # bắt "_ABF_edgeBanding"

    # Đếm số group/comp mang dấu dán cạnh trong toàn model.
    def self.count
      n = 0
      walk(Sketchup.active_model.entities, 0) { |e| n += 1 if e.name.to_s =~ EDGE_RE }
      n
    end

    def self.walk(entities, depth, &blk)
      return if depth > 40
      entities.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        blk.call(e)
        next if e.name.to_s =~ EDGE_RE   # là dấu dán cạnh → không đi sâu thêm
        sub = e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities
        walk(sub, depth + 1, &blk) if sub
      end
    end

    # ── Adapter cho dashboard ──────────────────────────────────
    def self.audit
      n = count
      if n.zero?
        { status: :warn, count: 0,
          message: 'Chưa thấy cạnh nào được dán — kiểm tra file đã chạy dán cạnh chưa.' }
      else
        { status: :pass, count: n, message: "Đã dán #{n} cạnh." }
      end
    end

    def self.review
      n = count
      if n.zero?
        UI.messagebox("⚠ Cảnh báo (không bắt buộc): chưa thấy cạnh nào được dán trong file.\n\n" \
                      "Kiểm tra xem file này đã chạy DÁN CẠNH chưa (ABF hoặc Auto Dán Cạnh) trước khi xuất DXF.")
      else
        UI.messagebox("✓ File đã dán cạnh.\n\nTìm thấy #{n} cạnh mang dấu \"_ABF_edgeBanding\".")
      end
    end

    def self.run
      review
    end

  end
end
