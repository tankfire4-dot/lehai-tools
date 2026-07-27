# encoding: UTF-8
# DÒ VÒNG 2 — in ĐẦY ĐỦ giá trị, không chỉ mẫu đầu. Chỉ ĐỌC, không sửa gì.
#
# Vòng 1 (`dan_canh_3d_probe.rb`, 27/07/2026) đã chốt được ABF ghi ở đâu:
#   group tấm : ABF/edge-band-types   (16 tấm)
#   face cạnh : ABF/edge-band-id      (18 face)
#   group rãnh: ABF/setting-name = "Rãnh hậu"  ← thứ quý nhất, không ai ngờ tới
#   bản 2D    : group _ABF_edgeBanding (13 dấu)
#
# Ba câu vòng 1 KHÔNG trả lời được, mỗi câu chặn một việc sửa:
#   1. `edge-band-types` = [0, "chi don KES 21417EV", 1, "#ec2525", 0] nghĩa là gì?
#      Không giải mã được thì biết tấm CÓ dán, nhưng không biết CẠNH NÀO → vẫn
#      không zoom tới đúng cạnh trên 3D được.
#   2. Vì sao 16 tấm khai · 18 face có id · mà bản 2D chỉ 13 dấu? Lệch ở đâu?
#   3. Cả 4 rãnh có cùng `setting-name` "Rãnh hậu" không, hay có cái là "Ngàm"?
#      Nếu ABF khai đủ loại thì `kiem_tra_lien_ket` nên đọc thẳng cái này thay vì
#      suy từ độ ăn sâu — nguồn ABF tự khai bao giờ cũng chắc hơn mình đoán.
#
# Số lượng ít (16 + 18 + 4) nên in hết được, khỏi phải gom nhóm.
#
# Cách chạy: Window → Ruby Console → dán
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/abf_attr_full.rb'

module AbfAttrFull

  NEST_HINT = '__ABF_Nesting'.freeze
  EDGE_RE   = /edgeband/i.freeze
  MM        = 25.4

  def self.run
    tam = []; face = []; ranh = []; dau2d = []
    walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, tam, face, ranh, dau2d)

    puts ''
    puts '=' * 92
    puts "1) TẤM 3D CÓ 'edge-band-types'  (#{tam.size} tấm)  — giải mã xem cạnh nào được dán"
    puts '=' * 92
    tam.each_with_index { |r, i| puts format('%3d. %-26s  kt=%-22s  %s', i + 1, cat(r[:ten], 26), r[:kt], r[:val]) }

    puts ''
    puts '=' * 92
    puts "2) FACE CÓ 'edge-band-id'  (#{face.size} face)  — id lặp lại hay mỗi cạnh một số?"
    puts '=' * 92
    face.each_with_index { |r, i| puts format('%3d. tấm %-24s  id=%-8s  kt mặt=%s', i + 1, cat(r[:ten], 24), r[:id], r[:kt]) }
    puts "   → các id khác nhau: #{face.map { |r| r[:id] }.uniq.sort_by(&:to_s).inspect}"

    puts ''
    puts '=' * 92
    puts "3) GROUP RÃNH ('is-intersect')  (#{ranh.size} cái)  — CẢ 4 CÓ CÙNG setting-name KHÔNG?"
    puts '=' * 92
    ranh.each_with_index do |r, i|
      puts format('%3d. setting-name=%-18s  offset=%-8s  chiều nhỏ nhất=%.1fmm  b-id=%s',
                  i + 1, r[:ten].inspect, r[:off].to_s, r[:day], r[:bid].to_s)
    end
    puts "   → các setting-name khác nhau: #{ranh.map { |r| r[:ten] }.uniq.inspect}"

    puts ''
    puts '=' * 92
    puts "4) DẤU 2D '_ABF_edgeBanding'  (#{dau2d.size} dấu) — dài bao nhiêu, có khớp cạnh nào không"
    puts '=' * 92
    dau2d.each_with_index { |r, i| puts format('%3d. trong %-26s  kt=%s', i + 1, cat(r[:owner], 26), r[:kt]) }
    puts '=' * 92
    nil
  end

  def self.walk(entities, t, depth, in_nest, tam, face, ranh, dau2d, owner = '(gốc)')
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      nest = in_nest || e.name.to_s.include?(NEST_HINT)
      te   = t * e.transformation
      sub  = ents_of(e)

      if e.name.to_s =~ EDGE_RE
        dau2d << { owner: owner, kt: kt_str(e, t) } if nest
        next
      end
      next unless sub

      d = (e.attribute_dictionary('ABF') rescue nil)
      if d && !nest
        ten = ten_hoac(e, owner)
        if d.keys.include?('edge-band-types')
          tam << { ten: ten, kt: kt_str(e, t), val: d['edge-band-types'].inspect }
        end
        if d.keys.include?('is-intersect')
          ranh << { ten: d['setting-name'], off: d['intersect-offset'],
                    bid: d['intersect-group-b-id'], day: chieu_nho_mm(e, t) }
        end
        sub.grep(Sketchup::Face).each do |f|
          fd = (f.attribute_dictionary('ABF') rescue nil)
          next unless fd && fd.keys.include?('edge-band-id')
          face << { ten: ten, id: fd['edge-band-id'].inspect, kt: kt_face(f, te) }
        end
      end

      walk(sub, te, depth + 1, nest, tam, face, ranh, dau2d, ten_hoac(e, owner))
    end
  end

  # ba chiều hộp bao (mm) sắp tăng dần — e.bounds ở hệ CHA nên nhân t của cha
  def self.dims_mm(e, t)
    bb = e.bounds
    return nil if bb.nil? || bb.empty?
    mn = bb.min; mx = bb.max
    w = Geom::BoundingBox.new
    [0, 1].each { |a| [0, 1].each { |b| [0, 1].each { |c|
      w.add(t * Geom::Point3d.new(a.zero? ? mn.x : mx.x, b.zero? ? mn.y : mx.y, c.zero? ? mn.z : mx.z))
    } } }
    [(w.max.x - w.min.x) * MM, (w.max.y - w.min.y) * MM, (w.max.z - w.min.z) * MM].sort
  end

  def self.kt_str(e, t)
    d = dims_mm(e, t)
    d ? format('%.0f×%.0f×%.1f', d[2], d[1], d[0]) : '—'
  end

  def self.chieu_nho_mm(e, t)
    d = dims_mm(e, t)
    d ? d[0] : 0.0
  end

  def self.kt_face(f, te)
    bb = Geom::BoundingBox.new
    f.vertices.each { |v| bb.add(te * v.position) }
    return '—' if bb.empty?
    d = [(bb.max.x - bb.min.x) * MM, (bb.max.y - bb.min.y) * MM, (bb.max.z - bb.min.z) * MM].sort
    format('%.0f×%.0f×%.1f', d[2], d[1], d[0])
  end

  def self.ten_hoac(e, thua_ke)
    n = e.name.to_s.strip
    return thua_ke if n.empty?
    n.sub(/\A__/, '')
  end

  def self.cat(s, n)
    t = s.to_s
    t.length <= n ? t : (t[0, n - 1] + '…')
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

AbfAttrFull.run
