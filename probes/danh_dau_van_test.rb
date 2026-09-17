# encoding: UTF-8
# =============================================================================
#  TEST GIẢ THUYẾT: ABF không gán nhãn tấm trái vì vỏ tấm THIẾU ABF/is-board.
#  Script này ĐÓNG DẤU is-board lên (các) tấm đang chọn, rồi bảo Khoa chạy lại
#  nesting/gán nhãn của ABF xem có ăn không.  SỬA MODEL nhưng bọc undo — Ctrl+Z
#  một phát là sạch.  Đây là PHÉP THỬ, không phải bản vá cuối (vá thật nằm trong
#  plugin xuất tấm của Khoa: cho nó đóng dấu này ngay lúc tạo group vỏ).
#
#  CÁCH CHẠY:
#    1. Chọn tấm TRÁI (tấm của mình, chưa gán nhãn được).
#    2. Window > Ruby Console >
#       load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/danh_dau_van_test.rb'
#    3. Chạy lại lệnh nesting/gán nhãn của ABF. Nếu tấm được gán nhãn -> đúng gốc.
#       Không ăn -> báo tôi, còn thiếu key khác (đọc lại so_sanh_ranh_tag).
#    4. Ctrl+Z để trả lại nguyên trạng nếu chỉ muốn thử.
# =============================================================================

module DanhDauVanTest

  def self.run
    model = Sketchup.active_model
    grps  = model.selection.to_a.select do |e|
      (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && !e.deleted?
    end
    if grps.empty?
      puts '⚠ Chưa chọn Group/Component tấm ván nào. Chọn tấm trái rồi chạy lại.'
      return nil
    end

    model.start_operation('ABF danh dau is-board', true)
    begin
      grps.each_with_index { |g, i| dong_dau(g, i + 1) }
      model.commit_operation
      puts '✓ Đã đóng dấu is-board xong. Giờ CHẠY LẠI nesting/gán nhãn của ABF.'
      puts '  (Không muốn giữ thì Ctrl+Z.)'
    rescue => e
      model.abort_operation
      puts "Lỗi: #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n") if e.backtrace
    end
    nil
  end

  # Đóng đúng bộ khoá ABF hiện ở vỏ tấm bên nesting: is-board / board-index / label-rotation.
  # Chỉ ghi key nào CHƯA có, để không đè giá trị ABF có thể đã đặt.
  def self.dong_dau(g, idx)
    g.make_unique if g.respond_to?(:make_unique)   # kẻo sửa lây tấm dùng chung
    set_neu_thieu(g, 'is-board',       true)
    set_neu_thieu(g, 'board-index',    idx)
    set_neu_thieu(g, 'label-rotation', 0)
    puts format('  • %-24s -> is-board=%s board-index=%s label-rotation=%s',
                ten(g), g.get_attribute('ABF', 'is-board').inspect,
                g.get_attribute('ABF', 'board-index').inspect,
                g.get_attribute('ABF', 'label-rotation').inspect)
  end

  def self.set_neu_thieu(g, key, val)
    d = (g.attribute_dictionary('ABF') rescue nil)
    return if d && d.keys.include?(key)
    g.set_attribute('ABF', key, val)
  end

  def self.ten(g)
    n = g.name.to_s.strip
    n.empty? ? '(không tên)' : n.sub(/\A__/, '')
  end

end

DanhDauVanTest.run
