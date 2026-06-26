# encoding: UTF-8
module LeHai
  module Tools
    unless file_loaded?(__FILE__)
      path = File.dirname(__FILE__)

      # Load mỗi sub-tool — rescue riêng để lỗi 1 tool không làm sập toàn bộ plugin
      [
        File.join(path, 'updater'),
        File.join(path, 'auto_dan_canh', 'main'),
        File.join(path, 'canh_cnc',      'main'),
        File.join(path, 'tam_go',        'main'),
        File.join(path, 'ha_nen',        'main'),
        File.join(path, 'dien_ten',      'main'),
        File.join(path, 'thu_vien',      'main'),
        File.join(path, 'go_group',      'main'),
        File.join(path, 'kiem_tra_do_day', 'main'),
        File.join(path, 'tim_tam_loi',   'main'),
        File.join(path, 'kiem_tra_khoang_cach', 'main'),
        File.join(path, 'truc_toa_do',   'main')
      ].each do |f|
        begin
          require f
        rescue => e
          puts "[LeHai_Tools] LOI load #{f}: #{e.class}: #{e.message}"
          puts e.backtrace.first(3).join("\n") if e.backtrace
        end
      end

      # Diagnostic: in ra console để debug
      puts "[LeHai_Tools] Defined? MyStudio::AutoEdgeBand = #{defined?(::MyStudio::AutoEdgeBand).inspect}"
      puts "[LeHai_Tools] Defined? CanhCNC               = #{defined?(::CanhCNC).inspect}"
      puts "[LeHai_Tools] Defined? Lehai::TamGoGen        = #{defined?(::Lehai::TamGoGen).inspect}"
      puts "[LeHai_Tools] Defined? LeHaiDecor::HaNen      = #{defined?(::LeHaiDecor::HaNen).inspect}"
      puts "[LeHai_Tools] Defined? TuDong::DienTen        = #{defined?(::TuDong::DienTen).inspect}"
      puts "[LeHai_Tools] Defined? TK::ThuVien            = #{defined?(::TK::ThuVien).inspect}"
      puts "[LeHai_Tools] Defined? TK::GoGroup            = #{defined?(::TK::GoGroup).inspect}"
      puts "[LeHai_Tools] Defined? TK::ThickCheck         = #{defined?(::TK::ThickCheck).inspect}"
      puts "[LeHai_Tools] Defined? TK::ABFFinder          = #{defined?(::TK::ABFFinder).inspect}"
      puts "[LeHai_Tools] Defined? TK::SpacingCheck       = #{defined?(::TK::SpacingCheck).inspect}"
      puts "[LeHai_Tools] Defined? TK::AxisFix            = #{defined?(::TK::AxisFix).inspect}"

      # Build toolbar — sắp theo CỤM (cụm DC để cuối). SketchUp không hỗ trợ
      # vạch ngăn trong 1 toolbar nên gom theo thứ tự là cách nhóm khả dĩ.
      toolbar = UI::Toolbar.new("LeHai's Decor Tools")
      loaded_count = 0

      # Mỗi phần tử: [điều kiện đã load?, lambda trả về create_cmd]
      groups = [
        # ── Cụm 1: Dựng hình ──
        [defined?(::Lehai::TamGoGen),       -> { ::Lehai::TamGoGen.create_cmd }],
        [defined?(::CanhCNC),               -> { ::CanhCNC.create_cmd }],
        [defined?(::LeHaiDecor::HaNen),     -> { ::LeHaiDecor::HaNen.create_cmd }],
        # ── Cụm 2: Gia công & nhãn ──
        [defined?(::MyStudio::AutoEdgeBand),-> { ::MyStudio::AutoEdgeBand.create_cmd }],
        [defined?(::TuDong::DienTen),       -> { ::TuDong::DienTen.create_cmd }],
        # ── Cụm 3: Thư viện ──
        [defined?(::TK::ThuVien) && ::TK::ThuVien.respond_to?(:create_cmd),
         -> { ::TK::ThuVien.create_cmd }],
        # ── Cụm 4 (cuối): DC / chuẩn bị xuất CNC ──
        [defined?(::TK::GoGroup) && ::TK::GoGroup.respond_to?(:create_cmd),
         -> { ::TK::GoGroup.create_cmd }],
        [defined?(::TK::ThickCheck) && ::TK::ThickCheck.respond_to?(:create_cmd),
         -> { ::TK::ThickCheck.create_cmd }],
        # Tìm Tấm Lỗi — đặt cạnh Kiểm Tra Độ Dày (cùng là kính lúp soi tấm)
        [defined?(::TK::ABFFinder) && ::TK::ABFFinder.respond_to?(:create_cmd),
         -> { ::TK::ABFFinder.create_cmd }],
        # Kiểm Tra Khoảng Cách — QC sau nesting, cùng cụm kiểm tra
        [defined?(::TK::SpacingCheck) && ::TK::SpacingCheck.respond_to?(:create_cmd),
         -> { ::TK::SpacingCheck.create_cmd }],
        [defined?(::TK::AxisFix) && ::TK::AxisFix.respond_to?(:create_cmd),
         -> { ::TK::AxisFix.create_cmd }]
      ]

      groups.each do |loaded, builder|
        next unless loaded
        toolbar.add_item(builder.call)
        loaded_count += 1
      end

      puts "[LeHai_Tools] Toolbar da load #{loaded_count}/#{groups.size} tools"

      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end

      LeHai::Tools.check_update if LeHai::Tools.respond_to?(:check_update)
      LeHai::Tools.ping_stats   if LeHai::Tools.respond_to?(:ping_stats)

      file_loaded(__FILE__)
    end
  end
end
