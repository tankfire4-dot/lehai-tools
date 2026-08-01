# encoding: UTF-8
# ============================================================
#  TEST — luật Đợt Chắn Bản Lề mới (±40mm) so với luật cũ (80mm)
#
#  Chạy — dán ĐÚNG MỘT DÒNG vào Ruby Console:
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/test_dot_chan_40.rb'
#
#  File này NẠP ĐÈ bản đã sửa trong kho lên bản đang chạy. Không cần cài lại .rbz.
#  Nạp đè chỉ sống tới khi đóng SketchUp — muốn dùng thật thì phải release .rbz.
#
#  CHỈ ĐỌC — không sửa, không xoá, không đụng gì vào model.
# ============================================================

TOOL = 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/LeHai_Tools/kiem_tra_ban_le_chan/main.rb'
OUT  = 'C:/Users/tankf/Desktop/agent_lab_khoa/scratch/test_dot_chan_ketqua.txt'

# Ruby sẽ kêu "already initialized constant" khi nạp đè — đó là BÌNH THƯỜNG,
# không phải lỗi. Tắt cảnh báo cho đỡ rối màn hình.
_v = $VERBOSE
$VERBOSE = nil
begin
  load TOOL
ensure
  $VERBOSE = _v
end

module TestDotChan
  MM = 25.4
  H  = TK::HingeBlockCheck

  # Luật CŨ: ngưỡng đứng 80mm + dung sai ngang 40mm CẢ HAI chiều
  def self.luat_cu(cups, shelves)
    vios = []
    near = 40.0 / MM
    cups.each do |cup|
      d = cup.door.ab
      shelves.each do |s|
        a = s.ab
        next if s.equal?(cup.door)
        next unless a[2] >= d[2] + H::BIEN_MM / MM && a[5] <= d[5] - H::BIEN_MM / MM
        c = cup.center
        next unless c.x >= a[0] - near && c.x <= a[3] + near
        next unless c.y >= a[1] - near && c.y <= a[4] + near
        gap = if c.z >= a[2] && c.z <= a[5] then 0.0
              else [(c.z - a[2]).abs, (c.z - a[5]).abs].min
              end
        gap_mm = gap * MM
        next if gap_mm >= 80.0
        vios << [cup.door.name, s.name, gap_mm]
      end
    end
    vios.sort_by { |v| v[2] }
  end

  def self.run
    d = []
    d << '======== TEST LUAT DOT CHAN BAN LE — CHI DOC ========'
    d << "File: #{Sketchup.active_model.title}"
    d << ''
    d << '--- Da nap de ban SUA trong kho. Kiem hang so: ---'
    d << format('  HO_MM     = %.1f   (phai la 40.0 — nguong dung, tu TAM coc len/xuong)', H::HO_MM)
    d << format('  GAN_XY_MM = %.1f   (dung sai CHI theo chieu SAU; trai/phai = 0)', H::GAN_XY_MM)
    if H::HO_MM != 40.0
      d << '  (!) HO_MM chua phai 40 -> nap de KHONG an. Kiem lai duong dan TOOL o dau file.'
    end
    d << ''

    cups, shelves = H.collect_all
    d << format('Quet duoc: %d coc ban le | %d tam nam ngang', cups.size, shelves.size)
    if cups.empty?
      d << '(!) Khong thay coc ban le nao — mo file co canh da khoet coc roi chay lai.'
      ket(d); return
    end

    moi = H.find_blocked(cups, shelves)
    cu  = luat_cu(cups, shelves)

    d << ''
    d << '======== SO SANH ========'
    d << format('  LUAT CU  (80mm, dung sai ngang ca 2 chieu): %d loi', cu.size)
    d << format('  LUAT MOI (+-40mm, trai/phai = 0)          : %d loi', moi.size)
    d << ''

    if cu.size == moi.size && cu.size.zero?
      d << '  Ca hai luat deu SACH tren file nay -> file nay khong phan biet duoc 2 luat.'
      d << '  Muon thay khac nhau: dung mot tam dot cach TAM COC khoang 50-60mm.'
      d << '     luat cu  -> BAO DO (vi < 80)'
      d << '     luat moi -> XANH   (vi > 40)'
    end

    d << '--- LUAT CU bao nhung moi nay ---'
    d << '  (khong co)' if cu.empty?
    cu.each_with_index do |(dn, sn, g), i|
      con = moi.any? { |v| v.door_name == dn && v.shelf_name == sn }
      d << format('  %2d. ho=%6.1fmm  canh=%-16s tam=%-16s  %s',
                  i + 1, g, dn.to_s, sn.to_s,
                  con ? 'van bao o luat moi' : '>>> LUAT MOI DA BO (dung y Khoa)')
    end

    d << ''
    d << '--- LUAT MOI bao nhung moi nay ---'
    d << '  (khong co)' if moi.empty?
    moi.each_with_index do |v, i|
      them = cu.none? { |(dn, sn, _)| dn == v.door_name && sn == v.shelf_name }
      d << format('  %2d. ho=%6.1fmm  canh=%-16s tam=%-16s  %s',
                  i + 1, v.gap_mm, v.door_name.to_s, v.shelf_name.to_s,
                  them ? '>>> MOI PHAT SINH — bao Claude, khong nen co' : '')
    end

    d << ''
    d << '--- Khoang cach dung tu tung coc toi tam dot GAN NHAT ---'
    d << '    (de thay tung coc dang nam o dau so voi moc 40 va 80)'
    cups.each_with_index do |cup, i|
      gan = nil; ten = nil
      shelves.each do |s|
        a = s.ab
        next if s.equal?(cup.door)
        c = cup.center
        g = if c.z >= a[2] && c.z <= a[5] then 0.0
            else [(c.z - a[2]).abs, (c.z - a[5]).abs].min
            end
        g *= MM
        if gan.nil? || g < gan
          gan = g; ten = s.name
        end
      end
      next unless gan
      moc = if gan < 40 then 'DO ca 2 luat'
            elsif gan < 80 then '<<< VUNG KHAC NHAU: cu=DO, moi=XANH'
            else 'XANH ca 2 luat'
            end
      d << format('  coc %2d: %7.1fmm toi %-16s  %s', i + 1, gan, ten.to_s, moc)
    end

    ket(d)
  end

  def self.ket(d)
    txt = d.join("\n")
    puts txt
    begin
      File.open(OUT, 'w:UTF-8') { |f| f.write(txt) }
      puts ''
      puts "[OK] Da ghi: #{OUT}"
      puts '[OK] Bao Claude "xong" la du.'
    rescue StandardError => e
      puts "[!] Khong ghi duoc file (#{e.message}) — copy o tren gui Claude."
    end
    nil
  end
end

TestDotChan.run
