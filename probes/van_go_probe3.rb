# encoding: UTF-8
# DÒ HƯỚNG VÂN — VÒNG 3: đọc ĐÚNG chiều mũi tên _ABF_Label. Chỉ ĐỌC, không sửa gì.
#
# Vòng 2 chốt: mũi tên = Group "_ABF_Label" (192×80, toàn edge), có sẵn trong mỗi tấm.
# Vòng 2 tính hướng còn LỖI (lẫn khung toạ độ nên 3 tấm đều ra +X). Vòng 3 đọc lại cho đúng:
#   - lấy hướng CẠNH DÀI của nhãn (192 = chiều mũi tên "→") chiếu ra world qua transform world
#   - so với cạnh dài của chính TẤM → vân chạy DỌC hay NGANG so với mảnh
#   - báo mũi tên nghiêng về đâu trong không gian (đứng/nằm)
# Mục tiêu: xem hướng vân có KHÁC nhau giữa các tấm không, và quan hệ mũi-tên ↔ mảnh.
#
# Cách chạy: Window → Ruby Console → dán:
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/van_go_probe3.rb'

module VanGoProbe3

  NEST_HINT = '__ABF_Nesting'.freeze
  MM        = 25.4

  def self.run
    boards = []
    find_boards(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, boards)
    if boards.empty?
      puts 'KHÔNG thấy tấm is-board nào.'
      return nil
    end

    puts ''
    puts '=' * 100
    puts "SOI VÂN v3 — chiều mũi tên _ABF_Label của #{boards.size} tấm"
    puts '=' * 100
    puts format('%-3s %-6s %-15s %-20s %-20s %-8s %s',
                '#', 'idx', 'size L×W×T', 'mũi tên → world', 'cạnh dài tấm → world', 'so tấm', 'so world')

    boards.each_with_index do |b, i|
      lbl = find_label(b[:ent])
      unless lbl
        puts format('%-3d %-6s %-15s  (KHÔNG thấy _ABF_Label trong tấm này)', i + 1, b[:idx].to_s, local_size(b[:ent]))
        next
      end
      lt      = b[:tr] * lbl.transformation
      arrow   = long_axis_world(lbl, lt)          # chiều "→" của nhãn
      blong   = long_axis_world(b[:ent], b[:tr])  # cạnh dài của tấm
      dotp    = arrow.dot(blong).abs
      vs_tam  = dotp > 0.7 ? 'DỌC' : (dotp < 0.3 ? 'NGANG' : 'xiên')
      vs_world = world_word(arrow)
      puts format('%-3d %-6s %-15s %-20s %-20s %-8s %s',
                  i + 1, b[:idx].to_s, local_size(b[:ent]),
                  vec_str(arrow), vec_str(blong), vs_tam, vs_world)
    end
    puts '=' * 100
    puts 'ĐỌC: "so tấm" = vân chạy dọc hay ngang so với cạnh dài mảnh; "so world" = mũi tên đứng/nằm.'
    puts 'Nếu cột "so tấm" MỖI TẤM MỖI KHÁC → hướng vân là thật, gắn theo mảnh (làm tool được).'
    nil
  end

  def self.find_label(board)
    stack = ents_of(board).to_a
    depth = 0
    while (e = stack.shift)
      next if e.deleted?
      if (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance))
        return e if e.name.to_s.include?('_ABF_Label')
        sub = ents_of(e)
        stack.concat(sub.to_a) if sub && (depth += 1) < 5000
      end
    end
    nil
  end

  # vector đơn vị (world) của trục LOCAL dài nhất của entity
  def self.long_axis_world(e, world_tr)
    bb = e.definition.bounds
    dims = [bb.width.to_f.abs, bb.height.to_f.abs, bb.depth.to_f.abs]
    ai = (0..2).max_by { |k| dims[k] }
    v = [world_tr.xaxis, world_tr.yaxis, world_tr.zaxis][ai]
    v = v.clone
    v.length < 1e-9 ? Geom::Vector3d.new(0, 0, 0) : (v.normalize! ; v)
  end

  def self.world_word(v)
    ax = [['X (ngang)', v.x.abs], ['Y (sâu)', v.y.abs], ['Z (đứng)', v.z.abs]].max_by { |_, m| m }
    ax[0]
  end

  def self.vec_str(v)
    format('(%+.2f,%+.2f,%+.2f)', v.x, v.y, v.z)
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
          out << { ent: e, tr: te, idx: d['board-index'] }
          next
        end
      end
      find_boards(ents_of(e), te, depth + 1, nest, out)
    end
  end

  def self.local_size(e)
    bb = e.definition.bounds
    d = [bb.width.to_f * MM, bb.height.to_f * MM, bb.depth.to_f * MM].sort
    format('%.0f×%.0f×%.1f', d[2], d[1], d[0])
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

VanGoProbe3.run
