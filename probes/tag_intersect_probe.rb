# encoding: UTF-8
# DÒ TAG CỦA DẤU _ABF_Intersect — script chỉ ĐỌC, không sửa gì trong model.
#
# Vì sao có file này (27/07/2026): Khoa mở file đã làm rãnh hậu bằng ABF, nhưng
# dashboard vẫn báo đỏ "2 tấm đâm xuyên chưa khoét". Entity Info của dấu đó cho
# thấy group `_ABF_Intersect` đeo tag **`ABF_Groove`**, trong khi
# `kiem_tra_lien_ket/main.rb:323` chỉ nhận rãnh hậu khi tag khớp `/phayranhhau/i`.
#
# Trước khi nới luật nhận diện phải BIẾT CHẮC `ABF_Groove` là tag riêng của rãnh
# hậu hay là tag CHUNG cho mọi loại rãnh (hậu / ngàm / led). Nới sai kiểu "cái gì
# cũng là rãnh hậu" thì tool im lặng cả khi thiếu thật — bỏ sót nguy hơn báo thừa.
#
# Cách chạy: Window → Ruby Console → dán
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/tag_intersect_probe.rb'

module TagIntersectProbe

  NEST_HINT = '__ABF_Nesting'.freeze

  def self.run
    rows = Hash.new(0)
    walk(Sketchup.active_model.entities, 0, rows)
    puts '=' * 72
    puts 'DẤU _ABF_Intersect TÌM ĐƯỢC (bỏ qua nhánh nesting):'
    puts '=' * 72
    if rows.empty?
      puts '(không thấy group nào tên chứa "intersect")'
    else
      rows.sort_by { |_, v| -v }.each { |k, v| puts format('%4d x   %s', v, k) }
    end
    puts '=' * 72
    puts "Tổng: #{rows.values.inject(0) { |s, v| s + v }} dấu, #{rows.size} kiểu tag khác nhau."
    nil
  end

  def self.walk(entities, depth, rows)
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.name.to_s.include?(NEST_HINT)
      sub = ents_of(e)
      next unless sub
      if e.name.to_s =~ /intersect/i
        tag_group = (e.layer.name rescue '?')
        tag_edge  = sub.grep(Sketchup::Edge).map { |x| x.layer.name rescue '?' }.uniq.sort.join('|')
        tag_edge  = '(không có edge)' if tag_edge.empty?
        n_face    = sub.grep(Sketchup::Face).size
        rows["ten='#{e.name}'  tag_GROUP='#{tag_group}'  tag_EDGE='#{tag_edge}'  face=#{n_face}"] += 1
      end
      walk(sub, depth + 1, rows)
    end
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

TagIntersectProbe.run
