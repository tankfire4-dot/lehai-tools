# encoding: UTF-8
# Ca thử LÕI TOÁN Tạo Bo (tao_bo/toan.rb) — chạy qua tests/tao_bo.test.mjs. Trả JSON {ten => kết quả}.
# Hình dựng bằng "con rùa": đi thẳng / rẽ theo cung R chia k đốt (giống SketchUp chia cung thành đoạn thẳng).

T = TK::TaoBo::Toan

module Rua
  # lenh: [[:thang, L], [:cung, goc_do (+ trái / − phải), R, so_dot]] ; dong: điểm khép thêm (mm, 2D)
  # Trả [pts 2D, khoa từng đoạn] — đoạn cung mang khóa "c<số lệnh>", đoạn thẳng nil.
  def self.di(lenh, dong = [], huong_do = 0.0)
    p = [0.0, 0.0]; phi = huong_do * Math::PI / 180
    pts = [p.dup]; khoa = []
    lenh.each_with_index do |l, li|
      if l[0] == :thang
        p = [p[0] + l[1] * Math.cos(phi), p[1] + l[1] * Math.sin(phi)]
        pts << p.dup; khoa << nil
      else
        th = l[1] * Math::PI / 180; r = l[2]; k = l[3]; s = th >= 0 ? 1 : -1
        tam = [p[0] - s * r * Math.sin(phi), p[1] + s * r * Math.cos(phi)]
        k.times do |j|
          f = phi + th * (j + 1) / k
          pts << [tam[0] + s * r * Math.sin(f), tam[1] - s * r * Math.cos(f)]
          khoa << "c#{li}"
        end
        phi += th
        p = pts.last.dup
      end
    end
    dong.each { |q| pts << q.map(&:to_f); khoa << nil }
    khoa << nil # đoạn khép cuối → điểm đầu
    pts.pop if (pts.last[0] - pts[0][0]).abs < 1e-9 && (pts.last[1] - pts[0][1]).abs < 1e-9 && (khoa.pop || true)
    [pts, khoa]
  end
end

# đưa vòng 2D lên 3D: mặt cắt ở cao độ z0, cục cao h; xoay quanh Z góc a, rồi (tuỳ) nghiêng trục
def dung(pts2, khoa, h: 710.0, a: 0.0, nam: false)
  ca = Math.cos(a * Math::PI / 180); sa = Math.sin(a * Math::PI / 180)
  bien = lambda do |x, y, z|
    x, y = x * ca - y * sa, x * sa + y * ca
    nam ? [x, z, -y] : [x, y, z] # nằm: trục đùn thành trục Y, cục nằm ngang
  end
  cap = pts2.map { |q| bien.(q[0], q[1], 0.0) }
  tat = pts2.map { |q| bien.(q[0], q[1], 0.0) } + pts2.map { |q| bien.(q[0], q[1], h) }
  [cap, khoa, tat]
end

def tom(r)
  return { ok: false, loi: r[:loi] } unless r[:ok]
  { ok: true, dai: r[:dai].round(4), cao: r[:cao].round(4), doan: r[:doan],
    vung: r[:vung].map { |v| [v[:s0].round(4), v[:s1].round(4), v[:loi]] },
    rg: r[:vung].map { |v| [v[:r] && v[:r].round(4), v[:goc].round(4)] },
    goc: r[:goc].map { |x| x.round(3) }, x: r[:truc_x].map { |x| x.round(4) },
    y: r[:truc_y].map { |x| x.round(4) }, z: r[:truc_z].map { |x| x.round(4) } }
end

def chay(pts2, khoa, **o)
  cap, k, tat = dung(pts2, khoa, **o)
  tom(T.phan_tich(cap, k, tat))
end

kq = {}

# 1. MẪU NTT 08/10: trước 450, cung R50 90° 20 đốt, hông 53, khép lưng 500 + hông trái 103
mau_pts, mau_k = Rua.di([[:thang, 450], [:cung, 90, 50, 20], [:thang, 53]], [[0, 103]])
kq['mau_ntt'] = chay(mau_pts, mau_k)
kq['mau_ntt_day_nguoc'] = chay(mau_pts.reverse, mau_k.reverse.rotate(1))
kq['mau_ntt_xoay'] = [90, 180, 270, 30].map { |a| [a, chay(mau_pts, mau_k, a: a)] }.to_h
kq['mau_ntt_nam'] = chay(mau_pts, mau_k, nam: true)
kq['mau_ntt_explode'] = chay(mau_pts, mau_k.map { nil })

# 2. chữ U: trái 300, cung 90 R40 12 đốt, đáy 500, cung 90 R60 16 đốt, phải 200
u_pts, u_k = Rua.di([[:thang, 300], [:cung, 90, 40, 12], [:thang, 500], [:cung, 90, 60, 16], [:thang, 200]], [], -90)
kq['chu_u'] = chay(u_pts, u_k)

