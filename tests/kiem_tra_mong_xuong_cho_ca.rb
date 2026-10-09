# encoding: UTF-8
# Ca thử Kiểm Mộng Xương Chó (kiem_tra_mong_xuong_cho/phan_tich.rb) — chạy bằng tests/kiem_tra_mong_xuong_cho.test.mjs.
#
# HÌNH THỬ LẤY TỪ CODE THẬT của tool Mộng (mong_xuong_cho/main.rb): plan_edge tính răng + dấu âm trên tấm
# nhận (qua contact_info thật), chen_rang chèn răng vào viền tấm. Test chỉ tự làm phần ĐÙN viền thành khối
# và đổi toạ độ — không tự vẽ răng theo trí nhớ (bài học 04/10: người viết chỉ thử cái mình tưởng tượng).
#
# Biến thể TỰ SINH (hạt cố định → chạy lại ra y hệt): số mộng, dài đầu, cao mộng (cả 13–14,9 — khe giữa hai
# khung độ ăn sâu của KT Liên Kết), thu một mặt A/B, đầu 1–4, tấm đứng (mỏng theo X hoặc Y) / nằm ngang,
# cả cụm xoay quanh Z, nghiêng 30°, lật gương. Trên mỗi biến thể: làm hỏng có chủ đích, biết trước đáp án.
M = TK::MongXuongCho
P = TK::DogboneCheck::PhanTich
IN = 25.4 # SketchUp tính inch; lõi kiểm nhận mm

# ── SketchUp giả cho TẤM NHẬN (plan_edge đọc cạnh/mặt/nhóm con của nó) ──────
VTX = Struct.new(:position)
class GEdge < Sketchup::Edge
  def initialize(a, b); @a = VTX.new(a); @b = VTX.new(b); end
  def start; @a; end
  def end; @b; end
end
# Mặt hộp thẳng trục local: trục k cố định = muc, hai trục còn lại trong [lo, hi].
class GFace < Sketchup::Face
  PointOutside = 16
  attr_reader :k, :muc
  def initialize(k, muc, lo, hi, chieu); @k = k; @muc = muc; @lo = lo; @hi = hi; @chieu = chieu; end
  def normal; v = [0.0, 0.0, 0.0]; v[@k] = @chieu; Geom::Vector3d.new(v); end
  def goc
    o = ([0, 1, 2] - [@k])
    [[0, 0], [1, 0], [1, 1], [0, 1]].map { |a, b|
      p = [0.0, 0.0, 0.0]; p[@k] = @muc; p[o[0]] = [@lo[o[0]], @hi[o[0]]][a]; p[o[1]] = [@lo[o[1]], @hi[o[1]]][b]
      Geom::Point3d.new(p)
    }
  end
  def vertices; goc.map { |p| VTX.new(p) }; end
  def classify_point(pt)
    a = pt.to_a
    return PointOutside unless (a[@k] - @muc).abs < 1e-6
    (([0, 1, 2] - [@k]).all? { |i| a[i] >= @lo[i] - 1e-9 && a[i] <= @hi[i] + 1e-9 }) ? PointInside : PointOutside
  end
end
class GHop
  attr_reader :transformation, :entities, :lo, :hi
  def initialize(tr, lo, hi)
    @transformation = tr; @lo = lo; @hi = hi
    c = [0, 1].product([0, 1], [0, 1]).map { |a, b, d| Geom::Point3d.new([[lo, hi][a][0], [lo, hi][b][1], [lo, hi][d][2]]) }
    canh = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
    @entities = canh.map { |i, j| GEdge.new(c[i], c[j]) } +
                (0..2).flat_map { |k| [GFace.new(k, lo[k], lo, hi, -1.0), GFace.new(k, hi[k], lo, hi, 1.0)] }
  end
end
Nguon = Struct.new(:transformation)

# ── Phép biến đổi thế giới (xoay Z, nghiêng X, lật gương) ──────
def bien(goc_z, nghieng, guong, dich)
  c = Math.cos(goc_z); s = Math.sin(goc_z)
  rz = [[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]]
  cx = Math.cos(nghieng); sx = Math.sin(nghieng)
  rx = [[1.0, 0.0, 0.0], [0.0, cx, -sx], [0.0, sx, cx]]
  g = [[guong ? -1.0 : 1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
  mul = ->(a, b) { (0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| a[i][k] * b[k][j] } } } }
  Geom::Transformation.new(mul.call(mul.call(rz, rx), g), dich.map(&:mm))
