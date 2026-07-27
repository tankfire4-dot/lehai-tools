# encoding: UTF-8
# DÒ: ABF ghi thông tin DÁN CẠNH ở đâu trên MÔ HÌNH 3D? — chỉ ĐỌC, không sửa gì.
#
# Câu hỏi Khoa đặt 27/07/2026, và nó đúng: nút "Xem" của dòng Dán Cạnh zoom tới
# BẢN TRẢI PHẲNG 2D, vì `kiem_tra_dan_canh` đếm group `_ABF_edgeBanding` — thứ
# chỉ sinh ra lúc nesting. Nhưng ABF phải biết TỪ TRƯỚC cạnh nào cần dán thì mới
# trải ra được. Vậy dấu ở 3D nằm đâu?
#
# Manh mối có sẵn trong repo (`auto_dan_canh/main.rb:362`) — tool dán cạnh của
# chính Le Hai ghi vào ATTRIBUTE, không phải tên group:
#     inst.set_attribute('ABF', 'is-board',        true)
#     inst.set_attribute('ABF', 'edge-band-types', band_type)
#     face.set_attribute('ABF', 'edge-band-id',    band_id)
# Attribute KHÔNG hiện trong Entity Info nên mắt thường không thấy — đó là lý do
# suốt từ đầu không ai để ý.
#
# Probe này đo xem ABF THẬT có ghi đúng chỗ đó không. Nếu có → `kiem_tra_dan_canh`
# đang đếm CÁI BÓNG (dấu ở nesting) thay vì CÁI GỐC (attribute ở 3D), và file đã
# đánh dấu dán cạnh nhưng CHƯA nesting sẽ bị báo nhầm "chưa dán".
#
# Cách chạy: Window → Ruby Console → dán
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/dan_canh_3d_probe.rb'

module DanCanh3DProbe

  NEST_HINT = '__ABF_Nesting'.freeze
  EDGE_RE   = /edgeband/i.freeze

  def self.run
    dicts   = Hash.new(0)     # tên dict -> số entity mang nó (chỉ khu 3D)
    abf_key = Hash.new(0)     # 'ABF' dict: key -> số entity có key đó
    mau     = {}              # vài giá trị mẫu để nhìn tận mắt
    face_bd = 0               # số FACE mang dấu dán cạnh
    n_tam   = 0
    dau_3d  = 0
    dau_nest = 0

    walk(Sketchup.active_model.entities, 0, false) do |e, in_nest|
      if e.name.to_s =~ EDGE_RE
        in_nest ? (dau_nest += 1) : (dau_3d += 1)
        next
      end
      next if in_nest                       # phần dưới chỉ soi khu 3D
      sub = ents_of(e)
      next unless sub
      faces = sub.grep(Sketchup::Face)
      next if faces.empty?                  # không phải tấm
      n_tam += 1

      ghi_dicts(e, dicts)
      d = e.attribute_dictionary('ABF') rescue nil
      if d
        d.keys.each do |k|
          abf_key["group: #{k}"] += 1
          mau["group: #{k}"] ||= d[k].inspect[0, 70]
        end
      end
      faces.each do |f|
        fd = f.attribute_dictionary('ABF') rescue nil
        next unless fd
        face_bd += 1
        fd.keys.each do |k|
          abf_key["face:  #{k}"] += 1
          mau["face:  #{k}"] ||= fd[k].inspect[0, 70]
        end
      end
    end

    puts ''
    puts '=' * 80
    puts 'ABF GHI DẤU DÁN CẠNH Ở ĐÂU TRÊN 3D?'
    puts '=' * 80
    puts "Dấu group `_ABF_edgeBanding`:   #{dau_3d} ở khu 3D   ·   #{dau_nest} ở bản trải phẳng"
    puts "Tấm 3D soi được: #{n_tam}   ·   Face mang attribute 'ABF': #{face_bd}"
    puts ''
    puts '--- Mọi attribute dictionary thấy trên tấm 3D (dict -> số tấm) ---'
    if dicts.empty?
      puts '(không tấm nào mang attribute dictionary — ABF ghi kiểu khác)'
    else
      dicts.sort_by { |_, v| -v }.each { |k, v| puts format('%6d tấm   %s', v, k) }
    end
    puts ''
    puts "--- Key trong dictionary 'ABF' (key -> số entity · giá trị mẫu) ---"
    if abf_key.empty?
      puts "(không thấy dictionary 'ABF' nào — giả thuyết SAI, phải dò tiếp)"
    else
      abf_key.sort.each { |k, v| puts format('%6d x   %-28s %s', v, k, mau[k]) }
    end
    puts '=' * 80
    nil
  end

  def self.ghi_dicts(e, out)
    ds = e.attribute_dictionaries rescue nil
    return unless ds
    ds.each { |d| out[d.name.to_s] += 1 }
  end

  def self.walk(entities, depth, in_nest, &blk)
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      nest = in_nest || e.name.to_s.include?(NEST_HINT)
      blk.call(e, nest)
      next if e.name.to_s =~ EDGE_RE
      sub = ents_of(e)
      walk(sub, depth + 1, nest, &blk) if sub
    end
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

DanCanh3DProbe.run
