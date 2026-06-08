# encoding: UTF-8
module LeHai
  module Tools
    unless file_loaded?(__FILE__)
      path = File.dirname(__FILE__)

      require File.join(path, 'updater')
      require File.join(path, 'auto_dan_canh', 'main')
      require File.join(path, 'canh_cnc',      'main')
      require File.join(path, 'tam_go',        'main')
      require File.join(path, 'ha_nen',        'main')
      require File.join(path, 'dien_ten',      'main')

      toolbar = UI::Toolbar.new("LeHai's Decor Tools")
      [
        ::MyStudio::AutoEdgeBand,
        ::CanhCNC,
        ::Lehai::TamGoGen,
        ::LeHaiDecor::HaNen,
        ::TuDong::DienTen
      ].each { |mod| toolbar.add_item(mod.create_cmd) }

      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end

      LeHai::Tools.check_update

      file_loaded(__FILE__)
    end
  end
end
