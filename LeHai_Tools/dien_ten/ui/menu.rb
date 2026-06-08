# frozen_string_literal: true

module TuDong
  module DienTen
    def self.create_cmd
      icons_path = File.join(PATH, 'icons')
      cmd = UI::Command.new('Ho Tro Dien Ten Nhanh') { TuDong::DienTen.run }
      cmd.tooltip         = 'Ho tro dien ten nhanh cho component/group duoc chon'
      cmd.status_bar_text = 'Chon component/group roi chay lenh nay de mo bang dien ten nhanh.'
      cmd.small_icon      = File.join(icons_path, 'icon_16.png')
      cmd.large_icon      = File.join(icons_path, 'icon_24.png')
      cmd
    end
  end
end
