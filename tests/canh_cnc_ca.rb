# encoding: UTF-8
# Ca thử Tạo Cánh CNC — CanhCNC.door_layout (công thức CHUNG cho xem trước + dựng thật). Chạy qua tests/canh_cnc.test.mjs.
# Viết 09/10/2026 (soát toàn bộ plugin): module này ra hàng thật mà trước đó chưa có bộ thử tự động nào.
# door_layout nhận 2 điểm (inch, hệ cánh) + thông số (mm), trả cánh [vị trí ngang, vị trí cao, sâu, rộng, cao] (mm).

class Geom::Vector3d
  def cross(o); self * o; end
end

P = ->(x, y, z) { Geom::Point3d.new(x.mm, y.mm, z.mm) }
TS = ->(h = {}) { { so_canh: 2, chieu_canh: 'dung', day: 17.5, ho_tren: 0.0, ho_duoi: 0.0, ho_trai: 2.0, ho_phai: 2.0, ho_giua: 2.0 }.merge(h) }
tron = ->(a) { a.map { |d| d.map { |x| x.round(4) } } }

kq = {}
# 1. khoang mặt trước 800 × 700, 2 cánh đứng, hở trái/phải/giữa 2 → mỗi cánh (800 − 2 − 2 − 2) / 2 = 397
r = CanhCNC.door_layout(P.(0, 0, 0), P.(800, 0, 700), TS.())
kq['hai_canh_dung'] = { plane: r[:plane].to_s, doors: tron.(r[:doors]) }
# 2. 3 cánh nằm ngang (chia trên-dưới), hở trên 3 dưới 1, giữa 2 → mỗi cánh (700 − 3 − 1 − 4) / 3 = 230,6667
r = CanhCNC.door_layout(P.(0, 0, 0), P.(800, 0, 700), TS.(so_canh: 3, chieu_canh: 'ngang', ho_tren: 3.0, ho_duoi: 1.0))
kq['ba_canh_ngang'] = { doors: tron.(r[:doors]) }
# 3. bấm 2 điểm theo thứ tự ngược (góc trên-phải trước) → y hệt ca 1
r = CanhCNC.door_layout(P.(800, 0, 700), P.(0, 0, 0), TS.())
kq['bam_nguoc'] = tron.(r[:doors]) == kq['hai_canh_dung'][:doors]
# 4. mặt hông (yz)
r = CanhCNC.door_layout(P.(0, 0, 0), P.(0, 600, 720), TS.(so_canh: 1))
kq['mat_hong'] = { plane: r[:plane].to_s, doors: tron.(r[:doors]) }
# 5. lỗi phải báo, KHÔNG ra cánh
kq['qua_nho'] = CanhCNC.door_layout(P.(0, 0, 0), P.(5, 0, 700), TS.())[:error].to_s
kq['ho_vuot_ngang'] = CanhCNC.door_layout(P.(0, 0, 0), P.(20, 0, 700), TS.(ho_trai: 8.0, ho_phai: 8.0, ho_giua: 4.0))[:error].to_s
kq['ho_vuot_doc'] = CanhCNC.door_layout(P.(0, 0, 0), P.(800, 0, 20), TS.(chieu_canh: 'ngang', so_canh: 3, ho_tren: 8.0, ho_duoi: 8.0))[:error].to_s
kq['mat_nam'] = CanhCNC.door_layout(P.(0, 0, 0), P.(800, 600, 0), TS.())[:error].to_s

# 6. NGẪU NHIÊN 3000 khoang: luật độc lập — cánh nằm gọn trong khoang, mép cánh cách mép khoang đúng hở,
#    khe giữa 2 cánh liền nhau đúng "hở giữa", các cánh bằng nhau, tổng (cánh + hở) = đúng kích thước khoang.
rng = Random.new(9102026)
sai = []; dem = Hash.new(0)
3000.times do |n|
  w = 30 + rng.rand(2400.0); h = 30 + rng.rand(2400.0)
  ngang = rng.rand < 0.4
  t = TS.(so_canh: 1 + rng.rand(6), chieu_canh: ngang ? 'ngang' : 'dung', ho_tren: rng.rand(10.0), ho_duoi: rng.rand(10.0),
          ho_trai: rng.rand(10.0), ho_phai: rng.rand(10.0), ho_giua: rng.rand(6.0))
  x0 = rng.rand(-3000.0..3000.0); z0 = rng.rand(0.0..2000.0); y0 = rng.rand(-3000.0..3000.0)
  a = P.(x0, y0, z0); b = P.(x0 + w, y0, z0 + h)
  a, b = b, a if rng.rand < 0.5
  r = CanhCNC.door_layout(a, b, t)
  can = ngang ? t[:ho_tren] + t[:ho_duoi] + (t[:so_canh] - 1) * t[:ho_giua] : t[:ho_trai] + t[:ho_phai] + (t[:so_canh] - 1) * t[:ho_giua]
  tong = ngang ? h : w
  if r[:error]
    ok = (r[:error] == :gap_h || r[:error] == :gap_w) && can >= tong - 1e-6
    dem[ok ? 'bao_loi_dung' : 'loi_oan'] += 1
    sai << [n, 'báo lỗi oan', r[:error], w, h, t] unless ok
    next
  end
  dem['ra_canh'] += 1
  d = r[:doors]
  e = 1e-6
  ok = d.size == t[:so_canh] && d.all? { |c| c[3] > 0 && c[4] > 0 } &&
       d.map { |c| [c[3].round(6), c[4].round(6)] }.uniq.size == 1
  if ngang
    ok &&= d.all? { |c| (c[0] - (x0 + t[:ho_trai])).abs < e && (c[3] - (w - t[:ho_trai] - t[:ho_phai])).abs < e }
    ok &&= (d.first[1] - (z0 + t[:ho_duoi])).abs < e && (d.last[1] + d.last[4] - (z0 + h - t[:ho_tren])).abs < e
    ok &&= d.each_cons(2).all? { |p, q| (q[1] - (p[1] + p[4]) - t[:ho_giua]).abs < e }
  else
    ok &&= d.all? { |c| (c[1] - (z0 + t[:ho_duoi])).abs < e && (c[4] - (h - t[:ho_tren] - t[:ho_duoi])).abs < e }
    ok &&= (d.first[0] - (x0 + t[:ho_trai])).abs < e && (d.last[0] + d.last[3] - (x0 + w - t[:ho_phai])).abs < e
    ok &&= d.each_cons(2).all? { |p, q| (q[0] - (p[0] + p[3]) - t[:ho_giua]).abs < e }
  end
  ok &&= d.all? { |c| (c[2] - y0).abs < e } # cánh nằm đúng mặt phẳng khoang
  sai << [n, 'sai số', w, h, t, d] unless ok
end
kq['ngau_nhien'] = { dem: dem, so_sai: sai.size, sai: sai.first(3).map(&:inspect) }

JSON.generate(kq)
