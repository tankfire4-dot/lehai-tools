# encoding: UTF-8
# Ca thử LÕI Soát Khung Tổng Thể (kiem_tra_khung/phan_tich.rb) — chạy qua kiem_tra_khung.test.mjs.
# Tủ mẫu 2300 × 600 × 1700, ván 18: thân sâu 582 (y 18..600) + 2 cánh dày 18 phía trước (y 0..18),
# khe giữa hai cánh 3 mm. Tủ sạch phải ra 0 lỗi đỏ; mỗi ca cài đúng một kiểu lỗi.
PT = TK::FrameCheck::PhanTich

def tam(id, ten, lo, hi, them = {})
  { id: id, ten: ten, lo: lo.map(&:to_f), hi: hi.map(&:to_f), cua: !(ten =~ /Cánh|Hộc/).nil?,
    lech_do: 0.0, meo_mm: nil, hinh_la: false }.merge(them)
end

def tu_sach
  [
    tam(1, 'Hông trái', [0, 18, 0], [18, 600, 1700]),
    tam(2, 'Hông phải', [2282, 18, 0], [2300, 600, 1700]),
    tam(3, 'Đáy', [18, 18, 0], [2282, 600, 18]),
    tam(4, 'Nóc', [18, 18, 1682], [2282, 600, 1700]),
    tam(5, 'Vách', [1141, 18, 18], [1159, 590, 1682]),
    tam(6, 'Đợt', [18, 18, 800], [1141, 580, 818]),
    tam(7, 'Hậu', [18, 590, 18], [2282, 600, 1682]),
    tam(8, 'Cánh trái', [0, 0, 0], [1148.5, 18, 1700]),
    tam(9, 'Cánh phải', [1151.5, 0, 0], [2300, 18, 1700])
  ]
end

def doi(ds, id, them)
  ds.map { |t| t[:id] == id ? t.merge(them) : t }
end

# Tóm tắt kết quả: đỏ theo loại, vàng theo khoá nhóm
def tom(kq)
  do_ = kq['ds'].select { |f| f['muc'] == 'do' }
  vang = kq['ds'].select { |f| f['muc'] == 'vang' }
  { 'do' => do_.map { |f| f['loai'] }.sort, 'vang' => vang.map { |f| f['khoa'] }.sort,
    'so_bo_qua' => kq['so_bo_qua'], 'tieu_de' => kq['ds'].map { |f| f['tieu_de'] },
    'giong' => do_.select { |f| f['loai'] == 'giong' }.map { |f| [f['tam'], f['chi_tiet']] } }
end

K = [2300, 600, 1700].freeze
ca = {}
ca['sach'] = tom(PT.soat(K, tu_sach))
ca['noc_cao_0_5'] = tom(PT.soat(K, doi(tu_sach, 4, lo: [18, 18, 1682.5], hi: [2282, 600, 1700.5])))
ca['dot_bay'] = tom(PT.soat(K, doi(tu_sach, 6, lo: [18.5, 18, 800], hi: [1140.5, 580, 818])))
ca['hong_phai_lui_1'] = tom(PT.soat(K, doi(tu_sach, 2, lo: [2281, 18, 0], hi: [2299, 600, 1700])))
ca['khung_cao_hon'] = tom(PT.soat([2300, 600, 1701], tu_sach))
ca['dot_xeo'] = tom(PT.soat(K, doi(tu_sach, 6, lech_do: 0.5)))
ca['dot_xien_30'] = tom(PT.soat(K, doi(tu_sach, 6, lech_do: 30.0)))
ca['vach_meo'] = tom(PT.soat(K, doi(tu_sach, 5, meo_mm: 0.3)))
ca['dot_ngam_9'] = tom(PT.soat(K, doi(tu_sach, 6, lo: [9, 18, 800])))
ca['noc_lech_mep'] = tom(PT.soat(K, doi(tu_sach, 4, lo: [18, 18.5, 1682])))
ca['cham_duong'] = tom(PT.soat(K, tu_sach + [tam(10, 'Nẹp', [2300, 600, 1700], [2400, 700, 1718])]))
ca['cum_roi'] = tom(PT.soat(K, tu_sach + [tam(10, 'Hộp A', [500, 300, 300], [600, 318, 400]),
                                           tam(11, 'Hộp B', [600, 300, 300], [618, 400, 400])]))

# Số đông: vách thụt ra sau 2 mm (mép trước ở 20, mọi tấm khác ở 18) → MỘT dòng gióng, chỉ đúng vách
ca['vach_thut_2'] = tom(PT.soat(K, doi(tu_sach, 5, lo: [1141, 20, 18])))

# Hộc kéo trên ray: hở 12,5 mm với hông/vách, không chạm gì — KHÔNG được báo tủ đứt
HOC = [tam(20, 'Hộc 1 · hông trái', [30.5, 20, 100], [48.5, 570, 300]),
       tam(21, 'Hộc 1 · hông phải', [1110.5, 20, 100], [1128.5, 570, 300]),
       tam(22, 'Hộc 1 · đáy', [48.5, 20, 100], [1110.5, 570, 118])]
ca['hoc_tren_ray'] = tom(PT.soat(K, tu_sach + HOC))
# Hộc lơ lửng giữa khoang phải (cách mọi tấm thân > 30 mm) → phải báo không bám
LO_LUNG = [tam(30, 'Hộc 2 · hông trái', [1400, 100, 300], [1418, 400, 500]),
           tam(31, 'Hộc 2 · hông phải', [1782, 100, 300], [1800, 400, 500]),
           tam(32, 'Hộc 2 · đáy', [1418, 100, 300], [1782, 400, 318])]
ca['hoc_lo_lung'] = tom(PT.soat(K, tu_sach + LO_LUNG))

# Soát chéo 30/09 điểm 1: cánh chừa khe 2 mm trên + dưới so với khung → VÀNG (nhóm cánh/hộc lệch mép), không đỏ
ca['canh_ho_2'] = tom(PT.soat(K, doi(doi(tu_sach, 8, lo: [0, 0, 2], hi: [1148.5, 18, 1698]), 9, lo: [1151.5, 0, 2], hi: [2300, 18, 1698])))

# Bỏ qua: lấy khoá của lỗi 'giong' ở ca nóc lệch mép, soát lại với khoá đó → lỗi biến mất, đếm 1
kq = PT.soat(K, doi(tu_sach, 4, lo: [18, 18.5, 1682]))
khoa = kq['ds'].find { |f| f['loai'] == 'giong' }['khoa']
ca['bo_qua'] = tom(PT.soat(K, doi(tu_sach, 4, lo: [18, 18.5, 1682]), [khoa]))

# Bỏ qua cả nhóm vàng khe cánh
kq = PT.soat(K, tu_sach)
ca['bo_qua_nhom'] = tom(PT.soat(K, tu_sach, [kq['ds'].find { |f| f['loai'] == 'nhom' }['khoa']]))

# Tốc độ: 400 tấm rải trong tủ (lưới), đo thời gian lõi
nhieu = (0...400).map do |i|
  x = (i % 20) * 110.0
  z = (i / 20) * 80.0
  tam(100 + i, "T#{i}", [x, 18, z], [x + 100, 600, z + 18])
end
t0 = Time.now
PT.soat([2300, 600, 1700], nhieu)
ca['toc_do_400_ms'] = ((Time.now - t0) * 1000).round

JSON.generate(ca)
