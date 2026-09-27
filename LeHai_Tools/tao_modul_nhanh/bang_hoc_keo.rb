# encoding: UTF-8
# ============================================================
#  HỘC KÉO — modul 2 của Tạo Modul Nhanh (27/09/2026, phát 1.9.72)
#
#  Rê chuột vào lòng khoang → tool bắn tia đo KHỐI RỖNG của khoang (không cần biết
#  khung vẽ liền hay từng tấm) → xem trước hộc ngay trong model + 3D trong bảng →
#  click chọn khoang → chỉnh thông số → Tạo. Lõi tính ở hoc_keo.rb (thuần Ruby).
#  Mở từ tab "Hộc kéo" trong bảng Tạo Modul Nhanh (main.rb).
#
#  Test dev (Ruby Console, Esc ra ngoài cùng):
#  load '<lab>/projects/lehai-tools/LeHai_Tools/tao_modul_nhanh/main.rb'  rồi  TK::TaoModulNhanh::BangHocKeo.show
# ============================================================

require 'sketchup.rb'
require 'json'
require File.join(File.dirname(__FILE__), 'hoc_keo')

module TK
  module TaoModulNhanh
    module BangHocKeo
      DIR       = File.dirname(__FILE__)
      DICT      = 'TaoModulNhanh'
      PHIEN_BAN = '2026-09-27'   # đổi khi quy tắc trong lõi đổi — hộc cũ biết mình dựng theo bản nào
      MM        = 25.4            # inch → mm
      TOI_DA    = 5000.0 / MM     # inch — tia xa hơn 5m coi như không chạm
      NHICH     = 0.2 / MM        # inch — nhích qua mặt vừa chạm rồi bắn tiếp
      DAY_MAX   = 100.0 / MM      # inch — mặt kia của tấm phải trong 100mm mới tính là cùng tấm
      KHOANG_MAX = 1500.0 / MM    # inch — mặt trong khoang xa hơn 1,5m = khoang hở (tia bay ra tường/phòng)
      TRAI  = Geom::Vector3d.new(-1, 0, 0)
      PHAI  = Geom::Vector3d.new(1, 0, 0)
      DUOI  = Geom::Vector3d.new(0, 0, -1)
      TREN  = Geom::Vector3d.new(0, 0, 1)
      SAU   = Geom::Vector3d.new(0, 1, 0)

      # Ô số người dùng sửa được. Thứ tự = thứ tự trong bảng.
      HOI = [
        [:van,          'Ván thùng + mặt'],
        [:van_day,      'Đáy hộc dày'],
        [:khe_ray,      'Khe ray mỗi bên'],
        [:cach_day,     'Đáy hộc cách mốc dưới'],
        [:thap_hon_noc, 'Hông thấp hơn mốc trên'],
        [:ranh_day,     'Rãnh đáy ăn vào hông'],
        [:khe_mat,      'Khe mặt hộc'],
        [:khe_phu,      'Mặt phủ cách mép tủ'],
        [:khe_sau,      'Khe sau tối thiểu (tới hậu)']
      ].freeze

      # ── Đo khoang bằng tia ─────────────────────────────────
      # Bắn một tia; xuyên qua hộc kéo tool đã dựng (rê lại khoang đã có hộc vẫn đo được khoang).
      def self.ban(model, pt, dir)
        20.times do
          kq = model.raytest([pt, dir])
          return nil unless kq
          diem, duong = kq
          return nil if pt.distance(diem) > TOI_DA
          cua_tool = duong.any? { |e| e.respond_to?(:get_attribute) && e.get_attribute(DICT, 'loai') == 'hoc_keo' }
          return [diem, duong] unless cua_tool
          @qua_hoc = true   # tia vừa xuyên qua một hộc tool đã dựng
          pt = diem.offset(dir, NHICH)
        end
        nil
      end

      # Một phía khoang: mặt trong (tia chạm đầu tiên), mặt kia của tấm đó, và bên kia
      # tấm còn khoang khác của CÙNG khung không (cùng group ngoài cùng → là đố/vách, không phải tường).
      def self.do_phia(model, q, dir)
        a = ban(model, q, dir)
        return nil unless a && q.distance(a[0]) <= KHOANG_MAX
        b = ban(model, a[0].offset(dir, NHICH), dir)
        cung_tam = b && b[1].first == a[1].first && a[0].distance(b[0]) <= DAY_MAX
        return { trong: a[0], ngoai: a[0], ke: false, sat: false, a: a } unless cung_tam
        c = ban(model, b[0].offset(dir, NHICH), dir)
        ke = !c.nil? && c[1].first == a[1].first
        # Ngay sau mặt ngoài (≤ 5mm) là hình của group KHÁC → tủ khác đứng sát (Khoa 27/09: phủ thì chỉ cảnh báo)
        sat = !c.nil? && !ke && b[0].distance(c[0]) <= 5.0 / MM
        { trong: a[0], ngoai: b[0], ke: ke, sat: sat, a: a }
      end

      # Mặt vừa chạm → khoảng y (inch) của nó trong toạ độ thế giới (mép trước / mép sau hông)
      def self.y_mat(hit)
        duong = hit[1]
        face = duong.last
        return nil unless face.is_a?(Sketchup::Face)
        tr = Geom::Transformation.new
        duong[0..-2].each { |e| tr *= e.transformation if e.respond_to?(:transformation) }
        ys = face.vertices.map { |v| (tr * v.position).y }
        [ys.min, ys.max]
      end

      # Tia chuột → khối rỗng của khoang (mm) cho lõi, hoặc raise với lý do tiếng Việt.
      def self.do_khoang(model, ray)
        cham = ban(model, ray[0], ray[1])
        raise 'Chuột không chạm hình nào.' unless cham
        p0 = cham[0].offset(ray[1].reverse, NHICH * 5)   # lùi về phía mắt: đứng trong lòng khoang

        tr0 = do_phia(model, p0, TRAI)
        ph0 = do_phia(model, p0, PHAI)
        raise 'Không thấy hai hông — rê chuột vào TRONG lòng khoang.' unless tr0 && ph0
        yt = y_mat(tr0[:a])
        yp = y_mat(ph0[:a])
        raise 'Không đọc được mặt hông.' unless yt && yp
        y_truoc = [yt[0], yp[0]].max   # mép trước lòng = chỗ cả hai hông đã bắt đầu
        y_sau_hong = [yt[1], yp[1]].min
        raise 'Chuột đang ở mặt ngoài tủ — rê vào TRONG lòng khoang.' if p0.y < y_truoc - NHICH

        # Đo lại ở sát mép trước (5mm): đố chỉ nằm ở mặt trước, đo ở sâu sẽ lọt qua sau đố
        q = Geom::Point3d.new(p0.x, y_truoc + 5.0 / MM, p0.z)
        @qua_hoc = false
        bien = { trai: do_phia(model, q, TRAI), phai: do_phia(model, q, PHAI),
                 duoi: do_phia(model, q, DUOI), tren: do_phia(model, q, TREN) }
        thieu = bien.select { |_, v| v.nil? }.keys
        raise "Khoang hở phía #{thieu.map { |k| { trai: 'trái', phai: 'phải', duoi: 'dưới', tren: 'trên' }[k] }.join(', ')}." unless thieu.empty?
        # Khung gom một group → 4 phía cùng group ngoài cùng. Khung tấm rời (mỗi tấm một group ở ngoài
        # cùng) vẫn đo được, nhưng không nhận ra đố/vách kề → mặt phủ phủ tới mép ngoài tấm.
        # (27/09: từng CHẶN ca này → chặn oan khung thật của Khoa; tường xa đã bị KHOANG_MAX loại.)
        khung = bien.values.map { |b| b[:a][1].first }.uniq

        x0 = bien[:trai][:trong].x
        x1 = bien[:phai][:trong].x
        z0 = bien[:duoi][:trong].z
        z1 = bien[:tren][:trong].z
        giua = Geom::Point3d.new((x0 + x1) / 2, y_truoc + 5.0 / MM, (z0 + z1) / 2)
        # Mặt trước khoang phải HỞ về phía -Y (trục xanh âm). Tủ xoay ngang / quay lưng thì phía
        # "trước" tool tưởng lại là hậu → mặt hộc sẽ dựng ở sau lưng tủ. Bản thử chặn, không đoán.
        # Đứng cách mép trước 5mm nhìn ra: gặp mặt trong 10mm = phía này đóng (hậu / cánh đang đóng).
        truoc = ban(model, giua, Geom::Vector3d.new(0, -1, 0))
        if truoc && giua.distance(truoc[0]) <= 10.0 / MM
          raise 'Mặt trước khoang bị chặn (cánh đang đóng, hoặc tủ xoay ngang/quay lưng?) — tool chỉ nhận tủ quay mặt về trục xanh âm (-Y).'
        end
        hau = do_phia(model, giua, SAU)
        y_sau = hau && hau[:trong].y <= y_sau_hong + NHICH ? hau[:trong].y : y_sau_hong

        mm = ->(v) { v.to_f * MM }
        k = {
          x: [mm.(x0), mm.(x1)], z: [mm.(z0), mm.(z1)], y_truoc: mm.(y_truoc), y_sau: mm.(y_sau),
          bien: {},
          co_hau: !hau.nil? && hau[:trong].y <= y_sau_hong + NHICH,
          y_hau_ngoai: hau ? mm.(hau[:ngoai].y) : nil,
          da_co_hoc: @qua_hoc,  # tia trong khoang xuyên qua hộc cũ → khoang này đã có hộc
          sat: %i[trai phai duoi tren].select { |s| bien[s][:sat] },  # phía có tủ khác đứng sát
          tam_roi: khung.size > 1   # khung chưa gom một group → không nhận đố/vách kề cho mặt phủ
        }
        # trái/phải đo theo x, dưới/trên theo z → số mm cho lõi (HocKeo.phu_bi)
        %i[trai phai].each { |s| k[:bien][s] = { trong: mm.(bien[s][:trong].x), ngoai: mm.(bien[s][:ngoai].x), ke: bien[s][:ke] } }
        %i[duoi tren].each { |s| k[:bien][s] = { trong: mm.(bien[s][:trong].z), ngoai: mm.(bien[s][:ngoai].z), ke: bien[s][:ke] } }

        rong = k[:x][1] - k[:x][0]
        cao = k[:z][1] - k[:z][0]
        sau = k[:y_sau] - k[:y_truoc]
        raise "Khoang #{rong.round} × #{cao.round} × #{sau.round} quá nhỏ cho hộc kéo." if rong < 150 || cao < 80 || sau < 250
        k
      end

      # Tấm bao quanh khoang (chỉ để vẽ 3D trong bảng) — dựng lại từ số đo tia
      def self.tam_bao(k)
        b = k[:bien]
        xa, xb = b[:trai][:ngoai], b[:phai][:ngoai]
        za, zb = b[:duoi][:ngoai], b[:tren][:ngoai]
        y = [k[:y_truoc], k[:y_sau]]
        ds = [
          { ten: 'khoang · trái', x: [xa, k[:x][0]], y: y, z: [za, zb] },
          { ten: 'khoang · phải', x: [k[:x][1], xb], y: y, z: [za, zb] },
          { ten: 'khoang · dưới', x: k[:x], y: y, z: [za, k[:z][0]] },
          { ten: 'khoang · trên', x: k[:x], y: y, z: [k[:z][1], zb] }
        ]
        ds << { ten: 'khoang · hậu', x: k[:x], y: [k[:y_sau], [k[:y_hau_ngoai] || k[:y_sau] + 9, k[:y_sau] + 1].max], z: k[:z] } if k[:co_hau]
        ds.reject { |s| [s[:x], s[:y], s[:z]].any? { |a, c| c - a < 0.5 } }
      end

      # ── Hộp thoại + trạng thái ─────────────────────────────
      def self.show
        model = Sketchup.active_model
        unless (model.active_path || []).empty?
          UI.messagebox('Đang ở TRONG một group. Bấm Esc tới khi ra ngoài cùng rồi chạy lại.')
          return
        end
        @ts ||= {}
        unless @dlg&.visible?
          @dlg = UI::HtmlDialog.new(
            dialog_title: 'Hộc kéo', preferences_key: 'tk.taomodulnhanh.hockeo.v1',
            width: 900, height: 680, min_width: 700, min_height: 500,
            resizable: true, style: UI::HtmlDialog::STYLE_DIALOG
          )
          @dlg.set_file(File.join(DIR, 'ui', 'hoc_keo.html'))
          @dlg.add_action_callback('ready') { |_ctx| khoi_dau }
          @dlg.add_action_callback('tinh') { |_ctx, json| doi_tham_so(json) }
          @dlg.add_action_callback('dung') { |_ctx, _json| tao }
          # "‹ Tạo Modul Nhanh" → đóng bảng này, về menu chọn modul
          @dlg.add_action_callback('mo_menu') { |_ctx| @dlg.close; UI.start_timer(0, false) { TaoModulNhanh.menu } }
          @dlg.set_on_closed { Sketchup.active_model.select_tool(nil) if @tool && @tool.dang_mo }
          @dlg.show
        end
        @tool = ChonKhoang.new
        model.select_tool(@tool)
      end

      def self.khoi_dau
        md = HocKeo::MAC_DINH
        bao('khoiDau', { hoi: HOI.map { |k, nhan| { khoa: k, nhan: nhan, mac_dinh: md[k] } }, ray_co: HocKeo::RAY_CO })
      end

      def self.bao(ham, msg)
        @dlg&.execute_script("window.#{ham}(#{msg.to_json});")
      end

      def self.doc_tham_so(json)
        vao = JSON.parse(json)
        ts = {}
        HOI.each do |k, nhan|
          so = vao[k.to_s].to_s.strip.tr(',', '.')
          raise "#{nhan}: '#{vao[k.to_s]}' không phải số." unless so =~ /\A\d+(\.\d+)?\z/
          ts[k] = so.to_f
        end
        ts[:kieu_mat] = vao['kieu_mat'] == 'phu' ? 'phu' : 'lot'
        ts[:so_hoc] = [vao['so_hoc'].to_i, 1].max
        ts[:ray] = vao['ray'].to_s == 'tu' ? nil : vao['ray'].to_f
        ts[:bo] = Array(vao['bo']).map(&:to_i)
        ts
      end

      # Bảng đổi số → tính lại khoang đang xem
      def self.doi_tham_so(json)
        @ts = doc_tham_so(json)
        xem(@tool&.khoang, @tool&.khoa)
      rescue StandardError => e
        bao('baoLoi', e.message)
      end

      # Khoang đang rê/đã chọn → lõi tính → gửi bảng (3D) + tool (nét xem trước)
      def self.xem(k, da_khoa)
        @kq = nil
        if k.nil?
          bao('datKhoang', nil)
        else
          bao('datKhoang', { khung: k.reject { |key, _| key == :bien }, tam_khung: tam_bao(k), khoa: da_khoa })
          @kq = HocKeo.tinh(k, @ts || {})
          bao('veLai', @kq.merge(canh_bao: canh_bao_sat(k)))
        end
      rescue StandardError => e
        bao('baoLoi', e.message)
      ensure
        Sketchup.active_model.active_view.invalidate
      end

      def self.ket_qua
        @kq
      end

      TEN_PHIA = { trai: 'trái', phai: 'phải', duoi: 'dưới', tren: 'trên' }.freeze

      # Cảnh báo phủ chạm tủ bên cạnh (Khoa chốt 27/09: không tự chừa khe, chỉ báo) — nil nếu không có
      def self.canh_bao_sat(k)
        return nil unless k && (@ts || {})[:kieu_mat] == 'phu' && k[:sat] && !k[:sat].empty?
        "Mặt phủ sẽ CHẠM mặt tủ bên cạnh (phía #{k[:sat].map { |s| TEN_PHIA[s] }.join(', ')}) — kiểm khe"
      end

      def self.tao
        model = Sketchup.active_model
        raise 'Chưa chọn khoang — rê chuột vào khoang rồi CLICK để chọn.' unless @tool&.khoa && @tool.khoang
        raise 'Khoang này đã có hộc kéo — xoá hộc cũ (hoặc Ctrl+Z) rồi mới tạo lại.' if @tool.khoang[:da_co_hoc]
        raise 'Đang ở TRONG một group. Bấm Esc tới khi ra ngoài cùng.' unless (model.active_path || []).empty?
        kq = HocKeo.tinh(@tool.khoang, @ts || {})   # sai thông số thì raise trước khi đụng model
        raise 'Không có hộc nào được tick.' if kq[:tam].empty?

        model.start_operation('Tao hoc keo', true)
        begin
          vo = model.entities.add_group
          k = @tool.khoang
          vo.name = "Hộc kéo #{(k[:x][1] - k[:x][0]).round}×#{(k[:z][1] - k[:z][0]).round}"
          kq[:tam].each { |s| TaoModulNhanh.dung_tam(vo, s) }   # dùng chung với khung bao (main.rb)
          vo.set_attribute(DICT, 'loai', 'hoc_keo')
          vo.set_attribute(DICT, 'phien_ban', PHIEN_BAN)
          vo.set_attribute(DICT, 'tham_so', JSON.generate(kq[:tham_so].merge(ray: kq[:ray])))
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        so_hoc = kq[:khoang].count { |x| x[:gan] }
        puts "[OK] Hộc kéo: #{so_hoc} hộc, #{kq[:tam].size} tấm, ray #{kq[:ray].round}"
        @tool.bo_chon
        bao('xong', "Đã tạo #{so_hoc} hộc (#{kq[:tam].size} tấm), ray #{kq[:ray].round}. Ctrl+Z để gỡ. Rê sang khoang khác để làm tiếp.")
      rescue StandardError => e
        bao('baoLoiDung', "Lỗi: #{e.message}")
        puts "[Hộc kéo] #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end

      # ── Tool chuột: rê = xem trước · click = chọn khoang · Esc = bỏ chọn / thoát ──
      class ChonKhoang
        attr_reader :khoang, :khoa, :dang_mo

        CANH = [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4],
                [0, 4], [1, 5], [2, 6], [3, 7]].freeze

        def initialize
          @khoang = nil
          @khoa = false
          @loi = nil
          @khoa_do = nil
        end

        def activate
          @dang_mo = true
          nhac_thanh
        end

        def deactivate(view)
          @dang_mo = false
          view.invalidate
        end

        def resume(view)
          nhac_thanh
          view.invalidate
        end

        def nhac_thanh
          Sketchup.status_text = @khoa ? 'Đã chọn khoang — chỉnh thông số trong bảng rồi bấm Tạo. Click khoang khác để đổi · Esc bỏ chọn.' :
                                         'Rê chuột vào TRONG lòng khoang để xem trước · click để chọn · Esc thoát.'
        end

        def do_tai(view, x, y)
          k = BangHocKeo.do_khoang(view.model, view.pickray(x, y))
          @loi = nil
          k
        rescue StandardError => e
          @loi = e.message
          nil
        end

        def onMouseMove(_flags, x, y, view)
          return if @khoa
          k = do_tai(view, x, y)
          khoa_moi = k && [k[:x], k[:z], k[:y_truoc], k[:y_sau]].flatten.map { |v| v.round(1) }
          if khoa_moi != @khoa_do
            @khoa_do = khoa_moi
            @khoang = k
            BangHocKeo.xem(@khoang, false)
          end
          view.invalidate
        rescue StandardError => e
          puts "[Hộc kéo] #{e.class}: #{e.message}"
        end

        def onLButtonDown(_flags, x, y, view)
          k = do_tai(view, x, y)
          if k
            @khoang = k
            @khoa = true
            @khoa_do = nil
            BangHocKeo.xem(@khoang, true)
          elsif @khoa
            bo_chon
          end
          nhac_thanh
          view.invalidate
        rescue StandardError => e
          puts "[Hộc kéo] #{e.class}: #{e.message}"
          UI.messagebox("Lỗi: #{e.message}")
        end

        def bo_chon
          @khoa = false
          @khoang = nil
          @khoa_do = nil
          BangHocKeo.xem(nil, false)
          nhac_thanh
        end

        # Lý do 2 = Ctrl+Z khi tool đang mở (tài liệu Trimble) → giữ tool để gỡ hộc rồi làm lại
        def onCancel(reason, view)
          return view.invalidate if reason == 2
          if @khoa then bo_chon else view.model.select_tool(nil) end
          view.invalidate
        end

        # ── Vẽ: khung xanh ôm lòng khoang + nét các tấm hộc ──
        def hop_diem(s)
          (0..7).map do |i|
            Geom::Point3d.new(s[:x][i & 1].mm, s[:y][(i >> 1) & 1].mm, s[:z][(i >> 2) & 1].mm)
          end
        end

        def canh_hop(s)
          c = hop_diem(s)
          CANH.flat_map { |a, b| [c[a], c[b]] }
        end

        def getExtents
          bb = Geom::BoundingBox.new
          mb = Sketchup.active_model.bounds
          (0..7).each { |i| bb.add(mb.corner(i)) } unless mb.empty?
          kq = BangHocKeo.ket_qua
          kq[:tam].each { |s| hop_diem(s).each { |p| bb.add(p) } } if kq && @khoang
          bb
        end

        def draw(view)
          if @khoang
            long = { x: @khoang[:x], y: [@khoang[:y_truoc], @khoang[:y_sau]], z: @khoang[:z] }
            ve_net(view, canh_hop(long), Sketchup::Color.new(30, 120, 230), 2)
            kq = BangHocKeo.ket_qua
            if kq
              mau = @khoa ? Sketchup::Color.new(20, 160, 80) : Sketchup::Color.new(230, 120, 20)
              ve_net(view, kq[:tam].flat_map { |s| canh_hop(s) }, mau, @khoa ? 3 : 2)
            end
          end
          ve_bang(view)
        end

        def ve_net(view, pts, mau, day)
          return if pts.empty?
          view.line_width = day
          view.drawing_color = mau
          view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
        end

        def ve_bang(view)
          kq = BangHocKeo.ket_qua
          if @khoang
            k = @khoang
            l1 = "Lòng #{(k[:x][1] - k[:x][0]).round(1)} × #{(k[:z][1] - k[:z][0]).round(1)} × #{(k[:y_sau] - k[:y_truoc]).round(1)}" +
                 (kq ? "   ·   ray #{kq[:ray].round}" : '')
            l2 = @khoa ? 'ĐÃ CHỌN — chỉnh trong bảng, bấm Tạo  ·  Esc bỏ chọn' : 'Click để chọn khoang này'
            mau = @khoa ? Sketchup::Color.new(20, 160, 80) : Sketchup::Color.new(230, 120, 20)
            if k[:da_co_hoc]
              l2 = 'KHOANG NÀY ĐÃ CÓ HỘC KÉO — xoá hộc cũ trước khi tạo lại'
              mau = Sketchup::Color.new(200, 60, 60)
            elsif (cb = BangHocKeo.canh_bao_sat(k))
              l2 = "⚠ #{cb}"
              mau = Sketchup::Color.new(230, 170, 20)
            end
          else
            l1 = @loi || 'Rê chuột vào trong lòng khoang'
            l2 = 'Esc thoát'
            mau = Sketchup::Color.new(200, 60, 60)
          end
          rong = 26 + [l1.length, l2.length].max * 8
          hop2d(view, 18, 18, rong, 58, Sketchup::Color.new(18, 22, 30, 215))
          hop2d(view, 18, 18, 6, 58, mau)
          chu(view, 34, 26, l1, Sketchup::Color.new(255, 255, 255), 13, true)
          chu(view, 34, 48, l2, Sketchup::Color.new(210, 210, 210), 11, false)
        end

        def hop2d(view, x, y, w, h, mau)
          pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
          view.drawing_color = mau
          view.draw2d(GL_POLYGON, pts)
        end

        def chu(view, x, y, s, mau, co, dam)
          view.draw_text(Geom::Point3d.new(x, y, 0), s, color: mau, font: 'Arial', size: co, bold: dam)
        end
      end
    end
  end
end
