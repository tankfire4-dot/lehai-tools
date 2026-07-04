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

    PATH     = File.dirname(__FILE__).freeze
    EDGE_RE  = /edgeband/i.freeze          # dấu ABF: group "_ABF_edgeBanding"
    AUTO_RE  = /\AHung_Show_ABF_/.freeze    # dấu Auto Dán Cạnh: material tô lên mặt

    # Đếm số group/comp mang dấu dán cạnh CỦA ABF trong toàn model.
    def self.count
      n = 0
      walk(Sketchup.active_model.entities, 0) { |e| n += 1 if e.name.to_s =~ EDGE_RE }
      n
    end

    # Auto Dán Cạnh (MyStudio::AutoEdgeBand) KHÔNG tạo group — nó tô material
    # "Hung_Show_ABF_..." lên mặt cạnh dán. Chỉ cần material đó có trong file là
    # dấu hiệu đã có dùng dán cạnh (mức thô — không đếm chính xác từng cạnh).
    def self.auto_banded?
      Sketchup.active_model.materials.any? { |m| m.name.to_s =~ AUTO_RE }
    rescue StandardError
      false
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
      return { status: :pass, count: n, message: "Đã dán #{n} cạnh (ABF)." } if n.positive?
      return { status: :pass, count: 0, message: 'Đã dán cạnh (Auto Dán Cạnh).' } if auto_banded?
      { status: :warn, count: 0,
        message: 'Chưa thấy cạnh nào được dán — kiểm tra file đã chạy dán cạnh chưa.' }
    end

    def self.review
      n = count
      if n.positive?
        UI.messagebox("✓ File đã dán cạnh (ABF).\n\nTìm thấy #{n} cạnh mang dấu \"_ABF_edgeBanding\".")
      elsif auto_banded?
        UI.messagebox("✓ File đã dán cạnh (Auto Dán Cạnh_LeHai).\n\n" \
                      "Có dấu material \"Hung_Show_ABF_...\" — cạnh đã được tô dán.")
      else
        UI.messagebox("⚠ Cảnh báo (không bắt buộc): chưa thấy cạnh nào được dán trong file.\n\n" \
                      "Kiểm tra xem file này đã chạy DÁN CẠNH chưa (ABF hoặc Auto Dán Cạnh) trước khi xuất DXF.")
      end
    end

    def self.run
      review
    end

  end
end