end
def mm(tr, p); (tr * Geom::Point3d.new(p.to_a)).to_a.map { |v| v * IN }; end

# Hộp lo..hi (inch, hệ tr) → 6 mặt thế giới mm; lo_mat = {chỉ số mặt => [lỗ (mm thế giới)]}.
def mat_hop(tr, lo, hi, lo_mat = {})
  GHop.new(tr, lo, hi).entities.grep(GFace).each_with_index.map { |f, i|
    { ngoai: f.goc.map { |p| mm(tr, p) }, lo: lo_mat[i] || [] }
  }
end

# ── Dựng một cặp ngàm → nhận bằng code thật ──────
# kieu: :dung_y (mỏng theo Y), :dung_x (mỏng theo X), :nam (mỏng theo Z — đợt)
def dung(cfg)
  dai, cao, day = cfg[:dai].mm, 300.mm, 17.5.mm
  lo = [0.0, 0.0, 0.0]
  hi = case cfg[:kieu]
       when :dung_y then [dai, day, cao]
       when :dung_x then [day, dai, cao]
       else [dai, cao, day]
       end
  box = Geom::BoundingBox.new.add(Geom::Point3d.new(lo), Geom::Point3d.new(hi))
  w = bien(cfg[:goc], cfg[:nghieng], cfg[:guong], [1000, -500, 200])
  src = Nguon.new(w)
  fd = M.frame_for(src, cfg[:canh], box)
  top = fd[:bounds].depth
  len = [fd[:bounds].width, fd[:bounds].height][fd[:u]]
  # Tấm nhận dày 18: ôm đầu mộng, thò 50 hai đầu cạnh và 100 hai bên bề dày; nằm sau mặt đầu (z ≥ top).
  rlo = [0.0, 0.0, top]; rhi = [0.0, 0.0, top + 18.mm]
  rlo[fd[:u]] = -50.mm; rhi[fd[:u]] = len + 50.mm
  rlo[fd[:thin]] = -100.mm; rhi[fd[:thin]] = [fd[:bounds].width, fd[:bounds].height][fd[:thin]] + 100.mm
  rtr = w * fd[:frame]
  recv = GHop.new(rtr, rlo, rhi)
  spec = { 'edge' => cfg[:canh], 'count' => cfg[:so], 'head' => 35, 'height' => cfg[:cao], 'neck' => 6, 'bevel' => 1,
           'inset' => cfg[:lui], 'side' => cfg[:ben], 'fit' => cfg[:fit], 'slackT' => 0.2, 'slackL' => 0.2, 'cutter' => 6 }
  plan = M.plan_edge(src, spec, recv, box, '')
  # Viền tấm ngàm (mặt A, hệ cạnh đầu 1) → chèn răng thật → đùn qua bề dày.
  fd1 = M.frame_for(src, 1, box)
  thin = fd1[:thin]; u1 = fd1[:u]
  b1 = [fd1[:bounds].width, fd1[:bounds].height, fd1[:bounds].depth]
  vien = [[0, 0], [b1[u1], 0], [b1[u1], b1[2]], [0, b1[2]]].map { |a, z| p = [0.0, 0.0, z]; p[u1] = a; p }
  prof = { fd1: fd1, thin: thin, thickness: b1[thin], outer: vien, inner: [] }
  pts = M.chen_rang(prof, [plan], '')
  sau_pts = pts.map { |p| q = p.dup; q[thin] += b1[thin]; q }
  to_w = ->(p) { mm(w * fd1[:frame], p) }
  mat_a = [{ ngoai: pts.map(&to_w) }, { ngoai: sau_pts.map(&to_w).reverse }] +
          pts.each_index.map { |i| j = (i + 1) % pts.length; { ngoai: [pts[i], pts[j], sau_pts[j], sau_pts[i]].map(&to_w) } }
  dau = plan[:mortises].map { |poly| { mat: [poly.map { |p| mm(rtr, p) }], sau: cfg[:cao].to_f } }
  # Mặt tiếp giáp của tấm nhận = mặt z = top trong hệ cạnh (chỉ số 4 trong GHop: k = 2, lo)
  { plan: plan, w: w, fd: fd, rtr: rtr, rlo: rlo, rhi: rhi, mat_a: mat_a, dau: dau,
    tam_dau: dau.map { |d| P.tb(d[:mat][0]) }, doc: mm(w * fd[:frame], [0, 0, 0]).zip(mm(w * fd[:frame], (v = [0.0, 0, 0]; v[fd[:u]] = 1.mm; v))).map { |a, b| b - a } }
