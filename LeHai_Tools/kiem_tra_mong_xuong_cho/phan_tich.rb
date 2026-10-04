# encoding: UTF-8
# Lõi Kiểm Mộng Xương Chó — THUẦN RUBY, không gọi SketchUp (thử được ngoài SketchUp).
#
# Câu hỏi duy nhất: RĂNG của một tấm găm vào lòng tấm khác thì chỗ đó trên tấm nhận có DẤU KHOÉT
# (_ABF_Intersect) phủ kín chân răng không? Thiếu → CNC cắt tấm nhận nguyên khối, lắp không vào, phôi phế.
#
# Vì sao không dựa KT Liên Kết (soát 04/10): nó coi cả đầu tấm là một khối giao rồi rải 27 điểm mẫu.
# Răng xương chó chỉ chiếm vài khúc trên đầu tấm → phần lớn điểm rơi vào khe giữa răng → tỉ lệ đâm xuyên
# dưới 40% → bị hiểu nhầm là "đã khấu tay" → ĐẠT dù dấu đã bị xóa. Ở đây xét TỪNG RĂNG.
#
# Đầu vào: mảng tấm, toạ độ THẾ GIỚI, đơn vị MM:
#   { id:, ten:, mat: [{ ngoai: [[x,y,z]...], lo: [[[x,y,z]...]...] }...],   # mặt RIÊNG của tấm (vòng ngoài + lỗ)
#     dau: [{ mat: [[[x,y,z]...]...], sau: mm|nil }...] }                    # dấu ABF con của tấm; sau = độ sâu khai
# Đầu ra: { so_tam:, so_rang:, loi: [răng...], dat: [răng...], hop: {id => 8 góc} }
#
# Nhận RĂNG bằng HÌNH, không bằng ghi nhớ của tool Mộng (tấm copy / import / sửa tay vẫn bắt được):
# một mặt của tấm A song song mặt lớn tấm B, nằm LỌT trong bề dày B, hẹp hơn đầu tấm A (cả đầu găm
# vào = ngàm thường — việc của KT Liên Kết), và chỗ đó B còn gỗ (B đã khoét tay thì không tính).

