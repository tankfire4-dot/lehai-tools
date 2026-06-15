# frozen_string_literal: true

module TK
  module ThuVien
    module Commands
      ICONS_PATH = File.join(PATH, 'icons').freeze

      def self.build_cmd
        cmd = UI::Command.new('Thư Viện Component') { Dialog.show }
        cmd.tooltip         = 'Thư Viện Component'
        cmd.status_bar_text = 'Mở thư viện component: xem thumbnail, tìm kiếm và chèn vào model.'
        cmd.small_icon      = File.join(ICONS_PATH, 'tk_thuvien_16.png')
        cmd.large_icon      = File.join(ICONS_PATH, 'tk_thuvien_24.png')
        cmd
      end
    end
  end
end