end

def tam(id, mat, dau = []); { id: id, ten: id, mat: mat, dau: dau }; end
def chay(d, dau_b: d[:dau], lo_vao: nil, dau_a: [])
  tl = [tam('ngam', d[:mat_a], dau_a), tam('nhan', mat_hop(d[:rtr], d[:rlo], d[:rhi], lo_vao ? { 4 => lo_vao } : {}), dau_b)]
  P.soat(tl)
end

out = []
def ca(out, ten)
  r = yield
  out << { ten: ten, dat: r[0] ? true : false, kq: r[1].to_s }
rescue StandardError => e
  out << { ten: ten, dat: false, kq: "LỖI #{e.class}: #{e.message} #{(e.backtrace || []).first(3).join(' | ')}" }
end

# ── Sinh biến thể ──────
rng = Random.new(20261004)
cfgs = []
while cfgs.length < 80
  kieu = %i[dung_y dung_x nam].sample(random: rng)
  dai = [60, 90, 140, 200, 350, 600, 900][rng.rand(7)]
  cao = [8, 10, 11, 13, 14.5, 16][rng.rand(6)]
  ben = %w[none A B][rng.rand(3)]
  cfg = { kieu: kieu, dai: dai, cao: cao, ben: ben, fit: [15, 14, 13.5][rng.rand(3)], canh: 1 + rng.rand(4),
          goc: [0, 90, 180, 270, 37][rng.rand(5)] * Math::PI / 180, nghieng: rng.rand(4).zero? ? Math::PI / 6 : 0.0,
          guong: rng.rand(4).zero?, lui: 50, so: 1 + rng.rand(5) }
  d = nil
  cfg[:so].downto(1) do |n| # số mộng không vừa thì giảm như người dùng sẽ làm
    begin
      cfg[:so] = n
      cfg[:lui] = n == 1 ? 50 : [50, 20.0 + rng.rand(10)].max
      d = dung(cfg)
      break
    rescue RuntimeError
      d = nil
    end
  end
  cfgs << [cfg, d] if d
