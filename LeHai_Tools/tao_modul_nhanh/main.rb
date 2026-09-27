# encoding: UTF-8
# Tạo Modul Nhanh: nhập thông số → dựng đủ tấm đúng kết cấu xưởng Lê Hải.
# Modul 1: KHUNG BAO TỦ LẠNH (Khoa nghiệm thu 24/09/2026) — bảng ở file này.
# Modul 2: HỘC KÉO (27/09/2026) — bang_hoc_keo.rb.
# Bấm nút → menu icon chọn modul (ui/menu.html) → mở bảng modul; bảng nào cũng có "‹" về menu.
#
# Lõi tính thuần Ruby ở khung_bao_tu_lanh.rb (không gọi SketchUp). Bảng thông số +
# hình 2D ở ui/khung_bao.html — hình vẽ từ CHÍNH danh sách tấm của lõi (callback
# 'tinh'), JS không có công thức riêng nên hình và tủ dựng ra không lệch được.
# Đồ dev (bộ dò module mẫu, so khớp, bảng quy tắc kèm nguồn) ở lab:
# agent_lab_khoa/projects/tao-modul-nhanh/ — không phát xuống máy thợ.
#
# Toolbar do LeHai_Tools/main.rb quản lý — file này chỉ expose create_cmd.

require 'sketchup.rb'
require 'json'
require File.join(File.dirname(__FILE__), 'khung_bao_tu_lanh')
require File.join(File.dirname(__FILE__), 'bang_hoc_keo')

