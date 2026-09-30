# encoding: UTF-8
# LeHai_Tools/shared/huong_tu.rb
#
# HƯỚNG TỦ lấy từ HÌNH, không từ trục file (LUAT_NHA mục 9, Khoa chốt 29/09/2026).
# Trước 29/09 các tool coi trục đỏ/xanh lá của FILE là trái-phải/trước-sau của tủ → tủ quay
# hướng khác / đặt xiên thì vẽ sai (Tạo Cánh đắp cánh ra ngoài, Tấm Gỗ vẽ lệch...).
#
# Tủ vuông: mọi mặt đứng song song một trong HAI hướng vuông góc {a, a⊥} = "họ trục" của tủ.
# Quét tia ngang quanh chỗ chuột → pháp tuyến các mặt đứng → cụm đông nhất = họ trục.
# Tủ thẳng trục file thì họ trục = đúng trục file (bat_truc) → số y hệt bản cũ.
# Hộc kéo (tao_modul_nhanh/bang_hoc_keo.rb) có bộ dò riêng, cùng cách, làm trước — đã soát.

module LeHai
  module HuongTu
    MM     = 25.4
    TAM_XA = 1500.0 / MM   # inch — mặt xa hơn 1,5m không tính là của tủ đang làm
    SO_TIA = 36            # tia ngang quét quanh điểm (10° một tia)

    module_function

    # Bắn một tia; nil nếu không chạm hoặc chạm xa hơn `xa` (inch)
    def ban(model, p, d, xa = TAM_XA)
      kq = model.raytest([p, d])
      return nil unless kq && p.distance(kq[0]) <= xa
      kq
    end

    # Tổng biến đổi của đường chạm (các group/component bọc ngoài mặt vừa chạm)
    def bien_doi(duong)
      tr = Geom::Transformation.new
      duong[0..-2].each { |e| tr *= e.transformation if e.respond_to?(:transformation) }
      tr
    end

    # Pháp tuyến THẾ GIỚI (đơn vị) của mặt vừa chạm; nil nếu chạm cạnh / không phải mặt
    def phap_tuyen(hit)
      face = hit[1].last
      return nil unless face.is_a?(Sketchup::Face)
      n = bien_doi(hit[1]) * face.normal
      return nil if n.length < 1e-9
      n.normalize
    end

    # Pháp tuyến NGANG (đơn vị, quay về phía p) của các mặt ĐỨNG chạm được quanh điểm p
    def mat_dung_quanh(model, p)
      (0...SO_TIA).map { |i|
        g = 2 * Math::PI * i / SO_TIA
        d = Geom::Vector3d.new(Math.cos(g), Math.sin(g), 0)
        a = ban(model, p, d)
        next unless a
        n = phap_tuyen(a)
        next unless n && n.z.abs < 0.02
        n = n.reverse if n.dot(d) > 0
        Geom::Vector3d.new(n.x, n.y, 0).normalize
      }.compact
    end

    # Góc (rad) của pháp tuyến quy về [0, 90°): hai hướng vuông góc của một tủ cho cùng một góc
    def goc_ho(n)
      Math.atan2(n.y, n.x) % (Math::PI / 2)
    end

    def lech_ho(g, h)   # chênh góc giữa hai họ (rad), tính vòng 0 ≡ 90°
      d = (g - h).abs % (Math::PI / 2)
      [d, Math::PI / 2 - d].min
    end

    # Họ trục của tủ từ các pháp tuyến ngang: cụm đông nhất (dung sai 1°), trung bình vòng.
    # Trả vector a (góc trong [0°, 90°): a là trục của họ gần +đỏ nhất); a⊥ = Z × a. nil nếu rỗng.
    def ho_truc(ds)
      return nil if ds.empty?
      tol = Math::PI / 180
      goc = ds.map { |n| goc_ho(n) }
      tam = goc.max_by { |g| goc.count { |h| lech_ho(g, h) < tol } }
      cum = goc.select { |h| lech_ho(tam, h) < tol }
      s = cum.sum { |h| Math.sin(4 * h) }
      c = cum.sum { |h| Math.cos(4 * h) }
      g = (Math.atan2(s, c) / 4) % (Math::PI / 2)
      bat_truc(Geom::Vector3d.new(Math.cos(g), Math.sin(g), 0))
    end

    # Họ trục quanh điểm p (quét tia) — nil nếu quanh đó không có mặt đứng nào
    def ho_quanh(model, p)
      ho_truc(mat_dung_quanh(model, p))
    end

    # Trục sát trục file (sai số máy, < 1e-9) → lấy đúng trục file: tủ thẳng trục ra số y hệt bản cũ
    def bat_truc(v)
      return Geom::Vector3d.new(v.x > 0 ? 1 : -1, 0, 0) if v.y.abs < 1e-9
      return Geom::Vector3d.new(0, v.y > 0 ? 1 : -1, 0) if v.x.abs < 1e-9
      v
    end

    # Đi từ c theo `huong` 20mm: hai bên (±u) đều gặp vách trong nua_rong + 5mm → phía đó là LÒNG
    # TỦ (có hậu hay không đều đúng). Phía phòng không có hai vách kẹp sát như vậy.
    def ben_trong?(model, c, huong, u, nua_rong)
      q = c.offset(huong, 20.0 / MM)
      xa = nua_rong + 5.0 / MM
      [u, u.reverse].all? { |d| ban(model, q, d, xa) }
    end

    # Hướng pháp tuyến n (đơn vị, ngang) chỉ VÀO lòng tủ, nhìn từ tâm c của mặt phẳng; u dọc bề rộng.
    # Hình phân được → theo hình. Không phân được → theo hướng nhìn (mắt ở phía trước). Nhìn song
    # song mặt phẳng → nil (không đoán).
    def huong_vao(model, c, n, u, nua_rong, nhin)
      a = ben_trong?(model, c, n, u, nua_rong)
      b = ben_trong?(model, c, n.reverse, u, nua_rong)
      return [n, false] if a && !b
      return [n.reverse, false] if b && !a
      k = nhin.dot(n)
      return [k > 0 ? n : n.reverse, true] if k.abs >= 0.2
      nil
    end

    # Độ lệch (độ) của CẶP VÁCH gần song song ngược chiều quanh p (hai hông của khoang): 0 = song song.
    # Cặp = hai cụm pháp tuyến chênh > 135° (lệch tới 45°; hông–hậu vuông góc 90° không bị nhận nhầm).
    # Bản đầu lọc > 170° → hông lệch 12–20° lọt qua (Codex soát lại 29/09). nil nếu không có cặp vách
    # nào (không kiểm được). Tool dựng báo khi > 1° (mục 9).
    def lech_hai_vach(model, p)
      nhom = []
      mat_dung_quanh(model, p).each do |n|
        g = nhom.find { |m| goc_do(m[0], n) < 0.5 }
        g ? g[1] += 1 : nhom << [n, 1]
      end
      cap = nhom.combination(2).select { |a, b| goc_do(a[0], b[0]) > 135 }
      return nil if cap.empty?
      a, b = cap.max_by { |m, n| m[1] + n[1] }
      180 - goc_do(a[0], b[0])
    end

    def goc_do(a, b)   # góc giữa hai vector đơn vị, độ
      Math.acos([[a.dot(b), 1.0].min, -1.0].max) * 180 / Math::PI
    end

    # Hệ tủ: x dọc bề rộng, y = hướng vào lòng tủ, z lên; gốc = gốc file (tủ thẳng trục mặt về
    # xanh lá âm → phép đồng nhất, số y hệt bản cũ)
    def he(vao)
      z = Geom::Vector3d.new(0, 0, 1)
      Geom::Transformation.axes(Geom::Point3d.new(0, 0, 0), vao.cross(z), vao, z)
    end

    # ── Hộp RIÊNG của tấm (cho tool KIỂM) ────────────────────────
    # Hộp bao thế giới của tấm XIÊN phình ra (sketchup-nen-tang.md mục 3a) → tấm xiên bị đo sai /
    # bỏ sót. Hộp riêng = hộp bao LOCAL (mặt của chính tấm) đặt bằng te: :he hệ cứng (gốc = góc thấp
    # local, trục = 3 cạnh thật chuẩn hoá), :e 3 cạnh (inch, thế giới), :u 3 hướng cạnh,
    # :thang = mọi cạnh trùng trục file (tủ thẳng trục / quay 90-180-270°) → tool giữ đường tính cũ.
    GOC8   = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    CANH12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    def hop_rieng(ents, te)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return nil if bb.empty?
      mn = bb.min
      mx = bb.max
      o = te * mn
      canh = [[mx.x, mn.y, mn.z], [mn.x, mx.y, mn.z], [mn.x, mn.y, mx.z]].map { |q| (te * Geom::Point3d.new(*q)) - o }
      e = canh.map(&:length)
      truc = [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1)]
      u = canh.each_with_index.map { |v, i| e[i] > 1e-9 ? v.normalize : truc[i] }
      thang = u.all? { |v| v.to_a.count { |c| c.abs < 1e-9 } == 2 }
      { he: Geom::Transformation.axes(o, *u), e: e, u: u, thang: thang }
    end

    # 8 góc thế giới của hộp riêng
    def goc_hop(h)
      GOC8.map { |cx, cy, cz| h[:he] * Geom::Point3d.new(cx * h[:e][0], cy * h[:e][1], cz * h[:e][2]) }
    end

    # 12 nét (mảng toạ độ) của hộp riêng — để vẽ nổi tấm
    def net_hop(h)
      pts = goc_hop(h).map(&:to_a)
      CANH12.map { |a, b| [pts[a], pts[b]] }
    end

    # Hộp riêng → AABB [minx,miny,minz,maxx,maxy,maxz] trong hệ fi (thế giới → hệ đo)
    def hop_trong(h, fi)
      bb = Geom::BoundingBox.new
      goc_hop(h).each { |p| bb.add(fi * p) }
      [bb.min.x, bb.min.y, bb.min.z, bb.max.x, bb.max.y, bb.max.z]
    end

    # b cùng họ trục với a (mỗi cạnh b song song một cạnh a — cùng một tủ)?
    def cung_ho?(a, b)
      b[:u].all? { |v| a[:u].any? { |w| v.dot(w).abs > 0.9999 } }
    end

    # Biến đổi cứng (không scale, không xiên)? — dựng tấm local + xoay group chỉ khi cứng
    def cung?(t)
      ax = [t * Geom::Vector3d.new(1, 0, 0), t * Geom::Vector3d.new(0, 1, 0), t * Geom::Vector3d.new(0, 0, 1)]
      ax.all? { |v| (v.length - 1.0).abs < 1e-6 } &&
        [[0, 1], [0, 2], [1, 2]].all? { |i, j| ax[i].dot(ax[j]).abs < 1e-6 }
    end
  end
end
