# ============================================================
#  DÒ CHẨN ĐOÁN — đo "dam xuyen goc dac" that su giua 2 tam (khong dung bbox).
#  Muc dich: KIEM xem cach HINH HOC THAT co phan biet duoc "da khau" vs "chua khau"
#  khong — va quan trong: ABF phay ngam co KHOET khoi 3D hay chi dan nhan?
#
#  Chay:  Window > Ruby Console >
#         load 'C:/Users/tankf/Desktop/claude_work/dam_xuyen_probe.rb'
#  Dan toan bo ket qua cho Claude.
# ============================================================
module TK_DamXuyenProbe
  NEST = '__ABF_Nesting'
  MM   = 25.4
  MIN_TH = 3.0; MAX_TH = 40.0; MIN_SIDE = 40.0
  NGAM_LO = 15.0; NGAM_HI = 20.0; MID_MAX = 250.0
  NEAR = 25.0 / MM
  N = 4   # luoi lay mau N x N x N diem trong vung giao

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  # ── thu tam van + tam giac (world) + aabb ──
  def self.collect
    planks = []; inters = []
    walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, planks, inters)
    [planks, inters]
  end

  def self.walk(entities, t, depth, in_plank, planks, inters)
    return if depth > 40
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      nm = e.name.to_s
      next if nm.include?(NEST)
      te = t * e.transformation
      ents = ents_of(e)
      next unless ents

      if nm =~ /intersect/i
        c = center_world(ents, te)
        inters << c if c
      end

      is_plank = false
      unless in_plank
        is_plank = register(e, te, ents, planks)
      end
      walk(ents, te, depth + 1, in_plank || is_plank, planks, inters)
    end
  end

  def self.center_world(ents, te)
    bb = Geom::BoundingBox.new
    ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
    return nil if bb.empty?
    p = te * bb.center
    [p.x, p.y, p.z]
  end

  def self.register(e, te, ents, planks)
    faces = ents.grep(Sketchup::Face)
    return false if faces.empty?
    bb = Geom::BoundingBox.new
    faces.each { |f| bb.add(f.bounds) }
    return false if bb.empty?
    dims = [bb.width, bb.height, bb.depth].sort
    th = dims[0] * MM; mid = dims[1] * MM; big = dims[2] * MM
    return false unless th >= MIN_TH && th <= MAX_TH && mid >= MIN_SIDE && big >= MIN_SIDE
    # world aabb + tam giac world
    mn = bb.min; mx = bb.max
    wbb = Geom::BoundingBox.new
    [[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]].each do |cx,cy,cz|
      wbb.add(te * Geom::Point3d.new(cx.zero? ? mn.x : mx.x, cy.zero? ? mn.y : mx.y, cz.zero? ? mn.z : mx.z))
    end
    tris = []
    faces.each do |f|
      mesh = f.mesh
      mesh.polygons.each do |poly|
        idx = poly.map(&:abs)
        next if idx.size < 3
        a = te * mesh.point_at(idx[0]); b = te * mesh.point_at(idx[1]); c = te * mesh.point_at(idx[2])
        tris << [[a.x,a.y,a.z],[b.x,b.y,b.z],[c.x,c.y,c.z]]
      end
    end
    planks << { name: e.name.to_s.sub(/\A__/,''),
                aabb: [wbb.min.x,wbb.min.y,wbb.min.z,wbb.max.x,wbb.max.y,wbb.max.z],
                tris: tris }
    true
  end

  # ── diem P co nam trong khoi dac (tris)? ray +X dem giao le/chan ──
  def self.inside?(px, py, pz, tris)
    cnt = 0
    tris.each do |a, b, c|
      t = ray_x_tri(px, py, pz, a, b, c)
      cnt += 1 if t && t > 1e-7
    end
    cnt.odd?
  end

  # ray tu (px,py,pz) huong +X cat tam giac? tra t (khoang cach) hoac nil
  def self.ray_x_tri(px, py, pz, a, b, c)
    e1 = [b[0]-a[0], b[1]-a[1], b[2]-a[2]]
    e2 = [c[0]-a[0], c[1]-a[1], c[2]-a[2]]
    # d = (1,0,0); h = d x e2 = (0*e2z-0*e2y, 0*e2x-1*e2z, 1*e2y-0*e2x) = (0, -e2z, e2y)
    hx = 0.0; hy = -e2[2]; hz = e2[1]
    aa = e1[0]*hx + e1[1]*hy + e1[2]*hz
    return nil if aa.abs < 1e-12
    ff = 1.0 / aa
    sx = px-a[0]; sy = py-a[1]; sz = pz-a[2]
    u = ff * (sx*hx + sy*hy + sz*hz)
    return nil if u < 0 || u > 1
    # q = s x e1
    qx = sy*e1[2] - sz*e1[1]
    qy = sz*e1[0] - sx*e1[2]
    qz = sx*e1[1] - sy*e1[0]
    # v = f * (d . q) ; d=(1,0,0) -> qx
    v = ff * qx
    return nil if v < 0 || (u+v) > 1
    t = ff * (e2[0]*qx + e2[1]*qy + e2[2]*qz)
    t > 1e-7 ? t : nil
  end

  def self.overlap(a, b)
    lox=[a[0],b[0]].max; hix=[a[3],b[3]].min; return nil if hix-lox<=0
    loy=[a[1],b[1]].max; hiy=[a[4],b[4]].min; return nil if hiy-loy<=0
    loz=[a[2],b[2]].max; hiz=[a[5],b[5]].min; return nil if hiz-loz<=0
    [lox,loy,loz,hix,hiy,hiz]
  end

  # ti le diem nam trong CA HAI tam (do dam xuyen)
  def self.collide_frac(ov, ta, tb)
    inside_both = 0; total = 0
    (0...N).each do |i|
      x = ov[0] + (ov[3]-ov[0])*(i+0.5)/N
      (0...N).each do |j|
        y = ov[1] + (ov[4]-ov[1])*(j+0.5)/N
        (0...N).each do |k|
          z = ov[2] + (ov[5]-ov[2])*(k+0.5)/N
          total += 1
          inside_both += 1 if inside?(x,y,z,ta) && inside?(x,y,z,tb)
        end
      end
    end
    inside_both.to_f / total
  end

  def self.has_inter(ov, inters)
    cx=(ov[0]+ov[3])/2; cy=(ov[1]+ov[4])/2; cz=(ov[2]+ov[5])/2
    hx=(ov[3]-ov[0])/2+NEAR; hy=(ov[4]-ov[1])/2+NEAR; hz=(ov[5]-ov[2])/2+NEAR
    inters.any? { |c| (c[0]-cx).abs<hx && (c[1]-cy).abs<hy && (c[2]-cz).abs<hz }
  end

  def self.run
    t0 = Time.now
    planks, inters = collect
    planks.sort_by! { |p| p[:aabb][0] }
    n = planks.size
    puts "[PROBE] tam=#{n}, intersect=#{inters.size}  (thu tam giac xong sau #{(Time.now-t0).round(1)}s)"

    made = []; miss = []
    i = 0
    while i < n
      a = planks[i]; axhi = a[:aabb][3]
      j = i+1
      while j < n
        b = planks[j]
        break if b[:aabb][0] > axhi
        ov = overlap(a[:aabb], b[:aabb])
        if ov
          dims = [ov[3]-ov[0], ov[4]-ov[1], ov[5]-ov[2]].sort
          pen = dims[0]*MM; mid = dims[1]*MM
          if mid <= MID_MAX && pen >= NGAM_LO && pen <= NGAM_HI
            frac = collide_frac(ov, a[:tris], b[:tris])
            rec = { a: a[:name], b: b[:name], frac: (frac*100).round, made: has_inter(ov, inters) }
            (rec[:made] ? made : miss) << rec
          end
        end
        j += 1
      end
      i += 1
    end

    puts ""
    puts "======== DO DAM XUYEN (%% diem nam trong CA 2 tam) ========"
    puts "  frac CAO = con dam xuyen goc dac = CHUA khau"
    puts "  frac ~0  = da khoet = DA khau (tay hoac ABF)"
    puts ""
    def_hist = lambda do |label, arr|
      puts "-- #{label}: #{arr.size} moi --"
      h = Hash.new(0)
      arr.each { |r| bucket = (r[:frac]/10)*10; h[bucket]+=1 }
      (0..100).step(10).each { |b| puts "   #{b.to_s.rjust(3)}-#{b+9}%%: #{'#'*h[b]} #{h[b]}" if h[b]>0 }
    end
    def_hist.call("Nhom CO dau ABF (dang bao 'da lam')", made)
    def_hist.call("Nhom KHONG dau ABF (dang bao 'thieu')", miss)

    puts ""
    puts "======== VAI VI DU (ten | %%dam xuyen | co ABF?) ========"
    (made+miss).sort_by { |r| -r[:frac] }.first(25).each do |r|
      puts "  #{r[:frac].to_s.rjust(3)}%%  #{r[:made] ? 'ABF' : '---'}  #{r[:a].inspect} <-> #{r[:b].inspect}"
    end
    puts ""
    puts "[PROBE] Xong sau #{(Time.now-t0).round(1)}s. Dan toan bo cho Claude."
  end
end

TK_DamXuyenProbe.run
