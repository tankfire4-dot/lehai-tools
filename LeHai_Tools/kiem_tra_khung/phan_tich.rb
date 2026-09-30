# encoding: UTF-8
# Lõi Soát Khung Tổng Thể — THUẦN RUBY, không gọi SketchUp (thử được ngoài SketchUp).
#
# Đầu vào: kích thước khung + các tấm đã quy về HỆ KHUNG, đơn vị mm:
#   gốc = góc trái-trước-dưới của khung; trục 0 = dài (trái→phải), 1 = sâu (trước→sau),
#   2 = cao (dưới→trên). Mỗi tấm: { id:, ten:, lo: [x,y,z], hi: [x,y,z], cua:, lech_do:,
#   meo_mm:, hinh_la: } — lo/hi là hộp của tấm trong hệ khung; cua = bộ phận DI ĐỘNG (cánh, hộc).
# Đầu ra: danh sách phát hiện, ĐỎ trước (từng dòng), VÀNG sau (gộp nhóm).
#
# Ý chính (Khoa chốt 30/09): lỗi vẽ lệch có dấu hiệu "GẦN BẰNG MÀ KHÔNG BẰNG" — hai mép chênh nhau
# 0,05–3 mm. Chỗ cố ý (ngàm ăn 9 mm, khe cánh 2 mm lặp lại) nằm ngoài cửa sổ đó hoặc lặp đều → VÀNG.
#
# ĐƯỜNG GIÓNG (Khoa thử thật 30/09: báo theo CẶP thì một lỗi tách 3–4 dòng, không biết sửa tấm
# nào, theo trục nào): các mép lệch nhau được gom theo MẶT PHẲNG (đường gióng). Chuẩn = mặt khung
# nếu gióng trùng mặt khung, không thì SỐ ĐÔNG mép nằm ở đó. Tấm lệch khỏi chuẩn = tấm cần sửa,
# kèm lệch bao nhiêu, về phía nào. Một lỗi = một dòng.

