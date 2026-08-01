# encoding: UTF-8
# ============================================================
#  DÒ CHẨN ĐOÁN 2 — MỞ TÚI RA XEM
#  Probe 1 đã loại 2 giả thuyết (nghiêng trục / cách đo). Hai cách đo độc lập
#  cùng ra số sai → vấn đề nằm ở CÁI GÌ ĐANG NẰM TRONG GROUP, không ở phép đo.
#
#  Probe này mổ đúng 2 container hỏng (33.1mm và 200mm) xem bên trong có gì.
#
#  Chạy — dán ĐÚNG MỘT DÒNG dưới đây vào Ruby Console:
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/do_day_probe2.rb'
#
#  CHỈ ĐỌC — không sửa, không xoá, không đụng gì vào model.
# ============================================================

module DoDayProbe2
  OUT  = 'C:/Users/tankf/Desktop/agent_lab_khoa/scratch/do_day_probe2_ketqua.txt'
  MM   = 25.4
  # tìm container theo độ dày cách cũ (mm)
  TARGET = [33.1, 200.0]
  DUNG_SAI = 1.0

  def self.ents_of(e)
    case e
    when Sketchup::Group             then e.entities
    when Sketchup::ComponentInstance then e.definition.entities
    end
  rescue StandardError
    nil
  end

  def self.cach_cu(ents)
    bb = Geom::BoundingBox.new
    ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
    return nil if bb.empty?
    [bb.width, bb.height, bb.depth].min.to_f * MM
  rescue StandardError
    nil
  end

  def self.walk(entities, depth, out, duong)
    return if depth > 8
    entities.to_a.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      ents = ents_of(e)
      next unless ents
      ten = e.name.to_s
      ten = "(ko ten:#{e.entityID})" if ten.empty?
      d2  = duong + [ten]
      cu  = cach_cu(ents)
      out << [e, cu, d2] if cu
      con = ents.any? { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
      walk(ents, depth + 1, out, d2) if con
    end
  end

  # tách các MẢNH RỜI NHAU trong đống mặt (dùng all_connected)
  def self.manh_roi(faces)
    con   = []
    da_xu = {}
    faces.each do |f|
      next if da_xu[f.entityID]
      nhom = f.all_connected.grep(Sketchup::Face)
      nhom.each { |g| da_xu[g.entityID] = true }
      con << nhom
    end
    con
  rescue StandardError
    [faces]
  end

  def self.day_theo_phap_tuyen(faces)
    return nil if faces.empty?
    big = faces.max_by { |f| f.area }
    n   = big.normal
    pts = faces.flat_map { |f| f.vertices.map { |v| v.position } }
    return nil if pts.empty?
    ds = pts.map { |p| (p - ORIGIN).dot(n) }
    [(ds.max - ds.min) * MM, n, big.area * MM * MM]
  rescue StandardError
    nil
  end

  def self.hop_bao_mm(faces)
    bb = Geom::BoundingBox.new
    faces.each { |f| bb.add(f.bounds) }
    return [0, 0, 0] if bb.empty?
    [bb.width.to_f * MM, bb.height.to_f * MM, bb.depth.to_f * MM].sort
  end

  def self.mo_tui(e, cu, duong, dong)
    ents  = ents_of(e)
    faces = ents.grep(Sketchup::Face)
    edges = ents.grep(Sketchup::Edge)
    cons  = ents.to_a.select { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }

    dong << ''
    dong << ('=' * 70)
    dong << "TUI: #{duong.join(' > ')}"
    dong << format('  cach cu = %.2f mm   |   loai = %s', cu, e.class.name.split('::').last)
    dong << format('  trong tui: %d Face, %d Edge, %d container con', faces.size, edges.size, cons.size)
    unless cons.empty?
      cons.first(10).each do |c|
        t = c.name.to_s
        t = '(ko ten)' if t.empty?
        dong << "     - con: #{t}  [#{c.class.name.split('::').last}]"
      end
    end

    manh = manh_roi(faces)
    dong << format('  >>> SO MANH ROI NHAU trong tui: %d <<<', manh.size)
    dong << '      (1 manh = mot tam lien khoi. >1 manh = tui dang chua nhieu thu)'

    manh.sort_by { |m| -m.map { |f| f.area }.sum }.first(12).each_with_index do |m, i|
      kq  = day_theo_phap_tuyen(m)
      hb  = hop_bao_mm(m)
      dt  = m.map { |f| f.area }.sum * MM * MM
      if kq
        day, n, _a = kq
        dong << format('   manh %2d: %3d mat | day(chieu)=%8.2f | hopbao=%8.1f x %8.1f x %8.1f | dtich=%10.0f mm2 | n=(%.3f,%.3f,%.3f)',
                       i + 1, m.size, day, hb[0], hb[1], hb[2], dt, n.x, n.y, n.z)
      else
        dong << format('   manh %2d: %3d mat | (khong do duoc)', i + 1, m.size)
      end
    end

    # gom huong phap tuyen de xem tui co bao nhieu "mat phang chinh"
    huong = Hash.new(0.0)
    faces.each do |f|
      n = f.normal
      k = format('%.2f,%.2f,%.2f', n.x.abs.round(2), n.y.abs.round(2), n.z.abs.round(2))
      huong[k] += f.area * MM * MM
    end
    dong << '  Huong phap tuyen (gom theo |x|,|y|,|z|, xep theo dien tich):'
    huong.sort_by { |_, v| -v }.first(8).each do |k, v|
      dong << format('     %s  -> %10.0f mm2', k, v)
    end

    # tag/layer
    tags = Hash.new(0)
    faces.each { |f| tags[f.layer.name.to_s] += 1 }
    dong << "  Tag cua cac mat: #{tags.map { |k, v| "#{k}(#{v})" }.join(', ')}"
  end

  def self.run
    model = Sketchup.active_model
    tam   = []
    walk(model.entities, 0, tam, [])

    dong = []
    dong << '======== DO DAY PROBE 2 — MO TUI RA XEM (CHI DOC) ========'
    dong << "File: #{model.title}"
    dong << "Tong container co mat: #{tam.size}"

    hong = tam.select { |_, cu, _| TARGET.any? { |t| (cu - t).abs < DUNG_SAI } }
    dong << "Tim thay #{hong.size} container khop muc tieu #{TARGET.inspect}"

    if hong.empty?
      dong << '(!) Khong tim thay — co the file da doi. Bao Claude.'
    else
      hong.each { |e, cu, duong| mo_tui(e, cu, duong, dong) }
    end

    # doi chung: mo 2 tui BINH THUONG (17.5mm) de so sanh
    binh_thuong = tam.select { |_, cu, _| (cu - 17.5).abs < 0.2 }.first(2)
    dong << ''
    dong << ('#' * 70)
    dong << '### DOI CHUNG — 2 tui BINH THUONG (17.5mm) de so sanh ###'
    binh_thuong.each { |e, cu, duong| mo_tui(e, cu, duong, dong) }

    txt = dong.join("\n")
    puts txt
    begin
      File.open(OUT, 'w:UTF-8') { |f| f.write(txt) }
      puts ''
      puts "[OK] Da ghi: #{OUT}"
      puts '[OK] Bao Claude "xong" la du.'
    rescue StandardError => err
      puts "[!] Khong ghi duoc file (#{err.message}) — copy o tren gui Claude."
    end
    nil
  end
end

DoDayProbe2.run
