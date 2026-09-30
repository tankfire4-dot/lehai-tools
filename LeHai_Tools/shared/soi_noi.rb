# encoding: UTF-8
# LeHai_Tools/shared/soi_noi.rb
#
# SOI NỔI — kiểu xem lỗi dùng chung cho các tool kiểm / tìm tấm (Khoa chốt 30/09/2026).
# Làm mờ phần còn lại của model (như SketchUp "Fade rest of model" khi mở group) rồi vẽ lại riêng
# các tấm liên quan thành KHỐI ĐẶC sáng nhẹ, đổ bóng theo hướng nhìn. KHÔNG đổi trạng thái model:
# chỉ vẽ trong Tool#draw — Esc là hết, không mở group, không đụng cài đặt Fade của máy thợ.
#
# Vì sao: các màn "Xem" cũ chỉ vẽ viền đỏ đè lên cả tủ — tấm lỗi lẫn trong hàng chục đường khác,
# Khoa phải tự đoán tấm nào. Làm ra đầu tiên cho Khung Tổng Thể (kiem_tra_khung), Khoa dùng thử:
# "khắc phục được rất nhiều thứ" → đưa về đây cho mọi tool dùng chung. Chỉnh độ mờ / màu ở MỘT chỗ.
#
# Cách dùng trong Tool#draw (thứ tự quan trọng — thứ vẽ SAU nằm TRÊN):
#   LeHai::SoiNoi.phu_mo(view)                              # 1. mờ cả màn
#   LeHai::SoiNoi.ve_nets(view, [[@draw_a, :do], [@draw_b, :la]])  # 2. khối đặc các tấm
#   ... viền / nhãn / bảng cũ của tool (draw2d) ...          # 3. vẫn nổi trên cùng
# `pts` = mảng điểm nối cặp (GL_LINES) của 12 cạnh hộp tấm — đúng thứ các tool đang giữ sẵn.
# Thứ không phải hộp (cạnh dán, cung R100, đường nesting) thì ve_nets bỏ qua, tool tự vẽ nét.

