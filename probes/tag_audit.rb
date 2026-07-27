# encoding: UTF-8
# SỔ ĐO TAG ABF — chạy ở TỪNG MỐC của một dự án CNC làm từ đầu tới cuối.
# Script chỉ ĐỌC model, không sửa gì. Nó ghi thêm (append) vào `tag_audit.txt`
# nằm cạnh file này, để cuối buổi có một sổ so được các mốc với nhau.
#
# Vì sao cần (27/07/2026): 16 module trong bộ tool dựa vào TÊN group `_ABF_*`,
# 3 module dựa vào TÊN TAG — mà chưa ai đo đủ một lần nào ABF thật sự đẻ ra cái
# gì ở mỗi bước. Hôm nay mới lòi ra một chỗ: `kiem_tra_lien_ket` chờ tag
# `...PHAYRANHHAU...` trong khi ABF chỉ còn đẻ `ABF_Groove`, nên báo đỏ oan một
# file phay tử tế. Đo một lượt cho hết, rồi chốt thành bảng trong
# `agent_lab_khoa/shared-notes/sketchup-api.md`.
#
# ── CÁCH DÙNG ─────────────────────────────────────────────────────────
#   Window → Ruby Console, nạp một lần đầu buổi:
#     load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/probes/tag_audit.rb'
#
#   Rồi SAU MỖI BƯỚC làm, gõ một dòng (tên mốc gõ tự do, tiếng Việt cũng được):
#     TagAudit.snap 'vua dung xong 3D, chua lam gi'
#     TagAudit.snap 'sau khi dan canh'
#     TagAudit.snap 'sau khi khoan ban le'
#     TagAudit.snap 'sau khi phay ranh hau'
#     TagAudit.snap 'sau khi lam ngam'
#     TagAudit.snap 'sau khi phay ranh led'
#     TagAudit.snap 'sau khi chong bay'
#     TagAudit.snap 'sau khi nesting'
#
#   Càng nhiều mốc càng tốt — cái đắt nhất là biết dấu nào SINH RA ở BƯỚC NÀO.
#   Cuối buổi đưa Claude file `probes/tag_audit.txt`.

module TagAudit

  NEST_HINT = '__ABF_Nesting'.freeze
  MM        = 25.4
  OUT       = File.join(File.dirname(__FILE__), 'tag_audit.txt').freeze

  # Đo cả cái KHÔNG tên ABF nhưng CÓ tag — tag lạ cũng là dữ liệu.
  def self.dang_quan_tam?(name, tag_g, tag_e)
    return true if name =~ /abf/i
    return true if co_tag?(tag_g) || co_tag?(tag_e)
    false
  end

  def self.co_tag?(t)
    s = t.to_s.strip
    !s.empty? && s !~ /\A(layer0|untagged)\z/i
  end

  def self.snap(moc = '(không đặt tên mốc)')
    rows = {}
    walk(Sketchup.active_model.entities, Geom::Transformation.new, 0, false, rows)
    dong = render(moc, rows)
    puts dong
    begin
      File.open(OUT, 'a:UTF-8') { |f| f.puts dong }
      puts "→ đã ghi thêm vào #{OUT}"
    rescue => e
      # nuốt được: ghi sổ hỏng thì phần in ra Console vẫn còn, không mất dữ liệu
      puts "(không ghi được file: #{e.message} — cứ chép phần in ở trên là đủ)"
    end
    nil
  end

  def self.walk(entities, t, depth, trong_nest, rows)
    return if depth > 40 || entities.nil?
    entities.each do |e|
      next if e.deleted?
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      sub = ents_of(e)
      next unless sub
      te     = t * e.transformation
      name   = e.name.to_s
      in_n   = trong_nest || name.include?(NEST_HINT)
      tag_g  = (e.layer.name rescue '?')
      tag_e  = sub.grep(Sketchup::Edge).map { |x| x.layer.name rescue '?' }.uniq.sort.join('|')

      if dang_quan_tam?(name, tag_g, tag_e)
        key = [in_n ? 'NESTING' : '3D', name, tag_g, (tag_e.empty? ? '(không edge)' : tag_e),
               sub.grep(Sketchup::Face).size]
        r = rows[key] ||= { n: 0, day: [] }
        r[:n] += 1
        d = chieu_nho_nhat_mm(sub, te)
        r[:day] << d if d
      end

      walk(sub, te, depth + 1, in_n, rows)
    end
  end

  # chiều NHỎ NHẤT của hộp bao (mm) — với rãnh thì đây xấp xỉ độ sâu/bề rộng,
  # con số giúp phân biệt rãnh hậu (~10) với ngàm (~17,5) khi tag giống nhau.
  def self.chieu_nho_nhat_mm(ents, te)
    bb = Geom::BoundingBox.new
    ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) || c.is_a?(Sketchup::Edge) }
    return nil if bb.empty?
    mn = bb.min; mx = bb.max
    wbb = Geom::BoundingBox.new
    [0, 1].each do |cx|
      [0, 1].each do |cy|
        [0, 1].each do |cz|
          wbb.add(te * Geom::Point3d.new(cx.zero? ? mn.x : mx.x,
                                         cy.zero? ? mn.y : mx.y,
                                         cz.zero? ? mn.z : mx.z))
        end
      end
    end
    [wbb.max.x - wbb.min.x, wbb.max.y - wbb.min.y, wbb.max.z - wbb.min.z].min * MM
  end

  def self.render(moc, rows)
    s = []
    s << ''
    s << '=' * 96
    s << "MỐC: #{moc}"
    s << "Lúc: #{Time.now.strftime('%d/%m/%Y %H:%M:%S')}   ·   File: #{ten_file}"
    s << '=' * 96
    if rows.empty?
      s << '(không thấy dấu ABF nào, cũng không thấy tag lạ nào)'
    else
      s << format('%-8s %4s  %-22s %-18s %-18s %5s  %s', 'KHU', 'SL', 'TÊN GROUP', 'TAG Ở GROUP', 'TAG Ở EDGE', 'FACE', 'CHIỀU NHỎ NHẤT (mm)')
      s << '-' * 96
      rows.sort_by { |k, v| [k[0], -v[:n], k[1]] }.each do |k, v|
        khu, name, tag_g, tag_e, nface = k
        day = v[:day]
        dm  = if day.empty? then '—'
              elsif (day.max - day.min) < 0.2 then format('%.1f', day.first)
              else format('%.1f – %.1f', day.min, day.max)
              end
        s << format('%-8s %4d  %-22s %-18s %-18s %5d  %s', khu, v[:n], cat(name, 22), cat(tag_g, 18), cat(tag_e, 18), nface, dm)
      end
    end
    s << '-' * 96
    s << "Tổng: #{rows.values.inject(0) { |a, v| a + v[:n] }} dấu · #{rows.size} kiểu khác nhau."
    s.join("\n")
  end

  def self.cat(s, n)
    t = s.to_s
    t.length <= n ? t : (t[0, n - 1] + '…')
  end

  def self.ten_file
    p = Sketchup.active_model.path.to_s
    p.empty? ? '(chưa lưu)' : File.basename(p)
  end

  def self.ents_of(e)
    if e.is_a?(Sketchup::Group)                then e.entities
    elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
    end
  end

end

puts 'TagAudit nạp xong. Sau mỗi bước làm, gõ:   TagAudit.snap \'ten moc\''
puts "Sổ ghi vào: #{TagAudit::OUT}"
