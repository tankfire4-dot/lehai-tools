# encoding: UTF-8
# ============================================================
#  LÕI TÍNH — HỘC KÉO RAY BI (27/09/2026, phát 1.9.72)
#
#  Khung đã dò (lòng, phủ bì, đố) + thông số → danh sách tấm (kích thước +
#  vị trí). KHÔNG gọi SketchUp: kiểm được bằng số trước khi dựng hình.
#
#  Hệ toạ độ (mm) = toạ độ THẾ GIỚI của khung: x trái → phải · y từ mặt trước
#  vào trong (mép trước khung = y_truoc) · z từ dưới lên. Tấm = hộp thẳng trục.
#
#  Quy tắc rút từ mẫu Khoa vẽ 27/09 (khoang 600 × 600 × 300) + các lần Khoa chốt
#  27/09. Bảng quy tắc kèm nguồn + trạng thái + mẫu so khớp ở lab:
#  agent_lab_khoa/projects/tao-modul-nhanh/
# ============================================================

module TK
  module TaoModulNhanh
    module HocKeo
      MAC_DINH = {
        van: 17.5,          # ván thùng hộc + mặt hộc (Khoa chốt 27/09, cho chỉnh)
        van_day: 9.0,       # đáy hộc — xưởng gọi "hậu" vì dùng ván hậu (Khoa chốt 27/09)
        khe_ray: 13.0,      # hông hộc cách hông khoang, mỗi bên — chỗ ray bi (Khoa chốt 27/09)
        cach_day: 15.0,     # mặt dưới đáy hộc cách mốc dưới của khoang (Khoa chốt 27/09)
        ranh_day: 10.0,     # đáy ăn rãnh vào mỗi hông trái/phải (KHỚP MẪU 27/09, chưa rõ vì sao)
        khe_mat: 2.0,       # mặt lọt cách mọi cạnh lòng; khe giữa hai mặt chồng nhau (Khoa chốt 27/09)
        khe_phu: 2.0,       # mặt phủ cách mép trước khung — dung sai không cạ cạnh tủ (Khoa chốt 27/09)
        khe_sau: 30.0,      # đuôi thùng hộc cách hậu ÍT NHẤT bấy nhiêu khi chọn ray (Khoa chốt 27/09)
        gia_ray: 0.0,       # thùng hộc dài ĐÚNG bằng ray (sếp dạy Khoa 02/10: không dư 2cm) — bỏ luật +20 của 29/09; không còn ô nhập
        kieu_mat: 'lot',    # 'lot' | 'phu'
        so_hoc: 1,          # chỉ dùng khi khung KHÔNG có đố; có đố thì số hộc = số đố + 1
        ray: nil,           # nil = tự chọn ray dài nhất còn lọt khoang
        bo: [],             # số thứ tự hộc (1 = trên cùng) KHÔNG gắn — người dùng bỏ tick khoang
        mong: true,         # mọc mộng xương chó (không thu) hông trước/sau → hông trái/phải (Khoa 03/10)
        ranh: true,         # gắn nhãn phay rãnh đáy lên hông trái/phải (Khoa 03/10)
        so_mong: nil,       # nil = Tự động; số = người dùng chọn tay, áp mọi hộc
        co_mong: nil,       # nil = Tự động; số (mm) = rộng đầu mộng chọn tay
        cao_thanh: nil      # nil = Tự động 2/3 khoang; số (mm) = thành hộc người dùng gõ (Khoa 03/10: có thiết kế muốn cao hơn)
      }.freeze

      # Ray bi bán theo bậc 50 (Khoa 27/09) — mm. 200: Khoa 27/09 "hình như có loại ray 200"
      RAY_CO = [200, 250, 300, 350, 400, 450, 500, 550, 600].map(&:to_f).freeze
      # Hông thùng (mặt dưới đáy → đỉnh hông) thấp nhất — ray bi 3 tầng cao ~45 (Khoa chốt 27/09)
      HONG_MIN = 50.0
      # Chiều cao thành hộc (sếp dạy Khoa, chốt 02/10): tính từ ĐÁY LÒNG KHOANG, 15 cách đáy + thành hộc
      # = 2/3 chiều cao khoang (mốc là khoang, không phải mặt hộc — hộc phủ mặt to hơn khoang sẽ sai).
      # Thành hộc (= 2/3 khoang − 15) làm tròn LÊN số đuôi 0 (Khoa đổi từ làm tròn xuống, 02/10).
      # Bỏ luật cũ "đỉnh hông thấp hơn nóc lòng 50" (27/09).
      TY_LE_THANH = 2.0 / 3.0
      LAM_TRON_THANH = 10.0

      # Cao thành hộc (mặt dưới đáy → đỉnh thành) cho khoang cao `cao_khoang`, đáy cách `cach_day`.
      def self.cao_thanh(cao_khoang, cach_day)
        ((cao_khoang * TY_LE_THANH - cach_day) / LAM_TRON_THANH - 1e-6).ceil * LAM_TRON_THANH
      end

      # ── Mộng xương chó cho hộc (Khoa 03/10) ──────────────────
      # Khớp 20/20 hộc Khoa làm tay (bàn trang điểm L 68,5 → 1×35; tủ áo/bàn học L 100–148 → 1×50).
      # L = chiều dài đầu mộng = chiều cao hông trước/sau.
      #   số mộng = ceil(L / NHIP_MONG)  — mỗi mộng "giữ" tối đa NHIP_MONG mm
      #   cỡ mộng = (L / số mộng) / 2, làm tròn xuống bậc 5, kẹp trong CO_MONG
      # Có ≥ 2 mộng: chia đều, mỗi mộng nằm giữa đoạn của nó (lùi tâm = L / 2n).
      NHIP_MONG = 160.0
      CO_MONG = [35.0, 50.0].freeze
      # Bộ số RIÊNG của hộc kéo (Khoa chốt 03/10: "bên hộc kéo thông số đặc biệt hơn") — cao 11 · dư dày 0,2 ·
      # dư dài 0,3 · LUÔN không thu. KHÁC plugin Mộng Xương Chó (dư 0,2 / 0,2) — đừng gộp làm một.
      HINH_MONG = { 'height' => 11, 'neck' => 6, 'bevel' => 1, 'slackT' => 0.2, 'slackL' => 0.3, 'cutter' => 6 }.freeze
      # Nhãn phay rãnh đáy: chép đúng 20/20 hộc Khoa làm tay (quét file 03/10) — rộng = dày đáy, dài = hông
      # + RANH_LOI mỗi đầu, tag/setting/intersect-x như dưới. intersect-x 3,0 chép nguyên (chưa rõ nghĩa).
      RANH_LOI = 3.0
      RANH_TAG = 'ABF_PHAYRANHHAU10LY'.freeze
      RANH_SETTING = 'PHÂY RÃNH HẬU 10LY'.freeze
      RANH_X = 3.0

      def self.mong_cho(l, p)
        n = p[:so_mong] ? p[:so_mong].to_i : (l / NHIP_MONG - 1e-9).ceil
        n = [n, 1].max
        co = p[:co_mong] ? p[:co_mong].to_f : ((l / n / 2.0) / 5.0).floor * 5.0
        co = [[co, CO_MONG[0]].max, CO_MONG[1]].min unless p[:co_mong]
        { 'count' => n, 'head' => co, 'inset' => (l / (2.0 * n)).round(3), 'tu_dong' => !p[:so_mong] && !p[:co_mong] }
      end

      # Tâm từng mộng dọc đầu dài l (từ mép dưới hông trước), y như lõi Mộng Xương Chó tính.
      def self.tam_mong(l, mg)
        n = mg['count']
        n == 1 ? [l / 2.0] : Array.new(n) { |i| mg['inset'] + i * (l - 2 * mg['inset']) / (n - 1) }
      end

      # Số/cỡ chọn tay có vừa đầu không — cùng luật lõi Mộng (chừa ≥ 1mm; dấu âm hai mộng cạnh nhau
      # cách ≥ rộng + dư dài + Ø dao + 1). Sai thì báo NGAY trong bảng, khỏi đợi bấm Tạo mới lỗi.
      def self.kiem_mong(ten, l, mg)
        n = mg['count']
        co = mg['head']
        if n == 1
          raise "#{ten}: mộng rộng #{co.round} không vừa hông trước cao #{l.round(1)} — chọn cỡ nhỏ hơn." if l - co < 2
        else
          nhip = (l - 2 * mg['inset']) / (n - 1)
          can = co + HINH_MONG['slackL'] + HINH_MONG['cutter'] + 1
          if mg['inset'] - co / 2.0 < 1 || nhip < can
            raise "#{ten}: #{n} mộng rộng #{co.round} không vừa hông trước cao #{l.round(1)} — giảm số mộng hoặc cỡ mộng."
          end
        end
      end

      def self.hop(ten, x0, x1, y0, y1, z0, z1)
        { ten: ten, x: [x0, x1], y: [y0, y1], z: [z0, z1] }
      end

      # Ray dài nhất mà thùng hộc (bắt đầu ở y_dau, dài = ray + gia) không vượt y_cuoi
      def self.chon_ray(y_dau, y_cuoi, gia = 0.0)
        RAY_CO.select { |r| y_dau + r + gia <= y_cuoi + 1e-6 }.max
      end

      # ── Chia khoang + mặt theo chiều cao ─────────────────────
      # Trả mảng từ DƯỚI lên: { khoang: [z0, z1], mat_z: [z0, z1] }.
      # khoang = mốc dưới/trên để đặt thùng hộc (đáy cách 15, đỉnh hông thấp 50).
      def self.chia(k, p)
        z0, z1 = k[:z]
        zn0, zn1 = k[:ngoai_z]
        kg = p[:khe_mat]
        lot = p[:kieu_mat] == 'lot'
        do_ = (k[:do] || []).sort_by(&:first)

        if do_.any?
          # Có đố: mỗi khoang nằm giữa hai mốc (đáy/đố/nóc) — Khoa chốt 27/09
          moc = [z0] + do_.flatten + [z1]
          khoang = moc.each_slice(2).to_a
          khoang.each_with_index.map do |(a, b), i|
            if lot
              # Mặt lọt trong khoang của nó, khe đều 4 phía
              { khoang: [a, b], mat_z: [a + kg, b - kg] }
            else
              # Phủ trên đố: khe giữa hai mặt nằm GIỮA đố (kiểu A) — GIẢ ĐỊNH, chờ Khoa xem thử
              duoi = i.zero? ? zn0 : (do_[i - 1][0] + do_[i - 1][1]) / 2.0 + kg / 2.0
              tren = i == khoang.size - 1 ? zn1 : (do_[i][0] + do_[i][1]) / 2.0 - kg / 2.0
              { khoang: [a, b], mat_z: [duoi, tren] }
            end
          end
        else
          # Không đố: chia đều như tool Tạo Cánh — lọt chừa khe quanh viền, phủ thì
          # sát phủ bì (mẫu phủ khe viền 0); khe giữa hai mặt = khe_mat.
          n = [p[:so_hoc].to_i, 1].max
          a, b = lot ? [z0 + kg, z1 - kg] : [zn0, zn1]
          h = (b - a - (n - 1) * kg) / n
          raise "Chia #{n} hộc thì mỗi mặt chỉ còn #{h.round(1)}mm." if h < 60
          (0...n).map do |i|
            m0 = a + i * (h + kg)
            m1 = m0 + h
            # Khoang ảo của hộc: phần lòng nằm sau mặt, ranh giới ở giữa khe — GIẢ ĐỊNH
            k0 = i.zero? ? z0 : [m0 - kg / 2.0, z0].max
            k1 = i == n - 1 ? z1 : [m1 + kg / 2.0, z1].min
            { khoang: [k0, k1], mat_z: [m0, m1] }
          end
        end
      end

      # ── Mép mặt phủ từ 4 tấm bao quanh khoang ────────────────
      # bien[:trai/:phai/:duoi/:tren] = { trong:, ngoai:, ke: } (mm): mặt trong + mặt kia của tấm,
      # ke = bên kia tấm còn khoang khác của cùng khung (đố / vách / tấm chung).
      # Không kề → phủ tới mép ngoài tấm (mẫu 27/09, phủ bì). Có kề → khe giữa hai mặt nằm
      # GIỮA tấm, mỗi mặt lùi khe_mat/2 (kiểu A — GIẢ ĐỊNH, Khoa xem thử rồi chốt).
      def self.phu_bi(bien, km)
        mep = lambda do |b, huong|   # huong = -1 phía âm (trái/dưới), +1 phía dương
          b[:ke] ? (b[:trong] + b[:ngoai]) / 2.0 - huong * km / 2.0 : b[:ngoai]
        end
        { ngoai_x: [mep.call(bien[:trai], -1), mep.call(bien[:phai], 1)],
          ngoai_z: [mep.call(bien[:duoi], -1), mep.call(bien[:tren], 1)] }
      end

      # ── Tính toàn bộ tấm ─────────────────────────────────────
      # khung: { x: [lòng trái, lòng phải], z: [lòng dưới, lòng trên],
      #          ngoai_x:, ngoai_z: (phủ bì), y_truoc:, y_sau: (mặt trước hậu / đáy lòng),
      #          do: [[z dưới, z trên], ...] }
      def self.tinh(khung, tham_so = {})
        p = MAC_DINH.merge(tham_so.reject { |_, v| v.nil? })
        khung = khung.merge(phu_bi(khung[:bien], p[:khe_mat])) if khung[:bien]
        t, td, kr = p[:van], p[:van_day], p[:khe_ray]
        x0, x1 = khung[:x]
        raise 'Ván và đáy hộc phải dày hơn 0.' if t <= 0 || td <= 0
        raise "Rãnh đáy #{p[:ranh_day]}mm phải nông hơn ván #{t}mm." if p[:ranh_day] >= t
        raise "Kiểu mặt '#{p[:kieu_mat]}' không có — chỉ 'lot' hoặc 'phu'." unless %w[lot phu].include?(p[:kieu_mat])

        lot = p[:kieu_mat] == 'lot'
        # Lọt: mặt bằng mép trước khung, thùng bắt ngay sau mặt.
        # Phủ: mặt cách mép trước khung khe_phu, thùng bắt ngay sau mặt → nhô ra khe_phu.
        y_mat = lot ? [khung[:y_truoc], khung[:y_truoc] + t] : [khung[:y_truoc] - p[:khe_phu] - t, khung[:y_truoc] - p[:khe_phu]]
        y_dau = y_mat[1]
        # Đuôi thùng phải cách hậu ≥ khe_sau → ray chỉ được tới y_sau − khe_sau
        y_het = khung[:y_sau] - p[:khe_sau]
        gia = p[:gia_ray]
        ray = p[:ray] || chon_ray(y_dau, y_het, gia)
        raise "Lòng khung sâu #{(khung[:y_sau] - khung[:y_truoc]).round(1)}mm — không ray nào (ngắn nhất #{RAY_CO.min.round}, thùng #{(RAY_CO.min + gia).round}) lọt mà còn chừa #{p[:khe_sau].round}mm sau." unless ray
        # Thùng hộc dài = ray (sếp 02/10; gia = 0, giữ biến để lõi còn nhận nếu sau này cần)
        dai = ray + gia
        raise "Thùng dài #{dai.round(1)}mm (ray #{ray.round} + #{gia.round(1)}) ngắn quá." if dai <= 2 * t + 50
        raise "Ray #{ray.round}mm dài quá: thùng #{dai.round(1)}mm, đuôi thùng chỉ còn cách hậu #{(khung[:y_sau] - y_dau - dai).round(1)}mm (cần ≥ #{p[:khe_sau].round})." if y_dau + dai > y_het + 1e-6

        # Thùng hộc rộng = lòng − 2 khe ray (Khoa chốt 27/09)
        hx0 = x0 + kr
        hx1 = x1 - kr
        raise "Lòng rộng #{(x1 - x0).round(1)}mm quá hẹp cho hai khe ray + hai hông." if hx1 - hx0 <= 2 * t + 50

        # Mặt: lọt thì trong lòng chừa khe; phủ thì bằng phủ bì khung
        mat_x = lot ? [x0 + p[:khe_mat], x1 - p[:khe_mat]] : khung[:ngoai_x]
        ten_mat = lot ? 'mặt lọt' : 'mặt phủ'

        ds = chia(khung, p)
        bo = Array(p[:bo]).map(&:to_i)
        tam = []
        khoang = []
        mong = []
        rang = []
        ds.reverse.each_with_index do |h, i|   # đặt tên từ TRÊN xuống: Hộc 1 = trên cùng
          ten = "Hộc #{i + 1}"
          khoang << { so: i + 1, z: h[:khoang], cao: (h[:khoang][1] - h[:khoang][0]).round(1), gan: !bo.include?(i + 1) }
          next if bo.include?(i + 1)
          zb = h[:khoang][0] + p[:cach_day]       # mặt dưới đáy hộc
          zt = zb + (p[:cao_thanh] ? p[:cao_thanh].to_f : cao_thanh(h[:khoang][1] - h[:khoang][0], p[:cach_day]))   # đỉnh thành: 2/3 khoang, hoặc số người gõ
          if p[:cao_thanh]
            tran = h[:khoang][1] - p[:khe_mat]   # đỉnh thành không vượt nóc lòng khoang (chừa khe mặt)
            raise "#{ten}: thành cao #{p[:cao_thanh].round(1)} vượt khoang — tối đa #{(tran - zb).floor}mm." if zt > tran + 1e-6
          end
          if zt - zb < HONG_MIN
            if p[:cao_thanh]
              raise "#{ten}: thành hộc #{(zt - zb).round(1)}mm thấp quá — cần ≥ #{HONG_MIN.round} (ray bi)."
            end
            raise "#{ten}: thành hộc chỉ còn #{(zt - zb).round(1)}mm (2/3 khoang − #{p[:cach_day].round}, cần ≥ #{HONG_MIN.round}) — khoang quá thấp hoặc chia nhiều hộc quá."
          end
          y1 = y_dau + dai

          tam << hop("#{ten} · #{ten_mat}", *mat_x, *y_mat, *h[:mat_z])
          # Hai hông chạy suốt chiều sâu, cao hết thùng
          tam << hop("#{ten} · hông trái", hx0, hx0 + t, y_dau, y1, zb, zt)
          tam << hop("#{ten} · hông phải", hx1 - t, hx1, y_dau, y1, zb, zt)
          # Đáy ăn rãnh vào hai hông, dài hết thùng, không rãnh hông trước/sau (KHỚP MẪU)
          tam << hop("#{ten} · đáy", hx0 + t - p[:ranh_day], hx1 - t + p[:ranh_day], y_dau, y1, zb, zb + td)
          # Hông trước/sau lọt giữa hai hông, ngồi trên đáy (KHỚP MẪU)
          tam << hop("#{ten} · hông trước", hx0 + t, hx1 - t, y_dau, y_dau + t, zb + td, zt)
          tam << hop("#{ten} · hông sau", hx0 + t, hx1 - t, y1 - t, y1, zb + td, zt)
          if p[:mong]
            l = zt - (zb + td)
            mg = mong_cho(l, p)
            kiem_mong(ten, l, mg)
            mong << mg.merge('hoc' => ten, 'L' => l.round(1))
            # Răng để XEM TRƯỚC 3D (không dựng): hộp rộng × cao mộng × dày ván, đâm vào hông trái/phải
            hm = HINH_MONG['height']
            [[y_dau, y_dau + t], [y1 - t, y1]].each do |ya, yb|
              tam_mong(l, mg).each do |c|
                za = zb + td + c - mg['head'] / 2.0
                zc = zb + td + c + mg['head'] / 2.0
                rang << hop("#{ten} · mộng", hx0 + t - hm, hx0 + t, ya, yb, za, zc)
                rang << hop("#{ten} · mộng", hx1 - t, hx1 - t + hm, ya, yb, za, zc)
              end
            end
          end
        end

        tam.each { |s| s[:kich_thuoc] = [s[:x], s[:y], s[:z]].map { |a, b| (b - a).round(1) }.sort }
        { ray: ray, so_hoc: ds.size, khoang: khoang, tham_so: p, tam: tam, mong: mong, rang: rang }
      end
    end
  end
end
