# encoding: UTF-8
# ============================================================
#  TEST — nhac vang 12mm cho chi tiet CHONG BAY (Khoang Cach)
#
#  Chay — dan DUNG MOT DONG vao Ruby Console:
#    load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/test_chong_bay_12.rb'
#
#  Nap de ban da sua trong kho len ban dang chay. Khong can cai lai .rbz.
#  CHI DOC — khong sua, khong xoa, khong dung gi vao model.
#
#  LUU Y: test nay CAN mot file co NESTING (__ABF_Nesting) va co tag chong bay.
#  File trong / file chua nesting thi probe se noi thang la chua chung minh duoc gi.
# ============================================================

TOOL_KC = 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/LeHai_Tools/kiem_tra_khoang_cach/main.rb'
OUT_KC  = 'C:/Users/tankf/Desktop/agent_lab_khoa/scratch/test_chong_bay_ketqua.txt'

_v = $VERBOSE
$VERBOSE = nil                     # nap de -> Ruby keu "already initialized constant", binh thuong
begin
  load TOOL_KC
ensure
  $VERBOSE = _v
end

module TestChongBay
  S  = TK::SpacingCheck
  MM = 25.4

  def self.run
    d = []
    d << '======== TEST NHAC VANG CHONG BAY 12mm — CHI DOC ========'
    d << "File: #{Sketchup.active_model.title}"
    d << ''
    d << '--- 1. Ban sua da an chua? ---'
    ok = true
    begin
      d << format('  GAP_MM      = %.1f  (nguong DO, giu nguyen 7)',  S::GAP_MM)
      d << format('  GAP_CB_MM   = %.1f  (nguong VANG, phai la 12)',  S::GAP_CB_MM)
      d << "  CB_RE       = #{S::CB_RE.inspect}  (phai la /chongbay/i)"
      ok = false if S::GAP_CB_MM != 12.0
    rescue NameError => e
      d << "  (!) THIEU hang so moi: #{e.message}"
      d << '  (!) Nap de KHONG an -> kiem lai duong dan TOOL_KC o dau file.'
      ket(d); return
    end
    d << '  (!) GAP_CB_MM chua phai 12 -> nap de khong an.' unless ok
    d << ''

    # --- 2. Model co tag chong bay nao khong? ---
    d << '--- 2. Tag chong bay co trong model khong? ---'
    tags_cb = Sketchup.active_model.layers.select { |l| l.name.to_s =~ S::CB_RE }
    if tags_cb.empty?
      d << '  KHONG co tag nao khop /chongbay/i.'
      d << '  -> Nhac vang KHONG THE bat tren file nay, du code dung.'
      d << '  -> Muon thu that: chay plugin Chong Bay tren ban nesting truoc, roi chay lai probe.'
    else
      d << "  Co #{tags_cb.size} tag chong bay:"
      tags_cb.first(15).each { |l| d << "     - #{l.name}" }
      d << "     ... (con #{tags_cb.size - 15} tag nua)" if tags_cb.size > 15
    end
    d << ''

    # --- 3. Co nesting khong? ---
    d << '--- 3. Co ban nesting khong? ---'
    vios = S.scan
    if vios.nil?
      d << "  KHONG tim thay nesting (#{S::NEST_HINT})."
      d << '  -> Check Khoang Cach chi chay tren ban TRAI PHANG sau nesting.'
      d << '  -> Mo file da nesting bang ABF roi chay lai. Chua chung minh duoc gi.'
      ket(d); return
    end
    d << '  Co nesting. Da quet xong.'
    d << ''

    # --- 4. Ket qua: do vs vang ---
    nhac = vios.select { |v| S.nhac?(v) }
    loi  = vios.reject { |v| S.nhac?(v) }
    d << '--- 4. Ket qua quet ---'
    d << format('  LOI DO   (ho < %.0fmm)           : %d cap', S::GAP_MM, loi.size)
    d << format('  NHAC VANG (chong bay, %.0f-%.0fmm): %d cap', S::GAP_MM, S::GAP_CB_MM, nhac.size)
    d << ''

    unless loi.empty?
      d << '  LOI DO:'
      loi.sort_by(&:gap_mm).first(25).each_with_index do |v, i|
        d << format('   %2d. %6.1fmm  [%s]  %s', i + 1, v.gap_mm, v.kind, v.label.to_s)
      end
      d << ''
    end

    if nhac.empty?
      d << '  Khong co nhac vang nao.'
    else
      d << '  NHAC VANG (moi phat sinh tu ban sua nay):'
      nhac.sort_by(&:gap_mm).each_with_index do |v, i|
        d << format('   %2d. %6.1fmm  %s', i + 1, v.gap_mm, v.label.to_s)
      end
      d << '  >>> Kiem tay: bam "Xem" o dong Khoang Cach, vien phai la VANG khong phai DO.'
    end
    d << ''

    # --- 5. Doi chung: co bao nhieu cap nam trong dai 7-12mm NHUNG khong co tag ---
    #     De biet neu Khoa gan tag chong bay cho chung thi se sang bao nhieu cham vang.
    d << '--- 5. Doi chung: cap 7-12mm KHONG mang tag chong bay ---'
    d << '    (neu sau nay gan tag chong bay cho chung, chung se thanh nhac vang)'
    dem = dem_dai_7_12
    if dem.nil?
      d << '    (khong dung lai duoc — bo qua)'
    else
      d << format('    Co %d cap nam trong dai %.0f-%.0fmm ma khong tam nao mang tag chong bay.',
                  dem, S::GAP_MM, S::GAP_CB_MM)
      d << '    Day la so chi de tham khao, KHONG phai loi.'
    end

    d << ''
    d << '--- KET LUAN ---'
    if tags_cb.empty?
      d << '  Chua chung minh duoc nhac vang chay dung: model khong co tag chong bay nao.'
      d << '  Code nap duoc, hang so dung, khong loi cu phap — nhung do la TAT CA nhung gi'
      d << '  test nay chung minh. Muon chac phai co file thuc te co tag chong bay.'
    elsif nhac.empty?
      d << '  Co tag chong bay nhung khong cap nao roi vao dai 7-12mm -> khong co cham vang.'
      d << '  Khong sai, chi la file nay khong phan biet duoc. Xem so o muc 5.'
    else
      d << "  Nhac vang CHAY DUOC: #{nhac.size} cap. Bam Xem kiem mau vien la xong."
    end

    ket(d)
  end

  # dem cap 7-12mm ma khong ben nao mang tag chong bay (dung lai logic quet cua tool)
  def self.dem_dai_7_12
    found = S.find_nest(Sketchup.active_model.entities, Geom::Transformation.new)
    return nil unless found
    nest, t_nest = found
    tong = 0
    S.kids(nest).each do |sheet|
      t_sheet = t_nest * sheet.transformation
      data = S.boards_of(sheet).map do |b|
        segs = []
        S.walk_edges(b, t_sheet * b.transformation, segs)
        { segs: segs, bbox: S.bbox_of(segs), cb: S.chong_bay?(b) }
      end
      data.each_with_index do |a, i|
        ((i + 1)...data.size).each do |j|
          b = data[j]
          next if a[:cb] || b[:cb]
          next if S.aabb_far?(a[:bbox], b[:bbox], S::GAP_CB_INCH)
          dist, = S.min_dist(a[:segs], b[:segs])
          next if dist.nil?
          tong += 1 if dist >= S::GAP_INCH - S::TOL_INCH && dist < S::GAP_CB_INCH - S::TOL_INCH
        end
      end
    end
    tong
  rescue StandardError => e
    nil
  end

  def self.ket(d)
    txt = d.join("\n")
    puts txt
    begin
      File.open(OUT_KC, 'w:UTF-8') { |f| f.write(txt) }
      puts ''
      puts "[OK] Da ghi: #{OUT_KC}"
      puts '[OK] Bao Claude "xong" la du.'
    rescue StandardError => e
      puts "[!] Khong ghi duoc file (#{e.message}) — copy o tren gui Claude."
    end
    nil
  end
end

TestChongBay.run