# 3. chữ S: 300, trái 90 R50, 100, phải 90 R50, 300 → vùng 2 phải hạ nền mặt NGOÀI
s_pts, s_k = Rua.di([[:thang, 300], [:cung, 90, 50, 10], [:thang, 100], [:cung, -90, 50, 10], [:thang, 300]],
                    [[700, 400], [0, 400]])
kq['chu_s'] = chay(s_pts, s_k)

# 4. ca phải BÁO LỖI, không được ra số
kq['hop_khong_bo'] = chay([[0, 0], [500, 0], [500, 300], [0, 300], [0, 150]], [nil] * 5)
# hai chuỗi bo tách bởi góc gãy: góc bo dưới-phải + góc bo trên-trái
p2, k2 = Rua.di([[:thang, 400], [:cung, 90, 50, 10], [:thang, 300]], [])
p3, k3 = Rua.di([[:thang, 400], [:cung, 90, 50, 10], [:thang, 300]], [], 180)
p3 = p3.map { |q| [q[0] + 450, q[1] + 350] }
kq['hai_chuoi_bo'] = chay(p2 + p3[1...-1], k2[0...-1] + k3[0...-1].map { |x| x && "b#{x}" })
san_pts, san_k = Rua.di([[:thang, 400], [:cung, 180, 50, 12], [:thang, 400], [:cung, 180, 50, 12]], [])
kq['khep_tron'] = chay(san_pts, san_k)
cap, k, tat = dung(mau_pts, mau_k)
tat[5] = [tat[5][0], tat[5][1], 300.0]
kq['khong_dun_thang'] = tom(T.phan_tich(cap, k, tat))
# mặt trên bị một nét thừa chia đôi: mặt nhiều đỉnh nhất chỉ còn MỘT MẢNH của mặt cắt → phải báo, không trải thiếu
cap, k, tat = dung(mau_pts, mau_k)
manh = cap[0..12] # nửa mặt cắt (tới giữa cung), khép bằng nét thừa
kq['mat_bi_chia'] = tom(T.phan_tich(manh, k[0..12].tap { |a| a[-1] = nil }, tat))

# 4b. khúc bo dài theo dưỡng: đoạn thẳng giữ nguyên, tổng tấm đổi theo
mau = T.phan_tich(*dung(mau_pts, mau_k))
vr = lambda do |ds|
  r = T.vung_theo_rong(mau, ds)
  r[:ok] ? { dai: r[:dai].round(4), vung: r[:vung].map { |v| [v[:s0].round(4), v[:s1].round(4), v[:loi]] } } : r[:loi]
end
kq['rong_bang_cung'] = vr.([mau[:vung][0][:s1] - mau[:vung][0][:s0]])
kq['rong_54'] = vr.([54])
kq['rong_81'] = vr.([81])
kq['rong_0'] = vr.([0])
kq['rong_thieu_khuc'] = vr.([])
uu = T.phan_tich(*dung(u_pts, u_k))
r = T.vung_theo_rong(uu, [54, 81])
kq['u_54_81'] = { dai: r[:dai].round(4), vung: r[:vung].map { |v| [v[:s0].round(4), v[:s1].round(4), v[:loi]] } }

# 4c. KIỂU RÃNH LIỀN — 3 tấm NTT đo 08/10 (vị trí tính từ mép trái tấm), dao 6 · thịt 5 · biên 3
rl = lambda do |pts, k, bu: nil, d: 6, s: 5, x: 3|
  q = T.phan_tich(*dung(pts, k))
  r = T.ranh_lien(q, d: d, s: s, x: x, bu: bu || q[:vung].map { 0 })
  next r[:loi] unless r[:ok]
  { dai: r[:dai].round(3), buoc: r[:buoc], khuc: r[:khuc].map { |c| { n: c[:xs].size, r0: c[:xs].first.round(3), r1: c[:xs].last.round(3), b0: c[:b0].round(3), b1: c[:b1].round(3), ho: c[:ho].round(3), loi: c[:loi] } } }
