# encoding: UTF-8
# =============================================================================
#  SO SÁNH TẤM ABF-nesting  vs  TẤM PLUGIN-mình  — vì sao nesting gán nhãn được
#  tấm bên phải mà KHÔNG gán được tấm bên trái.  Script chỉ ĐỌC, không sửa model.
#
#  Câu hỏi của Khoa: cái "tag phay rãnh hậu" của ABF khác gì tag do plugin mình
#  xuất ra. Cẩm nang shared-notes/sketchup-api.md (mục ⭐ 27/07) đã chốt sẵn:
#     "Tên và tag là thứ ABF HIỂN THỊ; ATTRIBUTE là thứ ABF DÙNG."
#  ABF nhận diện + gán nhãn rãnh KHÔNG qua tag/layer, mà qua dictionary tên `ABF`
#  (is-board / is-intersect / setting-name="Rãnh hậu" / is-labeled-face ...).
#  Entity Info KHÔNG hiện lớp attribute này -> nhìn màn hình cả ngày cũng không
#  thấy khác. Script này phơi cả HAI tầng cạnh nhau để so.
#
#  CÁCH CHẠY:
#    1. Window > Ruby Console.
#    2. Chọn (click) MỘT tấm — ví dụ tấm bên TRÁI của mình. Có thể chọn cả 2 tấm.
#    3. Dán:
#       load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/so_sanh_ranh_tag.rb'
#    4. Đọc bảng. Rồi chọn tấm bên PHẢI (nesting), chạy lại, đối chiếu.
#       Chọn cả 2 cùng lúc thì cuối bảng có mục SO KHỚP tự chỉ ra chỗ lệch.
# =============================================================================

