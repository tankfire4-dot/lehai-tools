# encoding: UTF-8
# ============================================================
#  LÕI TÍNH — KHUNG BAO TỦ LẠNH (24/09/2026)
#
#  Thông số → danh sách tấm (kích thước + vị trí). KHÔNG gọi SketchUp:
#  chạy được ở bất cứ đâu, kiểm được bằng số trước khi dựng hình.
#
#  Hệ toạ độ (mm): x từ mép ngoài hông trái sang phải · y từ mặt trước (0)
#  vào tường (D) · z từ sàn lên. Mỗi tấm là một hộp x0..x1, y0..y1, z0..z1.
#
#  Quy tắc rút từ mẫu Khoa vẽ 24/09 (600 × 600 × 2500). Bảng quy tắc kèm
#  nguồn + bộ dò/so khớp ở lab: agent_lab_khoa/projects/tao-modul-nhanh/
# ============================================================

module TK
  module TaoModulNhanh
    module KhungBaoTuLanh
      MAC_DINH = {
        rong: 600.0,        # W  — rộng phủ bì (mép ngoài hông trái → mép ngoài hông phải)
        sau: 600.0,         # D  — sâu, mặt trước → tường
        cao: 2500.0,        # H  — cao tổng, sàn → đỉnh bạ nóc (sát trần)
        cao_tu_lanh: 1595.0, # Hd — chỗ tủ lạnh: sàn → mặt trên nóc dưới
        cao_ba_noc: 60.0,   # Hb — bạ nóc trên cùng
        van: 17.5,          # t  — độ dày ván thân; cánh + xương bạ nóc dày bằng ván thân (Khoa chốt 24/09)
        van_hau: 9.0,       # độ dày hậu
        khe: 2.0,           # k  — khe cánh với mọi mặt tiếp giáp
        hau_lui: 10.0,      # mặt sau hậu (và bạ lưng) cách tường — sợ hở/ẩm tường (Khoa 24/09)
        ranh_hau: 10.0,     # rãnh hậu ăn vào mỗi hông — KHÁC hau_lui (Khoa chốt 24/09); có công trình ăn ít hơn
        len_day: 10.0,      # len chân tường hiện trạng — dày (đo từ tường ra)
        len_cao: 60.0,      #                            — cao
        ba_chan_cach_len: 20.0, # bạ lưng chân: đáy bạ cao hơn đỉnh chỗ khoét len — CỐ ĐỊNH, không đưa ra bảng hỏi (Khoa chốt 24/09)
        ba_rong: 60.0,      # bản rộng bạ nóc trước / bạ lưng / xương bạ nóc trước
        xuong_ben: 50.0     # bản rộng xương bạ nóc hai bên
      }.freeze

      def self.hop(ten, x0, x1, y0, y1, z0, z1, them = {})
        { ten: ten, x: [x0, x1], y: [y0, y1], z: [z0, z1] }.merge(them)
      end

      # Trả về mảng tấm; thông số sai thì raise với lời tiếng Việt.
      def self.tinh(tham_so = {})
        p = MAC_DINH.merge(tham_so)
        w, d, h, t, k = p[:rong], p[:sau], p[:cao], p[:van], p[:khe]
        hd, hb, ba = p[:cao_tu_lanh], p[:cao_ba_noc], p[:ba_rong]

        # Khoa chốt 24/09: tủ trên là phần còn lại sau chỗ tủ lạnh và bạ nóc
        ht = h - hd - hb
        raise "Tủ trên còn #{ht.round(1)}mm — cao tổng quá thấp so với chỗ tủ lạnh + bạ nóc." if ht < 4 * t
        raise "Rộng #{w}mm không đủ chỗ cho 2 hông và 2 cánh." if w - 2 * t - 3 * k <= 0
        raise 'Ván thân và hậu phải dày hơn 0.' if t <= 0 || p[:van_hau] <= 0
        raise "Hậu cách tường #{p[:hau_lui]}mm quá sâu so với tủ #{d}mm." if p[:hau_lui] + p[:van_hau] + t + k + t >= d

        z_noc_tren = hd + ht            # mặt trên nóc trên = đáy bạ nóc
        lui = t + k                     # nóc/đáy thụt so với mặt trước: dày cánh + khe
        y_sau = d - p[:hau_lui]         # mép sau nóc/đáy/hậu/bạ lưng: cách tường hau_lui
        lot = w - t                     # mép trong hông phải
        tam = []

        # ── Hông: dưới khoét góc sau-dưới đúng bằng len; trên nối tiếp tới nóc ──
        # Không có len (một trong hai số = 0) → hông nguyên tấm, không khoét
        co_len = p[:len_day] > 0 && p[:len_cao] > 0
        raise "Len dày #{p[:len_day]}mm phải nhỏ hơn sâu tủ." if co_len && p[:len_day] >= d
        raise "Len cao #{p[:len_cao]}mm phải thấp hơn chỗ tủ lạnh." if co_len && p[:len_cao] >= hd
        khoet = co_len ? { khoet: { y: [d - p[:len_day], d], z: [0.0, p[:len_cao]] } } : {}
        tam << hop('Hông dưới trái', 0, t, 0, d, 0, hd, khoet)
        tam << hop('Hông dưới phải', lot, w, 0, d, 0, hd, khoet)
        tam << hop('Hông trên trái', 0, t, 0, d, hd, z_noc_tren)
        tam << hop('Hông trên phải', lot, w, 0, d, hd, z_noc_tren)

        # ── Bạ nóc: hai tấm đứng trên đầu hông + một tấm mặt trước lọt giữa ──
        tam << hop('Bạ nóc trái', 0, t, 0, d, z_noc_tren, h)
        tam << hop('Bạ nóc phải', lot, w, 0, d, z_noc_tren, h)
        tam << hop('Bạ nóc trước', t, lot, 0, t, z_noc_tren, h)

        # ── Xương bạ nóc: nằm trên nóc trên, trước 1 thanh + hai bên chạy tới tường ──
        z_xuong = [z_noc_tren, z_noc_tren + t]
        tam << hop('Xương bạ nóc trước', t, lot, t, t + ba, *z_xuong)
        tam << hop('Xương bạ nóc trái', t, t + p[:xuong_ben], t + ba, d, *z_xuong)
        tam << hop('Xương bạ nóc phải', lot - p[:xuong_ben], lot, t + ba, d, *z_xuong)

        # ── Tủ trên: nóc, đáy lọt giữa hông, thụt 'lui' ở trước, cách tường ở sau ──
        tam << hop('Nóc trên', t, lot, lui, y_sau, z_noc_tren - t, z_noc_tren)
        tam << hop('Đáy trên', t, lot, lui, y_sau, hd, hd + t)
        # Hậu ăn rãnh vào hai hông (sâu ranh_hau), KHÔNG rãnh ở nóc/đáy (Khoa 24/09)
        raise "Rãnh hậu #{p[:ranh_hau]}mm phải nông hơn ván #{t}mm." if p[:ranh_hau] >= t
        tam << hop('Hậu trên', t - p[:ranh_hau], lot + p[:ranh_hau],
                   y_sau - p[:van_hau], y_sau, hd + t, z_noc_tren - t, day_rieng: p[:van_hau])

        # ── Cánh lọt lòng: khe k mọi mặt tiếp giáp; dưới phủ che đáy trên + nóc dưới ──
        rong_canh = (w - 2 * t - 3 * k) / 2.0
        z_canh = [hd - t, z_noc_tren - k]
        tam << hop('Cánh trái', t + k, t + k + rong_canh, 0, t, *z_canh)
        tam << hop('Cánh phải', lot - k - rong_canh, lot - k, 0, t, *z_canh)

        # ── Chỗ tủ lạnh: nóc dưới + 4 bạ lưng sát sau, không hậu ──
        tam << hop('Nóc dưới', t, lot, lui, y_sau, hd - t, hd)
        z_ba1 = hd - t - ba             # bạ lưng 1 sát ngay dưới nóc dưới
        # Bạ lưng chân: sát chân, đáy cao hơn đỉnh chỗ khoét len ba_chan_cach_len (Khoa 24/09)
        z_chan = (co_len ? p[:len_cao] : 0.0) + p[:ba_chan_cach_len]
        # 2 bạ giữa: 3 khoảng hở bằng nhau từ đỉnh bạ chân tới đáy bạ lưng 1 (Khoa oke 24/09)
        ho = (z_ba1 - (z_chan + ba) - 2 * ba) / 3.0
        raise "Chỗ tủ lạnh #{hd}mm quá thấp để đặt 4 bạ lưng." if ho <= 0
        y_ba = [y_sau - t, y_sau]
        z_giua = z_chan + ba
        tam << hop('Bạ lưng 1', t, lot, *y_ba, z_ba1, z_ba1 + ba)
        tam << hop('Bạ lưng 2', t, lot, *y_ba, z_giua + 2 * ho + ba, z_giua + 2 * ho + 2 * ba)
        tam << hop('Bạ lưng 3', t, lot, *y_ba, z_giua + ho, z_giua + ho + ba)
        tam << hop('Bạ lưng chân', t, lot, *y_ba, z_chan, z_chan + ba)

        tam.each { |s| s[:kich_thuoc] = [s[:x], s[:y], s[:z]].map { |a, b| (b - a).round(1) }.sort }
        tam
      end
    end
  end
end