module TK
  module TaoModulNhanh

    PATH      = File.dirname(__FILE__).freeze
    DICT      = 'TaoModulNhanh'
    PHIEN_BAN = '2026-09-24'   # đổi khi quy tắc trong lõi đổi — tủ cũ biết mình dựng theo bản nào
    CACH_BEN  = 500.0          # mm — khoảng hở với hình đang có trong file

    # Thông số người dùng được sửa. Thứ tự = thứ tự ô trong bảng.
    # Bạ chân cách len CỐ ĐỊNH 20 — Khoa chốt 24/09 không đưa ra bảng.
    HOI = [
      [:rong,        'Rộng phủ bì'],
      [:sau,         'Sâu'],
      [:cao,         'Cao tổng tới trần'],
      [:cao_tu_lanh, 'Chỗ tủ lạnh (sàn → mặt nóc dưới)'],
      [:cao_ba_noc,  'Bạ nóc'],
      [:len_day,     'Len chân tường — dày'],
      [:len_cao,     'Len chân tường — cao'],
      [:van,         'Ván thân (cả cánh, xương)'],
      [:van_hau,     'Hậu dày'],
      [:hau_lui,     'Hậu cách tường'],
      [:ranh_hau,    'Rãnh hậu ăn vào mỗi hông']
    ].freeze

    # ── Menu chọn modul (Khoa 27/09: bấm nút → bảng icon các modul, bấm cái nào mở cái đó) ──
    # Chỉ liệt kê modul đã xong đủ 4 bước — không thẻ "sắp có". Icon + chữ nằm trong ui/menu.html;
    # ở đây chỉ nối id → hàm mở, id lạ thì bỏ qua.
    MO_MODUL = {
      'khung_bao' => -> { TaoModulNhanh.show },
      'hoc_keo'   => -> { BangHocKeo.show }
    }.freeze

    def self.menu
      if @menu&.visible? then @menu.bring_to_front; return end
      @menu = UI::HtmlDialog.new(
        dialog_title:    'Tạo Modul Nhanh',
        preferences_key: 'tk.taomodulnhanh.menu.v1',
        width:           520, height: 360,
        min_width:       420, min_height: 300,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @menu.set_file(File.join(File.dirname(__FILE__), 'ui', 'menu.html'))
      @menu.add_action_callback('mo') do |_ctx, id|
        mo = MO_MODUL[id.to_s]
        next unless mo
        @menu.close
        UI.start_timer(0, false) { mo.call }
      end
      @menu.show
    end

    # ── Hộp thoại ────────────────────────────────────────────
    def self.show
      if @dlg&.visible? then @dlg.bring_to_front; return end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Khung bao tủ lạnh',
        preferences_key: 'tk.taomodulnhanh.khungbao.v1',
        width:           780, height: 720,
        min_width:       620, min_height: 520,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @dlg.set_file(File.join(PATH, 'ui', 'khung_bao.html'))
      # đẩy mặc định + nhãn từ lõi → JS không giữ bản sao số mặc định nào
      @dlg.add_action_callback('ready') do |_ctx|
        md = KhungBaoTuLanh::MAC_DINH
        bao('khoiDau', HOI.map { |k, nhan| { khoa: k, nhan: nhan, mac_dinh: md[k] } })
      end
      @dlg.add_action_callback('tinh') { |_ctx, json| tinh(json) }
      @dlg.add_action_callback('dung') { |_ctx, json| dung(json) }
      # "‹ Tạo Modul Nhanh" → đóng bảng này, về menu chọn modul
      @dlg.add_action_callback('mo_menu') { |_ctx| @dlg.close; UI.start_timer(0, false) { menu } }
      @dlg.show
    end

    def self.bao(ham, msg)
      @dlg&.execute_script("window.#{ham}(#{msg.to_json});")
    end
    private_class_method :bao

    # JSON từ bảng → hash thông số; chỉ nhận đúng các khoá trong HOI
    def self.doc_tham_so(json)
      vao = JSON.parse(json)
      HOI.each_with_object({}) do |(k, nhan), h|
        so = vao[k.to_s].to_s.strip.tr(',', '.')
        raise "#{nhan}: '#{vao[k.to_s]}' không phải số." unless so =~ /\A\d+(\.\d+)?\z/
        h[k] = so.to_f
      end
    end
    private_class_method :doc_tham_so

    # Gõ số → lõi tính lại → gửi tấm sang vẽ, hoặc gửi lỗi (không đụng model)
    def self.tinh(json)
      tham_so = doc_tham_so(json)
      tam = KhungBaoTuLanh.tinh(tham_so)
      p = KhungBaoTuLanh::MAC_DINH.merge(tham_so)
      bao('veLai', { tham_so: p, tam: tam, nen: nen_3d(p) })
    rescue StandardError => e
      bao('baoLoi', e.message)
    end

    # Tường + len hiện trạng — CHỈ để vẽ nền 3D trong bảng, không dựng vào model.
    # Tường sát lưng tủ (y = sâu D), thò mỗi bên 200 cho thấy là tường; len nằm chân tường.
    def self.nen_3d(p)
      w, d, h = p[:rong], p[:sau], p[:cao]
      ds = [{ ten: 'Tường hiện trạng', x: [-200.0, w + 200], y: [d, d + 80], z: [0.0, h] }]
      if p[:len_day] > 0 && p[:len_cao] > 0
        ds << { ten: 'Len chân tường', x: [-200.0, w + 200], y: [d - p[:len_day], d], z: [0.0, p[:len_cao]] }
      end
      ds
    end

    def self.dung(json)
      model = Sketchup.active_model
      unless (model.active_path || []).empty?
        bao('baoLoiDung', 'Đang ở TRONG một group. Bấm Esc tới khi ra ngoài cùng rồi bấm Dựng lại.')
        return
      end
      tham_so = doc_tham_so(json)
      tam = KhungBaoTuLanh.tinh(tham_so) # sai thông số thì raise trước khi đụng model
      p = KhungBaoTuLanh::MAC_DINH.merge(tham_so)

      bb  = model.bounds
      goc = bb.empty? ? ORIGIN : Geom::Point3d.new(bb.max.x + CACH_BEN.mm, bb.min.y, 0)
      model.start_operation('Dung khung bao tu lanh', true)
      begin
        vo = model.entities.add_group
        vo.name = "Khung bao tủ lạnh #{p[:rong].round}×#{p[:sau].round}×#{p[:cao].round}"
        tam.each { |s| dung_tam(vo, s) }
        vo.transform!(Geom::Transformation.translation(goc))
        # lưu thông số + bản quy tắc để sau này sửa/dựng lại đúng tủ này
        vo.set_attribute(DICT, 'loai', 'khung_bao_tu_lanh')
        vo.set_attribute(DICT, 'phien_ban', PHIEN_BAN)
        vo.set_attribute(DICT, 'tham_so', JSON.generate(p))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      puts "[OK] Dựng #{tam.size} tấm: #{vo.name}"
      bao('xong', "Đã dựng #{tam.size} tấm — #{vo.name}")
    rescue StandardError => e
      bao('baoLoiDung', "Lỗi: #{e.message}")
      puts "[Tạo Modul Nhanh] #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    # Một tấm = hộp thẳng trục. Vẽ mặt ở phía nhỏ của trục MỎNG NHẤT rồi đùn
    # đúng bề dày — cùng cách tam_go (kiểm dấu pháp tuyến trước khi pushpull).
    def self.dung_tam(cha, s)
      lo = [s[:x][0], s[:y][0], s[:z][0]]
      dd = [s[:x][1] - s[:x][0], s[:y][1] - s[:y][0], s[:z][1] - s[:z][0]]
      mong = dd.index(dd.min)
      a, b = ([0, 1, 2] - [mong])

      # đường bao trong mặt (a, b), toạ độ tính từ góc tấm, mm
      bao_tam = [[0, 0], [dd[a], 0], [dd[a], dd[b]], [0, dd[b]]]
      if s[:khoet]
        # hông dưới: a = y (sâu), b = z (cao) — khoét góc sau-dưới đúng bằng len
        raise "Khoét chỉ hỗ trợ tấm đứng ⟂X (#{s[:ten]})" unless mong == 0
        ky = s[:khoet][:y][0] - s[:y][0]
        kz = s[:khoet][:z][1] - s[:z][0]
        bao_tam = [[0, 0], [ky, 0], [ky, kz], [dd[a], kz], [dd[a], dd[b]], [0, dd[b]]]
      end

      pts = bao_tam.map do |u, v|
        c = [0.0, 0.0, 0.0]
        c[a] = u
        c[b] = v
        Geom::Point3d.new(c[0].mm, c[1].mm, c[2].mm)
      end
      grp = cha.entities.add_group
      grp.name = s[:ten]
      face = grp.entities.add_face(pts)
      raise "Không vẽ được mặt tấm #{s[:ten]}" unless face
      phap = face.normal.to_a[mong]
      face.pushpull(phap >= 0 ? dd[mong].mm : -dd[mong].mm)
      grp.transform!(Geom::Transformation.translation(Geom::Point3d.new(*lo.map(&:mm))))
      grp
    end

    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Tạo Modul Nhanh') { TK::TaoModulNhanh.menu }
      cmd.tooltip         = 'Tạo Modul Nhanh — khung bao tủ lạnh, hộc kéo'
      cmd.status_bar_text = 'Chọn modul trong bảng, dựng đủ tấm đúng kết cấu xưởng.'
      s16 = File.join(icons, 'tao_modul_16.png')
      s24 = File.join(icons, 'tao_modul_24.png')
      cmd.small_icon = s16 if File.exist?(s16)
      cmd.large_icon = s24 if File.exist?(s24)
      cmd
    end

  end
end
