# encoding: UTF-8
# Kiểm Mộng Xương Chó — chạy trong dashboard "Check Chốt Sản Xuất" (không có nút riêng).
# Bắt RĂNG mộng găm vào tấm khác mà chỗ đó trên tấm nhận THIẾU / LỆCH / NÔNG dấu khoét _ABF_Intersect —
# vd ai đó lỡ xóa dấu mộng âm: CNC cắt tấm nhận nguyên khối, lắp không vào, phôi phế (Khoa hỏi 04/10).
#
# KT Liên Kết không bắt được ca này: nó lấy mẫu cả đầu tấm, khe giữa các răng làm tỉ lệ đâm xuyên thấp
# → hiểu nhầm "đã khấu tay". Lõi toán xét TỪNG RĂNG, nằm ở phan_tich.rb (thuần Ruby, thử ngoài SketchUp:
# tests/kiem_tra_mong_xuong_cho.test.mjs). File này chỉ: gom tấm + dấu từ model → mm thế giới → gọi lõi;
# và màn Xem soi từng răng. CHỈ ĐỌC, không sửa model.
#
# Nhận răng bằng HÌNH, không đọc ghi nhớ LeHai_MXC của tool Mộng — tấm copy / import / sửa tay vẫn bắt.

require 'sketchup.rb'
require File.join(File.dirname(__FILE__), 'phan_tich')
require File.join(File.dirname(__FILE__), '..', 'shared', 'soi_noi')

