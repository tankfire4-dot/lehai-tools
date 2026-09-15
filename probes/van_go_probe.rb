# encoding: UTF-8
# DÒ HƯỚNG VÂN — ABF giấu chiều mũi tên/thớ gỗ ở attribute nào? Chỉ ĐỌC, không sửa gì.
#
# Câu hỏi cần trả lời (Khoa 15/09): cái mũi tên "→" trên nhãn tấm là HƯỚNG VÂN, nó
# GẮN LIỀN với mảnh module và xoay theo mảnh. Đổ màu solid thì mất dấu, nên muốn tool
# vẽ lại. Trước khi viết tool phải biết hướng vân nằm ở đâu — luật nhà: cấm đoán attribute.
#
# Nghi phạm số 1: ABF/label-rotation (đo 27/07 thấy 544 tấm đều mang, mẫu = 0).
#   - Nếu nó CHỈ bằng 0 khắp nơi → KHÔNG phải hướng vân (vân phải có tấm dọc tấm ngang).
#   - Nếu nó nhận 0/90/180/270 → gần như chắc là hướng vân. Đó là phép đo quyết định.
# Đồng thời in TẤT CẢ key trong dictionary "ABF" phòng khi vân nằm ở key mình chưa biết.
#
# Cách chạy: Window → Ruby Console → dán:
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/van_go_probe.rb'

module VanGoProbe

  NEST_HINT = '__ABF_Nesting'.freeze
  MM        = 25.4
  SHOW      = 15                      # số tấm in chi tiết
  DUMP_FULL = 3                       # số tấm in NGUYÊN dictionary (bắt key lạ)

  def self.run
    boards = []
    walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, boards)

    if boards.empty?
      puts 'KHÔNG thấy tấm nào mang dictionary "ABF"/is-board. File này đã nest chưa?'
      return nil
    end

    n = boards.size
    puts ''
    puts '=' * 92
    puts "SOI VÂN — #{n} tấm ván ABF (bỏ qua nhánh __ABF_Nesting)"
    puts '=' * 92

    # 1) Union tất cả key + số tấm mang key đó (để không bỏ sót key hướng vân)
    seen = Hash.new(0); sample = {}
    boards.each do |b|
      b[:keys].each do |k|
        seen[k] += 1
        sample[k] ||= b[:dict][k]
      end
    end
    puts ''
    puts "1) MỌI key trong dictionary \"ABF\" trên tấm ván  (key : số tấm mang : ví dụ giá trị)"
    puts '-' * 92
    seen.sort_by { |k, _| k }.each do |k, c|
      puts format('   %-24s : %4d/%-4d : %s', k, c, n, sample[k].inspect)
    end

    # 2) Phép đo quyết định: label-rotation có ĐỔI theo tấm không?
    puts ''
    puts '2) PHÂN BỐ label-rotation  (nếu chỉ có 1 giá trị → KHÔNG phải hướng vân)'
    puts '-' * 92
    hist = Hash.new(0)
    boards.each { |b| hist[b[:dict]['label-rotation']] += 1 }
    hist.sort_by { |v, _| v.to_s }.each { |v, c| puts format('   rotation = %-8s : %4d tấm', v.inspect, c) }
    puts hist.size <= 1 ? '   → CHỈ MỘT giá trị: hướng vân nằm ở CHỖ KHÁC (xem key lạ mục 1 + dump mục 4).' \
                        : '   → NHIỀU giá trị: rất có thể label-rotation CHÍNH LÀ hướng vân.'

    # 3) Bảng: tấm + kích thước + rotation + hai trục cạnh chiếu ra world
    #    (để sau này biết mũi tên vẽ theo chiều nào trong không gian thật)
    puts ''
    puts "3) #{[SHOW, n].min}/#{n} TẤM ĐẦU — rotation so với chiều tấm & hướng world"
    puts '-' * 92
    puts format('   %-3s %-8s %-16s %-8s %-14s %-14s', '#', 'idx', 'size L×W×T(mm)', 'rot', 'trục-dài→world', 'trục-ngắn→world')
    boards.first(SHOW).each_with_index do |b, i|
      puts format('   %-3d %-8s %-16s %-8s %-14s %-14s',
                  i + 1, b[:dict]['board-index'].to_s, b[:size], b[:dict]['label-rotation'].inspect,
                  b[:long_dir], b[:short_dir])
    end

    # 4) Dump NGUYÊN vài tấm — bắt key lạ mà mục 1 chỉ in tên
    puts ''
    puts "4) DUMP nguyên dictionary #{[DUMP_FULL, n].min} tấm đầu (soi key lạ tận mắt)"
    puts '-' * 92
    boards.first(DUMP_FULL).each_with_index do |b, i|
      puts "   --- tấm ##{i + 1}  (idx=#{b[:dict]['board-index']}, size=#{b[:size]}) ---"
      b[:dict].sort_by { |k, _| k }.each { |k, v| puts format('       %-24s = %s', k, v.inspect) }
    end
    puts '=' * 92
    nil
  end

  def self.walk(entities, t, depth, in_nest, out)
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      nest = in_nest || e.name.to_s.include?(NEST_HINT)
      te   = t * e.transformation
      sub  = ents_of(e)

      unless nest
        d = (e.attribute_dictionary('ABF') rescue nil)
        if d && d.keys.include?('is-board')
          out << { keys: d.keys, dict: dict_hash(d), size: kt_str(e, t),
                   long_dir: axis_str(te, longest_local_axis(e)),
                   short_dir: axis_str(te, mid_local_axis(e)) }
        end
      end

      walk(sub, te, depth + 1, nest, out) if sub
    end
  end

  # copy dictionary ra hash thường để in/sắp cho gọn
  def self.dict_hash(d)
    h = {}
    d.keys.each { |k| h[k] = (d[k] rescue nil) }
    h
  end

  # trục local dài nhất / trung bình của hộp bao (0=X,1=Y,2=Z) — thớ thường chạy theo cạnh dài
  def self.longest_local_axis(e)
    order_axes(e)[2]
  end

  def self.mid_local_axis(e)
    order_axes(e)[1]
  end

  def self.order_axes(e)
    bb = e.bounds
    dims = [bb.width.to_f.abs, bb.height.to_f.abs, bb.depth.to_f.abs]  # X,Y,Z ở hệ CHA
    (0..2).to_a.sort_by { |i| dims[i] }
  end

  # chiều của trục local (0/1/2) chiếu ra world, làm tròn thành vector đơn vị đọc được
  def self.axis_str(te, axis_i)
    base = [X_AXIS, Y_AXIS, Z_AXIS][axis_i]
    v = (te * Geom::Point3d.new(base.x, base.y, base.z)) - te.origin
    return '(0,0,0)' if v.length < 1e-6
    v.normalize!
    format('(%+.2f,%+.2f,%+.2f)', v.x, v.y, v.z)
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

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

VanGoProbe.run