module LeHai
  module SoiNoi
    # Lớp mờ: 185/255 — Khoa 30/09 thấy 228 "làm mờ quá mức", hạ xuống vẫn đọc được tủ xung quanh
    MO = Sketchup::Color.new(246, 245, 241, 185)

    # Màu khối (nền nhạt, đổ bóng) + viền theo vai: đỏ = tấm lỗi, lá = tấm chuẩn/đúng,
    # xanh = tấm tìm thấy / tham chiếu, vàng = nhắc (không phải lỗi)
    NEN = { do: [250, 214, 210], la: [212, 238, 214], xanh: [212, 226, 248], vang: [250, 234, 198] }.freeze
    VIEN = { do: [220, 40, 40], la: [0, 150, 60], xanh: [30, 110, 230], vang: [210, 140, 0] }.freeze

    # 8 góc theo thứ tự [x,y,z] ∈ {0,1}: 000 100 110 010 001 101 111 011 — cùng GOC8 của huong_tu
    MAT6 = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]].freeze

    module_function

    # Phủ lớp mờ lên cả khung nhìn. draw2d tự cắt theo màn → màn to cỡ nào cũng phủ hết.
    def phu_mo(view)
      view.drawing_color = MO
      view.draw2d(GL_POLYGON, [[-20000, -20000], [40000, -20000], [40000, 40000], [-20000, 40000]].map { |x, y| Geom::Point3d.new(x, y, 0) })
    end

    # Vẽ nhiều tấm (mỗi tấm = mảng điểm GL_LINES của 12 cạnh hộp) thành khối đặc, sắp chung mặt
    # xa→gần (vẽ kiểu hoạ sĩ). Tấm nào không dựng được hộp thì bỏ qua (tool tự vẽ nét của nó).
    def ve_nets(view, ds)
      ve_khois(view, ds.map { |pts, mau| [khoi_tu_net(pts), mau] }.select(&:first))
    end

    # ds = [[8 góc thế giới, :do|:la|:xanh|:vang], ...]
    #
    # THẤY / KHUẤT (Khoa 30/09: tấm bị che vẫn sáng rõ → tưởng nó nằm trong, thật ra ở ngoài). Theo
    # quy ước bản vẽ kỹ thuật: phần THẤY tô đặc + nét liền, phần KHUẤT tô trong suốt + nét đứt. Tính theo
    # TỪNG PHẦN: mỗi mặt quay về mắt chia 2×2 ô, mỗi cạnh chia 2 đoạn, bắn tia từ mắt kiểm từng ô/đoạn.
    # Mặt quay lưng luôn khuất (sau chính tấm đó) → trong suốt. Cả tấm khuất → nhãn "khuất sau tấm khác".
    def ve_khois(view, ds)
      cam = view.camera
      mat = []
      ds.each_with_index do |(g, mau), gi|
        tam = tam_diem(g)
        MAT6.each do |ids|
          pts = ids.map { |i| g[i] }
          # bỏ mặt có góc ở SAU camera (xoay/lăn quá sát) — chiếu điểm sau lưng ra màn là hình vỡ
          next if pts.any? { |p| (p - cam.eye).dot(cam.direction) <= 0 }
          c = tam_diem(pts)
          n = (pts[1] - pts[0]).cross(pts[3] - pts[0])
          n = n.reverse if n.length > 1e-12 && n.dot(c - tam) < 0     # pháp tuyến quay RA ngoài hộp
          # mặt phẳng dẹt (tấm nesting dày 0) không có "ngoài" → coi như quay về mắt
          # chiếu SONG SONG: mắt ở vô cực theo hướng nhìn → xét theo cam.direction, không theo cam.eye
          nhin = cam.perspective? ? cam.eye - c : cam.direction.reverse
          truoc = n.length <= 1e-12 || (c - tam).length < 1e-9 || n.dot(nhin) > 0
          sang = n.length > 1e-12 ? n.normalize.dot(cam.direction).abs : 1.0
          mat << [pts, mau, truoc, 0.72 + 0.28 * sang, gi]
        end
      end
      mat.sort_by { |pts, *| -pts.sum { |p| p.distance(cam.eye) } }.each do |pts, mau, truoc, k, _gi|
        nen = NEN[mau].map { |x| (x * k).round }
        unless truoc
          view.drawing_color = Sketchup::Color.new(*nen, KHUAT_ALPHA)
          view.draw2d(GL_POLYGON, pts.map { |p| view.screen_coords(p) })
          next
        end
        o_con(pts).each do |q|
          thay = thay?(view, tam_diem(q))
          view.drawing_color = thay ? Sketchup::Color.new(*nen) : Sketchup::Color.new(*nen, KHUAT_ALPHA)
          view.draw2d(GL_POLYGON, q.map { |p| view.screen_coords(p) })
        end
      end
      # viền 12 cạnh mỗi tấm: đoạn thấy liền, đoạn khuất đứt; cả tấm khuất → nhãn nhỏ
      ds.each_with_index do |(g, mau), gi|
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(*VIEN[mau])
        net2d(view, CANH12.flat_map { |a, b| [g[a], g[b]] })
        o = mat.select { |_p, _m, truoc, _k, g2| truoc && g2 == gi }
        next if o.empty?
        next unless o.all? { |pts, *| o_con(pts).none? { |q| thay?(view, tam_diem(q)) } }
        s = view.screen_coords(tam_diem(g))
        nhan_nho(view, s.x - 60, s.y - 11, 'khuất sau tấm khác')
      end
    end

    KHUAT_ALPHA = 70
    CANH12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].freeze
    NHIEU_DOAN = 60   # quá số đoạn này thì net2d không bắn tia
    NET = 7        # px nét đứt
    HO  = 5        # px hở giữa hai nét

    # Nét (GL_LINES, điểm thế giới): mỗi đoạn chia đôi, nửa nào THẤY vẽ liền, nửa KHUẤT vẽ đứt.
    # Dùng màu / độ dày đang đặt trên view — tool đặt màu rồi gọi, như gọi draw2d.
    def net2d(view, pts)
      # Quá nhiều đoạn (tấm cong: một dấu dán cạnh gom hàng trăm mặt con → ~1.600 tia mỗi khung hình khi
      # xoay — soát chéo 30/09 điểm 3) → vẽ liền như cũ, không bắn tia.
      if pts.size > 2 * NHIEU_DOAN
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
        return
      end
      lien = []
      dut = []
      pts.each_slice(2) do |a, b|
        next unless a && b
        m = Geom::Point3d.new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0)
        [[a, m], [m, b]].each do |p, q|
          g = Geom::Point3d.new((p.x + q.x) / 2.0, (p.y + q.y) / 2.0, (p.z + q.z) / 2.0)
          next if [p, q].any? { |x| (x - view.camera.eye).dot(view.camera.direction) <= 0 }
          sp = view.screen_coords(p)
          sq = view.screen_coords(q)
          thay?(view, g) ? lien.push(sp, sq) : dut.concat(cat_dut(sp, sq))
        end
      end
      view.draw2d(GL_LINES, lien) unless lien.empty?
      view.draw2d(GL_LINES, dut) unless dut.empty?
    end

    # Đường gấp khúc (GL_LINE_STRIP) → như net2d
    def day2d(view, pts)
      net2d(view, pts.each_cons(2).flat_map { |a, b| [a, b] })
    end

    # Một đoạn trên màn → các nét đứt đều NET px, hở HO px
    def cat_dut(a, b)
      dx = b.x - a.x
      dy = b.y - a.y
      l = Math.sqrt(dx * dx + dy * dy)
      return [] if l < 1
      out = []
      t = 0.0
      while t < l
        t1 = [t + NET, l].min
        out << Geom::Point3d.new(a.x + dx * t / l, a.y + dy * t / l, 0) << Geom::Point3d.new(a.x + dx * t1 / l, a.y + dy * t1 / l, 0)
        t += NET + HO
      end
      out
    end

    # Điểm p (nằm trên mặt tấm) có THẤY từ mắt không: bắn tia mắt → p; chạm vật khác TRƯỚC p (quá
    # 0,5 mm) thì khuất. raytest mặc định bỏ qua thứ đang ẩn. Nhớ kết quả theo vị trí camera: xoay /
    # lăn mới bắn lại, vẽ lại màn hình thì không; sau 1,5 s cũng bắn lại (model có thể vừa bị sửa).
    def thay?(view, p)
      cam = view.camera
      e = cam.eye
      # khoá theo model + camera: đổi file / đổi góc nhìn thì bắn lại (thử 30/09: thiếu model thì
      # mở file khác đúng góc cũ sẽ dùng nhầm kết quả của file trước)
      khoa_cam = [view.model.object_id] + (e.to_a + cam.target.to_a).map { |x| x.round(4) }
      if khoa_cam != @khoa_cam || @luc_cam.nil? || Time.now - @luc_cam > 1.5
        @khoa_cam = khoa_cam
        @luc_cam = Time.now
        @thay = {}
      end
      k = p.to_a.map { |x| x.round(4) }
      return @thay[k] if @thay.key?(k)
      # gốc tia: phối cảnh = mắt; SONG SONG = chân của p trên mặt phẳng camera, tia song song hướng nhìn
      # (bắn từ mắt thì điểm xa tâm màn bị xét sai — soát chéo 30/09 điểm 4)
      if cam.perspective?
        g = e
      else
        dd = cam.direction
        g = p.offset(dd.reverse, (p - e).dot(dd))
      end
      v = p - g
      d = v.length
      @thay[k] = if d < 1e-6 then true
                 else
                   hit = view.model.raytest([g, v.normalize])
                   hit.nil? || g.distance(hit[0]) >= d - 0.5 / 25.4
                 end
    end

    # Mặt tứ giác → 4 ô con 2×2 (nội suy song tuyến)
    def o_con(pts)
      p0, p1, p2, p3 = pts
      d = lambda do |u, v|
        w = [(1 - u) * (1 - v), u * (1 - v), u * v, (1 - u) * v]
        Geom::Point3d.new(*(0..2).map { |i| w[0] * p0.to_a[i] + w[1] * p1.to_a[i] + w[2] * p2.to_a[i] + w[3] * p3.to_a[i] })
      end
      [[0, 0], [0.5, 0], [0.5, 0.5], [0, 0.5]].map do |u, v|
        [d.call(u, v), d.call(u + 0.5, v), d.call(u + 0.5, v + 0.5), d.call(u, v + 0.5)]
      end
    end

    def tam_diem(pts)
      n = pts.size.to_f
      Geom::Point3d.new(pts.sum(&:x) / n, pts.sum(&:y) / n, pts.sum(&:z) / n)
    end

    # Nhãn nhỏ nhạt — nói thêm, không giành chú ý với nhãn lỗi chính
    def nhan_nho(view, x, y, s)
      o_vuong(view, x, y, 16 + s.length * 7, 22, Sketchup::Color.new(60, 60, 60, 150))
      view.draw_text(Geom::Point3d.new(x + 8, y + 4, 0), s, color: Sketchup::Color.new(255, 255, 255), font: 'Arial', size: 11, bold: false)
    end

    # 12 cạnh hộp (điểm nối cặp) → 8 góc theo MAT6. Nhận cả hộp thẳng trục lẫn hộp xiên (net_hop):
    # lấy một góc, 3 góc kề nó cho 3 vector cạnh, dựng đủ 8 góc. Không đúng 8 đỉnh bậc 3 → nil.
    def khoi_tu_net(pts)
      return nil if pts.nil? || pts.size != 24
      khoa = ->(p) { [p.x.round(6), p.y.round(6), p.z.round(6)] }
      dinh = {}
      ke = Hash.new { |h, k| h[k] = [] }
      pts.each_slice(2) do |a, b|
        ka = khoa.call(a)
        kb = khoa.call(b)
        next if ka == kb
        dinh[ka] = a
        dinh[kb] = b
        ke[ka] << kb
        ke[kb] << ka
      end
      # Hình chữ nhật PHẲNG (dấu dán cạnh / chi tiết trên bản nesting dày 0): 4 đỉnh bậc 2 khép vòng →
      # đi vòng lấy thứ tự, đáy = nắp (mặt bên diện tích 0, vẽ vô hại) → vẫn tô được mặt đặc
      if dinh.size == 4 && ke.values.all? { |v| v.uniq.size == 2 }
        vong = [dinh.keys.first]
        3.times { vong << (ke[vong[-1]].uniq - vong).first }
        return nil if vong.include?(nil)
        g = vong.map { |k| dinh[k] }
        return g + g
      end
      return nil unless dinh.size == 8 && ke.values.all? { |v| v.uniq.size == 3 }
      k0 = dinh.keys.first
      o = dinh[k0]
      v1, v2, v3 = ke[k0].uniq.map { |k| dinh[k] - o }
      [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].map do |a, b, c|
        Geom::Point3d.new(o.x + a * v1.x + b * v2.x + c * v3.x,
                          o.y + a * v1.y + b * v2.y + c * v3.y,
                          o.z + a * v1.z + b * v2.z + c * v3.z)
      end
    end

    # Hộp của một tấm (group/component) từ MẶT bên trong nó: hộp bao local của các mặt, đặt ra thế
    # giới bằng te → 8 góc theo MAT6. Ôm sát cả tấm xoay (không dùng bounds thế giới — phình ra,
    # sketchup-nen-tang mục 3a). Không có mặt nào → nil.
    def goc_tam(ents, te)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return nil if bb.empty?
      mn = bb.min
      mx = bb.max
      [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].map do |a, b, c|
        te * Geom::Point3d.new(a.zero? ? mn.x : mx.x, b.zero? ? mn.y : mx.y, c.zero? ? mn.z : mx.z)
      end
    end

    # Nhãn chữ trắng nền tối, sọc màu bên trái — đọc được trên mọi nền.
    # Chữ đậm cỡ 13 ~9,5 px/ký tự (8 thì cắt chữ cuối — Khoa thấy 30/09).
    def chip(view, x, y, s, mau = [255, 0, 200])
      w = 20 + s.length * 9.5
      o_vuong(view, x, y, w, 26, Sketchup::Color.new(18, 22, 30, 235))
      o_vuong(view, x, y, 4, 26, Sketchup::Color.new(*mau))
      view.draw_text(Geom::Point3d.new(x + 10, y + 5, 0), s.to_s,
                     color: Sketchup::Color.new(255, 255, 255), font: 'Arial', size: 13, bold: true)
    end

    def o_vuong(view, x, y, w, h, mau)
      view.drawing_color = mau
      view.draw2d(GL_POLYGON, [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) })
    end
  end
end
