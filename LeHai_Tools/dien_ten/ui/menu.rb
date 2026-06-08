# frozen_string_literal: true

module TuDong
  module DienTen
    def self.create_cmd
      icons_path = File.join(PATH, 'icons')
      cmd = UI::Command.new('Hỗ Trợ Điền Tên Nhanh') { TuDong::DienTen.run }
      cmd.tooltip         = 'Hỗ trợ điền tên nhanh cho component/group được chọn'
      cmd.status_bar_text = 'Chọn component/group rồi chạy lệnh này để mở bảng điền tên nhanh.'
      cmd.small_icon      = File.join(icons_path, 'icon_16.png')
      cmd.large_icon      = File.join(icons_path, 'icon_24.png')
      cmd
    end
  end
end
