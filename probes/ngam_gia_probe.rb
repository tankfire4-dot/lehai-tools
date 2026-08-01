# encoding: UTF-8
# ============================================================
#  DÒ CHẨN ĐOÁN — vì sao báo "thiếu NGÀM" khi hai tấm không chạm nhau
#
#  Khoa (01/08): dashboard báo 4 mối ngàm "2 tấm đâm xuyên 17.5mm chưa khoét",
#  nhưng nhìn model thì xung quanh không có gỗ nào cấn vào.
#
#  Probe gọi THẲNG hàm của tool (TK::JointCheck.*), không viết lại — để đo đúng
#  cái tool đang chạy chứ không đo bản sao.
#
#  Chạy — dán ĐÚNG MỘT DÒNG:
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/ngam_gia_probe.rb'
#
#  CHỈ ĐỌC — không sửa, không xoá, không đụng gì vào model.
# ============================================================

module NgamGiaProbe
  OUT = 'C:/Users/tankf/Desktop/agent_lab_khoa/scratch/ngam_gia_probe_ketqua.txt'
  MM  = 25.4
  J   = TK::JointCheck

  # đếm tỉ lệ điểm nằm trong CẢ 2 tấm, với lưới n×n×n tuỳ ý
  # (bản sao y hệt collide_frac của tool, chỉ khác cho chỉnh n)
  def self.frac_n(ov, ta, tb, n)
    dx = ov[3] - ov[0]; dy = ov[4] - ov[1]; dz = ov[5] - ov[2]
    both = 0; in_a = 0; in_b = 0; total = 0
    (0...n).each do |i|
      x = ov[0] + dx * (i + 0.5) / n
      (0...n).each do |j|
        y = ov[1] + dy * (j + 0.5) / n
        (0...n).each do |k|
          z = ov[2] + dz * (k + 0.5) / n
          total += 1
          a = J.point_inside?(x, y, z, ta)
          b = J.point_inside?(x, y, z, tb)
          in_a += 1 if a
          in_b += 1 if b
          both += 1 if a && b
        end
      end
    end
    [both.to_f / total, in_a.to_f / total, in_b.to_f / total, total]
  end

  # vỏ mặt có KÍN không? cạnh hở (khác 2 mặt) làm phép "bắn tia đếm lẻ" vô nghĩa
  def self.do_kin(faces)
    canh = {}
    faces.each do |f|
      next if f.deleted?
      f.edges.each { |e| canh[e.entityID] ||= e }
    end
    ho = canh.values.count { |e| e.faces.size != 2 }
    [canh.size, ho]
  rescue StandardError
    [-1, -1]
  end

  def self.kich_thuoc(ab)
    [(ab[3] - ab[0]) * MM, (ab[4] - ab[1]) * MM, (ab[5] - ab[2]) * MM].sort
  end

  def self.run
    dong = []
    dong << '======== NGAM GIA PROBE — CHI DOC ========'
    dong << "File: #{Sketchup.active_model.title}"

    planks, inters = J.collect_all
    joints = J.find_joints(planks, inters)
    thieu  = joints.select { |v| !v.made }

    dong << "Tong tam nhan dien: #{planks.size}"
    dong << "Tong moi lien ket: #{joints.size} | THIEU (bao loi): #{thieu.size}"
    dong << "Nguong tool: SAMPLE_N=3 (27 diem)  COLLIDE_THRESH=0.4 (>=11/27 diem = 'chua khoet')"
    dong << ''

    ten2plank = {}
    planks.each { |p| (ten2plank[p[:name].to_s] ||= []) << p }

    thieu.first(8).each_with_index do |v, idx|
      dong << ('=' * 72)
      dong << "MOI #{idx + 1}/#{thieu.size}: [#{v.kind}]  #{v.name_a.inspect}  <->  #{v.name_b.inspect}"
      dong << format('  tool bao dam xuyen: %.1f mm', v.pen)

      pa = (ten2plank[v.name_a.to_s] || [])
      pb = (ten2plank[v.name_b.to_s] || [])
      if pa.empty? || pb.empty?
        dong << '  (!) khong tra lai duoc 2 tam theo ten — bo qua'
        next
      end

      # chọn đúng cặp cho ra overlap box khớp pen
      cap = nil
      pa.each do |a|
        pb.each do |b|
          next if a.equal?(b)
          ov = J.overlap_box(a[:aabb], b[:aabb])
          next unless ov
          pen = [ov[3] - ov[0], ov[4] - ov[1], ov[5] - ov[2]].min * MM
          cap = [a, b, ov] if (pen - v.pen).abs < 0.6
        end
      end
      unless cap
        dong << '  (!) khong dung lai duoc vung giao — bo qua'
        next
      end
      a, b, ov = cap

      da = kich_thuoc(a[:aabb]); db = kich_thuoc(b[:aabb]); dov = kich_thuoc(ov)
      dong << format('  tam A  hop bao world: %8.1f x %8.1f x %8.1f mm', da[0], da[1], da[2])
      dong << format('  tam B  hop bao world: %8.1f x %8.1f x %8.1f mm', db[0], db[1], db[2])
      dong << format('  VUNG GIAO hai hop:    %8.1f x %8.1f x %8.1f mm', dov[0], dov[1], dov[2])

      ta = J.tris_of(a); tb = J.tris_of(b)
      ca, ha = do_kin(a[:faces]); cb, hb = do_kin(b[:faces])
      dong << format('  tam A: %5d tam giac | %4d canh, %3d canh HO', ta.size, ca, ha)
      dong << format('  tam B: %5d tam giac | %4d canh, %3d canh HO', tb.size, cb, hb)
      if ha > 0 || hb > 0
        dong << '  >>> CO CANH HO -> vo mat KHONG KIN -> phep "ban tia dem le" VO NGHIA <<<'
      end

      [3, 7, 13].each do |n|
        both, ia, ib, tot = frac_n(ov, ta, tb, n)
        cho = n == 3 ? '  <-- muc tool dang dung' : ''
        dong << format('  luoi %2dx%2dx%2d (%5d diem): trong CA HAI=%.3f | trong A=%.3f | trong B=%.3f%s',
                       n, n, n, tot, both, ia, ib, cho)
      end
      dong << '  Doc: "trong CA HAI" >= 0.4 -> tool ket luan CHUA KHOET (bao loi).'
      dong << '       Neu luoi min lam con so tut manh -> loi do LUOI QUA THO (27 diem).'
      dong << '       Neu "trong A" hoac "trong B" ~ 0 -> vung giao KHONG CO GO -> hop bao lua.'
    end

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

NgamGiaProbe.run
