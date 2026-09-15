# encoding: UTF-8
# DÒ HƯỚNG VÂN — VÒNG 2: mổ bụng tấm ván tìm cái NHÃN/MŨI TÊN. Chỉ ĐỌC, không sửa gì.
#
# Vòng 1 (van_go_probe.rb) chốt: hướng vân KHÔNG nằm trong dictionary vỏ tấm
# (label-rotation toàn 0, không key lạ). Vậy mũi tên "②→" Khoa thấy là HÌNH THẬT
# nằm trong nhãn con của tấm. Vòng 2 in cây con của vài tấm để lộ:
#   - cái nhãn tên là gì (_ABF_Label? text? hình?)
#   - nó quay hướng nào trong world (= chiều vân)
#   - nó có mang dictionary/attribute riêng không (rotation nằm ở ĐÂY chăng?)
#
# Cách chạy: Window → Ruby Console → dán:
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/van_go_probe2.rb'

module VanGoProbe2

  NEST_HINT = '__ABF_Nesting'.freeze
  MM        = 25.4
  BOARDS    = 3           # số tấm đầu mổ bụng
  MAXDEPTH  = 8

  def self.run
    boards = []
    find_boards(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, boards)
    if boards.empty?
      puts 'KHÔNG thấy tấm is-board nào.'
      return nil
    end

    puts ''
    puts '=' * 92
    puts "SOI VÂN v2 — mổ #{[BOARDS, boards.size].min}/#{boards.size} tấm đầu tìm nhãn/mũi tên"
    puts '=' * 92

    boards.first(BOARDS).each_with_index do |b, i|
      e = b[:ent]; te = b[:tr]
      puts ''
      puts "### TẤM ##{i + 1}  idx=#{b[:idx]}  size=#{kt_str(e, b[:parent_tr])}"
      puts '-' * 92
      dump(e, te, 1)
    end
    puts '=' * 92
    puts '(chú ý: dòng nào tên có "Label"/"arrow"/"text", hoặc là Text/hình mũi tên → đó là vân)'
    nil
  end

  # in đệ quy cây con: mỗi entity một dòng, kèm loại/tên/kích thước/hướng/attr
  def self.dump(container, tr, depth)
    return if depth > MAXDEPTH
    ents = ents_of(container)
    return unless ents
    pad = '  ' * depth
    ents.each do |e|
      next if e.deleted?
      case e
      when Sketchup::Group, Sketchup::ComponentInstance
        te   = tr * e.transformation
        nm   = e.name.to_s
        nm   = "(#{e.definition.name})" if nm.empty? && e.is_a?(Sketchup::ComponentInstance)
        akey = attr_brief(e)
        puts format('%s• %-9s %-22s %-16s dài→%s %s',
                    pad, cls(e), cut(nm, 22), kt_local(e), dir_long(e, te), akey)
        dump(e, te, depth + 1)
      when Sketchup::Text
        puts format('%s· TEXT      "%s"', pad, cut(e.text.to_s.gsub("\n", ' '), 40))
      when Sketchup::Face
        # bỏ qua face thường cho gọn, chỉ đếm
      end
    end
    # đếm nhanh face/edge để biết đây là hình hay text
    nf = ents.grep(Sketchup::Face).size
    ne = ents.grep(Sketchup::Edge).size
    nt = ents.grep(Sketchup::Text).size
    puts format('%s  [%d face, %d edge, %d text]', pad, nf, ne, nt) if nf + ne + nt > 0
  end

  def self.attr_brief(e)
    d = (e.attribute_dictionary('ABF') rescue nil)
    return '' unless d
    ks = d.keys
    rot = ks.include?('label-rotation') ? " rot=#{d['label-rotation']}" : ''
    "ABF{#{ks.join(',')}}#{rot}"
  end

  def self.find_boards(entities, t, depth, in_nest, out)
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      nest = in_nest || e.name.to_s.include?(NEST_HINT)
      te   = t * e.transformation
      unless nest
        d = (e.attribute_dictionary('ABF') rescue nil)
        if d && d.keys.include?('is-board')
          out << { ent: e, tr: te, parent_tr: t, idx: d['board-index'] }
          next   # không chui tiếp bằng vòng find (dump lo phần trong)
        end
      end
      find_boards(ents_of(e), te, depth + 1, nest, out)
    end
  end

  def self.cls(e)
    e.is_a?(Sketchup::Group) ? 'Group' : 'Comp'
  end

  # chiều dài local (theo hộp bao local) chiếu ra world, vector đơn vị
  def self.dir_long(e, te)
    bb = e.bounds
    dims = [bb.width.to_f.abs, bb.height.to_f.abs, bb.depth.to_f.abs]
    ai = (0..2).max_by { |k| dims[k] }
    base = [X_AXIS, Y_AXIS, Z_AXIS][ai]
    v = (te * Geom::Point3d.new(base.x, base.y, base.z)) - te.origin
    return '(0,0,0)' if v.length < 1e-6
    v.normalize!
    format('(%+.2f,%+.2f,%+.2f)', v.x, v.y, v.z)
  end

  def self.kt_local(e)
    bb = e.bounds
    return '—' if bb.empty?
    d = [bb.width.to_f * MM, bb.height.to_f * MM, bb.depth.to_f * MM].sort
    format('%.0f×%.0f×%.1f', d[2], d[1], d[0])
  end

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

  def self.cut(s, n)
    t = s.to_s
    t.length <= n ? t : (t[0, n - 1] + '…')
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

VanGoProbe2.run
