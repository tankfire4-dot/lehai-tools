# encoding: UTF-8
# ============================================================
#  DÒ CHẨN ĐOÁN — vì sao "Kiểm Tra Độ Dày" báo sai (33.1mm / 200mm)
#
#  Chạy:  Window > Ruby Console >
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/do_day_probe.rb'
#
#  CHỈ ĐỌC — không sửa, không xoá, không đụng gì vào model.
#  Kết quả tự ghi ra file, Claude đọc thẳng — Khoa không phải copy dòng nào.
# ============================================================

module DoDayProbe
  OUT   = 'C:/Users/tankf/Desktop/agent_lab_khoa/scratch/do_day_probe_ketqua.txt'
  MM    = 25.4
  CHUAN = [9.0, 10.0, 17.5, 18.0]   # dải chuẩn theo tool

  def self.ents_of(e)
    case e
    when Sketchup::Group             then e.entities
    when Sketchup::ComponentInstance then e.definition.entities
    end
  rescue StandardError
    nil
  end

  # ── CÁCH ĐANG DÙNG (kiem_tra_do_day/main.rb:108) ──
  # hộp bao thẳng trục của các mặt, lấy cạnh ngắn nhất
  def self.cach_cu(ents)
    bb = Geom::BoundingBox.new
    ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
    return nil if bb.empty?
    [bb.width, bb.height, bb.depth].min.to_f * MM
  rescue StandardError
    nil
  end

  # ── CÁCH ĐO ĐÚNG ──
  # lấy pháp tuyến mặt LỚN NHẤT (chính là mặt phẳng của tấm), rồi chiếu mọi
  # đỉnh lên pháp tuyến đó. Khoảng cách max-min = độ dày thật, bất kể tấm
  # nằm nghiêng bao nhiêu.
  def self.cach_dung(ents)
    faces = ents.grep(Sketchup::Face)
    return nil if faces.empty?
    big = faces.max_by { |f| f.area }
    n   = big.normal
    pts = faces.flat_map { |f| f.vertices.map { |v| v.position } }
    return nil if pts.empty?
    ds = pts.map { |p| (p - ORIGIN).dot(n) }
    [(ds.max - ds.min) * MM, n]
  rescue StandardError
    nil
  end

  # góc giữa pháp tuyến tấm và trục toạ độ gần nhất (độ)
  def self.goc_lech(n)
    c = [n.x.abs, n.y.abs, n.z.abs].max
    c = 1.0 if c > 1.0
    Math.acos(c) * 180.0 / Math::PI
  rescue StandardError
    -1.0
  end

  def self.chuan?(mm)
    CHUAN.any? { |c| (mm - c).abs < 0.2 }
  end

  def self.walk(entities, depth, out)
    return if depth > 8
    entities.to_a.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      ents = ents_of(e)
      next unless ents
      cu = cach_cu(ents)
      out << [e, cu] if cu
      con = ents.any? { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
      walk(ents, depth + 1, out) if con
    end
  end

  def self.run
    model = Sketchup.active_model
    tam   = []
    walk(model.entities, 0, tam)

    dong = []
    dong << '======== DO DAY PROBE — CHI DOC ========'
    dong << "File: #{model.title}"
    dong << "Tong so container co mat: #{tam.size}"
    dong << ''
    dong << 'Cot: [cach CU = min hop bao]  [cach DUNG = chieu len phap tuyen]  [goc lech truc]'
    dong << ''

    nghi = []
    tam.each do |e, cu|
      ents = ents_of(e)
      next unless ents
      kq = cach_dung(ents)
      next unless kq
      dung, n = kq
      goc     = goc_lech(n)
      lech    = (cu - dung).abs
      nghi << [e, cu, dung, goc, lech] if lech > 0.3 || !chuan?(cu)
    end

    dong << "======== #{nghi.size} TAM LECH GIUA HAI CACH DO ========"
    if nghi.empty?
      dong << '  (khong co — hai cach do cho cung ket qua tren moi tam)'
    end
    nghi.sort_by { |a| -a[4] }.first(60).each_with_index do |(e, cu, dung, goc, lech), i|
      ten = e.name.to_s
      ten = '(khong ten)' if ten.empty?
      ten = e.definition.name.to_s if ten == '(khong ten)' && e.is_a?(Sketchup::ComponentInstance)
      dong << format('  %3d. CU=%8.2fmm  DUNG=%8.2fmm  lech=%8.2fmm  goc=%6.2f do  %s',
                     i + 1, cu, dung, lech, goc, ten)
    end

    dong << ''
    dong << '======== GOM THEO CACH CU (giong bieu do trong tool) ========'
    tam.group_by { |_, cu| (cu * 10).round / 10.0 }
       .sort_by { |k, v| -v.size }.first(20).each do |k, v|
      dong << format('  %8.1f mm : %d tam %s', k, v.size, chuan?(k) ? '' : '  <-- KHONG CHUAN')
    end

    dong << ''
    dong << '======== GOM THEO CACH DUNG ========'
    hop = {}
    tam.each do |e, _|
      ents = ents_of(e)
      next unless ents
      kq = cach_dung(ents)
      next unless kq
      k = (kq[0] * 10).round / 10.0
      hop[k] = (hop[k] || 0) + 1
    end
    hop.sort_by { |k, v| -v }.first(20).each do |k, v|
      dong << format('  %8.1f mm : %d tam %s', k, v, chuan?(k) ? '' : '  <-- KHONG CHUAN')
    end

    dong << ''
    dong << '======== KET LUAN ========'
    if nghi.empty?
      dong << 'Hai cach do KHOP nhau -> gia thuyet "hop bao phong vi tam nghieng" SAI.'
      dong << 'Nguyen nhan nam cho khac, phai do tiep.'
    else
      nghieng = nghi.count { |x| x[3] > 0.05 }
      dong << "#{nghi.size} tam lech. Trong do #{nghieng} tam co phap tuyen LECH TRUC (>0.05 do)."
      dong << 'Neu phan lon tam lech deu nghieng -> dung gia thuyet: hop bao phong theo goc nghieng.'
      dong << 'Cach sua: bo do bang hop bao, dung phep chieu len phap tuyen (ham cach_dung o tren).'
    end

    txt = dong.join("\n")
    puts txt
    begin
      File.open(OUT, 'w:UTF-8') { |f| f.write(txt) }
      puts ''
      puts "[OK] Da ghi ket qua ra: #{OUT}"
      puts '[OK] Bao Claude mot cau "xong" la du — Claude tu doc file nay.'
    rescue StandardError => err
      puts ''
      puts "[!] Khong ghi duoc file (#{err.message}) — Khoa copy toan bo o tren gui Claude."
    end
    nil
  end
end

DoDayProbe.run