end
kq['ranh_ntt1'] = rl.(mau_pts, mau_k)
n2p, n2k = Rua.di([[:thang, 523], [:cung, 90, 100, 40], [:thang, 172]], [[0, 272]])
kq['ranh_ntt2'] = rl.(n2p, n2k)
n3p, n3k = Rua.di([[:thang, 513], [:cung, 90, 50, 20], [:thang, 183]], [[0, 233]])
kq['ranh_ntt3'] = rl.(n3p, n3k)
r34p, r34k = Rua.di([[:thang, 450], [:cung, 90, 34, 20], [:thang, 53]], [[0, 103]])
kq['ranh_r34'] = rl.(r34p, r34k)
kq['ranh_bu_tru4'] = rl.(mau_pts, mau_k, bu: [-4])
kq['ranh_dao0'] = rl.(mau_pts, mau_k, d: 0)
kq['ranh_thit_qua_day'] = rl.(mau_pts, mau_k, s: 17.5)
kq['ranh_ket'] = rl.(mau_pts, mau_k, d: 1, s: 16)            # dao 1, da 16: rãnh khép kín trước 90°
nganp, ngank = Rua.di([[:thang, 2], [:cung, 90, 50, 20], [:thang, 53]], [[0, 103]])
kq['ranh_lo_dau_tam'] = rl.(nganp, ngank)                    # đoạn thẳng trước 2mm: rãnh đầu lòi khỏi tấm
kq['ranh_chu_u'] = rl.(u_pts, u_k)

# 5. NGẪU NHIÊN: 3000 cục 1–3 khúc bo góc 20–160°, R 5–300, 2–48 đốt, xoay bất kỳ, đảo chiều, Explode hết/một phần/không.
#    Đáp án tính độc lập từ lệnh rùa (không qua toan.rb): dài = Σ thẳng + Σ 2R·sin(θ/2k)·k ; vùng = đúng chỗ cung.
rng = Random.new(20261008)
sai = []; dem = Hash.new(0)
3000.times do |n|
  so = 1 + rng.rand(3)
  lenh = [[:thang, 20 + rng.rand(1500.0)]]
  dap = []; s = lenh[0][1]; tong_goc = 0
  so.times do
    g = 20 + rng.rand(140.0)
    g = [g, 175 - tong_goc].min
    break if g < 10
    r = 5 + rng.rand(295.0); k = 2 + rng.rand(47)
    w = k * 2 * r * Math.sin(g * Math::PI / 180 / (2 * k))
    lenh << [:cung, g, r, k]; dap << [s, s + w]; s += w; tong_goc += g
    l = 30 + rng.rand(800.0)
    lenh << [:thang, l]; s += l
  end
  pts, kh = Rua.di(lenh, [])
  # góc gãy ở 2 chỗ khép (đầu + cuối chuỗi), tính độc lập từ điểm rùa — dưới 50° là luật "báo, không đoán"
  hg = ->(a, b) { d = [b[0] - a[0], b[1] - a[1]]; l = Math.hypot(*d); [d[0] / l, d[1] / l] }
  gk = ->(d1, d2) { Math.acos([[d1[0] * d2[0] + d1[1] * d2[1], -1.0].max, 1.0].min) * 180 / Math::PI }
  khep = hg.(pts[-1], pts[0])
  goc_khep = [gk.(hg.(pts[-2], pts[-1]), khep), gk.(khep, hg.(pts[0], pts[1]))].min
  # 30% Explode hết, 20% Explode một phần (khúc nào bị thì mất khóa), còn lại giữ cung
  xx = rng.rand
  no = lenh.each_index.select { |li| lenh[li][0] == :cung }.select { xx < 0.3 || (xx < 0.5 && rng.rand < 0.5) }
  explode = !no.empty?
  kh = kh.map { |x| x && no.include?(x[1..].to_i) ? nil : x }
  if rng.rand < 0.5
    pts = pts.reverse; kh = kh.reverse.rotate(1)
  end
  r = chay(pts, kh, a: rng.rand(360.0), h: 100 + rng.rand(2400.0))
  # Explode chỉ đoán được khi đốt ≤ 25mm và gãy ≤ 30°; còn lại PHẢI báo lỗi chứ không ra số sai
  doan_duoc = goc_khep >= 50.5 && no.all? { |li| l = lenh[li]; 2 * l[2] * Math.sin(l[1] * Math::PI / 180 / (2 * l[3])) <= 25 && l[1] / l[3] <= 30 }
  if !r[:ok]
    dem[doan_duoc ? 'loi_oan' : 'bao_loi_dung'] += 1
    sai << [n, 'báo lỗi oan', r[:loi], lenh] if doan_duoc
    next
  end
  dem['ra_so'] += 1
  cung_l = lenh.select { |l| l[0] == :cung }
  ok_rg = r[:rg].zip(cung_l).all? { |(rr, gg), l| rr && (rr - l[2]).abs < 1e-3 && (gg - l[1]).abs < 1e-3 }
  sai << [n, 'sai R/góc', r[:rg], cung_l.map { |l| [l[2], l[1]] }] unless ok_rg
  ok = (r[:dai] - s).abs < 1e-3 && r[:vung].size == dap.size &&
       r[:vung].zip(dap).all? { |v, d| (v[0] - d[0]).abs < 1e-3 && (v[1] - d[1]).abs < 1e-3 && v[2] == true }
  sai << [n, 'sai số', r, s, dap, lenh, explode] unless ok
