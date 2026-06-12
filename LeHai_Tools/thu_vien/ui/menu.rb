# frozen_string_literal: true

module TK
  module ThuVien
    # Chỉ expose create_cmd — toolbar do LeHai_Tools/main.rb quản lý chung.
    def self.create_cmd
      icons_path = File.join(PATH, 'icons')
      cmd = UI::Command.new('Thư Viện Component') { Dialog.show }
      cmd.tooltip         = 'Thư viện component dùng chung'
      cmd.status_bar_text = 'Mở thư viện component: xem thumbnail, tìm kiếm và chèn vào model.'
      cmd.small_icon      = File.join(icons_path, 'tk_thuvien_16.png')
      cmd.large_icon      = File.join(icons_path, 'tk_thuvien_24.png')
      cmd
    end
  end
end
