# encoding: UTF-8
# =============================================================================
#  MO XE DAU TRONG __ABF_Nesting — so dau PLUGIN minh vs dau ABF THAT (rãnh hậu
#  Khoa vua them), tim khac biet co the lam DXF rot LAYER0. Chi DOC, khong sua.
#
#  Da biet (17/09): edge trong nesting VAN mang tag dung (ABF_PHAYDAUMONG_K,
#  ABF_PHAYRANHHAU10LY); group _ABF_Intersect deo Untagged la binh thuong (ABF
#  that cung vay). Nhung vao Aspire lai LAYER0. Nghi van CUOI: exporter DXF cua
#  ABF chi ghi layer nao ABF DA DANG KY (co attribute rieng tren doi tuong Layer);
#  layer minh `model.layers.add(...)` tro trui -> exporter bo -> LAYER0.
#
#  Probe in 2 phan:
#    A. SOI ATTRIBUTE CUA LAYER — layer ABF that co dictionary gi, layer minh co khong.
#    B. MO XE tung dau trong nesting — group tag / edge tag / ABF dict, de so tay
#       dau ABF THAT (rãnh hậu vua them) vs dau MINH.
#
#  CACH CHAY (file da nest): Window > Ruby Console >
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/soi_nesting_dau.rb'
# =============================================================================

module SoiNestingDau

  NEST = '__ABF_Nesting'.freeze
  MAX_DEPTH = 60
  # Layer minh quan tam: ho ABF + tag rãnh/phay/ngam.
  LAYER_RE = /^_?ABF_|phaydaumong|phayranhhau|groove|ngam|phayled/i.freeze
  MARK_RE  = /intersect|groove|phayranhhau|phaydaumong|ngam|hingecup|edgeband|_abf_label/i.freeze

  def self.run
    soi_layer
    soi_dau_nesting
    puts '=' * 88
    puts 'DOC: so dong "group tag / edge tag / ABF-dict" cua dau ABF THAT (rãnh hậu Khoa'
    puts 'vua them) vs dau MINH. Va xem phan A: layer ABF that co dictionary ma layer minh'
    puts 'thieu khong. Khac o dau -> do la manh moi cho khau DXF.'
    puts '=' * 88
    nil
  end

  # ---- A. attribute tren doi tuong LAYER --------------------------------------
  def self.soi_layer
    puts ''
    puts '=' * 88
    puts 'A) ATTRIBUTE CUA LAYER (ABF co danh dau layer cua no khong? layer minh co khong?)'
    puts '=' * 88
    Sketchup.active_model.layers.each do |lay|
      next unless lay.name =~ LAYER_RE
      puts "• #{lay.name}"
      dd = (lay.attribute_dictionaries rescue nil)
      if dd_empty?(dd)
        puts '     (KHONG co dictionary — layer tro trui)'
      else
        dd.each do |d|
          puts "     [#{d.name}]"
          d.keys.each { |k| puts format('        %-20s = %s', k, (d[k] rescue nil).inspect) }
        end
      end
    end
  end

  # ---- B. mo xe tung dau trong nesting ----------------------------------------
  def self.soi_dau_nesting
    rows = []
    walk(Sketchup.active_model.entities, 0, false, '(goc)', rows)
    puts ''
    puts '=' * 88
    puts "B) TUNG DAU TRONG __ABF_Nesting (#{rows.size} dau) — group tag | edge tag | ABF dict"
    puts '=' * 88
    if rows.empty?
      puts '   (khong thay dau nao trong nesting — da nest chua?)'
      return
    end
    rows.each_with_index do |r, i|
      puts format('%3d. [tấm %s] name=%-16s  group-tag=%s', i + 1, r[:sheet], cat(r[:name], 16), r[:gtag].inspect)
      puts format('     edge-tag: %s', bang(r[:etags]))
      puts format('     ABF-dict: %s', r[:abf].empty? ? '(khong co)' : r[:abf].map { |k, v| "#{k}=#{v.inspect}" }.join('  '))
    end
  end

  def self.walk(entities, depth, in_nest, sheet, rows)
    return if depth > MAX_DEPTH || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      name = e.name.to_s
      nest = in_nest || name.include?(NEST)
      sub  = ents_of(e)
      # ten tam: group con truc tiep cua nesting, ket thuc "-sheet-N"
      cur_sheet = sheet
      cur_sheet = kts(name) if name =~ /sheet-\d+/i

      if nest && name =~ MARK_RE
        rows << mo_xe(e, sub, cur_sheet)
        # dau la la, khong di sau nua
        next
      end
      walk(sub, depth + 1, nest, cur_sheet, rows)
    end
  end

  def self.mo_xe(e, sub, sheet)
    etags = Hash.new(0)
    (sub || []).grep(Sketchup::Edge).each { |x| etags[lay(x)] += 1 }
    { sheet: sheet, name: kts(e.name.to_s), gtag: lay(e), etags: etags, abf: abf(e) }
  end

  # ---- tien ich ---------------------------------------------------------------
  def self.abf(e)
    d = (e.attribute_dictionary('ABF') rescue nil)
    return {} unless d
    h = {}; d.keys.each { |k| h[k] = (d[k] rescue nil) }; h
  end

  def self.dd_empty?(dd)
    dd.nil? || (dd.respond_to?(:to_a) && dd.to_a.empty?)
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

  def self.lay(e)
    e.layer.name rescue '?'
  end

  def self.bang(h)
    return '(khong co edge)' if h.empty?
    h.sort_by { |_, v| -v }.map { |k, v| "#{v}×#{k}" }.join('  ')
  end

  def self.kts(s)
    t = s.to_s.strip.sub(/\A_+/, '')
    t.empty? ? '(khong ten)' : t
  end

  def self.cat(s, n)
    t = s.to_s
    t.length <= n ? t : (t[0, n - 1] + '…')
  end

end

SoiNestingDau.run
