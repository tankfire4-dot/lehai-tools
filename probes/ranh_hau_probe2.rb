# ============================================================
#  DÒ CHẨN ĐOÁN #2 — do "cap tam an nhau" de chon nguong dung cho rãnh hậu.
#  Chay:  Window > Ruby Console >
#         load 'C:/Users/tankf/Desktop/claude_work/ranh_hau_probe2.rb'
#  KHONG ket luan gi — chi DEM va ve PHAN BO do an sau, va doi chieu voi
#  cac diem ABF da lam, de Claude chon nguong + danh gia do nhieu.
#  Dan toan bo ket qua cho Claude.
# ============================================================
module TK_RanhHauProbe2
  NEST      = '__ABF_Nesting'
  MM        = 25.4
  MIN_TH_MM = 3.0
  MAX_TH_MM = 40.0
  MIN_SIDE  = 40.0
  NEAR_MM   = 25.0    # nới vùng giao khi tìm Intersect (mm)

  CORNERS = [[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]]

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.tag_of(e) e.layer.name rescue '' end

  # world AABB tu face rieng cua e -> [minx,miny,minz,maxx,maxy,maxz] (inch) hoac nil
  def self.world_aabb(ents, te)
    bb = Geom::BoundingBox.new
    ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
    return nil if bb.empty?
    mn = bb.min; mx = bb.max
    wbb = Geom::BoundingBox.new
    CORNERS.each do |cx,cy,cz|
      p = Geom::Point3d.new(cx.zero? ? mn.x : mx.x, cy.zero? ? mn.y : mx.y, cz.zero? ? mn.z : mx.z)
      wbb.add(te * p)
    end
    [wbb.min.x, wbb.min.y, wbb.min.z, wbb.max.x, wbb.max.y, wbb.max.z]
  end

  def self.collect(entities, t, depth, planks, inters)
    return if depth > 40
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.name.to_s.include?(NEST)
      te   = t * e.transformation
      ents = ents_of(e)
      tag  = tag_of(e)
      nm   = e.name.to_s

      # ghi nhan diem ABF Intersect (theo tag)
      if nm =~ /intersect/i && ents
        ab = world_aabb(ents, te)
        if ab
          cx = (ab[0]+ab[3])/2; cy = (ab[1]+ab[4])/2; cz = (ab[2]+ab[5])/2
          kind = tag =~ /phayranhhau/i ? :ranhhau : (tag =~ /ngam/i ? :ngam : :other)
          inters << { kind: kind, c: [cx,cy,cz] }
        end
      end

      # ghi nhan tam van
      if ents
        ab = world_aabb(ents, te)
        if ab
          dims = [ab[3]-ab[0], ab[4]-ab[1], ab[5]-ab[2]].sort
          th = dims[0]*MM; mid = dims[1]*MM; big = dims[2]*MM
          if th >= MIN_TH_MM && th <= MAX_TH_MM && mid >= MIN_SIDE && big >= MIN_SIDE
            planks << { name: nm.sub(/\A__/,''), aabb: ab }
          end
        end
      end

      collect(ents, te, depth+1, planks, inters) if ents
    end
  end

  # do chong 1 truc
  def self.ov(a0,a1,b0,b1)
    lo = a0 > b0 ? a0 : b0
    hi = a1 < b1 ? a1 : b1
    hi - lo   # >0 la chong, <=0 la roi
  end

  def self.run
    model = Sketchup.active_model
    planks = []; inters = []
    t0 = Time.now
    collect(model.entities, Geom::Transformation.new, 0, planks, inters)
    puts ""
    puts "======== DO CAP TAM AN NHAU ========"
    puts "[PROBE2] So tam van: #{planks.size}   |  So diem Intersect: #{inters.size}"
    ranhhau_pts = inters.select { |x| x[:kind] == :ranhhau }
    ngam_pts    = inters.select { |x| x[:kind] == :ngam }
    puts "[PROBE2] Diem rãnh hậu: #{ranhhau_pts.size}  |  Diem ngàm: #{ngam_pts.size}"

    # sort theo minX de sweep cho nhanh
    planks.sort_by! { |p| p[:aabb][0] }
    n = planks.size
    hist_all = Hash.new(0)
    hist_rh  = Hash.new(0)
    missing  = []   # cap penetration ~10 ma KHONG co diem rãnh hậu gan

    i = 0
    while i < n
      a = planks[i]; ax1 = a[:aabb][3]
      j = i + 1
      while j < n
        b = planks[j]
        break if b[:aabb][0] > ax1   # da sort minX -> khong the giao nua
        ox = ov(a[:aabb][0], a[:aabb][3], b[:aabb][0], b[:aabb][3])
        if ox > 0
          oy = ov(a[:aabb][1], a[:aabb][4], b[:aabb][1], b[:aabb][4])
          if oy > 0
            oz = ov(a[:aabb][2], a[:aabb][5], b[:aabb][2], b[:aabb][5])
            if oz > 0
              pen_mm = ([ox, oy, oz].min * MM)
              pr = pen_mm.round
              hist_all[pr] += 1 if pr <= 40
              # tam giao (world) center
              gx = ([a[:aabb][0],b[:aabb][0]].max + [a[:aabb][3],b[:aabb][3]].min)/2
              gy = ([a[:aabb][1],b[:aabb][1]].max + [a[:aabb][4],b[:aabb][4]].min)/2
              gz = ([a[:aabb][2],b[:aabb][2]].max + [a[:aabb][5],b[:aabb][5]].min)/2
              near = NEAR_MM / MM
              has_rh = ranhhau_pts.any? do |ic|
                (ic[:c][0]-gx).abs < near && (ic[:c][1]-gy).abs < near && (ic[:c][2]-gz).abs < near
              end
              hist_rh[pr] += 1 if has_rh && pr <= 40
              if pr >= 7 && pr <= 12 && !has_rh
                has_ngam = ngam_pts.any? do |ic|
                  (ic[:c][0]-gx).abs < near && (ic[:c][1]-gy).abs < near && (ic[:c][2]-gz).abs < near
                end
                missing << { a: a[:name], b: b[:name], pen: pen_mm.round(1), ngam: has_ngam } if missing.size < 40
              end
            end
          end
        end
        j += 1
      end
      i += 1
    end

    puts ""
    puts "[PROBE2] PHAN BO do an sau (mm) — TAT CA cap an nhau:"
    (1..40).each { |mm| puts "   #{mm.to_s.rjust(2)}mm : #{'#'*[hist_all[mm],80].min} #{hist_all[mm]}" if hist_all[mm] > 0 }
    puts ""
    puts "[PROBE2] PHAN BO do an sau (mm) — cap CO diem rãnh hậu gan (da lam):"
    (1..40).each { |mm| puts "   #{mm.to_s.rjust(2)}mm : #{'#'*[hist_rh[mm],80].min} #{hist_rh[mm]}" if hist_rh[mm] > 0 }
    puts ""
    puts "[PROBE2] Cap an sau 7-12mm ma KHONG thay diem rãnh hậu (toi da 40):"
    if missing.empty?
      puts "   (khong co)"
    else
      missing.each_with_index do |m, k|
        note = m[:ngam] ? '  [co diem NGAM gan -> lien ket kieu khac, KHONG phai loi]' : '  [khong co lien ket nao -> nghi THIEU that]'
        puts "   #{k+1}. #{m[:pen]}mm  #{m[:a].inspect} <-> #{m[:b].inspect}#{note}"
      end
    end
    puts ""
    puts "[PROBE2] Xong sau #{(Time.now - t0).round(1)}s. Dan toan bo cho Claude."
  end
end

TK_RanhHauProbe2.run
