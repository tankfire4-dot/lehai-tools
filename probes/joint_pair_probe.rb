# encoding: UTF-8
# DÒ: vì sao Kiểm Tra Liên Kết báo "đâm xuyên" khi hai tấm CHƯA ăn vào nhau.
# Chỉ ĐỌC model, không sửa gì.
#
# Câu Khoa nêu 28/07/2026 trên file sản xuất `CNC C.THUY`: dashboard báo
# "Thiếu RÃNH HẬU (mối 2/3) — 268. hau TU MAY GIAT ↔ 275 — đâm xuyên 8.5mm",
# nhưng nhìn mắt thì **hai tấm còn chưa chạm nhau**.
#
# NGHI PHẠM: `kiem_tra_lien_ket` đo giao nhau bằng **AABB — hộp bao THẲNG TRỤC**.
# Đầu file nó ghi rõ giả định: *"tủ thẳng trục"*. File này có tấm **XIÊN** (vách
# cong, tấm vát) — tấm xiên thì hộp bao phình ra to hơn khối gỗ thật rất nhiều,
# nên hai tấm cách nhau vẫn có thể có hộp bao chồng 8,5mm.
#
# Nhưng code còn một lớp nữa: khi không thấy dấu ABF, nó đo ĐÂM XUYÊN THẬT bằng
# bắn tia (`collide_frac`). Nếu lớp đó chạy đúng thì tấm không chạm phải cho
# frac thấp → coi như đã khoét → KHÔNG báo. Vậy phải biết frac thật là bao nhiêu
# rồi mới biết lỗi nằm ở AABB hay ở phép bắn tia.
#
# Probe in cả hai để phân xử, kèm ĐỘ NGHIÊNG của từng tấm (góc pháp tuyến mặt
# lớn nhất lệch khỏi trục gần nhất) — con số quyết định giả thuyết đứng hay đổ.
#
# Cách chạy: Window → Ruby Console
#   load '.../probes/joint_pair_probe.rb'
#   JointPair.do '268', '275'          # gõ một mẩu tên là đủ