end
kq['ngau_nhien'] = { dem: dem, sai: sai.first(5), so_sai: sai.size }

# 6. RÃNH LIỀN NGẪU NHIÊN: 2000 cục 1–3 khúc + dao/thịt/biên/bù ngẫu nhiên. Luật kiểm ĐỘC LẬP với toan.rb:
#    bước đều = D+S · số rãnh = floor(khúc/bước)+1 · rãnh căn giữa và nằm gọn trong khúc · bảo vệ = khúc ± (D+X) ·
#    tổng tấm = cũ + Σbù · ca báo lỗi chỉ được là: rãnh lòi khỏi tấm / rãnh khép kín (kiểm lại bằng chính luật đó).
rng2 = Random.new(9102026)
sai2 = []; dem2 = Hash.new(0)
2000.times do |n|
  lenh = [[:thang, 5 + rng2.rand(800.0)]]
  (1 + rng2.rand(3)).times do
    lenh << [:cung, 30 + rng2.rand(60.0), 10 + rng2.rand(250.0), 4 + rng2.rand(40)]
    lenh << [:thang, 5 + rng2.rand(600.0)]
  end
  pts, kh = Rua.di(lenh, [])
  q = T.phan_tich(*dung(pts, kh, a: rng2.rand(360.0)))
  next dem2['cuc_loi'] += 1 unless q[:ok]
  d = 3 + rng2.rand(10.0); s = 1 + rng2.rand(10.0); x = rng2.rand(6.0)
  bu = q[:vung].map { rng2.rand < 0.5 ? 0 : rng2.rand(-5.0..5.0) }
  r = T.ranh_lien(q, d: d, s: s, x: x, bu: bu)
  p = d + s
  # đáp án độc lập: khúc mới, số rãnh, tâm rãnh
  dau = 0.0; cu = 0.0; ky = []
  q[:vung].each_with_index do |v, i|
    w = v[:s1] - v[:s0] + bu[i]; dau += v[:s0] - cu
    nn = (w / p + 1e-9).floor + 1; g = dau + w / 2
    ky << { s0: dau, s1: dau + w, n: nn, xs: (0...nn).map { |j| g + (j - (nn - 1) / 2.0) * p }, goc: v[:goc] }
    dau += w; cu = v[:s1]
  end
  dai = dau + (q[:dai] - cu)
  phai_loi = ky.any? { |c| c[:xs].first - d / 2 < -1e-6 || c[:xs].last + d / 2 > dai + 1e-6 || d - (q[:day] - s / 2.0) * c[:goc] * Math::PI / 180 / c[:n] <= 0 }
  if !r[:ok]
    dem2[phai_loi ? 'bao_loi_dung' : 'loi_oan'] += 1
    sai2 << [n, 'báo lỗi oan', r[:loi]] unless phai_loi
    next
  end
  dem2['ra_so'] += 1
  ok = !phai_loi && (r[:dai] - dai).abs < 1e-6 && r[:buoc] == p && r[:khuc].size == ky.size &&
       r[:khuc].zip(ky).all? do |c, e|
         c[:xs].size == e[:n] && c[:xs].zip(e[:xs]).all? { |u, w| (u - w).abs < 1e-6 } &&
           c[:xs].first >= e[:s0] - 1e-6 && c[:xs].last <= e[:s1] + 1e-6 &&
           (c[:b0] - (e[:s0] - d - x)).abs < 1e-6 && (c[:b1] - (e[:s1] + d + x)).abs < 1e-6
       end
  sai2 << [n, 'sai số', lenh, d, s, x, bu] unless ok
end
kq['ranh_ngau_nhien'] = { dem: dem2, sai: sai2.first(3), so_sai: sai2.size }

# Khúc bo SÁT góc gãy (soát 09/10): đầu/cuối chuỗi là góc vuông của hình, không có đoạn thẳng tiếp tuyến.
# Trước bản vá: R50 90° ra R51,28 · 87,75° → bảng không tự chọn dưỡng 81.
p, k = Rua.di([[:thang, 500], [:cung, 90, 50, 20]], [[0, 50]])
kq['bo_cuoi_chuoi'] = chay(p, k)
p, k = Rua.di([[:cung, 90, 50, 20], [:thang, 500]], [[-200, 550], [-200, -100], [0, -100]])
kq['bo_dau_chuoi'] = chay(p, k)
p, k = Rua.di([[:thang, 500], [:cung, 90, 34, 12]], [[0, 34]])
kq['bo_cuoi_r34'] = chay(p, k)

JSON.generate(kq)
