# ============================================================
#  DÒ CHẨN ĐOÁN — hiểu dấu vết "phay rãnh hậu" mà ABF để lại.
#  Chay:  Window > Ruby Console >
#         load 'C:/Users/tankf/Desktop/claude_work/ranh_hau_probe.rb'
#  In ra: moi group co ten "_ABF_Intersect" hoac tag chua "PHAYRANHHAU" ->
#         ten, tag, group CHA no nam trong, vi tri + kich thuoc (mm).
#  Bo qua nhanh nesting. Dan toan bo ket qua cho Claude.
# ============================================================
module TK_RanhHauProbe
  NEST = '__ABF_Nesting'
  MM   = 25.4

  CORNERS = [[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]]

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.tag_of(e)
    e.layer.name rescue ''
  end

  # world bbox (mm) tu chinh cac face cua e (1 cap), fallback: dung e.bounds
  def self.world_info(e, te)
    bb = Geom::BoundingBox.new
    ents = ents_of(e)
    ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) } if ents
    if bb.empty?
      c = te * e.bounds.center
      return ["center=(#{(c.x*MM).round(1)},#{(c.y*MM).round(1)},#{(c.z*MM).round(1)})",
              "size=(? — khong co face rieng)"]
    end
    mn = bb.min; mx = bb.max
    pts = CORNERS.map do |cx,cy,cz|
      p = Geom::Point3d.new(cx.zero? ? mn.x : mx.x, cy.zero? ? mn.y : mx.y, cz.zero? ? mn.z : mx.z)
      te * p
    end
    wbb = Geom::BoundingBox.new
    pts.each { |p| wbb.add(p) }
    c = wbb.center
    ["center=(#{(c.x*MM).round(1)},#{(c.y*MM).round(1)},#{(c.z*MM).round(1)})",
     "size=(#{(wbb.width*MM).round(1)} x #{(wbb.height*MM).round(1)} x #{(wbb.depth*MM).round(1)})"]
  end

  def self.run
    model = Sketchup.active_model
    hits = []
    tags = Hash.new(0)
    walk(model.entities, Geom::Transformation.new, 0, '(model)', hits, tags)

    puts ""
    puts "======== DẤU VẾT PHAY RÃNH HẬU ========"
    puts "[PROBE] Tim thay #{hits.size} group Intersect/PhayRanhHau:"
    hits.each_with_index do |h, i|
      puts "  ##{i+1}  name=#{h[:name].inspect}  tag=#{h[:tag].inspect}"
      puts "        nam trong CHA: #{h[:parent].inspect}"
      puts "        #{h[:c]}  #{h[:s]}"
    end
    puts ""
    puts "[PROBE] Cac tag (layer) co chu 'ABF' gap trong model + so luong:"
    tags.select { |k,_| k =~ /abf/i }.sort.each { |k,v| puts "        #{k.inspect} : #{v}" }
    puts ""
    puts "[PROBE] Xong. Dan toan bo cho Claude."
  end

  def self.walk(entities, t, depth, parent, hits, tags)
    return if depth > 40
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.name.to_s.include?(NEST)
      te  = t * e.transformation
      tag = tag_of(e)
      tags[tag] += 1 unless tag.to_s.empty?
      nm  = e.name.to_s
      if nm =~ /intersect/i || nm =~ /phayranhhau/i || tag =~ /phayranhhau/i
        c, s = world_info(e, te)
        hits << { name: nm, tag: tag, parent: parent, c: c, s: s }
      end
      ents = ents_of(e)
      walk(ents, te, depth + 1, (nm.empty? ? parent : nm), hits, tags) if ents
    end
  end
end

TK_RanhHauProbe.run
