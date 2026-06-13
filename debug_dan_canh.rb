# encoding: UTF-8
# Chon tam go truoc, roi chay: load 'C:/Users/tankf/Desktop/lehai_tools/debug_dan_canh.rb'

puts "\n===== DEBUG AUTO DAN CANH ====="

inst = Sketchup.active_model.selection.first
unless inst
  puts "!!! Chua chon gi. Chon tam go truoc roi chay lai."
else
  ents  = inst.respond_to?(:definition) ? inst.definition.entities : inst.entities
  faces = ents.grep(Sketchup::Face)
  large = faces.max_by(&:area)

  puts "Tong so mat: #{faces.size}"

  perp = faces.select { |f| f != large && f.normal.dot(large.normal).abs < 0.3 }
  puts "Mat vuong goc (ung vien dan canh): #{perp.size}"

  straight = perp.reject { |f| f.edges.any? { |e| e.curve } }
  curved   = perp.select { |f| f.edges.any? { |e| e.curve } }
  puts "  Mat thang: #{straight.size}"
  puts "  Mat cong (co arc edge): #{curved.size}"

  if curved.any?
    puts "\n  Chi tiet curve per mat:"
    curved.each_with_index do |f, i|
      cids = f.edges.map(&:curve).compact.map(&:entityID).uniq
      puts "    Mat cong #{i+1}: curve IDs=#{cids.inspect}"
    end

    groups = MyStudio::AutoEdgeBand.group_arc_faces(curved)
    puts "\n  Nhom cung sau khi gom (BFS): #{groups.size}"
    groups.each_with_index { |g, i| puts "    Nhom #{i+1}: #{g.size} mat" }
  end

  cam    = Sketchup.active_model.active_view.camera
  cdir   = cam.direction
  ceye   = cam.eye
  xform  = inst.transformation

  puts "\nKiem tra visibility tung mat thang:"
  straight.each_with_index do |f, i|
    vis = MyStudio::AutoEdgeBand.face_visible_from_camera?(f, xform, cdir, ceye, Sketchup.active_model)
    puts "  Mat thang #{i+1}: normal=#{f.normal.to_a.map{|v| v.round(2)}.inspect}  visible=#{vis}"
  end

  if curved.any?
    groups = MyStudio::AutoEdgeBand.group_arc_faces(curved)
    puts "\nKiem tra visibility tung nhom cung:"
    groups.each_with_index do |group, i|
      vis_any = group.any? { |f| MyStudio::AutoEdgeBand.face_visible_from_camera?(f, xform, cdir, ceye, Sketchup.active_model) }
      vis_count = group.count { |f| MyStudio::AutoEdgeBand.face_visible_from_camera?(f, xform, cdir, ceye, Sketchup.active_model) }
      puts "  Nhom #{i+1} (#{group.size} mat): #{vis_count} mat visible --> Dan ca nhom? #{vis_any}"
    end
  end
end

puts "===== XONG =====\n"