module TK
  module DogboneCheck

    PATH      = File.dirname(__FILE__).freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    # Trùng TK::MongXuongCho::TAG_MONG_AM — không require chéo, để check vẫn chạy khi tool Mộng nạp lỗi.
    TAG_MONG_AM = 'LEHAI_MONGAM'.freeze
    MM = 25.4   # inch → mm (SketchUp tính inch)

    COLOR_BAD = Sketchup::Color.new(255, 60, 0)
    COLOR_OK  = Sketchup::Color.new(0, 170, 80)

    # ── Adapter cho "Check Chốt Sản Xuất" (TK::PreExportCheck) ──────
    def self.audit
      unless (Sketchup.active_model.active_path || []).empty?
        # Đang mở group: toạ độ hình bên trong group mở và group ngoài lệch hệ nhau (SKETCHUP_NEN_TANG
        # mục 5) — quét lúc này có thể báo sai, nên không quét.
        return { status: :warn, count: 0, message: 'Đang mở group/component — thoát ra ngoài cùng rồi bấm Quét lại.' }
      end
      kq = quet
      return { status: :na, count: 0, message: 'Không tìm thấy tấm ván nào để kiểm tra.' } if kq[:so_tam].zero?
      if kq[:so_rang].zero?
        return { status: :na, count: 0, message: "Đã soi #{kq[:so_tam]} tấm — không có răng mộng nào găm vào tấm khác." }
      end
      if kq[:loi].empty?
        return { status: :pass, count: 0, message: "#{kq[:so_rang]} răng mộng — răng nào cũng có dấu khoét phủ kín." }
      end
      { status: :fail, count: kq[:loi].size,
        message: "#{kq[:loi].size}/#{kq[:so_rang]} răng mộng găm vào tấm nhận mà thiếu / lệch / nông dấu khoét — CNC không phay lỗ cho răng." }
    end

    def self.review
      unless (Sketchup.active_model.active_path || []).empty?
        return UI.messagebox('Đang mở group/component — thoát ra ngoài cùng rồi bấm Xem lại.')
      end
      kq = quet
      return UI.messagebox('Không tìm thấy tấm ván nào để kiểm tra.') if kq[:so_tam].zero?
      return UI.messagebox("Đã soi #{kq[:so_tam]} tấm — không có răng mộng nào găm vào tấm khác.") if kq[:so_rang].zero?
      ds, mode = kq[:loi].empty? ? [kq[:dat], :ok] : [kq[:loi], :loi]
      Sketchup.active_model.select_tool(ReviewTool.new(ds, mode, kq[:hop]))
    end

    # ── Quét model ──────
    def self.quet
      Sketchup.set_status_text('Đang soát răng mộng xương chó...', SB_PROMPT)
      tam = []
      gom(Sketchup.active_model.entities, Geom::Transformation.new, 0, tam, false)
      PhanTich.soat(tam)
    ensure
      Sketchup.set_status_text('', SB_PROMPT)
    end

    # trong_tam = đang ở BÊN TRONG một tấm rồi → không lấy mảnh con làm tấm nữa (tấm là lá).
    def self.gom(entities, t, depth, tam, trong_tam)
      return if depth > 40
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.deleted?
        next if e.name.to_s.include?(NEST_HINT)   # bản trải phẳng để cắt, không phải tủ 3D
        next if dau_abf?(e)
        te = t * e.transformation
        ents = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
        la_tam = !trong_tam && them_tam(e, te, ents, tam)
        gom(ents, te, depth + 1, tam, trong_tam || la_tam)
      end
    end

    def self.dau_abf?(e)
      e.is_a?(Sketchup::Group) && (e.name == '_ABF_Intersect' || e.get_attribute('ABF', 'is-intersect') == true)
    end

    def self.mm(te, pos)
      p = te * pos
      [p.x.to_f * MM, p.y.to_f * MM, p.z.to_f * MM]
    end

    def self.vong(lp, te)
      lp.vertices.map { |v| mm(te, v.position) }
    end

    # Tấm = group có MẶT RIÊNG dạng tấm ván (lõi quyết định bằng bề dày). Dấu ABF con của nó gom kèm.
    def self.them_tam(e, te, ents, tam)
      faces = ents.grep(Sketchup::Face)
      return false if faces.length < 4
      mat = faces.map { |f| { ngoai: vong(f.outer_loop, te), lo: f.loops.reject(&:outer?).map { |l| vong(l, te) } } }
      t = { id: tam.length, ten: ten_tam(e), mat: mat }
      c = PhanTich.chuan_bi(t) # chuẩn bị MỘT lần (lõi dùng lại); nil = không phải tấm ván
      return false unless c
      t[:dau] = ents.select { |c| dau_abf?(c) }.map { |d|
        td = te * d.transformation
        df = d.entities.grep(Sketchup::Face)
        # Độ sâu chỉ tin ở dấu do tool Mộng đặt (tag LEHAI_MONGAM, intersect-x = cao mộng, mm). Dấu ABF
        # khác chưa đo nghĩa của intersect-x → không xét nông/sâu, chỉ xét có phủ chân răng không.
        mong_am = d.layer.name == TAG_MONG_AM || df.any? { |f| f.layer.name == TAG_MONG_AM }
        x = d.get_attribute('ABF', 'intersect-x')
        { mat: df.map { |f| vong(f.outer_loop, td) }, sau: mong_am && x.is_a?(Numeric) ? x.to_f : nil }
      }
      c[:dau] = t[:dau]
      t[:chuan] = c
      tam << t
      true
    end

    def self.ten_tam(e)
      n = e.name.to_s
      return n.sub(/\A__/, '') unless n.empty?
      if e.is_a?(Sketchup::ComponentInstance)
        dn = e.definition.name.to_s
        return dn unless dn.empty?
      end
      '(tấm không tên)'
    end

    # =========================================================
    #  XEM TỪNG RĂNG (lỗi = đỏ / đạt = xanh) — khuôn ReviewTool của kiem_tra_lien_ket
    # =========================================================
    class ReviewTool
      HOP12 = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]].freeze

      # ds = răng từ PhanTich.soat; hop = {id tấm => 8 góc mm}
      def initialize(ds, mode, hop)
        @ds = ds
        @mode = mode
        @hop = hop
        @color = mode == :ok ? COLOR_OK : COLOR_BAD
        @idx = 0
      end

      def activate; focus(0); end
      def deactivate(view); view.invalidate; end
      def resume(view); update_status; view.invalidate; end
      def getExtents; @bounds; end
      def onCancel(_r, view); quit(view); end

      def onKeyDown(key, _rep, _flags, view)
        case key
        when 27 then quit(view)
        when 39, 38 then step(1, view)
        when 37, 40 then step(-1, view)
        end
        false
      end

      def enableVCB?; true; end

      def onUserText(text, view)
        n = text.to_s.scan(/\d+/).first
        return unless n
        i = n.to_i - 1
        return UI.messagebox("Chỉ có #{@ds.size} răng (1–#{@ds.size}).") if i < 0 || i >= @ds.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        LeHai::SoiNoi.phu_mo(view)
        LeHai::SoiNoi.ve_nets(view, [[@net_a, @mode == :ok ? :la : :do], [@net_b, :xanh]])
        ve(view, @chan, 4)    # chân răng trên mặt tấm nhận = chỗ phải có dấu khoét
        ve(view, @dinh, 2)    # đỉnh răng nằm trong lòng tấm nhận
        draw_banner(view)
      rescue => e
        puts "KT Mộng xem: #{e.message}" unless @failed
        @failed = true
      end

      def focus(i)
        @idx = i
        r = @ds[i]
        @net_a = net(@hop[r[:a]])
        @net_b = net(@hop[r[:b]])
        @chan = vien(r[:chan])
        @dinh = vien(r[:dinh])
        bb = Geom::BoundingBox.new
        @chan.each { |p| bb.add(p) }
        # ôm quanh răng + lề 120mm để thấy hai tấm
        c = bb.center
        m = 120.0 / MM
        bb.add(c.offset(Geom::Vector3d.new(m, m, m)))
        bb.add(c.offset(Geom::Vector3d.new(-m, -m, -m)))
        @bounds = bb
        frame(bb)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def step(dir, view)
        focus((@idx + dir) % @ds.size)
        view.invalidate
      end

      def pt(a); Geom::Point3d.new(a[0] / MM, a[1] / MM, a[2] / MM); end

      # 8 góc → 12 cạnh (điểm nối cặp GL_LINES) như các tool kiểm khác giữ sẵn
      def net(goc)
        return [] unless goc
        HOP12.flat_map { |a, b| [pt(goc[a]), pt(goc[b])] }
      end

      # đa giác khép kín → điểm nối cặp
      def vien(poly)
        ps = poly.map { |a| pt(a) }
        ps.each_index.flat_map { |k| [ps[k], ps[(k + 1) % ps.length]] }
      end

      def ve(view, pts, w)
        return if pts.empty?
        LeHai::SoiNoi.but(view, @color, w)
        view.draw(GL_LINES, pts)
        LeHai::SoiNoi.net2d(view, pts)
      end

      def draw_banner(view)
        r = @ds[@idx]
        if @mode == :ok
          l1 = "Răng mộng đạt   (#{@idx + 1}/#{@ds.size})"
          title_col = Sketchup::Color.new(120, 240, 160)
          info_col  = Sketchup::Color.new(150, 255, 190)
        else
          ten = { thieu: 'THIẾU dấu khoét', lech: 'Dấu khoét LỆCH', nong: 'Dấu khoét NÔNG' }[r[:loai]]
          l1 = "#{ten}   (răng #{@idx + 1}/#{@ds.size})"
          title_col = Sketchup::Color.new(255, 180, 90)
          info_col  = Sketchup::Color.new(255, 210, 60)
        end
        l2 = "Tấm ngàm: #{r[:ten_a]}  →  tấm nhận: #{r[:ten_b]}"
        l3 = PhanTich.cau(r)
        l4 = '← → đổi răng  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, @color)
        txt(view, 34, 26, l1, title_col, 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, info_col, 12, false)
        txt(view, 34, 90, l4, Sketchup::Color.new(200, 200, 200), 11, false)
      end

      def draw_box2d(view, x, y, w, h, color)
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = color
        view.draw2d(GL_POLYGON, pts)
      end

      def txt(view, x, y, s, color, size, bold)
        view.draw_text(Geom::Point3d.new(x, y, 0), s, color: color, font: 'Arial', size: size, bold: bold)
      end

      def frame(bb)
        cam = Sketchup.active_model.active_view.camera
        ctr = bb.center
        diag = bb.diagonal
        diag = 100.0 if diag < 1.0
        if cam.perspective?
          fov = cam.fov * Math::PI / 180.0
          dist = (diag / 2.0) / Math.tan(fov / 2.0) * 1.5
          cam.set(ctr.offset(cam.direction.reverse, dist), ctr, cam.up)
        else
          cam.set(ctr.offset(cam.direction.reverse, diag * 3.0), ctr, cam.up)
          cam.height = diag * 1.5
        end
      end

      def quit(view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end

      def update_status
        lbl = @mode == :ok ? 'Răng đạt' : 'Răng lỗi'
        Sketchup.set_status_text("#{lbl} — #{@idx + 1}/#{@ds.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số răng', SB_VCB_LABEL)
      end
    end

  end
end