module TK
  module FrameCheck
    module PhanTich
      TOL  = 0.05  # mm — chênh dưới mức này coi là TRÙNG (SketchUp tự gộp điểm < 0,0254 mm)
      LE   = 3.0   # mm — chênh từ TOL tới LE = "gần bằng mà không bằng" → nghi vẽ lệch
      XEO0 = 0.01  # độ — tấm lệch trục khung dưới mức này coi như thẳng (sai số máy)
      XEO  = 3.0   # độ — lệch XEO0–XEO = vẽ xéo nhầm (đỏ); từ XEO trở lên coi là cố ý đặt xiên
      LAP  = 3     # khe hở CÙNG số đo lặp ≥ 3 lần trong một tủ → nghi cố ý (khe cánh...) → vàng
      BAM  = 30.0  # mm — cánh/hộc cách thân tủ tới mức này vẫn tính là BÁM (hộc trên ray hở ~13 mm)

      TRUC = %w[dài sâu cao].freeze
      MAT  = [%w[trái phải], %w[trước sau], %w[dưới trên]].freeze

      # Thứ tự dòng đỏ: lỗi tổng thể trước, lỗi từng chỗ sau
      THU_TU = %w[hut loi giong bay cum ho lem xeo meo].freeze

      # ── Điểm vào ────────────────────────────────────────────────
      # kich = [dài, sâu, cao] mm; bo_qua = các khoá người vẽ đã bấm "Đúng rồi, bỏ qua".
      # Trả { 'ds' => [phát hiện], 'so_bo_qua' => n, 'so_tam' => n }
      def self.soat(kich, tams, bo_qua = [])
        do_  = []
        vang = Hash.new { |h, k| h[k] = [] }   # [loại, số đo] → các phát hiện con
        thang = []
        tams.each do |t|
          if t[:lech_do].to_f >= XEO
            vang[['xien', nil]] << don(t, 'xien', "Tấm đặt xiên #{so(t[:lech_do])}°: #{t[:ten]}",
                                       'Tấm xiên không soát tiếp xúc được — tự xem bằng mắt.')
          elsif t[:lech_do].to_f > XEO0
            do_ << don(t, 'xeo', "Tấm xéo #{so(t[:lech_do])}°: #{t[:ten]}",
                       'Tấm lệch trục khung một góc nhỏ — thường do xoay/kéo nhầm. Tấm này bỏ khỏi phép soát tiếp xúc.',
                       so(t[:lech_do]))
          else
            thang << t
          end
          if t[:meo_mm]
            do_ << don(t, 'meo', "Tấm méo #{so(t[:meo_mm])} mm: #{t[:ten]}",
                       "Có mặt lệch khỏi hộp #{so(t[:meo_mm])} mm — tấm không còn vuông thành sắc cạnh.",
                       so(t[:meo_mm]))
          elsif t[:hinh_la]
            vang[['hinh', nil]] << don(t, 'hinh', "Tấm không phải hộp vuông: #{t[:ten]}",
                                       'Tấm cong/khoét — chỉ soát theo hộp bao của tấm.')
          end
        end

        chung = []                               # chứng cứ lệch mép: [trục, mép A, mép B]
        soat_khung(kich, thang, do_, chung)
        soat_cap(thang, do_, vang, chung)
        # Gióng mà MỌI tấm lệch đều là cánh/hộc → vàng (thường là khe chừa cố ý quanh cánh). Soát chéo
        # 30/09 điểm 1: cánh hở 2 mm trên/dưới so với khung bị báo ĐỎ, dashboard chặn xuất DXF oan.
        # Vẫn giữ trong danh sách (vàng) vì hai cánh lệch mép nhau có thể là lỗi thật.
        cua = thang.select { |t| t[:cua] }.map { |t| t[:id] }
        giong(kich, thang, chung).each do |f|
          if (f['tam'] - cua).empty?
            f['muc'] = 'vang'
            vang[['giong_cua', nil]] << f
          else
            do_ << f
          end
        end

        do_.sort_by! { |f| [THU_TU.index(f['loai']) || 99, -f['mm'].to_f] }
        ds = do_ + nhom_vang(vang)
        loc(ds, bo_qua).merge('so_tam' => tams.size)
      end

      # ── Khung: tủ có lấp đúng khung không ───────────────────────
      # Mép tấm = { id:, ten:, mat: 0|1 (mặt thấp/cao của tấm), v: toạ độ }. Mép khung: id nil.
      def self.soat_khung(kich, tams, do_, chung)
        return if tams.empty?
        3.times do |k|
          [0, 1].each do |s|                       # s = 0 mặt thấp (trái/trước/dưới), 1 mặt cao
            bien = s.zero? ? 0.0 : kich[k].to_f
            mat  = MAT[k][s]
            # ra = tấm vượt khỏi mặt khung bao nhiêu (> 0 lồi ra, < 0 còn cách vào trong)
            ra = tams.map { |t| s.zero? ? bien - t[:lo][k] : t[:hi][k] - bien }
            if ra.max < -TOL
              # Không tấm nào chạm mặt này → tủ hụt so với kích thước giao (hoặc khung đặt lệch).
              # Không đưa các mép vào gióng: cả mặt hụt đều nhau là MỘT lỗi, không phải N tấm lệch.
              hut = -ra.max
              gan = tams.each_index.select { |i| (ra[i] - ra.max).abs <= TOL }
              do_ << moi('do', 'hut', "Hụt khung #{so(hut)} mm ở mặt #{mat}",
                         "Không tấm nào chạm mặt #{mat} của khung — tủ thiếu #{so(hut)} mm theo chiều #{TRUC[k]} " \
                         '(hoặc khung đặt lệch).',
                         gan.map { |i| tams[i][:id] }, diem_mat(kich, k, bien), hut, "hut:#{mat}:#{so(hut)}")
              next
            end
            tams.each_with_index do |t, i|
              if ra[i] >= LE
                do_ << don(t, 'loi', "Lồi khỏi khung #{so(ra[i])} mm (mặt #{mat}): #{t[:ten]}",
                           "Tấm vượt ra ngoài mặt #{mat} của khung #{so(ra[i])} mm.", so(ra[i]),
                           diem_tam(t, k, s), "loi:#{mat}")
              elsif ra[i].abs > TOL && ra[i].abs < LE
                # Lồi/thụt lẻ so với mặt khung (mà mặt này có tấm chạm) → chứng cứ gióng, chuẩn = khung
                chung << [k, { id: nil, v: bien }, mep(t, k, s)]
              end
            end
          end
        end
      end

      # ── Từng cặp tấm: dính / hở lẻ / ăn vào nhau + gom chứng cứ lệch mép ──
      def self.soat_cap(tams, do_, vang, chung)
        n = tams.size
        cha = (0...n).to_a                        # hợp-tìm: gom các tấm dính nhau thành cụm
        # Cánh/hộc (di động) KHÔNG đỡ được thân tủ: đợt hở hai đầu mà mép trước chạm lưng cánh vẫn
        # là tấm bay (cánh mở ra là rơi). Nên: thân nối thân, di động nối di động (một bộ hộc là một
        # cụm), thân–di động chỉ đánh dấu "bám".
        bam = {}
        lien = lambda do |i, j|
          ci = tams[i][:cua]
          cj = tams[j][:cua]
          if ci == cj then noi(cha, i, j)
          else bam[ci ? i : j] = true
          end
        end
        khe = []                                  # [i, j, trục, độ hở]
        # Sắp theo mép trái: tấm sau đã cách quá BAM theo chiều dài thì mọi tấm sau nữa cũng xa → dừng
        ord = (0...n).sort_by { |i| tams[i][:lo][0] }
        ord.each_with_index do |i, oi|
          a = tams[i]
          ord[(oi + 1)..-1].each do |j|
            b = tams[j]
            break if b[:lo][0] - a[:hi][0] > BAM
            # g[k] > 0: hai tấm cách nhau g theo trục k · g[k] < 0: chồng lên nhau -g theo trục k
            g = (0..2).map { |k| [a[:lo][k], b[:lo][k]].max - [a[:hi][k], b[:hi][k]].min }
            xa  = (0..2).select { |k| g[k] > TOL }
            cham = (0..2).select { |k| g[k].abs <= TOL }
            chong = (0..2).select { |k| g[k] < -TOL }
            if chong.size == 3
              lien.call(i, j)
              sau = -g.max                          # độ ăn sâu = chiều chồng NHỎ nhất
              if sau < LE
                do_ << cap(a, b, 'lem', "Chồng lẹm #{so(sau)} mm: #{a[:ten]} ↔ #{b[:ten]}",
                           "Hai tấm ăn vào nhau rất ít (#{so(sau)} mm) — thường là vẽ lệch, không phải ngàm.", sau)
              else
                vang[['an', (sau * 2).round / 2.0]] << cap(a, b, 'an', "Ăn vào nhau #{so(sau)} mm: #{a[:ten]} ↔ #{b[:ten]}",
                                                         'Thường là ngàm/rãnh cố ý.', sau)
              end
            elsif cham.size == 1 && chong.size == 2
              lien.call(i, j)                       # áp mặt vào nhau có diện tích = DÍNH
              mep_lech(a, b, chong, chung)
            elsif xa.size == 1 && chong.size == 2 && g[xa[0]] <= LE
              khe << [i, j, xa[0], g[xa[0]]]
              mep_lech(a, b, chong, chung)
              lien.call(i, j) if a[:cua] != b[:cua]  # khe cánh cố ý: cánh vẫn tính là bám tủ
            elsif xa.size == 1 && chong.size == 2 && g[xa[0]] <= BAM && a[:cua] != b[:cua]
              bam[a[:cua] ? i : j] = true           # hộc trên ray: hở ~13 mm với hông vẫn là bám
            elsif xa.empty? && cham.size >= 2
              vang[['canh', nil]] << cap(a, b, 'canh', "Chỉ chạm theo đường: #{a[:ten]} ↔ #{b[:ten]}",
                                         'Hai tấm không áp mặt vào nhau — chỉ chạm ở cạnh/góc.', 0.0)
            end
          end
        end

        dem = Hash.new(0)
        khe.each { |_, _, _, v| dem[v.round(1)] += 1 }
        gan = {}                                  # tấm → khe gần nhất (để nói tấm bay cách ai)
        khe.each do |i, j, k, v|
          a = tams[i]
          b = tams[j]
          [[i, j], [j, i]].each { |p, q| gan[p] = [v, tams[q][:ten]] if gan[p].nil? || v < gan[p][0] }
          f = cap(a, b, 'ho', "Hở #{so(v)} mm: #{a[:ten]} ↔ #{b[:ten]}",
                  "Hai mặt đối nhau gần sát mà không chạm (chiều #{TRUC[k]}).", v)
          if a[:cua] || b[:cua] || dem[v.round(1)] >= LAP
            f['muc'] = 'vang'
            vang[['khe', v.round(1)]] << f
          else
            do_ << f
          end
        end

        # Tấm bay / tủ đứt. Thân: cụm đông nhất là thân tủ, cụm thân khác đều tách rời.
        # Di động (cánh, một bộ hộc): cả cụm phải bám thân ở ít nhất một chỗ.
        cum = (0...n).group_by { |i| goc(cha, i) }.values
        lon = cum.reject { |c| tams[c[0]][:cua] }.max_by(&:size)
        cum.each do |c|
          next if c.equal?(lon)
          di_dong = tams[c[0]][:cua]
          next if di_dong && c.any? { |i| bam[i] }
          ts = c.map { |i| tams[i] }
          chu = di_dong ? 'Cánh/hộc không bám thân tủ' : nil
          if c.size == 1
            t = ts[0]
            ct = gan[c[0]] ? " Gần nhất: hở #{so(gan[c[0]][0])} mm với #{gan[c[0]][1]}." : ''
            do_ << don(t, 'bay', "#{chu || 'Tấm bay'}: #{t[:ten]}", "Không áp mặt vào tấm nào.#{ct}")
          else
            ten = ts.first(4).map { |t| t[:ten] }.join(', ') + (ts.size > 4 ? '…' : '')
            do_ << moi('do', 'cum', "#{chu || 'Tủ đứt'}: cụm #{ts.size} tấm tách rời",
                       "Cụm này không dính vào thân tủ: #{ten}.", ts.map { |t| t[:id] },
                       tam_hop(ts), ts.size, "cum:#{ts.map { |t| t[:id] }.sort.join('-')}")
          end
        end
      end

      # Hai tấm áp/sát nhau: mỗi chiều đang chồng, so 4 cặp mép. Chênh 0,05–3 mm = chứng cứ lệch mép
      # (cặp chéo lo↔hi = một tấm chỉ tì lên tấm kia vài li: mép tấm này phải thẳng mặt tấm kia).
      def self.mep_lech(a, b, chong, chung)
        chong.each do |k|
          [[0, 0], [1, 1], [0, 1], [1, 0]].each do |sa, sb|
            ma = mep(a, k, sa)
            mb = mep(b, k, sb)
            d = (ma[:v] - mb[:v]).abs
            chung << [k, ma, mb] if d > TOL && d < LE
          end
        end
      end

      def self.mep(t, k, s)
        { id: t[:id], ten: t[:ten], mat: s, v: s.zero? ? t[:lo][k] : t[:hi][k] }
      end

      # ── Đường gióng: gom chứng cứ theo mặt phẳng, chọn chuẩn, chỉ ra tấm lệch ──
      def self.giong(kich, tams, chung)
        out = []
        3.times do |k|
          ck = chung.select { |x| x[0] == k }
          next if ck.empty?
          # Nối các toạ độ có chứng cứ với nhau → mỗi cụm toạ độ là MỘT đường gióng
          ids = {}
          cha = []
          khoa = ->(v) { ids[v.round(3)] ||= (cha << cha.size; cha.size - 1) }
          ck.each { |_, a, b| noi(cha, khoa.call(a[:v]), khoa.call(b[:v])) }
          # toạ độ chênh ≤ TOL là CÙNG một chỗ (SketchUp coi như trùng) → một nút
          ids.keys.sort.each_cons(2) { |u, v| noi(cha, ids[u], ids[v]) if v - u <= TOL }
          ck.group_by { |_, a, _| goc(cha, khoa.call(a[:v])) }.each_value do |nhom|
            meps = nhom.flat_map { |_, a, b| [a, b] }
            chuan, theo_khung = chon_chuan(kich, k, tams, meps)
            lech = meps.select { |m| m[:id] && (m[:v] - chuan).abs > TOL }.uniq { |m| [m[:id], m[:mat]] }
            next if lech.empty?
            out << dong_giong(k, chuan, theo_khung, lech, tams, nhom)
          end
        end
        out
      end

      # Chuẩn = mặt khung nếu gióng dính mặt khung; không thì toạ độ có NHIỀU mép tấm nằm đúng nhất
      # (đếm mọi tấm trong khung, không chỉ tấm có chứng cứ). Hoà thì lấy toạ độ nhỏ hơn cho ổn định.
      def self.chon_chuan(kich, k, tams, meps)
        kh = meps.find { |m| m[:id].nil? }
        return [kh[:v], true] if kh
        ung = meps.map { |m| m[:v] }.uniq { |v| v.round(3) }
        dem = ->(v) { tams.sum { |t| [t[:lo][k], t[:hi][k]].count { |x| (x - v).abs <= TOL } } }
        [ung.min_by { |v| [-dem.call(v), v] }, false]
      end

      DUONG = %w[phải sau trên].freeze   # hướng dương của 3 trục
      AM    = %w[trái trước dưới].freeze

      # Một dòng gióng. Mỗi mép lệch kèm "CHỖ" để xem: điểm hai mép gặp nhau (tấm lệch ↔ tấm bạn nằm
      # đúng chuẩn), đoạn mép đỏ (lệch) + đoạn mép xanh lá (chuẩn) chạy song song, cỡ phóng.
      # Vì sao (Khoa thử thật lần 2, 30/09): camera đóng khung cả tấm 2 m thì 1,5 mm nhỏ hơn một điểm
      # ảnh, mặt gióng cắt cả khung chỉ thêm nhiễu → "vẫn không hiểu lệch chỗ nào". Phải phóng SÁT
      # đúng chỗ gặp nhau, thấy hai mép song song, biết lệch SO VỚI TẤM NÀO.
      def self.dong_giong(k, chuan, theo_khung, lech, tams, nhom)
        dung = tams.sum { |t| [t[:lo][k], t[:hi][k]].count { |x| (x - chuan).abs <= TOL } }
        lon = lech.map { |m| (m[:v] - chuan).abs }.max
        cho = lech.map { |m| cho_lech(k, chuan, m, tams, nhom) }
        sua = cho.first(4).map { |c| c['chu'] }
        sua << "… và #{lech.size - 4} mép nữa" if lech.size > 4
        goc_chuan = theo_khung ? 'Chuẩn = mặt khung.' : "Chuẩn = số đông (#{dung} mép thẳng hàng)."
        ten = lech.map { |m| m[:ten] }.uniq
        ten_ds = ten.first(3).join(', ') + (ten.size > 3 ? '…' : '')
        diem = cho[0]['o']
        f = moi('do', 'giong', "Lệch #{so(lon)} mm theo chiều #{TRUC[k]}: #{ten_ds}",
                "#{sua.join('. ')}. #{goc_chuan}", lech.map { |m| m[:id] }.uniq, diem, lon,
                "giong:#{k}:#{so(chuan)}:#{lech.map { |m| m[:id] }.uniq.sort.join('-')}")
        f['giong'] = { 'truc' => k, 'chuan' => chuan, 'cho' => cho }
        f
      end

      # Chỗ xem của một mép lệch m. Tấm bạn = tấm có chứng cứ với m và nằm ĐÚNG chuẩn (hoặc mặt khung).
      def self.cho_lech(k, chuan, m, tams, nhom)
        a = tams.find { |t| t[:id] == m[:id] }
        la_m = ->(x) { x[:id] == m[:id] && x[:mat] == m[:mat] && (x[:v] - m[:v]).abs <= TOL }
        ban = nhom.map { |_, x, y| la_m.call(x) ? y : (la_m.call(y) ? x : nil) }.compact
        bm = ban.find { |x| (x[:v] - chuan).abs <= TOL } || ban.first
        b = bm && bm[:id] && tams.find { |t| t[:id] == bm[:id] }
        khac = [0, 1, 2] - [k]
        if b
          # vùng hai tấm gặp nhau trên 2 trục còn lại: trục dài nhất = hướng chạy của mép,
          # trục kia = mặt tiếp xúc (hoặc giữa khe)
          vung = khac.map { |j| [j, [a[:lo][j], b[:lo][j]].max, [a[:hi][j], b[:hi][j]].min] }
          chay, c0, c1 = vung.max_by { |_, lo, hi| hi - lo }
          _, p0, p1 = vung.find { |j, _, _| j != chay }
          ngang = (p0 + p1) / 2.0
        else
          # bạn là mặt khung: mép tấm chạy theo chiều dài nhất của tấm, lấy cạnh ngoài của tấm
          chay = khac.max_by { |j| a[:hi][j] - a[:lo][j] }
          c0 = a[:lo][chay]
          c1 = a[:hi][chay]
          ngang = a[:lo][(khac - [chay])[0]]
        end
        ke = (khac - [chay])[0]
        dai = c1 - c0
        s = c0 + [40.0, dai / 2.0].min               # gần một đầu mép: có góc tấm làm mốc cho mắt
        s0 = [c0, s - 200].max
        s1 = [c1, s + 200].min
        diem = lambda do |uk, ur|
          q = [0.0, 0.0, 0.0]
          q[k] = uk
          q[chay] = ur
          q[ke] = ngang
          q
        end
        d = m[:v] - chuan
        tho = (m[:mat] == 1 && d > 0) || (m[:mat].zero? && d < 0)   # mép đi RA ngoài tấm = thò ra
        so_voi = bm && bm[:id] ? bm[:ten] : 'mặt khung'
        { 'id' => m[:id], 'ban' => b && b[:id], 'truc' => k, 'chay' => chay, 'ke' => ke,
          'dau' => d > 0 ? 1 : -1,                       # mép đã đi về phía dương/âm của trục k
          'o' => diem.call((m[:v] + chuan) / 2.0, s),
          'do' => [diem.call(m[:v], s0), diem.call(m[:v], s1)],
          'xanh' => [diem.call(chuan, s0), diem.call(chuan, s1)],
          'nua' => [[d.abs * 40, 25.0].max, 150.0].min,   # nửa cỡ vùng xem (mm): khung nhìn ≈ 3×nua — đủ thấy HÌNH KHỐI hai tấm; lệch ≥ 1 mm ≈ 8 px
          'nhan' => "#{m[:ten]} #{tho ? 'thò ra' : 'thụt vào'} #{so(d.abs)} mm",
          'chu' => "#{m[:ten]}: mép #{MAT[k][m[:mat]]} #{tho ? 'thò ra' : 'thụt vào'} #{so(d.abs)} mm so với #{so_voi}" }
      end

      # ── Vàng: gộp theo loại + số đo ─────────────────────────────
      NHOM = {
        'khe'  => ['khe hở %s mm', 'Khe đều nhau hoặc có cánh/hộc thường là cố ý (khe cánh). Khe nào lệch số với nhóm cánh thì xem kỹ.'],
        'an'   => ['chỗ ăn vào nhau %s mm', 'Thường là ngàm/rãnh cố ý. Không phải thì sửa.'],
        'canh' => ['cặp chỉ chạm theo đường', 'Hai tấm không áp mặt — chỉ chạm ở cạnh/góc. Kiểm có thiếu tấm hay lệch.'],
        'xien' => ['tấm đặt xiên so với khung', 'Không soát tiếp xúc cho tấm xiên — tự xem bằng mắt.'],
        'hinh' => ['tấm không phải hộp vuông (cong/khoét)', 'Chỉ soát theo hộp bao của tấm; đường cong không soát được.'],
        'giong_cua' => ['chỗ cánh/hộc lệch mép', 'Cánh/hộc thò/thụt so với khung hoặc tấm khác — thường là khe chừa cố ý. Hai cánh lệch mép nhau thì xem kỹ.']
      }.freeze

      def self.nhom_vang(vang)
        vang.keys.sort_by { |l, v| [NHOM.keys.index(l), v.to_f] }.map do |l, v|
          con = vang[[l, v]]
          con.each { |c| c['muc'] = 'vang' }   # con trong nhóm vàng là vàng (soát chéo điểm 6: ăn/chạm đường mang 'do')
          mau, chu = NHOM[l]
          ten = mau.include?('%s') ? format(mau, so(v)) : mau
          { 'muc' => 'vang', 'loai' => 'nhom', 'tieu_de' => "#{con.size} #{ten}",
            'chi_tiet' => chu, 'tam' => con.flat_map { |f| f['tam'] }.uniq, 'diem' => nil,
            'mm' => v, 'khoa' => "nhom:#{l}:#{so(v)}", 'con' => con }
        end
      end

      # Bỏ các mục người vẽ đã xác nhận "đúng rồi"
      def self.loc(ds, bo_qua)
        bq = bo_qua.to_a
        n = 0
        out = ds.map do |f|
          if bq.include?(f['khoa'])
            n += f['con'] ? f['con'].size : 1
            next nil
          end
          next f unless f['con']
          con = f['con'].reject { |c| bq.include?(c['khoa']) && (n += 1) }
          next nil if con.empty?
          f.merge('con' => con, 'tieu_de' => f['tieu_de'].sub(/\A\d+/, con.size.to_s))
        end
        { 'ds' => out.compact, 'so_bo_qua' => n }
      end

      # ── Dựng phát hiện ──────────────────────────────────────────
      def self.moi(muc, loai, tieu_de, chi_tiet, tam, diem, mm, khoa, doan = nil)
        { 'muc' => muc, 'loai' => loai, 'tieu_de' => tieu_de, 'chi_tiet' => chi_tiet, 'tam' => tam,
          'diem' => diem, 'doan' => doan, 'mm' => mm.to_f.round(2), 'khoa' => khoa }
      end

      # Phát hiện một tấm
      def self.don(t, loai, tieu_de, chi_tiet, mm = 0.0, diem = nil, khoa_them = nil)
        muc = %w[xien hinh].include?(loai) ? 'vang' : 'do'
        moi(muc, loai, tieu_de, chi_tiet, [t[:id]], diem || tam_hop([t]), mm,
            [loai, t[:id], khoa_them, so(mm)].compact.join(':'))
      end

      # Phát hiện một cặp — điểm đánh dấu ở giữa vùng hai tấm gặp nhau
      def self.cap(a, b, loai, tieu_de, chi_tiet, mm)
        diem = (0..2).map { |k| ([a[:lo][k], b[:lo][k]].max + [a[:hi][k], b[:hi][k]].min) / 2.0 }
        moi('do', loai, tieu_de, chi_tiet, [a[:id], b[:id]], diem, mm,
            "#{loai}:#{[a[:id], b[:id]].sort.join('-')}:#{so(mm)}")
      end

      def self.tam_hop(ts)
        (0..2).map { |k| (ts.map { |t| t[:lo][k] }.min + ts.map { |t| t[:hi][k] }.max) / 2.0 }
      end

      def self.diem_tam(t, k, s)
        p = tam_hop([t])
        p[k] = s.zero? ? t[:lo][k] : t[:hi][k]
        p
      end

      def self.diem_mat(kich, k, bien)
        p = kich.map { |x| x.to_f / 2.0 }
        p[k] = bien
        p
      end

      # Số mm để HIỂN THỊ: dưới 1 mm giữ 2 số lẻ (0,05 khác 0,1), còn lại 1 số lẻ
      def self.so(v)
        return '' if v.nil?
        v = v.to_f
        r = v.abs < 1 ? v.round(2) : v.round(1)
        r == r.to_i ? r.to_i.to_s : r.to_s
      end

      def self.goc(cha, i)
        i = cha[i] = cha[cha[i]] while cha[i] != i
        i
      end

      def self.noi(cha, i, j)
        cha[goc(cha, i)] = goc(cha, j)
      end
    end
  end
end
