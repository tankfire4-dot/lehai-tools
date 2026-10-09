# encoding: UTF-8
# Tạo Bo — LÕI TOÁN thuần Ruby (không gọi API SketchUp) để thử được ngoài SketchUp:
#   node projects/lehai-tools/tests/tao_bo.test.mjs
#
# Đầu vào: mặt cắt của cục bo (vòng điểm khép kín, mm) + khóa đường cong của từng đoạn.
# Đầu ra : chiều dài trải phẳng + các vùng hạ nền (mỗi khúc bo một vùng, RỘNG ĐÚNG BẰNG khúc bo —
#          Khoa chốt 08/10: NTT lấn thêm 13mm mỗi bên là sai) + khung đặt tấm.
#
# Cách đo khớp NTT (đo mẫu 08/10, scratch/tao-bo/do_bo.txt): chiều dài = tổng các ĐOẠN THẲNG SketchUp
# vẽ (cung R50 20 đoạn → 78,52, không phải 78,54 của cung tròn thật); chỉ trải CHUỖI MẶT NỐI TRƠN chứa
# khúc bo, dừng ở góc gãy (mẫu: trước 450 + cung + hông 53 = 581,52; bỏ hông trái 103 và lưng 500).

module TK
  module TaoBo
    module Toan

      GOC_TRON_DO   = 0.5    # hai đoạn thẳng gãy ≤ 0,5° coi như nối trơn (vẽ tay lệch nhẹ)
      HE_SO_NOI     = 0.75   # chỗ cung nối đoạn thẳng gãy ≈ nửa góc một đốt cung → cho tới 0,75 đốt
      DOT_LE_MM     = 25.0   # cung đã Explode: đốt ngắn hơn ngần này, hai đầu gãy nhẹ → coi là đốt cung
      DOT_LE_GOC_DO = 30.0
      PHANG_MM      = 0.1    # dung sai kiểm cục là khối đùn thẳng
      GOC_NGHI_DO   = 50.0   # góc gãy dưới ngần này mà không nối trơn → nghi cung Explode quá thô → BÁO, không đoán

      # ── Vector mảng [x,y,z] ─────────────────────────────────────
      def self.tru(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def self.cong(a, b)
        [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
      end

      def self.nhan(a, k)
        [a[0] * k, a[1] * k, a[2] * k]
      end

      def self.cham(a, b)
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
      end

      def self.dai(a)
        Math.sqrt(cham(a, a))
      end

      def self.cheo(a, b)
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
      end
      def self.don_vi(a)
        l = dai(a)
        l < 1e-12 ? nil : nhan(a, 1.0 / l)
      end

      # Pháp tuyến vòng điểm (Newell): hướng sao cho vòng đi NGƯỢC chiều kim đồng hồ khi nhìn từ đầu mũi.
      def self.phap_tuyen(pts)
        n = [0.0, 0.0, 0.0]
        pts.each_with_index do |p, i|
          q = pts[(i + 1) % pts.size]
          n = cong(n, [(p[1] - q[1]) * (p[2] + q[2]), (p[2] - q[2]) * (p[0] + q[0]), (p[0] - q[0]) * (p[1] + q[1])])
        end
        don_vi(n)
      end

      # Góc gãy CÓ DẤU (độ) tại đỉnh giữa hai hướng d1→d2: dương = rẽ trái quanh n (góc lồi của vòng CCW).
      def self.goc_gay(d1, d2, n)
        c = [[cham(d1, d2), -1.0].max, 1.0].min
        g = Math.acos(c) * 180.0 / Math::PI
        cham(cheo(d1, d2), n) >= 0 ? g : -g
      end

      # pts    : vòng điểm mặt cắt (mm), đoạn i = pts[i] → pts[i+1]
      # khoa   : khoa[i] = khóa đường cong của đoạn i (nil = đoạn thẳng thường)
      # moi_dinh: MỌI đỉnh của cục (mm) — để đo chiều cao + kiểm cục là khối đùn thẳng
      # len    : hướng "lên" của ngữ cảnh — chỉ để chọn chiều đọc cho tấm đứng xuôi, không ảnh hưởng số đo
      # Trả {ok: true, ...} hoặc {ok: false, loi: 'câu báo tiếng Việt'}.
      def self.phan_tich(pts, khoa, moi_dinh, len: [0.0, 0.0, 1.0], day: 17.5, cach: 150.0, loi_ra: 3.0)
        pts = pts.map { |p| p.map(&:to_f) }
        khoa = khoa.dup
        return { ok: false, loi: 'Mặt cắt của cục chỉ có 4 góc — không thấy khúc bo nào.' } if pts.size < 5
        n = phap_tuyen(pts)
        return { ok: false, loi: 'Mặt cắt của cục bị suy biến (các điểm thẳng hàng).' } unless n
        if cham(n, len) < -1e-9 # đảo chiều đi để tấm đứng xuôi (pháp tuyến CCW = hướng lên của tấm)
          pts.reverse!
          khoa = khoa.reverse.rotate(1) # đoạn i mới = pts[i]→pts[i+1] mới = đoạn cũ ngược chiều
          n = nhan(n, -1.0)
        end

        # cục phải là khối ĐÙN THẲNG: mọi đỉnh nằm ở đúng hai cao độ theo n
        cao = moi_dinh.map { |p| cham(p.map(&:to_f), n) }
        h0, h1 = cao.minmax
        le = cao.reject { |h| (h - h0).abs <= PHANG_MM || (h - h1).abs <= PHANG_MM }
        return { ok: false, loi: "Cục không phải khối đùn thẳng (#{le.size} đỉnh nằm lưng chừng) — chưa hỗ trợ." } unless le.empty?
        cao_mm = h1 - h0
        return { ok: false, loi: 'Cục không có chiều cao.' } if cao_mm < 1.0
        # khối đùn thẳng có ĐÚNG 2 × (số đỉnh mặt cắt) đỉnh. Thừa đỉnh = mặt trên/dưới bị nét thừa chia ra
        # nhiều mặt (hoặc có lỗ) → mặt cắt đang lấy chỉ là MỘT MẢNH: trải tiếp sẽ thiếu mà vẫn ra số. Báo.
        so_dinh = moi_dinh.map { |p| p.map { |x| (x.to_f * 100).round } }.uniq.size
        if so_dinh != 2 * pts.size
          return { ok: false, loi: "Mặt trên/dưới của cục bị chia thành nhiều mảnh hoặc có lỗ (#{so_dinh} đỉnh, mặt cắt " \
                                   "chỉ #{pts.size}). Xoá nét vẽ thừa trên mặt cục rồi chạy lại." }
        end

        m = pts.size
        huong = (0...m).map { |i| don_vi(tru(pts[(i + 1) % m], pts[i])) }
        return { ok: false, loi: 'Mặt cắt có hai điểm trùng nhau.' } if huong.any?(&:nil?)
        dai_doan = (0...m).map { |i| dai(tru(pts[(i + 1) % m], pts[i])) }
        gay = (0...m).map { |i| goc_gay(huong[(i - 1) % m], huong[i], n) } # gay[i] = tại đỉnh i (vào đoạn i)

        # cung đã Explode (đoạn không còn khóa): đốt ngắn mà hai đầu cùng gãy nhẹ → gom thành "cung đoán".
        # Chạy cả khi cục còn khúc khác là cung thật (một khúc Explode, một khúc không).
        doan_ = false
        if khoa.any?(&:nil?)
          (0...m).each do |i|
            next if khoa[i] || dai_doan[i] > DOT_LE_MM
            a = gay[i].abs; b = gay[(i + 1) % m].abs
            next unless a > 0.05 && a <= DOT_LE_GOC_DO && b > 0.05 && b <= DOT_LE_GOC_DO
            khoa[i] = :doan
            doan_ = true
          end
          # nối các đốt liền nhau thành MỘT khóa, đi từ một đoạn thường để khỏi chẻ đôi khúc vắt qua đỉnh 0
          st = (0...m).find { |i| khoa[i].nil? }
          (1..m).each do |k|
            i = (st + k) % m
            next unless khoa[i] == :doan
            truoc = khoa[(i - 1) % m]
            khoa[i] = truoc.is_a?(String) ? truoc : "doan#{i}"
          end if st
        end
        return { ok: false, loi: 'Không thấy khúc bo nào trên mặt cắt (không có cung).' } if khoa.none?

        # góc gãy lớn nhất BÊN TRONG mỗi đường cong (giữa hai đốt cùng khóa)
        dot_max = Hash.new(0.0)
        (0...m).each do |i|
          k = khoa[i]
          dot_max[k] = [dot_max[k], gay[i].abs].max if k && khoa[(i - 1) % m] == k
        end
        tron = (0...m).map do |i| # tron[i] = đỉnh i nối trơn hai đoạn i-1 và i
          a = khoa[(i - 1) % m]; b = khoa[i]
          if a && a == b then true
          else gay[i].abs <= GOC_TRON_DO + HE_SO_NOI * [dot_max[a], dot_max[b]].max
          end
        end
        return { ok: false, loi: 'Mặt cắt nối trơn khép kín (không có góc gãy để làm đầu tấm).' } if tron.all?
        # Góc gãy lưng chừng = rất có thể khúc bo bị Explode với đốt quá thô (> 25mm): đoán tiếp sẽ trải
        # THIẾU khúc đó mà vẫn ra số (bộ thử ngẫu nhiên bắt được 08/10). Báo để vẽ lại, không đoán.
        nghi = (0...m).reject { |i| tron[i] }.map { |i| gay[i].abs }.select { |g| g < GOC_NGHI_DO }
        unless nghi.empty?
          return { ok: false, loi: "Mặt cắt có #{nghi.size} góc gãy lưng chừng (#{nghi.map { |g| g.round(1) }.uniq.first(3).join('°, ')}°) — "                                    'thường do khúc bo bị Explode. Vẽ lại khúc bo bằng công cụ Arc rồi chạy lại.' }
        end

        # chuỗi = dãy đoạn liên tiếp giữa hai góc gãy
        dau = (0...m).find { |i| !tron[i] }
        chuoi = []
        (0...m).each do |k|
          i = (dau + k) % m
          chuoi << [] unless tron[i]
          chuoi.last << i
        end
        co_bo = chuoi.select { |c| c.any? { |i| khoa[i] } }
        if co_bo.size > 1
          return { ok: false, loi: "Cục có #{co_bo.size} chuỗi bo tách rời bởi góc gãy — không biết trải chuỗi nào. Tách cục ra từng phần." }
        end
        c = co_bo.first

        # đi dọc chuỗi: cộng chiều dài, gom các đốt bo liền nhau CÙNG CHIỀU UỐN thành một vùng
        vung = []
        s = 0.0
        c.each_with_index do |i, vi|
          if khoa[i]
            # chiều uốn của đốt = tổng góc gãy hai đầu đốt (nửa trong đốt): + = lồi = hạ nền mặt áp cục
            dau_d = vi.zero? ? 0.0 : gay[i]
            cuoi_d = vi == c.size - 1 ? 0.0 : gay[(i + 1) % m]
            loi = (dau_d + cuoi_d) >= 0
            if vung.last && vung.last[:s1] == s && vung.last[:loi] == loi
              vung.last[:s1] = s + dai_doan[i]
              vung.last[:dot] += 1
              vung.last[:v1] = vi
            else
              vung << { s0: s, s1: s + dai_doan[i], loi: loi, dot: 1, v0: vi, v1: vi }
            end
          end
          s += dai_doan[i]
        end
        dai_tam = s

        # góc uốn + bán kính từng khúc (để bảng tự chọn dưỡng: Khoa 08/10 — R34 → dưỡng 54, R50 → dưỡng 81).
        # Góc = tổng góc gãy từ đầu tới cuối khúc (hai đầu nối tiếp tuyến mỗi đầu gãy nửa đốt → cộng đủ Θ).
        # SketchUp chia cung n đốt đều: mỗi đốt dài 2R·sin(Θ/2n) → R = tổng dây / (2n·sin(Θ/2n)).
        vung.each do |v|
          trong = (v[:v0]...v[:v1]).sum { |k| gay[c[k + 1]] } # góc gãy GIỮA các đốt: (n − 1) × Θ/n
          # Khúc bo sát góc gãy (đầu/cuối chuỗi): đỉnh đó là góc gãy của hình, không phải nửa đốt nối tiếp
          # tuyến → bù nửa góc một đốt (đoán từ góc giữa các đốt). Thiếu bù: R50 90° ra R51,28 · 87,75° và
          # không tự chọn được dưỡng (soát 09/10). Khúc chỉ 1 đốt thì không có gì để đoán — giữ như cũ.
          nua = v[:dot] > 1 ? trong / (v[:dot] - 1) / 2.0 : 0.0
          tong = (v[:v0].zero? ? nua : gay[c[v[:v0]]]) + trong +
                 (v[:v1] == c.size - 1 ? nua : gay[(c[v[:v1]] + 1) % m])
          th = tong.abs * Math::PI / 180.0
          v[:goc] = tong.abs
          v[:r] = th > 1e-9 ? (v[:s1] - v[:s0]) / (2.0 * v[:dot] * Math.sin(th / (2.0 * v[:dot]))) : nil
          v.delete(:v0)
          v.delete(:v1)
        end

        # khung đặt tấm: x = chiều trải (hướng đoạn đầu), y = n (lên), z = pháp tuyến NGOÀI của đoạn đầu
        # (z = 0 là mặt áp cục, z = dày là mặt ngoài). Gốc lùi ra ngoài `cach` mm, đáy ở cao độ thấp nhất.
        u = huong[c.first]
        ra = cheo(u, n) # vòng CCW quanh n: bên phải hướng đi = phía ngoài cục
        p0 = pts[c.first]
        goc = cong(cong(p0, nhan(n, h0 - cham(p0, n))), nhan(ra, cach))

        { ok: true, dai: dai_tam, cao: cao_mm, day: day, loi_ra: loi_ra, vung: vung,
          goc: goc, truc_x: u, truc_y: n, truc_z: ra, doan: doan_, so_doan: c.size }
      end

      # Khúc bo dài theo số người chọn (08/10 Khoa: xưởng uốn bằng DƯỠNG BO nên khúc bo trên tấm phẳng dài 54, 81…
      # chứ không phải chiều dài cung). Các đoạn THẲNG giữ nguyên; khúc bo đổi dài → tổng tấm đổi theo.
      # Vùng hạ nền = đúng khúc bo mới. rong[i] = mm cho khúc i.
      # Trả {ok: true, dai: tổng mới, vung: [...]} hoặc {ok: false, loi: '...'}.
      def self.vung_theo_rong(kq, rong)
        return { ok: false, loi: "Cần #{kq[:vung].size} chiều rộng, nhận #{rong.size}." } unless rong.size == kq[:vung].size
        ra = []
        x = 0.0     # vị trí trên tấm MỚI
        cu = 0.0    # vị trí tương ứng trên tấm trải theo cung
        kq[:vung].each_with_index do |v, i|
          w = rong[i].to_f
          return { ok: false, loi: "Khúc #{i + 1}: chiều dài khúc bo phải lớn hơn 0." } unless w > 0
          x += v[:s0] - cu                                  # đoạn thẳng trước khúc: giữ nguyên
          ra << { s0: x, s1: x + w, loi: v[:loi], cung: v[:s1] - v[:s0] }
          x += w
          cu = v[:s1]
        end
        { ok: true, dai: x + (kq[:dai] - cu), vung: ra }    # + đoạn thẳng cuối: giữ nguyên
      end

      # ── Kiểu RÃNH LIỀN (Khoa chốt 09/10: xưởng làm CÁCH A — cục = hình món đồ, tấm là vỏ ngoài, rãnh quay vào) ──
      # Vẽ y như NTT, đọc từ 3 tấm NTT đo 08/10 (scratch/tao-bo/do_bo3.txt, khớp 18/18 số):
      #   bước rãnh = dao D + thịt S · số rãnh = phần nguyên(khúc bo ÷ bước) + 1 · căn giữa khúc bo ·
      #   nét bảo vệ = khúc bo thò thêm D + X mỗi đầu · rãnh + nét bảo vệ lòi X ra ngoài mép trên/dưới.
      # bu[i] = mm cộng vào khúc bo i (mặc định 0 = như NTT; lý thuyết cách A NTT cắt dư ≈ góc × S/2, xem
      # artifact "Hai Cách Bo Rãnh"). Đoạn thẳng giữ nguyên như dưỡng ở kiểu hạ nền.
      # Trả {ok: true, dai:, buoc:, khuc: [{s0, s1, loi, xs: [tâm rãnh], b0, b1, ho}]} hoặc {ok: false, loi:}.
      def self.ranh_lien(kq, d:, s:, x:, bu:)
        return { ok: false, loi: 'Đường kính dao phải lớn hơn 0.' } unless d.to_f > 0
        return { ok: false, loi: "Thịt chừa lại phải từ 0 tới dưới độ dày ván (#{kq[:day]})." } unless s.to_f >= 0 && s.to_f < kq[:day]
        return { ok: false, loi: 'Mở rộng biên không được âm.' } unless x.to_f >= 0
        d = d.to_f; s = s.to_f; x = x.to_f
        rv = vung_theo_rong(kq, kq[:vung].each_with_index.map { |v, i| (v[:s1] - v[:s0]) + bu[i].to_f })
        return rv unless rv[:ok]
        p = d + s # bước rãnh
        khuc = rv[:vung].each_with_index.map do |v, i|
          lb = v[:s1] - v[:s0]
          n = (lb / p + 1e-9).floor + 1                       # số rãnh (1e-9: khúc đúng bằng bội số bước không bị hụt 1)
          giua = (v[:s0] + v[:s1]) / 2.0
          xs = (0...n).map { |k| giua - (n - 1) * p / 2.0 + k * p }
          # miệng rãnh còn hở khi gập đủ góc (mô hình bản lề cách A): mặt rãnh cách giữa lớp da (độ dày − S/2),
          # phải co (độ dày − S/2) × góc, chia đều n rãnh
          goc = kq[:vung][i][:goc].to_f * Math::PI / 180.0
          ho = d - (kq[:day] - s / 2.0) * goc / n
          if xs.first - d / 2 < -1e-6 || xs.last + d / 2 > rv[:dai] + 1e-6
            return { ok: false, loi: "Khúc #{i + 1}: rãnh lòi khỏi đầu tấm — đoạn thẳng hai bên khúc bo quá ngắn." }
          end
          return { ok: false, loi: "Khúc #{i + 1}: rãnh sẽ khép kín trước khi uốn đủ góc (#{n} rãnh dao #{d}). Tăng dao hoặc tăng thịt chừa." } if ho <= 0
          { s0: v[:s0], s1: v[:s1], loi: v[:loi], xs: xs, b0: v[:s0] - (d + x), b1: v[:s1] + (d + x), ho: ho }
        end
        { ok: true, dai: rv[:dai], buoc: p, khuc: khuc }
      end

    end
  end
end
