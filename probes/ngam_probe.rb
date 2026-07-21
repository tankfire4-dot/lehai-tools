# ============================================================
#  DÒ CHẨN ĐOÁN — liet ke moi "thieu ngam" de phan loai (khau tay? khung? that?)
#  Chay:  Window > Ruby Console >
#         load 'C:/Users/tankf/Desktop/claude_work/ngam_probe.rb'
#  Dan toan bo cho Claude.
# ============================================================
load 'C:/Users/tankf/Desktop/claude_work/lehai-tools/LeHai_Tools/kiem_tra_lien_ket/main.rb'

module TK_NgamProbe
  def self.run
    planks, inters = TK::JointCheck.collect_all
    joints = TK::JointCheck.find_joints(planks, inters)

    ng_miss = joints.select { |v| v.kind == :ngam && !v.made }
    ng_made = joints.select { |v| v.kind == :ngam && v.made }
    rh_miss = joints.select { |v| v.kind == :ranhhau && !v.made }

    puts ""
    puts "======== THONG KE MOI LIEN KET ========"
    puts "[PROBE] Tong so tam nhan dien: #{planks.size}"
    puts "[PROBE] NGAM: #{ng_miss.size} thieu, #{ng_made.size} da lam"
    puts "[PROBE] RANH HAU: #{rh_miss.size} thieu"
    puts ""
    puts "======== #{ng_miss.size} MOI THIEU NGAM (do an sau mm | ten 2 tam) ========"
    ng_miss.sort_by { |v| v.name_a }.each_with_index do |v, i|
      puts "  #{(i+1).to_s.rjust(3)}. #{v.pen}mm  #{v.name_a.inspect} <-> #{v.name_b.inspect}"
    end
    puts ""
    # Gom theo tu khoa trong ten de thay pattern
    puts "======== GOM THEO TU KHOA (dem moi thieu ngam theo ten) ========"
    kw = Hash.new(0)
    ng_miss.each do |v|
      key = case "#{v.name_a} #{v.name_b}"
            when /giuong/i then 'giuong (giuong)'
            when /hoc keo|hoc_keo|canh hoc/i then 'hoc keo'
            when /tab/i then 'tab dau giuong'
            when /ke tv|ke_tv/i then 'ke tv'
            when /tu bep|bep/i then 'tu bep'
            when /tu giay|tu ao/i then 'tu ao/giay'
            else 'khac'
            end
      kw[key] += 1
    end
    kw.sort_by { |_, n| -n }.each { |k, n| puts "  #{n.to_s.rjust(3)}  #{k}" }
    puts ""
    puts "[PROBE] Xong. Dan toan bo cho Claude."
  end
end

TK_NgamProbe.run