module JointPair

  NEST_HINT = '__ABF_Nesting'.freeze
  MM        = 25.4

  def self.do(ten_a, ten_b)
    tam = []
    walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, tam)
    a = tam.find { |p| p[:ten].include?(ten_a) }
    b = tam.find { |p| p[:ten].include?(ten_b) }
    return puts("Không thấy tấm chứa '#{ten_a}'") if a.nil?
    return puts("Không thấy tấm chứa '#{ten_b}'") if b.nil?

    puts ''
    puts '=' * 88
    puts "CẶP: #{a[:ten]}   ↔   #{b[:ten]}"
    puts '=' * 88
    [a, b].each do |p|
      d = p[:ab]
      puts format('%-34s hộp bao %.0f × %.0f × %.0f mm', cat(p[:ten], 34),
                  (d[3] - d[0]) * MM, (d[4] - d[1]) * MM, (d[5] - d[2]) * MM)
      puts format('%-34s NGHIÊNG %.1f° so với trục gần nhất   (%d mặt)', '', p[:nghieng], p[:nface])
    end

    ov = overlap(a[:ab], b[:ab])
    if ov.nil?
      puts 'Hai HỘP BAO không chồng nhau → tool sẽ không xét cặp này.'
      return nil
    end
    # In TOẠ ĐỘ THẬT từng trục để Khoa đặt thước đúng chỗ mà kiểm — con số trừu
    # tượng "chồng 8.5mm" không kiểm được bằng mắt, toạ độ thì kiểm được.
    puts ''
    puts format('%-6s %14s %14s   %14s %14s   %s', 'TRỤC', 'A từ', 'A đến', 'B từ', 'B đến', 'CHỒNG')
    %w[X Y Z].each_with_index do |ax, k|
      a0 = a[:ab][k] * MM; a1 = a[:ab][k + 3] * MM
      b0 = b[:ab][k] * MM; b1 = b[:ab][k + 3] * MM
      lo = [a0, b0].max;   hi = [a1, b1].min
      puts format('%-6s %11.1f mm %11.1f mm   %11.1f mm %11.1f mm   %s', ax, a0, a1, b0, b1,
                  hi > lo ? format('%.1f mm  (từ %.1f đến %.1f)', hi - lo, lo, hi) : 'không chồng')
    end

    dims = [ov[3] - ov[0], ov[4] - ov[1], ov[5] - ov[2]].sort
    puts ''
    puts format('Khối chồng của HAI HỘP BAO: %.1f × %.1f × %.1f mm', dims[2] * MM, dims[1] * MM, dims[0] * MM)
    puts format('→ tool đọc "độ ăn sâu" = %.1f mm  (8–12,5 = rãnh hậu · 15–20 = ngàm)', dims[0] * MM)

    f3 = collide_frac(ov, a[:tris], b[:tris], 3)   # ĐÚNG như tool (SAMPLE_N = 3)
    f7 = collide_frac(ov, a[:tris], b[:tris], 7)   # mịn hơn, để lộ ca lưới thưa đánh lừa
    puts format('Đâm xuyên GỖ THẬT — lưới 3×3×3 (Y HỆT TOOL): %.0f%%  → tool %s',
                f3 * 100, f3 >= 0.4 ? 'BÁO LỖI' : 'coi như đã khoét')
    puts format('Đâm xuyên GỖ THẬT — lưới 7×7×7 (mịn hơn)   : %.0f%%', f7 * 100)
    puts ''
    if (f3 - f7).abs > 0.2
      puts 'KẾT: hai lưới lệch nhau nhiều → LƯỚI 27 ĐIỂM QUÁ THƯA cho khối giao này.'
      puts '     Lỗi ở phép lấy mẫu, không phải ở AABB.'
    end
    frac = f3
    if frac < 0.05
      puts 'KẾT: gỗ hầu như KHÔNG chạm nhau → chồng nhau chỉ là HỘP BAO (tấm xiên).'
      puts '     Lỗi nằm ở khâu AABB, không phải ở phép bắn tia.'
    elsif frac < 0.4
      puts 'KẾT: có chạm nhưng ít — nằm dưới ngưỡng 0.4, đáng ra tool coi là ĐÃ KHOÉT.'
    else
      puts 'KẾT: gỗ CÓ đâm xuyên thật ≥40% → tool báo đúng, mắt nhìn nhầm góc.'
    end
    puts '=' * 88
    nil
  end

  # ── quét tấm ──────────────────────────────────────────────
  def self.walk(entities, t, depth, out)
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.name.to_s.include?(NEST_HINT)
      te  = t * e.transformation
      sub = ents_of(e)
      next unless sub
      faces = sub.grep(Sketchup::Face)
      if !faces.empty? && !e.name.to_s.strip.empty?
        ab = world_aabb(faces, te)
        out << { ten: e.name.to_s, ab: ab, nface: faces.size,
                 nghieng: nghieng_deg(faces, te), tris: tris_of(faces, te) } if ab
      end
      walk(sub, te, depth + 1, out)
    end
  end

  # góc pháp tuyến mặt LỚN NHẤT lệch khỏi trục gần nhất (0° = thẳng trục)
  def self.nghieng_deg(faces, te)
    big = faces.max_by { |f| f.area rescue 0 }
    return 0.0 if big.nil?
    n = (te * big.normal) rescue big.normal          # khuôn auto_dan_canh/main.rb:457-461
    n.normalize!
    c = [n.x.abs, n.y.abs, n.z.abs].max
    c = 1.0 if c > 1.0
    (Math.acos(c) * 180.0 / Math::PI).abs
  end

  def self.world_aabb(faces, te)
    bb = Geom::BoundingBox.new
    faces.each { |f| f.vertices.each { |v| bb.add(te * v.position) } }
    return nil if bb.empty?
    [bb.min.x, bb.min.y, bb.min.z, bb.max.x, bb.max.y, bb.max.z]
  end

  def self.overlap(a, b)
    lox = [a[0], b[0]].max; hix = [a[3], b[3]].min
    return nil if hix - lox <= 0
    loy = [a[1], b[1]].max; hiy = [a[4], b[4]].min
    return nil if hiy - loy <= 0
    loz = [a[2], b[2]].max; hiz = [a[5], b[5]].min
    return nil if hiz - loz <= 0
    [lox, loy, loz, hix, hiy, hiz]
  end

  # ── đâm xuyên thật: chép cách của kiem_tra_lien_ket (bắn tia +X) ──
  # CHÉP NGUYÊN `build_tris` của kiem_tra_lien_ket/main.rb:254 — probe phải tái
  # hiện ĐÚNG phép đo của tool, khác một chi tiết là so sánh mất nghĩa.
  # Toạ độ giữ dạng mảng [x,y,z] (không phải Point3d), polygon quạt từ đỉnh 0.
  def self.tris_of(faces, te)
    out = []
    faces.each do |f|
      next if f.deleted?
      mesh = f.mesh
      mesh.polygons.each do |poly|
        idx = poly.map(&:abs)
        next if idx.size < 3
        a  = te * mesh.point_at(idx[0])
        pa = [a.x, a.y, a.z]
        (1...(idx.size - 1)).each do |k|
          b = te * mesh.point_at(idx[k]); c = te * mesh.point_at(idx[k + 1])
          pb = [b.x, b.y, b.z]; pc = [c.x, c.y, c.z]
          out << [pa, pb, pc,
                  [pa[1], pb[1], pc[1]].min, [pa[1], pb[1], pc[1]].max,
                  [pa[2], pb[2], pc[2]].min, [pa[2], pb[2], pc[2]].max,
                  [pa[0], pb[0], pc[0]].max]
        end
      end
    end
    out
  end

  def self.collide_frac(ov, ta, tb, n)
    dx = ov[3] - ov[0]; dy = ov[4] - ov[1]; dz = ov[5] - ov[2]
    both = 0; total = 0
    (0...n).each do |i|
      x = ov[0] + dx * (i + 0.5) / n
      (0...n).each do |j|
        y = ov[1] + dy * (j + 0.5) / n
        (0...n).each do |k|
          z = ov[2] + dz * (k + 0.5) / n
          total += 1
          both += 1 if inside?(x, y, z, ta) && inside?(x, y, z, tb)
        end
      end
    end
    total.zero? ? 0.0 : both.to_f / total
  end

  def self.inside?(x, y, z, tris)
    cnt = 0
    tris.each do |tr|
      next if y < tr[3] || y > tr[4] || z < tr[5] || z > tr[6] || tr[7] < x
      cnt += 1 if hit?(x, y, z, tr[0], tr[1], tr[2])
    end
    cnt.odd?
  end

  # tia +X từ (x,y,z) có cắt tam giác ABC không — toạ độ mảng [x,y,z]
  def self.hit?(x, y, z, a, b, c)
    d = (b[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (b[2] - a[2])
    return false if d.abs < 1e-12
    u = ((y - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (z - a[2])) / d
    v = ((b[1] - a[1]) * (z - a[2]) - (y - a[1]) * (b[2] - a[2])) / d
    return false if u < 0 || v < 0 || u + v > 1
    xi = a[0] + u * (b[0] - a[0]) + v * (c[0] - a[0])
    xi > x
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.cat(s, n)
    t = s.to_s
    t.length <= n ? t : (t[0, n - 1] + '…')
  end

end

puts "JointPair nạp xong. Gõ:   JointPair.do '268', '275'"

module JointPair

# ─────────────────────────────────────────────────────────────────────
#  SOI RUỘT MỘT TẤM — phép đo ĐỘC LẬP, không dùng lại gì của tool.
#
#  Vì sao thêm (28/07/2026, sau khi kết luận sai): `JointPair.do` chép NGUYÊN
#  phép đo của tool để "so cho công bằng". Chính vì thế nó **không thể phát hiện
#  lỗi nằm trong phép đo đó** — cả hai cùng sai một kiểu rồi báo "khớp", và tôi
#  kết luận "tool báo đúng" trong khi Khoa cầm thước đo ra 572 vs 574: không chạm.
#
#  Ở đây đo kiểu khác hẳn: liệt kê TỪNG mặt trong group, xem mặt nào nằm ngoài
#  khối gỗ. Mặt lạ (chữ khắc, mũi tên, nhãn ABF) vừa làm PHÌNH hộp bao, vừa phá
#  phép bắn tia — đếm chẵn/lẻ chỉ đúng với khối KÍN.
#
#    JointPair.soi '275'
# ─────────────────────────────────────────────────────────────────────
def self.soi(ten)
  tam = []
  walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, tam)
  p = tam.find { |x| x[:ten].include?(ten) }
  return puts("Không thấy tấm chứa '#{ten}'") if p.nil?

  ent = nil
  find_ent(Sketchup.active_model.entities, Geom::Transformation.new, 0, ten) { |e, te| ent = [e, te] }
  return puts('Không lấy được entity') if ent.nil?
  e, te = ent
  sub   = ents_of(e)
  faces = sub.grep(Sketchup::Face)

  puts ''
  puts '=' * 92
  puts "SOI RUỘT: #{e.name}"
  puts '=' * 92
  puts "Face trực tiếp: #{faces.size}   ·   Group/Component con: #{sub.grep(Sketchup::Group).size + sub.grep(Sketchup::ComponentInstance).size}   ·   Edge rời: #{sub.grep(Sketchup::Edge).size}"
  puts ''
  puts format('%3s %12s  %-26s %s', '#', 'DIỆN TÍCH', 'HỘP BAO MẶT (mm)', 'HỞ MÉP? (edge chỉ có 1 mặt)')
  puts '-' * 92
  ho_tong = 0
  faces.each_with_index do |f, i|
    bb = Geom::BoundingBox.new
    f.vertices.each { |v| bb.add(te * v.position) }
    d  = [(bb.max.x - bb.min.x) * MM, (bb.max.y - bb.min.y) * MM, (bb.max.z - bb.min.z) * MM]
    ho = f.edges.count { |ed| ed.faces.size < 2 }
    ho_tong += ho
    puts format('%3d %10.0f mm²  %-26s %s', i + 1, (f.area rescue 0) * MM * MM,
                format('%.0f × %.0f × %.0f', d[0], d[1], d[2]),
                ho.zero? ? '' : "HỞ #{ho} cạnh  ← mặt rời, KHÔNG thuộc khối kín")
  end
  puts '-' * 92
  puts ho_tong.zero? ?
    'Khối KÍN hoàn toàn → phép bắn tia (đếm chẵn/lẻ) dùng được.' :
    "⚠ CÓ #{ho_tong} cạnh hở → khối KHÔNG KÍN. Phép bắn tia của tool cho kết quả RÁC ở đây."
  puts ''
  ab = p[:ab]
  puts format('Hộp bao tính từ TẤT CẢ mặt: %.1f × %.1f × %.1f mm',
              (ab[3] - ab[0]) * MM, (ab[4] - ab[1]) * MM, (ab[5] - ab[2]) * MM)
  puts '→ so con số này với thước đo tay. Lệch = có mặt nhô ra ngoài khối gỗ.'
  puts '=' * 92
  nil
end

def self.find_ent(entities, t, depth, ten, &blk)
  return if depth > 40 || entities.nil?
  entities.each do |e|
    next if e.deleted?
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    next if e.name.to_s.include?(NEST_HINT)
    te = t * e.transformation
    blk.call(e, te) if e.name.to_s.include?(ten) && !ents_of(e).nil?
    find_ent(ents_of(e), te, depth + 1, ten, &blk)
  end
end

end
