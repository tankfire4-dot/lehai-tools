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
        File.join(path, 'dien_ten',      'main')
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

      # Build toolbar — chỉ add những tool đã load thành công
      toolbar = UI::Toolbar.new("LeHai's Decor Tools")
      loaded_count = 0

      if defined?(::MyStudio::AutoEdgeBand)
        toolbar.add_item(::MyStudio::AutoEdgeBand.create_cmd)
        loaded_count += 1
      end
      if defined?(::CanhCNC)
        toolbar.add_item(::CanhCNC.create_cmd)
        loaded_count += 1
      end
      if defined?(::Lehai::TamGoGen)
        toolbar.add_item(::Lehai::TamGoGen.create_cmd)
        loaded_count += 1
      end
      if defined?(::LeHaiDecor::HaNen)
        toolbar.add_item(::LeHaiDecor::HaNen.create_cmd)
        loaded_count += 1
      end
      if defined?(::TuDong::DienTen)
        toolbar.add_item(::TuDong::DienTen.create_cmd)
        loaded_count += 1
      end

      puts "[LeHai_Tools] Toolbar da load #{loaded_count}/5 tools"

      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end

      LeHai::Tools.check_update if LeHai::Tools.respond_to?(:check_update)

      file_loaded(__FILE__)
    end
  end
end
