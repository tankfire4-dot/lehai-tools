# encoding: UTF-8
# ── Khảo Sát Hiện Trường → 3D ───────────────────────────────
# NÚT CHỜ (Khoa chốt 28/09/2026): đặt sẵn icon trên toolbar, bấm thì báo "sắp cập nhật" vì app khảo
# sát trên điện thoại chưa hoàn thiện. Bản dựng 3D thật đang chạy thử RIÊNG trên máy Khoa ở lab
# `projects/khao-sat-hien-truong/sketchup/` (Ruby chỉ vẽ, JS tính) — xong thì thay thân `show` bằng bản thật.
# Nguồn icon (SVG + lệnh xuất PNG): lab `projects/khao-sat-hien-truong/sketchup/icon/`.
module TK
  module KhaoSatHienTruong
    PATH = File.dirname(__FILE__).freeze

    def self.show
      UI.messagebox(
        "Khảo Sát Hiện Trường → 3D\n\n" \
        "Tính năng đang hoàn thiện — sắp cập nhật.\n\n" \
        'Khi xong: lấy số đo từ app khảo sát trên điện thoại, dựng sẵn hiện trạng 3D ' \
        '(tường, cửa, ổ điện, len chân tường, hộp trần) ngay trong SketchUp.',
        MB_OK
      )
    end

    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Khảo Sát Hiện Trường') { TK::KhaoSatHienTruong.show }
      cmd.tooltip         = 'Khảo sát hiện trường → 3D (sắp cập nhật)'
      cmd.status_bar_text = 'Dựng hiện trạng 3D từ số đo app khảo sát trên điện thoại — đang hoàn thiện, sắp cập nhật.'
      s16 = File.join(icons, 'khao_sat_16.png')
      s24 = File.join(icons, 'khao_sat_24.png')
      cmd.small_icon = s16 if File.exist?(s16)
      cmd.large_icon = s24 if File.exist?(s24)
      cmd
    end
  end
end