module SoSanhRanhTag

  ABF_DICT = 'ABF'.freeze
  # Các tag/layer mà mọi loại rãnh của ABF hay đeo (hậu / ngàm / led / groove).
  TAG_RANH = /ranhhau|groove|intersect|ngam|phayled/i.freeze
  MAX_DEPTH = 40

  # ---------------------------------------------------------------- điểm vào
  def self.run
    sel = Sketchup.active_model.selection.to_a
                                         .select { |e| grp?(e) }
    if sel.empty?
      puts '⚠ Chưa chọn tấm nào (hoặc chọn phải Group/Component). Click 1 tấm rồi chạy lại.'
      return nil
    end

    reports = sel.map { |e| soi_tam(e) }

    reports.each { |r| in_bao_cao(r) }
    in_so_khop(reports) if reports.size >= 2
    puts '=' * 88
    nil
  end

  # -------------------------------------------------- soi 1 tấm -> hash kết quả
  def self.soi_tam(root)
    acc = {
      ten:        ten_hoac(root, '(không tên)'),
      klass:      root.is_a?(Sketchup::Group) ? 'Group' : 'Component',
      tag_group:  tag_of(root),
      dicts_root: dicts_str(root),
      abf_root:   abf_hash(root),
      edge_tags:  Hash.new(0),   # tag layer -> số edge
      face_tags:  Hash.new(0),
      faces_abf:  Hash.new(0),   # "is-labeled-face=true" -> số face
      sub_ranh:   [],            # các group con giống dấu rãnh
      other_dict_names: {}       # tên mọi dictionary lạ (không phải 'ABF') đã gặp
    }
    walk(ents_of(root), 0, acc)
    acc
  end

  def self.walk(entities, depth, acc)
    return if depth > MAX_DEPTH || entities.nil?
    entities.each do |e|
      next if e.deleted?
      case e
      when Sketchup::Edge
        acc[:edge_tags][tag_of(e)] += 1
      when Sketchup::Face
        acc[:face_tags][tag_of(e)] += 1
        ghi_face_abf(e, acc)
      when Sketchup::Group, Sketchup::ComponentInstance
        ghi_sub_group(e, acc)
        walk(ents_of(e), depth + 1, acc)
      end
      thu_dict_names(e, acc)
    end
  end

  # group con có mùi "dấu rãnh" -> ghi kèm ABF của nó (đây là nơi setting-name nằm)
  def self.ghi_sub_group(e, acc)
    nm  = e.name.to_s
    tag = tag_of(e)
    return unless nm =~ /intersect/i || tag =~ TAG_RANH || abf_hash(e).key?('is-intersect')
    a = abf_hash(e)
    acc[:sub_ranh] << {
      ten: ten_hoac(e, '(con không tên)'),
      tag: tag,
      setting: a['setting-name'],
      is_intersect: a['is-intersect'],
      b_id: a['intersect-group-b-id'],
      offset: a['intersect-offset'],
      dicts: dicts_str(e)
    }
  end

  def self.ghi_face_abf(f, acc)
    a = abf_hash(f)
    acc[:faces_abf]['is-labeled-face'] += 1 if a['is-labeled-face']
    acc[:faces_abf]['is-cnced-face']   += 1 if a['is-cnced-face']
    acc[:faces_abf]['edge-band-id']    += 1 if a.key?('edge-band-id')
  end

  # ---------------------------------------------------------------- in báo cáo
  def self.in_bao_cao(r)
    puts ''
    puts '#' * 88
    puts "# TẤM: #{r[:ten].inspect}   [#{r[:klass]}]   tag(layer) ở GROUP = #{r[:tag_group].inspect}"
    puts '#' * 88

    puts '— Dictionary Ở GROUP VỎ:'
    puts indent(r[:dicts_root])

    puts '— TAG CỦA EDGE bên trong (gộp theo tag):'
    puts indent(bang_tag(r[:edge_tags]))
    puts '— TAG CỦA FACE bên trong (gộp theo tag):'
    puts indent(bang_tag(r[:face_tags]))

    puts '— ATTRIBUTE trên FACE (thứ ABF thật sự đọc để gán nhãn):'
    if r[:faces_abf].empty?
      puts '     (không face nào mang attribute ABF)'
    else
      r[:faces_abf].each { |k, v| puts format('     %-18s : %d face', k, v) }
    end

    puts '— GROUP CON GIỐNG DẤU RÃNH (is-intersect / tag rãnh):'
    if r[:sub_ranh].empty?
      puts '     (không có)'
    else
      r[:sub_ranh].each_with_index do |s, i|
        puts format('  %2d. %-22s tag=%-16s is-intersect=%s  setting-name=%s  b-id=%s  offset=%s',
                    i + 1, cat(s[:ten], 22), s[:tag].inspect, s[:is_intersect].inspect,
                    s[:setting].inspect, s[:b_id].inspect, s[:offset].inspect)
        puts indent(s[:dicts], 8) unless s[:dicts].strip.empty? || s[:dicts] =~ /\(không có dictionary\)/
      end
    end

    in_checklist(r)
  end

  # 6 tín hiệu ABF dùng để nhận + gán nhãn rãnh hậu; ✓/✗ cho thấy tấm thiếu cái gì
  def self.in_checklist(r)
    edge_ranh = r[:edge_tags].keys.any? { |t| t =~ TAG_RANH }
    puts '— ✔ TÍN HIỆU NESTING DÙNG ĐỂ GÁN NHÃN (tấm thiếu cái nào = nesting bỏ qua):'
    row('Group vỏ có dictionary `ABF`',        !r[:abf_root].empty?)
    row('ABF/is-board = true (được coi là ván)', r[:abf_root]['is-board'] == true)
    row('Có group con is-intersect (dấu rãnh)',  r[:sub_ranh].any? { |s| s[:is_intersect] })
    row('Dấu rãnh khai setting-name',            r[:sub_ranh].any? { |s| s[:setting] })
    row('Edge đeo tag rãnh (Groove/RanhHau/…)',  edge_ranh)
    row('Face có is-labeled-face / is-cnced-face', r[:faces_abf]['is-labeled-face'].to_i > 0 || r[:faces_abf]['is-cnced-face'].to_i > 0)
  end

  # --------------------------------------------------------------- so 2 tấm
  def self.in_so_khop(reports)
    puts ''
    puts '=' * 88
    puts 'SO KHỚP 2 TẤM ĐẦU — key có ở tấm này mà THIẾU ở tấm kia (đây là gốc “không gán nhãn được”):'
    puts '=' * 88
    a, b = reports[0], reports[1]
    ka = keyset(a); kb = keyset(b)
    puts "Tấm A = #{a[:ten].inspect}"
    puts "Tấm B = #{b[:ten].inspect}"
    diff('CÓ ở A, THIẾU ở B', ka - kb)
    diff('CÓ ở B, THIẾU ở A', kb - ka)
    puts '(Rỗng cả hai chiều = hai tấm mang cùng bộ dữ liệu ABF; khác biệt nằm ở GIÁ TRỊ, đọc bảng trên.)' if (ka - kb).empty? && (kb - ka).empty?
  end

  # tập "dấu hiệu" của một tấm để đem trừ nhau
  def self.keyset(r)
    s = []
    s << 'ABF@group'                         unless r[:abf_root].empty?
    r[:abf_root].keys.each   { |k| s << "ABF@group/#{k}" }
    r[:edge_tags].keys.each  { |t| s << "edge-tag/#{t}" }
    r[:faces_abf].keys.each  { |k| s << "face-attr/#{k}" }
    s << 'sub-intersect'                      if r[:sub_ranh].any? { |x| x[:is_intersect] }
    r[:sub_ranh].each        { |x| s << "sub/setting=#{x[:setting].inspect}" if x[:setting] }
    r[:other_dict_names].keys.each { |n| s << "dict/#{n}" }
    s.uniq
  end

  def self.diff(label, keys)
    puts "• #{label}:"
    if keys.empty?
      puts '     (không có)'
    else
      keys.sort.each { |k| puts "     - #{k}" }
    end
  end

  # ---------------------------------------------------------------- tiện ích
  def self.abf_hash(e)
    d = (e.attribute_dictionary(ABF_DICT) rescue nil)
    return {} unless d
    h = {}
    d.keys.each { |k| h[k] = (d[k] rescue nil) }
    h
  end

  # gom TÊN mọi dictionary lạ để đối chiếu (plugin mình có thể dùng dict tên khác)
  def self.thu_dict_names(e, acc)
    dd = (e.attribute_dictionaries rescue nil)
    return unless dd
    dd.each { |d| acc[:other_dict_names][d.name] = true unless d.name == ABF_DICT }
  end

  def self.dicts_str(e)
    dd = (e.attribute_dictionaries rescue nil)
    return '(không có dictionary)' if dd.nil? || dd.to_a.empty?
    lines = []
    dd.each do |d|
      lines << "[#{d.name}]"
      d.keys.each { |k| lines << format('   %-22s = %s', k, (d[k] rescue nil).inspect) }
    end
    lines.join("\n")
  end

  def self.bang_tag(h)
    return '(không có)' if h.empty?
    h.sort_by { |_, v| -v }.map { |k, v| format('%5d ×  %s', v, k) }.join("\n")
  end

  def self.row(label, ok)
    puts format('     %s  %s', ok ? '✓' : '✗', label)
  end

  def self.grp?(e)
    (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && !e.deleted?
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.tag_of(e)
    e.layer.name rescue '?'
  end

  def self.ten_hoac(e, mac_dinh)
    n = e.name.to_s.strip
    n.empty? ? mac_dinh : n.sub(/\A__/, '')
  end

  def self.cat(s, n)
    t = s.to_s
    t.length <= n ? t : (t[0, n - 1] + '…')
  end

  def self.indent(str, n = 5)
    pad = ' ' * n
    str.to_s.split("\n").map { |l| pad + l }.join("\n")
  end

end

SoSanhRanhTag.run
