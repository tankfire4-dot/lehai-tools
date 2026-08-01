# frozen_string_literal: true

# Thư Viện Component — trình duyệt thư viện .skp dùng chung:
# lưới thumbnail, cây thư mục n-cấp (đúng như trên ổ đĩa), tìm kiếm,
# click để chèn, lưu component từ model vào thư mục bất kỳ trong cây.
#
# Theo kiến trúc LeHai_Tools: không tự tạo toolbar/menu,
# chỉ expose TK::ThuVien.create_cmd (xem ui/menu.rb).

module TK
  module ThuVien
    PATH = File.dirname(__FILE__.dup.force_encoding('UTF-8')).freeze

    if defined?(UI::HtmlDialog)
      require File.join(PATH, 'core', 'library')
      require File.join(PATH, 'ui',   'dialog')
      require File.join(PATH, 'ui',   'menu')
    else
      puts '[LeHai_Tools] Thu Vien Component yeu cau SketchUp 2017+ (UI::HtmlDialog).'
    end
  end
end