end
ten = ->(c) { "#{c[:kieu]} dài #{c[:dai]} đầu #{c[:canh]} #{c[:so]} mộng cao #{c[:cao]} #{c[:ben] == 'none' ? 'không thu' : "giữ #{c[:ben]} dày #{c[:fit]}"}#{c[:nghieng] > 0 ? ' nghiêng 30°' : ''}#{c[:guong] ? ' lật gương' : ''} xoay #{(c[:goc] * 180 / Math::PI).round}°" }
gan = ->(p, q, tol) { P.dai(P.tru(p, q)) < tol }

dem = Hash.new(0)
loi_ca = []
cfgs.each do |cfg, d|
  n = cfg[:so]
  # 1. Đủ dấu → không lỗi, đếm đủ răng
  r = chay(d)
  (r[:loi].empty? && r[:so_rang] == n) ? dem[:du] += 1 : loi_ca << "ĐỦ DẤU #{ten.(cfg)}: #{r[:so_rang]} răng, #{r[:loi].length} lỗi #{r[:loi].map { |x| x[:loai] }}"
  # 2. Xóa k dấu ngẫu nhiên → đúng k răng :thieu, đúng chỗ
  k = 1 + rng.rand(n)
  xoa = (0...n).to_a.sample(k, random: rng)
  r = chay(d, dau_b: d[:dau].each_with_index.reject { |_x, i| xoa.include?(i) }.map(&:first))
  dung_cho = xoa.all? { |i| r[:loi].any? { |x| gan.(x[:giua], d[:tam_dau][i], 17.5) } }
  (r[:loi].length == k && r[:loi].all? { |x| x[:loai] == :thieu } && dung_cho) ? dem[:xoa] += 1 : loi_ca << "XÓA #{k}/#{n} #{ten.(cfg)}: #{r[:loi].map { |x| x[:loai] }} đúng chỗ=#{dung_cho}"
  # 3. Dời 1 dấu 20 mm dọc đầu tấm → răng đó :lech (hoặc :thieu nếu dời trượt hẳn), răng khác không sao
  i = rng.rand(n)
  doi = d[:dau].each_with_index.map { |x, j| j == i ? { mat: [x[:mat][0].map { |p| P.cong(p, P.nhan(d[:doc], 20.0)) }], sau: x[:sau] } : x }
  r = chay(d, dau_b: doi)
  (r[:loi].length == 1 && %i[lech thieu].include?(r[:loi][0][:loai]) && gan.(r[:loi][0][:giua], d[:tam_dau][i], 17.5)) ? dem[:doi] += 1 : loi_ca << "DỜI #{ten.(cfg)}: #{r[:loi].map { |x| x[:loai] }}"
  # 3b. Dời 1 dấu chỉ 1 mm (soát 09/10: trước đó lệch 1–7 mm vẫn ĐẠT, dư dài mộng chỉ 0,1 mm/bên) → răng đó :lech
  doi1 = d[:dau].each_with_index.map { |x, j| j == i ? { mat: [x[:mat][0].map { |p| P.cong(p, P.nhan(d[:doc], 1.0)) }], sau: x[:sau] } : x }
  r = chay(d, dau_b: doi1)
  (r[:loi].length == 1 && r[:loi][0][:loai] == :lech && gan.(r[:loi][0][:giua], d[:tam_dau][i], 17.5)) ? dem[:doi1] += 1 : loi_ca << "DỜI1 #{ten.(cfg)}: #{r[:loi].map { |x| x[:loai] }}"
  # 4. Dấu khai nông hơn răng 1 mm → :nong
  nong = d[:dau].each_with_index.map { |x, j| j == i ? { mat: x[:mat], sau: cfg[:cao] - 1.0 } : x }
  r = chay(d, dau_b: nong)
  (r[:loi].map { |x| x[:loai] } == [:nong]) ? dem[:nong] += 1 : loi_ca << "NÔNG #{ten.(cfg)}: #{r[:loi].map { |x| x[:loai] }}"
  # 5. Khấu tay: không dấu nhưng mặt tấm nhận đã khoét lỗ đúng chỗ răng → không tính là răng găm
  r = chay(d, dau_b: [], lo_vao: d[:dau].map { |x| x[:mat][0] })
  (r[:loi].empty?) ? dem[:khau] += 1 : loi_ca << "KHẤU TAY #{ten.(cfg)}: #{r[:loi].map { |x| x[:loai] }}"
  # 6. Dấu đặt nhầm vào TẤM NGÀM (không phải tấm nhận) → mọi răng :thieu
  r = chay(d, dau_b: [], dau_a: d[:dau])
  (r[:loi].length == n && r[:loi].all? { |x| x[:loai] == :thieu }) ? dem[:nham] += 1 : loi_ca << "DẤU NHẦM TẤM #{ten.(cfg)}: #{r[:loi].length}"
end
tong = cfgs.length
ca(out, "#{tong} biến thể đủ dấu → 0 lỗi, đếm đủ răng") { [dem[:du] == tong, "#{dem[:du]}/#{tong} · #{loi_ca.grep(/^ĐỦ/).first(3)}"] }
ca(out, "#{tong} biến thể xóa ngẫu nhiên k dấu → đúng k răng THIẾU, đúng chỗ") { [dem[:xoa] == tong, "#{dem[:xoa]}/#{tong} · #{loi_ca.grep(/^XÓA/).first(3)}"] }
ca(out, "#{tong} biến thể dời 1 dấu 20 mm → đúng răng đó báo LỆCH") { [dem[:doi] == tong, "#{dem[:doi]}/#{tong} · #{loi_ca.grep(/^DỜI/).first(3)}"] }
ca(out, "#{tong} biến thể dời 1 dấu chỉ 1 mm → răng đó báo LỆCH") { [dem[:doi1] == tong, "#{dem[:doi1]}/#{tong} · #{loi_ca.grep(/^DỜI1/).first(3)}"] }
ca(out, "#{tong} biến thể dấu nông hơn răng 1 mm → báo NÔNG") { [dem[:nong] == tong, "#{dem[:nong]}/#{tong} · #{loi_ca.grep(/^NÔNG/).first(3)}"] }
ca(out, "#{tong} biến thể khấu tay (mặt nhận khoét lỗ, không dấu) → không báo") { [dem[:khau] == tong, "#{dem[:khau]}/#{tong} · #{loi_ca.grep(/^KHẤU/).first(3)}"] }
ca(out, "#{tong} biến thể dấu đặt nhầm vào tấm ngàm → mọi răng THIẾU") { [dem[:nham] == tong, "#{dem[:nham]}/#{tong} · #{loi_ca.grep(/^DẤU NHẦM/).first(3)}"] }
ca(out, 'Độ phủ biến thể: đủ 3 kiểu tấm, 4 đầu, 1–5 mộng, cao 13–14,9, thu A/B, nghiêng, lật gương') do
  c = cfgs.map(&:first)
  ok = %i[dung_y dung_x nam].all? { |k| c.any? { |x| x[:kieu] == k } } && (1..4).all? { |e| c.any? { |x| x[:canh] == e } } &&
       (1..5).all? { |s| c.any? { |x| x[:so] == s } } && c.any? { |x| x[:cao] == 14.5 } && c.any? { |x| x[:cao] == 13 } &&
       %w[A B].all? { |b| c.any? { |x| x[:ben] == b } } && c.any? { |x| x[:nghieng] > 0 } && c.any? { |x| x[:guong] }
  [ok, { so: c.map { |x| x[:so] }.tally, canh: c.map { |x| x[:canh] }.tally, kieu: c.map { |x| x[:kieu] }.tally }]
end

# ── Ca cố định: thứ KHÔNG phải răng thì không được báo ──────
I = Geom::Transformation.new
ca(out, 'Ngàm thường: cả đầu đợt găm 9 mm vào hông, không răng → không tính là răng (việc của KT Liên Kết)') do
  r = P.soat([tam('dot', mat_hop(I, [0, 0, 0], [600.mm, 400.mm, 17.5.mm])), tam('hong', mat_hop(I, [591.mm, -10.mm, -300.mm], [609.mm, 410.mm, 400.mm]))])
  [r[:so_rang].zero?, r[:so_rang]]
end
ca(out, 'Hai tấm chỉ chạm mặt, không găm → 0 răng') do
  r = P.soat([tam('dot', mat_hop(I, [0, 0, 0], [600.mm, 400.mm, 17.5.mm])), tam('hong', mat_hop(I, [600.mm, -10.mm, -300.mm], [618.mm, 410.mm, 400.mm]))])
  [r[:so_rang].zero?, r[:so_rang]]
end
ca(out, 'Hai tấm trùng chồng (song song) → 0 răng') do
  r = P.soat([tam('a', mat_hop(I, [0, 0, 0], [600.mm, 400.mm, 17.5.mm])), tam('b', mat_hop(I, [100.mm, 50.mm, 5.mm], [700.mm, 450.mm, 22.5.mm]))])
  [r[:so_rang].zero?, r[:so_rang]]
end
ca(out, 'Hai cặp ngàm→nhận trong cùng model, xóa hết dấu của MỘT cặp → chỉ răng cặp đó báo, cặp kia đạt') do
  base = { kieu: :dung_y, dai: 600, cao: 11, ben: 'none', fit: 15, canh: 2, goc: 0.0, nghieng: 0.0, guong: false, lui: 50, so: 3 }
  d1 = dung(base)
  d2 = dung(base.merge(dai: 400, so: 2))
  # cặp thứ hai dời lên 2 m cho khỏi chạm cặp đầu; tấm nhận thứ hai bỏ hết dấu
  tl = [tam('ngam1', d1[:mat_a]), tam('nhan1', mat_hop(d1[:rtr], d1[:rlo], d1[:rhi]), d1[:dau]),
        tam('ngam2', d2[:mat_a].map { |m| { ngoai: m[:ngoai].map { |p| P.cong(p, [0, 0, 2000]) } } }),
        tam('nhan2', mat_hop(d2[:rtr], d2[:rlo], d2[:rhi]).map { |m| { ngoai: m[:ngoai].map { |p| P.cong(p, [0, 0, 2000]) }, lo: [] } }, [])]
  r = P.soat(tl)
  [r[:loi].length == 2 && r[:loi].all? { |x| x[:a] == 'ngam2' } && r[:dat].length == 3, { loi: r[:loi].map { |x| x[:a] }, dat: r[:dat].length }]
end
# Tốc độ: tủ thật đa số tấm thường (6 mặt), ít tấm có răng. Ngưỡng tính trong wasm — Ruby wasm chậm hơn
# Ruby trong SketchUp nhiều lần, nên qua đây thì trong SketchUp còn dư.
def lap_lai(base, so_cap, so_thuong, co_dau)
  d = dung(base)
  nhan = mat_hop(d[:rtr], d[:rlo], d[:rhi])
  doi = ->(mats, dx) { mats.map { |m| { ngoai: m[:ngoai].map { |p| P.cong(p, dx) }, lo: [] } } }
  cap = (0...so_cap).flat_map { |k|
    dx = [k * 800.0, 0, 0]
    [tam("a#{k}", doi.(d[:mat_a], dx)),
     tam("b#{k}", doi.(nhan, dx), co_dau.(k) ? d[:dau].map { |x| { mat: [x[:mat][0].map { |p| P.cong(p, dx) }], sau: x[:sau] } } : [])]
  }
  thuong = (0...so_thuong).map { |k| tam("t#{k}", mat_hop(I, [k * 700.mm, 3000.mm, 0], [k * 700.mm + 600.mm, 3400.mm, 18.mm])) }
  cap + thuong
end
base3 = { kieu: :dung_y, dai: 600, cao: 11, ben: 'none', fit: 15, canh: 2, goc: 0.0, nghieng: 0.0, guong: false, lui: 50, so: 3 }
ca(out, 'Tủ 1000 tấm (40 cặp mộng 3 răng + 920 tấm thường) chạy dưới 3 giây trong wasm') do
  tl = lap_lai(base3, 40, 920, ->(k) { k.even? })
  t0 = Time.now
  r = P.soat(tl)
  ms = ((Time.now - t0) * 1000).round
  [ms < 3000 && r[:so_rang] == 120 && r[:loi].length == 60, "#{ms} ms · #{r[:so_tam]} tấm · #{r[:so_rang]} răng · #{r[:loi].length} lỗi"]
end
ca(out, '(số đo, không chấm) 400 tấm toàn răng: 200 cặp 3 mộng') do
  tl = lap_lai(base3, 200, 0, ->(k) { k.even? })
  t0 = Time.now
  r = P.soat(tl)
  [r[:so_rang] == 600 && r[:loi].length == 300, "#{((Time.now - t0) * 1000).round} ms · #{r[:so_rang]} răng · #{r[:loi].length} lỗi"]
end
# ── LỚP SketchUp (main.rb thật) trên cây group giả: tủ → tấm ngàm (group) + tấm nhận (component) có dấu
# con + nhánh __ABF_Nesting (phải bỏ). Hình lưu ở hệ LOCAL như SketchUp; gom phải nhân đủ transform. ──────
class Sketchup::ComponentInstance; end unless defined?(Sketchup::ComponentInstance)
Lop = Struct.new(:name)
class FLoop
  def initialize(pts, ngoai); @pts = pts; @ngoai = ngoai; end
  def vertices; @pts.map { |p| VTX.new(p) }; end
  def outer?; @ngoai; end
end
class FMat < Sketchup::Face
  attr_reader :layer
  def initialize(ngoai, lo = [], tag = 'Layer0'); @o = FLoop.new(ngoai, true); @l = lo.map { |x| FLoop.new(x, false) }; @layer = Lop.new(tag); end
  def outer_loop; @o; end
  def loops; [@o] + @l; end
end
class FNhom < Sketchup::Group
  attr_reader :entities, :transformation, :name, :layer
  def initialize(name, tr, entities, attrs = {}, tag = 'Layer0'); @name = name; @transformation = tr; @entities = entities; @attrs = attrs; @layer = Lop.new(tag); end
  def deleted?; false; end
  def get_attribute(d, k); (@attrs[d] || {})[k]; end
end
FDinh = Struct.new(:name, :entities)
class FThe < Sketchup::ComponentInstance
  attr_reader :definition, :transformation, :name
  def initialize(name, tr, defn); @name = name; @transformation = tr; @definition = defn; end
  def deleted?; false; end
  def get_attribute(*_a); nil; end
end
# mm thế giới → Point3d inch trong hệ có transform tổng tr
def ve_local(tr, pts); inv = tr.inverse; pts.map { |p| inv * Geom::Point3d.new(p.map { |v| v / IN }) }; end
def mat_local(tr, mats, tag = 'Layer0'); mats.map { |m| FMat.new(ve_local(tr, m[:ngoai]), (m[:lo] || []).map { |l| ve_local(tr, l) }, tag) }; end
def cay(d, dau: d[:dau], tag: 'LEHAI_MONGAM', sau: nil)
  t_tu = bien(0.4, 0.0, false, [-300, 800, 0])
  t_a = bien(1.1, 0.0, true, [50, 0, 20])
  t_b = bien(-0.7, 0.0, false, [10, 40, 0])
  t_d = bien(0.3, 0.0, false, [5, 5, 5])
  ngam = FNhom.new('Đợt', t_a, mat_local(t_tu * t_a, d[:mat_a]))
  dau_g = dau.map { |x| FNhom.new('_ABF_Intersect', t_d, mat_local(t_tu * t_b * t_d, x[:mat].map { |p| { ngoai: p } }, tag),
                                  { 'ABF' => { 'is-intersect' => true, 'intersect-x' => sau || x[:sau] } }) }
  nhan = FThe.new('', t_b, FDinh.new('Hông trái', mat_local(t_tu * t_b, mat_hop(d[:rtr], d[:rlo], d[:rhi])) + dau_g))
  nest = FNhom.new('__ABF_Nesting', I, [FNhom.new('Đợt copy', t_a, mat_local(t_tu * t_a, d[:mat_a]))])
  [FNhom.new('Tủ', t_tu, [ngam, nhan]), nest]
end
def quet_cay(goc); tam = []; TK::DogboneCheck.gom(goc, I, 0, tam, false); TK::DogboneCheck::PhanTich.soat(tam); end
d4 = dung({ kieu: :dung_y, dai: 600, cao: 11, ben: 'B', fit: 15, canh: 4, goc: 0.0, nghieng: 0.0, guong: false, lui: 50, so: 3 })
ca(out, 'Lớp SketchUp: gom qua tủ → group + component lồng, bỏ nhánh nesting; đủ dấu → 3 răng đạt') do
  r = quet_cay(cay(d4))
  [r[:so_tam] == 2 && r[:so_rang] == 3 && r[:loi].empty?, "#{r[:so_tam]} tấm · #{r[:so_rang]} răng · #{r[:loi].map { |x| x[:loai] }}"]
end
ca(out, 'Lớp SketchUp: xóa 1 dấu con trong component tấm nhận → đúng 1 răng THIẾU, tên tấm lấy từ definition') do
  r = quet_cay(cay(d4, dau: d4[:dau][0, 2]))
  [r[:loi].map { |x| x[:loai] } == [:thieu] && r[:loi][0][:ten_b] == 'Hông trái' && r[:loi][0][:ten_a] == 'Đợt', r[:loi].map { |x| [x[:loai], x[:ten_a], x[:ten_b]] }]
end
ca(out, 'Lớp SketchUp: dấu tag LEHAI_MONGAM khai sâu 9 < răng 11 → NÔNG; cùng dấu tag khác → không xét sâu') do
  a = quet_cay(cay(d4, sau: 9.0))
  b = quet_cay(cay(d4, sau: 9.0, tag: 'ABF_Groove'))
  [a[:loi].map { |x| x[:loai] } == %i[nong nong nong] && b[:loi].empty?, [a[:loi].map { |x| x[:loai] }, b[:loi].length]]
end

JSON.generate(out)
