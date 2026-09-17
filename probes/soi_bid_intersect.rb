# encoding: UTF-8
# =============================================================================
#  SOI intersect-group-b-id — dau ABF THAT tro sang tam KHAC, dau MINH tu tro
#  chinh no? Xac nhan gia thuyet truoc khi sua plugin. Chi DOC mo hinh 3D.
#
#  Da biet (17/09): vao DXF, rãnh hậu ABF that -> layer ABF_PHAYRANHHAU10LY,
#  con dau minh (cung tag) -> LAYER0. Nghi: ABF chi cong nhan intersect la CAP
#  A<->B (b-id tro tam doi tac that). Plugin minh dat b-id = persistent_id CUA
#  CHINH tam no -> tu tro -> ABF khong cong nhan.
#
#  Probe: voi moi _ABF_Intersect o 3D (bo nhanh nesting), in:
#    - tam CHU (host) no nam trong        : pid + ten
#    - intersect-group-b-id tro toi        : pid + ten tam (neu giai duoc)
#    - SELF (tro chinh host) hay OTHER (tam khac)
#    - setting-name (de biet dau THAT vs dau MINH)
#
#  CACH CHAY: Window > Ruby Console >
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/soi_bid_intersect.rb'
# =============================================================================

module SoiBidIntersect

  NEST = '__ABF_Nesting'.freeze
  MAX_DEPTH = 60

  def self.run
    model = Sketchup.active_model
    @pid2name = {}
    index_pids(model.entities, 0)          # pass 1: pid -> ten moi group

    rows = []
    walk(model.entities, 0, nil, nil, rows) # pass 2: tim intersect + host

    puts ''
    puts '=' * 92
    puts "intersect-group-b-id CUA TUNG _ABF_Intersect (bo nhanh nesting) — #{rows.size} dau"
    puts '=' * 92
    if rows.empty?
      puts '   (khong thay _ABF_Intersect nao o 3D)'
      return nil
    end
    rows.each_with_index do |r, i|
      target = @pid2name[r[:bid]] || '(khong giai duoc / khong phai group)'
      kind = r[:bid] == r[:host_pid] ? '*** SELF (tu tro chinh no) ***' : 'OTHER (tro tam khac)'
      puts format('%2d. setting=%-20s', i + 1, r[:setting].inspect)
      puts format('    host  = pid %-8s  %s', r[:host_pid].to_s, r[:host_name])
      puts format('    b-id  = pid %-8s  %s', r[:bid].to_s, target)
      puts format('    => %s', kind)
    end
    puts '=' * 92
    puts 'KY VONG: dau ABF THAT = OTHER; dau MINH = SELF. Neu dung vay, sua plugin cho'
    puts 'b-id tro sang tam DOI TAC (phay dau mong -> tam nhan; mong am -> tam dung).'
    puts '=' * 92
    nil
  end

  def self.index_pids(entities, depth)
    return if depth > MAX_DEPTH || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.name.to_s.include?(NEST)
      @pid2name[e.persistent_id] = ten(e) rescue nil
      index_pids(ents_of(e), depth + 1)
    end
  end

  # host_pid/host_name = group gan nhat bao quanh dau (= tam ChU)
  def self.walk(entities, depth, host_pid, host_name, rows)
    return if depth > MAX_DEPTH || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next if e.name.to_s.include?(NEST)
      if e.name.to_s =~ /intersect/i
        d = (e.attribute_dictionary('ABF') rescue nil)
        rows << {
          setting: d ? d['setting-name'] : nil,
          bid:     d ? d['intersect-group-b-id'] : nil,
          host_pid: host_pid, host_name: host_name || '(khong ro)'
        }
        next
      end
      walk(ents_of(e), depth + 1, e.persistent_id, ten(e), rows)
    end
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.ten(e)
    n = e.name.to_s.strip
    n.empty? ? "(group pid #{e.persistent_id})" : n.sub(/\A_+/, '')
  end

end

SoiBidIntersect.run
