# encoding: UTF-8
# =============================================================================
#  SOI LAYER TRONG __ABF_Nesting — cai gi THAT SU ra DXF/Aspire. Chi DOC.
#
#  Van de (17/09/2026): dat tag khac nhau trong SketchUp (ABF_PHAYDAUMONG_K,
#  ABF_PHAYRANHHAU10LY) nhung vao Aspire ca hai deu roi ve LAYER0. Nghi van:
#  ABF KHONG dung tag minh gan de dat layer DXF — no tu dat layer khi NHAN RA
#  thao tac. Bang trai phang de cat la nhanh __ABF_Nesting; DXF xuat tu day.
#  Probe nay dem layer cua tung doan cat trong nesting -> thay dau minh nam dau.
#
#  So sanh 2 tang cho ro:
#    (1) Dau _ABF_Intersect o mo hinh 3D  -> tag + setting-name minh gan.
#    (2) Hinh trong __ABF_Nesting          -> layer THAT ABF sinh ra (ra DXF).
#  Neu (1) co tag rieng ma (2) toan Layer0 => ABF KHONG mang tag minh sang nesting.
#
#  CACH CHAY (mo file DA NEST trong SketchUp): Window > Ruby Console >
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/soi_nesting_layer.rb'
# =============================================================================

module SoiNestingLayer

  NEST = '__ABF_Nesting'.freeze
  MAX_DEPTH = 60

  def self.run
    intersect_3d = Hash.new(0)   # "tag | setting-name" -> so dau _ABF_Intersect ngoai nesting
    nest_layers  = Hash.new(0)   # layer -> so edge trong __ABF_Nesting
    stats = { in_nest: false }

    walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, intersect_3d, nest_layers, stats)

    puts ''
    puts '=' * 84
    puts '1) DAU _ABF_Intersect o MO HINH 3D (tag + setting-name minh gan)'
    puts '=' * 84
    if intersect_3d.empty?
      puts '   (khong thay _ABF_Intersect nao ngoai nesting)'
    else
      intersect_3d.sort.each { |k, v| puts format('%4d x   %s', v, k) }
    end

    puts ''
    puts '=' * 84
    puts "2) LAYER THAT trong __ABF_Nesting (= cai ra DXF/Aspire)#{stats[:in_nest] ? '' : '  — KHONG THAY NHANH NESTING!'}"
    puts '=' * 84
    if nest_layers.empty?
      puts '   (chua nest, hoac nhanh __ABF_Nesting rong)'
    else
      total = nest_layers.values.inject(0) { |s, v| s + v }
      nest_layers.sort_by { |_, v| -v }.each do |k, v|
        puts format('%6d edge (%4.1f%%)   %s', v, 100.0 * v / total, k)
      end
      puts "   -> Tong #{total} edge, #{nest_layers.size} layer."
    end

    puts ''
    puts 'DOC KET QUA:'
    puts '  - Neu (1) co ABF_PHAYDAUMONG_K / ABF_PHAYRANHHAU10LY ma (2) chi co LAYER0'
    puts '    => ABF KHONG mang tag minh sang nesting; layer DXF do ABF tu quyet.'
    puts '  - Neu (2) co layer ten thao tac that (vd ABF_PHAYRANHHAU10LY) cho dau ABF that'
    puts '    nhung dau MINH van Layer0 => ABF khong nhan dau minh la thao tac hop le.'
    puts '=' * 84
    nil
  end

  def self.walk(entities, t, depth, in_nest, intersect_3d, nest_layers, stats)
    return if depth > MAX_DEPTH || entities.nil?
    entities.each do |e|
      next if e.deleted?
      if in_nest && e.is_a?(Sketchup::Edge)
        nest_layers[layer_of(e)] += 1
        next
      end
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      nest = in_nest || e.name.to_s.include?(NEST)
      stats[:in_nest] = true if nest
      if !in_nest && e.name.to_s =~ /intersect/i
        a = (e.attribute_dictionary('ABF') rescue nil)
        setting = a ? a['setting-name'] : nil
        intersect_3d["tag=#{layer_of(e)}  setting-name=#{setting.inspect}"] += 1
      end
      walk(ents_of(e), t, depth + 1, nest, intersect_3d, nest_layers, stats)
    end
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.layer_of(e)
    e.layer.name rescue '?'
  end

end

SoiNestingLayer.run