module TK
  module DogboneCheck
    module PhanTich
      SAI       = 0.05    # mm — điểm cách mặt phẳng dưới mức này coi là NẰM TRÊN (SketchUp gộp điểm < 0,0254)
      VAO_MIN   = 0.5     # mm — găm nông hơn mức này coi như chỉ chạm mặt, không phải răng
      SONG_SONG = 0.9999  # cos góc — hai mặt lệch dưới ~0,8° coi là song song
      MOT_PHAN  = 0.9     # mặt găm rộng dưới 90% đầu tấm = RĂNG; rộng hơn = cả đầu găm (ngàm thường)
      RONG_MIN  = 1.0     # mm — mặt găm hẹp hơn mức này là mảnh vụn hình học, bỏ
      MAU       = 5       # lưới điểm mẫu trên chân răng: MAU dọc răng × MAU ngang bề dày
      NONG      = 0.1     # mm — dấu khai sâu kém răng quá mức này = dấu nông, CNC phay không tới đáy răng
      DAY_MIN   = 3.0     # mm — bề dày tấm ván hợp lệ (cùng mức KT Liên Kết)
      DAY_MAX   = 40.0

      # ── Véc-tơ ──────
      def self.tru(a, b); [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; end
      def self.cong(a, b); [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; end
      def self.nhan(a, k); [a[0] * k, a[1] * k, a[2] * k]; end
      def self.cham(a, b); a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; end
      def self.cheo(a, b); [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; end
      def self.dai(a); Math.sqrt(cham(a, a)); end
      def self.don_vi(a); l = dai(a); l < 1e-12 ? nil : nhan(a, 1.0 / l); end
      def self.tb(pts); nhan(pts.reduce([0.0, 0.0, 0.0]) { |s, p| cong(s, p) }, 1.0 / pts.length); end

      # Pháp tuyến Newell: độ dài = 2 × diện tích đa giác, đúng cả với đa giác lõm (răng, cung cổ).
      def self.newell(pts)
        n = [0.0, 0.0, 0.0]
        pts.each_with_index do |p, i|
          q = pts[(i + 1) % pts.length]
          n[0] += (p[1] - q[1]) * (p[2] + q[2])
          n[1] += (p[2] - q[2]) * (p[0] + q[0])
          n[2] += (p[0] - q[0]) * (p[1] + q[1])
        end
        n
      end

      # Hai trục nằm trong mặt phẳng pháp tuyến n — để đưa điểm về 2D.
      def self.he_phang(n)
        tam = n[0].abs < 0.9 ? [1.0, 0.0, 0.0] : [0.0, 1.0, 0.0]
        u = don_vi(cheo(n, tam))
        [u, cheo(n, u)]
      end

      # Điểm 2D trong đa giác (tia ngang, đếm lẻ). Đa giác lõm vẫn đúng.
      def self.trong_da_giac?(x, y, poly)
        trong = false
        j = poly.length - 1
        poly.each_with_index do |(xi, yi), i|
          xj, yj = poly[j]
          trong = !trong if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi
          j = i
        end
        trong
      end

      # ── Chuẩn bị một tấm ──────
      # Pháp tuyến bề dày = pháp tuyến MẶT LỚN NHẤT (mặt profile — tấm có răng vẫn đúng).
      # nil nếu không phải tấm ván (bề dày ngoài 3–40 mm).
      def self.chuan_bi(t)
        # Pháp tuyến từng mặt tính MỘT lần ở đây (mỗi cặp tấm dùng lại — 400 tấm wasm 6,2 s → nhanh hơn).
        mats = (t[:mat] || []).select { |m| m[:ngoai] && m[:ngoai].length >= 3 }.map { |m|
          nw = newell(m[:ngoai])
          m.merge(n: don_vi(nw), dt: dai(nw))
        }.select { |m| m[:n] }
        return nil if mats.length < 4
        lon = mats.max_by { |m| m[:dt] }
        n = lon[:n]
        return nil unless n
        dinh = mats.flat_map { |m| m[:ngoai] + (m[:lo] || []).flatten(1) }.uniq # mỗi đỉnh nằm ở ~3 mặt
        lo, hi = dinh.map { |p| cham(p, n) }.minmax
        return nil unless hi - lo >= DAY_MIN && hi - lo <= DAY_MAX
        # Hộp riêng của tấm (theo cạnh dài nhất của mặt lớn) — để vẽ khi Xem, tấm xoay vẫn ôm sát.
        canh = lon[:ngoai].each_with_index.map { |p, i| tru(lon[:ngoai][(i + 1) % lon[:ngoai].length], p) }
        d1 = don_vi(canh.max_by { |c| dai(c) })
        d1 = don_vi(tru(d1, nhan(n, cham(d1, n)))) || he_phang(n)[0]
        d2 = cheo(n, d1)
        r1 = dinh.map { |p| cham(p, d1) }.minmax
        r2 = dinh.map { |p| cham(p, d2) }.minmax
        hop = [0, 1].product([0, 1], [0, 1]).map { |a, b, c|
          cong(cong(nhan(d1, r1[a]), nhan(d2, r2[b])), nhan(n, [lo, hi][c]))
        }
        box = (0..2).map { |k| dinh.map { |p| p[k] }.minmax }
        { id: t[:id], ten: t[:ten], n: n, lo: lo, hi: hi, day: hi - lo, mats: mats, dinh: dinh,
          box: box, hop: hop, dau: t[:dau] || [] }
      end

      # Vòng ngoài + lỗ của các mặt nằm trên mặt phẳng {p : p·n = muc}, đưa về 2D theo (u, v).
      def self.mat_tren(mats, n, muc, u, v)
        mats.select { |m|
          nm = m[:n] || don_vi(newell(m[:ngoai]))
          nm && cham(nm, n).abs > SONG_SONG && m[:ngoai].all? { |p| (cham(p, n) - muc).abs < SAI }
        }.map { |m|
          to2 = ->(lp) { lp.map { |p| [cham(p, u), cham(p, v)] } }
          { ngoai: to2.call(m[:ngoai]), lo: (m[:lo] || []).map(&to2) }
        }
      end

      def self.trong_mat?(x, y, mats2)
        mats2.any? { |m| trong_da_giac?(x, y, m[:ngoai]) && m[:lo].none? { |l| trong_da_giac?(x, y, l) } }
      end

      # ── Răng của tấm a găm vào tấm b ──────
      def self.rang_vao(a, b)
        n = b[:n]
        return [] if cham(a[:n], n).abs > SONG_SONG # hai tấm song song: chồng mặt, không phải răng
        # Mặt vào = mặt lớn của b phía THÂN tấm a = phía a thò ra xa hơn. Không lấy trọng tâm đỉnh: mỗi
        # răng ~60 đỉnh dồn ở đầu tấm, kéo trọng tâm lọt vào lòng b.
        a_lo, a_hi = a[:dinh].map { |p| cham(p, n) }.minmax
        tho_lo = b[:lo] - a_lo
        tho_hi = a_hi - b[:hi]
        if tho_lo > tho_hi && tho_lo > VAO_MIN then vao = b[:lo]; chieu = 1.0
        elsif tho_hi > VAO_MIN then vao = b[:hi]; chieu = -1.0
        else return []
        end
        e = don_vi(cheo(a[:n], n)) # dọc đầu tấm a (dọc hàng răng)
        return [] unless e
        w = don_vi(tru(a[:n], nhan(n, cham(a[:n], n)))) # bề dày a, chiếu vào mặt b
        rong_a = a[:dinh].map { |p| cham(p, e) }.minmax.reverse.reduce(:-)
        u, v = he_phang(n)
        go = mat_tren(b[:mats], n, vao, u, v)
        return [] if go.empty?
        dau = b[:dau].map { |d| { sau: d[:sau], mat: mat_tren(d[:mat].map { |p| { ngoai: p } }, n, vao, u, v) } }
                     .reject { |d| d[:mat].empty? }
        out = []
        a[:mats].each do |f|
          next unless cham(f[:n], n).abs > SONG_SONG
          muc = cham(f[:ngoai][0], n)
          next unless f[:ngoai].all? { |p| (cham(p, n) - muc).abs < SAI }
          sau = (muc - vao) * chieu
          next unless sau > VAO_MIN && sau < b[:day] - VAO_MIN # lọt trong lòng tấm b
          re = f[:ngoai].map { |p| cham(p, e) }.minmax
          rong = re[1] - re[0]
          next unless rong >= RONG_MIN && rong < MOT_PHAN * rong_a
          # Chân răng = mặt đỉnh chiếu thẳng về mặt vào của b.
          chan = ->(pe, pw) { cong(cong(nhan(e, pe), nhan(w, pw)), nhan(n, vao)) }
          rw = f[:ngoai].map { |p| cham(p, w) }.minmax
          giua = chan.call((re[0] + re[1]) / 2.0, (rw[0] + rw[1]) / 2.0)
          next unless trong_mat?(cham(giua, u), cham(giua, v), go) # b đã khoét / khe ở đó → không tính
          # Lưới mẫu lùi 10% mỗi mép: dọc răng chỗ nào cũng phải có ít nhất một điểm ngang bề dày nằm
          # trong dấu (dấu thu một mặt hẹp hơn răng 3D — CNC phay bớt răng, nên không đòi phủ đủ bề dày).
          buoc = ->(r, i) { r[0] + (r[1] - r[0]) * (0.1 + 0.8 * i / (MAU - 1)) }
          trung = ->(p) { dau.find { |d| trong_mat?(cham(p, u), cham(p, v), d[:mat]) } }
          hang = (0...MAU).map { |i| (0...MAU).any? { |k| trung.call(chan.call(buoc.call(re, i), buoc.call(rw, k))) } }
          loai = if hang.none? then :thieu
                 elsif !hang.all? then :lech
                 end
          d0 = loai ? nil : (0...MAU).map { |k| trung.call(chan.call((re[0] + re[1]) / 2.0, buoc.call(rw, k))) }.compact.first
          loai = :nong if d0 && d0[:sau] && d0[:sau] < sau - NONG
          out << { a: a[:id], b: b[:id], ten_a: a[:ten], ten_b: b[:ten], loai: loai, sau: sau.round(1),
                   dau_sau: d0 && d0[:sau], giua: giua,
                   chan: [[re[0], rw[0]], [re[1], rw[0]], [re[1], rw[1]], [re[0], rw[1]]].map { |pe, pw| chan.call(pe, pw) },
                   dinh: f[:ngoai] }
        end
        out
      end

      # ── Soát cả model ──────
      def self.soat(tam_list)
        ds = tam_list.map { |t| t[:chuan] || chuan_bi(t) }.compact.sort_by { |t| t[:box][0][0] }
        rang = []
        ds.each_with_index do |a, i|
          ((i + 1)...ds.length).each do |j|
            b = ds[j]
            break if b[:box][0][0] > a[:box][0][1] - VAO_MIN
            next unless (0..2).all? { |k| [a[:box][k][1], b[:box][k][1]].min - [a[:box][k][0], b[:box][k][0]].max > VAO_MIN }
            rang.concat(rang_vao(a, b))
            rang.concat(rang_vao(b, a))
          end
        end
        { so_tam: ds.length, so_rang: rang.length, loi: rang.select { |r| r[:loai] }, dat: rang.reject { |r| r[:loai] },
          hop: ds.map { |t| [t[:id], t[:hop]] }.to_h }
      end

      # Câu báo một răng — dùng chung cho bảng Xem và dashboard.
      def self.cau(r)
        case r[:loai]
        when :thieu then "Răng găm #{r[:sau]} mm vào tấm nhận mà chỗ đó KHÔNG có dấu khoét — CNC không phay lỗ"
        when :lech  then "Dấu khoét không phủ hết chân răng (lệch hoặc thiếu một phần) — răng găm #{r[:sau]} mm"
        when :nong  then "Dấu khoét khai sâu #{r[:dau_sau]} mm, nông hơn răng #{r[:sau]} mm — răng không vào hết"
        else "Răng găm #{r[:sau]} mm — có dấu khoét phủ kín ✓"
        end
      end
    end
  end
end
