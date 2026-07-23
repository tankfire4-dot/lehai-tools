# encoding: UTF-8
#
# Chống Bay — quét đổi tag chi tiết từ ABF_cuttingLines sang tag chống bay.
#
# Vì sao phải tự viết bộ quét thay vì dùng selection của SketchUp:
#   Chi tiết nesting nằm sâu trong group __ABF_Nesting. Quét bằng công cụ Select
#   ở ngoài group thì không chạm được chi tiết bên trong (Entity Info báo
#   "No Selection"). Bộ quét này không đụng tới selection — nó chiếu toạ độ thật
#   của từng cạnh lên màn hình rồi so với khung quét.
#
# Hai điều đã trả giá bằng lần chạy thật 19/07/2026 (probe trên file đã nest):
#   1. Tag ABF nằm ở EDGE, không nằm ở GROUP vỏ (group vỏ đeo Layer0). Đổi tag
#      phải đổi cả hai cấp, đổi mỗi group thì DXF ra layer rỗng.
#   2. Chi tiết nesting DÙNG CHUNG group — lần chạy thật báo "tách 18 container".
#      Không make_unique trước khi sửa thì đổi 1 cái là đổi lây sang tấm khác,
#      mà nhìn màn hình không thấy gì bất thường cho tới lúc ra máy cắt.

module TK
  module ChongBay

    PATH      = File.dirname(__FILE__).freeze
    THEME     = File.join(PATH, '..', 'shared', 'lehai_theme.css').freeze

    SRC_TAG   = 'ABF_cuttingLines'.freeze
    SRC_RE    = /cutting.?lines/i.freeze     # phòng tên viết hoa/thường khác nhau
    DST_RE      = /chongbay/i.freeze         # nhận DIỆN mọi tag chống bay (kể cả
                                             # tag cũ chưa đánh số, để gỡ được)

    # ── Tag = HƯỚNG + SỐ THỨ TỰ CẮT ──────────────────────────────
    # Số không phải để đánh dấu — nó là THỨ TỰ CẮT. Mỗi số thành một tag riêng
    # → bên Aspire thành một đường dao riêng, máy chạy lần lượt. Chống bay bằng
    # cách xếp trình tự: chi tiết nào cắt trước, chi tiết nào cắt sau khi xung
    # quanh còn nguyên để giữ ván. (Khuôn ABF moro, Khoa chốt 20/07.)
    HUONG = ['CHONGBAYTRAI', 'CHONGBAYPHAI'].freeze   # thứ tự Tab xoay
    # HUONG[0] = bên NHỎ hơn mốc chia, HUONG[1] = bên lớn hơn. Đừng đảo thứ tự
    # mảng này nếu không sửa luôn huong_tu_dong.

    # Nhận dạng tấm ván trong cây nesting (đo thật 23/07 — xem traverse).
    SHEET_RE  = /-sheet-\d+\z/i.freeze
    BORDER_RE = /sheetBorder/i.freeze

    # Màu GỐC của từng hướng — số 1 đậm nhất, số càng lớn càng nhạt dần.
    # Nhìn cả tấm là đọc được trình tự cắt, khỏi bấm từng tag.
    MAU_GOC = {
      'CHONGBAYTRAI' => Sketchup::Color.new(0, 150, 60),     # xanh lá đậm
      'CHONGBAYPHAI' => Sketchup::Color.new(210, 90, 0)      # cam đậm
    }.freeze

    # TRẦN **100** — Khoa chốt 23/07 (nâng từ 9; cân nhắc 200 rồi hạ xuống 100:
    # "không bao giờ một tấm ván cộng cả trái phải hơn 200 chi tiết").
    # Vì sao 9 không còn đủ: trần 9 vừa là số ĐỢT vừa là trần SỐ CHI TIẾT mỗi lượt
    # kéo (`hits.first(chu_ky)` cũ) — vẽ một nét qua 30 chi tiết thì nhận 9 cái,
    # cắt 21 cái mà nhìn không ra. Và gộp nhiều chi tiết vào cùng một đợt thì máy
    # không biết cắt cái nào trước trong đợt đó. Nay MỖI CHI TIẾT MỘT ĐỢT RIÊNG,
    # thứ tự do nét vẽ tay quyết định.
    #
    # Hai lý do của trần 9 cũ, và vì sao 100 vẫn sống:
    #   1. "Mỗi số là một đường dao dựng tay bên Aspire" — Khoa 23/07: chỉ set dao
    #      MẪU một lần rồi tái dùng, nên 100 layer không đội việc lên 100 lần.
    #   2. Aspire sắp tên layer bằng CHUỖI → "TRAI10" chen trước "TRAI2". Cái này
    #      vẫn đúng và vẫn nguy hiểm → ĐỆM 0 BA CHỮ SỐ trong ten_tag (bắt buộc,
    #      xem ten_tag). Bỏ đệm là tái phát ngay.
    SO_TOI_DA  = 100
    # KHÔNG còn dải màu đậm→nhạt (bỏ 23/07, Khoa: "đã đánh số rồi thì không cần
    # màu"). Đã có số thì màu chỉ còn một việc: nói cho biết chi tiết nào ĐÃ gắn
    # và gắn hướng nào. Một màu dịu cho mỗi hướng là đủ; dải nhạt dần chỉ làm
    # nền tranh nhau với con số, mà 100 mức thì mắt vẫn không đọc ra thứ tự.

    # ── Kiểu quét ────────────────────────────────────────────────
    # :khung = kéo hình chữ nhật, trúng cả cụm (nhanh, thứ tự theo hướng kéo)
    # :tu_do = vẽ tay tự do, đánh số theo đúng thứ tự nét đi qua
    #          (trước gọi "zigzag" — Khoa 20/07: nét là do mình vẽ chứ không phải
    #           hình zigzag đều, gọi "vẽ tự do" đúng hơn)
    # Từng có kiểu thứ ba :duong (kéo một đường thẳng) — BỎ 23/07, Khoa: "khung
    # với tự do đủ rồi". Vẽ tự do làm được mọi thứ đường thẳng làm được, chỉ tốn
    # thêm cái nút phải nhìn qua mỗi lần chọn.
    KIEU     = [:khung, :tu_do].freeze
    BUOC_NET = 4        # nét tự do chỉ ghi thêm điểm khi chuột đi quá 4px

    # Tô NỀN chi tiết thay vì chỉ tô viền: viền mảnh nhìn không ra (Khoa 20/07).
    # Khuôn alpha: tim_tam_loi/main.rb:211.
    # 120 → 70 (23/07): nền giờ chỉ để biết "đã gắn", con số mới là thứ phải đọc.
    # Nền đậm bằng số thì mắt không biết bám vào cái nào.
    FILL_ALPHA = 70

    MAX_DEPTH = 12

    COL_DONE  = Sketchup::Color.new(0, 190, 80)      # xanh lá = đã đổi
    COL_TODO  = Sketchup::Color.new(150, 150, 150)   # xám    = chưa đổi
    COL_BAND  = Sketchup::Color.new(255, 20, 200)    # hồng   = khung đang quét
    # ── Huy hiệu số ──────────────────────────────────────────────
    # Số của tool phải KHÁC HẲN nhãn ABF trên cùng bản vẽ (Khoa 23/07, nhìn ảnh
    # chạy thật: chữ đen Arial của tool lẫn vào đám nhãn ABF cũng đen, cũng nhỏ).
    # Nên số không đứng trần mà nằm trong một ĐĨA TRÒN đặc màu hướng, chữ trắng,
    # viền trắng — ABF không vẽ gì có hình dạng đó, nhìn phát biết là của mình.
    COL_CHU_SO = Sketchup::Color.new(255, 255, 255)  # chữ số: trắng
    COL_VANH   = Sketchup::Color.new(255, 255, 255)  # vành ngoài huy hiệu: trắng
    CO_CHU_SO  = 13                                  # cỡ chữ số đợt
    BK_HUY_HIEU = 12.0                               # bán kính đĩa (px màn hình)
    CANH_TRON   = 16                                 # số cạnh xấp xỉ hình tròn

    # ── Helper đọc ───────────────────────────────────────────────

    def self.tag_name(e)
      # nuốt được: entity không phải Drawingelement thì coi như không có tag
      e.layer.name.to_s rescue ''
    end

    def self.container?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end

    def self.kids_of(e)
      e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    end

    def self.src?(e)
      n = tag_name(e)
      n == SRC_TAG || !!(n =~ SRC_RE)
    end

    # ── Chọn tag đích ────────────────────────────────────────────
    # Không hardcode một tên: quét các tag có chữ CHONGBAY trong model.
    # 1 cái  → dùng luôn, không hỏi (đỡ vướng tay).
    # nhiều  → cho chọn.  0 cái → bảo Khoa tạo bên ABF trước.

    # Danh sách Layer bên ABF KHÔNG phải tag SketchUp — đó là danh sách riêng của
    # ABF (đo thật 19/07: model có 8 tag, hộp thoại ABF liệt kê 31 layer).
    # **Tag chống bay KHÔNG phụ thuộc ABF** (Khoa 23/07): tool tự tạo tag trong
    # SketchUp, xuất DXF là Aspire đọc được, không phải khai trước bên ABF. Ghi
    # chú cũ ở đây viết ngược lại và suýt chặn việc nâng trần — đã sửa.
    # Tách tên tag thành [hướng, số]. Tag cũ chưa đánh số → số nil.
    def self.tach_tag(ten)
      m = ten.to_s.match(/\A(CHONGBAY(?:TRAI|PHAI))(\d*)\z/i)
      return [nil, nil] unless m
      [m[1].upcase, (m[2].empty? ? nil : m[2].to_i)]
    end

    # ĐỆM 0 BA CHỮ SỐ — "CHONGBAYTRAI001" … "CHONGBAYTRAI100".
    # Bắt buộc từ lúc trần vượt 9 (23/07): Aspire sắp tên layer bằng chuỗi, không
    # đệm thì "TRAI10" chen lên trước "TRAI2" và sai thứ tự đường dao — lỗi nằm
    # bên Aspire, không vá được từ đây. BA chữ số chứ không phải hai: trần 100 có
    # số 100, mà "10" đệm hai chữ số là "10" — hụt một ký tự là sai lại từ đầu.
    # Đổi trần lên >999 thì phải nới đệm, nếu không là tái phát đúng lỗi cũ.
    def self.ten_tag(huong, so)
      format('%s%03d', huong, so.to_i)
    end

    # Tag đánh số KIỂU CŨ (chưa đệm 0): "CHONGBAYTRAI1" thay vì "…001".
    # File làm dở từ bản ≤1.9.48 sẽ có loại này. Trộn hai kiểu trong một file là
    # hỏng THỨ TỰ CẮT mà không báo gì: Aspire sắp chuỗi nên "…001" đứng trước
    # "…1", tức chi tiết số 1 cũ bị đẩy xuống sau cả trăm cái. Phải gỡ hết rồi
    # gắn lại — nên tool phải nói ra ngay lúc mở, đừng để phát hiện ở máy cắt.
    def self.tag_cu?(ten)
      m = ten.to_s.match(/\ACHONGBAY(?:TRAI|PHAI)(\d+)\z/i)
      !m.nil? && m[1].length != 3
    end

    # Sắp tên tag theo [hướng, SỐ THẬT] — KHÔNG sắp bằng chuỗi.
    # Sắp chuỗi thì "TRAI12" đứng trước "TRAI2" vì so ký tự '1' với '2'.
    # Khoa bắt được lỗi này HAI LẦN (bảng điều khiển, rồi bảng tổng kết) vì lần
    # đầu vá một chỗ mà không tìm hết. Nay dùng chung một hàm — mọi chỗ sắp tên
    # tag đều phải gọi nó.
    def self.sap_tag(tens)
      tens.sort_by do |t|
        h, s = tach_tag(t)
        [h || t.to_s, s || 0]
      end
    end

    # MỘT màu cho mỗi hướng, không phụ thuộc số nữa. Dùng cho viền chi tiết, nền
    # huy hiệu số, và chấm màu trong hai bảng.
    def self.color_for(tag_name)
      return COL_TODO if tag_name.nil? || tag_name == SRC_TAG
      huong, _so = tach_tag(tag_name)
      MAU_GOC[huong] || COL_TODO
    end

    # Tìm hoặc TẠO tag theo hướng+số, và sơn màu cho nó luôn để bảng Tags của
    # SketchUp cũng hiện đúng dải màu. Tạo LƯỜI — chỉ đẻ tag khi thật sự dùng
    # tới, không nhồi sẵn 80 tag vào mọi file.
    def self.tag_theo_so(model, huong, so)
      ten = ten_tag(huong, so)
      lay = find_tag(model, ten) || model.layers.add(ten)
      # Layer#color= CHƯA có tiền lệ chạy trong repo → bọc respond_to? + rescue.
      # Hỏng thì chỉ mất màu trong bảng Tags, overlay của tool vẫn đúng.
      begin
        lay.color = color_for(ten) if lay.respond_to?(:color=)
      rescue => e
        puts "[Chống Bay] không sơn được màu tag #{ten}: #{e.message}"
      end
      lay
    end

    def self.find_tag(model, name)
      model.layers.to_a.find { |l| l.name.to_s == name }
    end

    # Layer ABF_cuttingLines — chỉ dùng làm ĐƯỜNG LUI khi không có ghi chú tag gốc.
    def self.src_layer(model)
      find_tag(model, SRC_TAG) || model.layers.add(SRC_TAG)
    end

    # ── Nhớ tag gốc để gỡ đúng ────────────────────────────────────
    # Gỡ KHÔNG đoán "chắc nó vốn là ABF_cuttingLines". Mình không viết ABF, không
    # biết nó còn dựa vào gì. Nên lúc gắn thì GHI LẠI tag gốc lên chính entity đó,
    # lúc gỡ thì đọc ra mà trả về. Khuôn: auto_dan_canh/main.rb:504-517 (nhớ
    # OriginalMat rồi trả lại + delete_attribute).
    DICT = 'LeHai_ChongBay'.freeze
    KEY  = 'tag_goc'.freeze

    def self.set_tag(e, mode, dst)
      model = Sketchup.active_model
      if mode == :go
        ten = e.get_attribute(DICT, KEY)
        lay = ten && find_tag(model, ten.to_s)
        e.layer = lay || src_layer(model)   # không có ghi chú → đường lui
        e.delete_attribute(DICT)
      else
        # ghi MỘT LẦN: chuyển trái ↔ phải không được đè mất tag gốc thật
        e.set_attribute(DICT, KEY, tag_name(e)) if e.get_attribute(DICT, KEY).nil?
        e.layer = dst
      end
    end

    # ── Bảng điều khiển chạy song song với bộ quét ───────────────
    # Khuôn dien_ten: HtmlDialog mở cùng lúc với một Tool, hai bên đồng bộ.
    # Bảng nhắc trong khung nhìn chỉ ĐỌC được; bảng này BẤM được.
    # Ivar riêng @panel — KHÔNG dùng chung @dlg với bảng tổng kết, kẻo thoát tool
    # là đóng nhầm nhau.

    def self.show_panel(tool)
      @tool = tool
      if @panel && (@panel.visible? rescue false)
        @panel.bring_to_front
        return
      end
      @panel = UI::HtmlDialog.new(
        dialog_title:    'Chống Bay',
        preferences_key: 'tk.chongbay.panel',
        width: 300, height: 430, min_width: 260, min_height: 360,
        resizable: true, style: UI::HtmlDialog::STYLE_UTILITY
      )
      @panel.add_action_callback('dat_huong') do |_c, i|
        @tool.dat_huong(i.to_i) if @tool
      end
      @panel.add_action_callback('dat_kieu') do |_c, i|
        @tool.dat_kieu(i.to_i) if @tool
      end
      @panel.add_action_callback('dat_so_ke') do |_c, i, n|
        @tool.dat_so_ke(i.to_i, n.to_i) if @tool
      end
      # Kết thúc tool từ bảng. HOÃN qua timer: đóng tool sẽ đóng luôn chính cái
      # dialog đang chạy callback này — làm thẳng là tự rút ghế mình đang ngồi.
      # Khuôn hoãn: ha_nen/main.rb:66.
      @panel.add_action_callback('xong') do |_c|
        UI.start_timer(0, false) { @tool.ket_thuc if @tool }
      end
      @panel.set_html(build_panel_html)
      @panel.show
    end

    # Lời nhắc ngắn trên bảng (vd "đã gắn rồi, Gỡ trước"). Chuỗi truyền vào
    # KHÔNG được chứa dấu nháy đơn — nó đi thẳng vào lời gọi JS.
    def self.nhac(msg)
      return unless @panel && (@panel.visible? rescue false)
      @panel.execute_script("nhac('#{msg.to_s.gsub("'", '')}')")
    rescue => e
      puts "[Chống Bay] không hiện được lời nhắc: #{e.message}"
    end

    def self.dong_panel
      @tool = nil
      begin
        @panel.close if @panel && (@panel.visible? rescue false)
      rescue => e
        puts "[Chống Bay] không đóng được bảng: #{e.message}"
      end
      @panel = nil
    end

    # dem = [[ten_tag_hoac_nil, so_luong], ...]
    # so_ke = mảng đợt kế tiếp, một phần tử cho mỗi hướng trong HUONG.
    # tam   = tên tấm ván mà hai ô số đang nói tới.
    def self.sync_panel(huong_i, kieu_i, so_ke, tam, dem)
      return unless @panel && (@panel.visible? rescue false)
      hang = dem.map do |ten, n|
        mau = hex(color_for(ten))
        "[\"#{esc_html(ten || 'chưa gắn')}\",#{n},\"#{mau}\"]"
      end.join(',')
      @panel.execute_script(
        "capNhat(#{huong_i},#{kieu_i},[#{so_ke.join(',')}]," \
        "\"#{esc_html(tam)}\",[#{hang}])"
      )
    rescue => e
      puts "[Chống Bay] không cập nhật được bảng: #{e.message}"
    end

    def self.build_panel_html
      theme = File.exist?(THEME) ? File.read(THEME, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          /* chỉ thêm phần theme chưa có: bảng đếm + chấm màu.
             Nút bấm / ô nhập dùng nguyên class nhà (.lh-chip, .lh-input). */
          table { width: 100%; border-collapse: collapse; font-size: 13px; }
          td { padding: 6px 8px; border-bottom: 1px solid var(--lh-line-2); }
          td.v { text-align: right; font-weight: 600; font-variant-numeric: tabular-nums; }
          .dot {
            display: inline-block; width: 10px; height: 10px; border-radius: 3px;
            margin-right: 7px; vertical-align: -1px;
          }
        </style></head>
        <body class="lh"><div class="lh-dialog">
          <div class="lh-eyebrow">LeHai's Decor Tools</div>
          <h1 class="lh-title">Chống Bay</h1>

          <div class="lh-field">
            <label class="lh-label">Hướng</label>
            <div class="lh-chips">
              <button class="lh-chip is-active" id="h0" onclick="pick(0)">Tự động</button>
              <button class="lh-chip" id="h1" onclick="pick(1)">Trái</button>
              <button class="lh-chip" id="h2" onclick="pick(2)">Phải</button>
              <button class="lh-chip" id="h3" onclick="pick(3)">Gỡ</button>
            </div>
            <div class="lh-hint">
              <b>Tự động</b> đọc vị trí chi tiết trên tấm ván — bên nào của đường
              giữa tấm thì vào bên đó, khỏi phải nghĩ. Chi tiết nằm vắt ngang
              đường giữa thì tính theo tâm nó; muốn khác thì bấm Trái/Phải để ép.
            </div>
          </div>

          <div class="lh-field">
            <label class="lh-label">Kiểu quét</label>
            <div class="lh-chips">
              <button class="lh-chip is-active" id="k0" onclick="pickK(0)">Khung</button>
              <button class="lh-chip" id="k1" onclick="pickK(1)">Vẽ tự do</button>
            </div>
          </div>

          <div class="lh-field">
            <label class="lh-label">Đợt kế tiếp — <span id="tam">…</span></label>
            <div class="lh-row">
              <div>
                <label class="lh-label" style="font-weight:400">Trái</label>
                <input class="lh-input" id="n0" type="number" min="1" max="#{SO_TOI_DA}"
                       value="1" onchange="gui(0)">
              </div>
              <div>
                <label class="lh-label" style="font-weight:400">Phải</label>
                <input class="lh-input" id="n1" type="number" min="1" max="#{SO_TOI_DA}"
                       value="1" onchange="gui(1)">
              </div>
            </div>
          </div>
          <div class="lh-hint">
            Số là THỨ TỰ CẮT, mỗi chi tiết một số riêng. Đếm RIÊNG cho <b>từng tấm
            ván</b> và từng bên — mỗi tấm là một lần chạy máy, nên quét sang tấm
            khác là số bắt đầu lại. Hai ô này nói về tấm vừa quét. Tự dò từ file
            (số lớn nhất đang có + 1); gõ đè để nhảy tới đợt khác.
            Trần #{SO_TOI_DA} mỗi bên, mỗi tấm.
          </div>

          <hr class="lh-divider">
          <div class="lh-card" style="padding:6px 8px 8px">
            <table id="dem"></table>
          </div>

          <div id="nhac" class="lh-status"></div>

          <button class="lh-btn lh-btn--primary" style="margin-top:14px"
                  onclick="sketchup.xong()">Xong</button>
          <div class="lh-hint">
            Chi tiết đã gắn thì không dán đè được — bấm Gỡ rồi quét lại.
            Hoặc ESC trong khung nhìn để kết thúc.
          </div>

          <div class="lh-foot"><span>LeHai Tools</span><span>Chống Bay</span></div>
        </div>
        <script>
          function pick(i){ sketchup.dat_huong(i); }
          function pickK(i){ sketchup.dat_kieu(i); }
          function gui(i){
            var n = parseInt(document.getElementById("n" + i).value, 10);
            if (!n) { return; }
            sketchup.dat_so_ke(i, n);
          }
          function nhac(s){
            var e = document.getElementById("nhac");
            e.innerHTML = s;
            e.style.display = s ? "block" : "none";
          }
          // Hai vòng RIÊNG: số chip hướng và số chip kiểu không bằng nhau, và
          // không có gì bảo đảm chúng sẽ bằng nhau. Dùng chung một vòng thì bỏ
          // bớt một kiểu quét là getElementById trả null, capNhat chết giữa
          // chừng và CẢ BẢNG ngừng cập nhật — hỏng ở chỗ không liên quan gì.
          // Số lấy từ Ruby, khỏi phải nhớ sửa hai nơi. (23/07)
          // n = mảng đợt kế tiếp (một phần tử mỗi hướng), tam = tên tấm ván mà
          // hai ô số đang nói tới.
          function capNhat(h, k, n, tam, dem){
            for (var i = 0; i < #{HUONG.size + 2}; i++){
              document.getElementById("h" + i).className =
                (i === h) ? "lh-chip is-active" : "lh-chip";
            }
            for (var j2 = 0; j2 < #{KIEU.size}; j2++){
              document.getElementById("k" + j2).className =
                (j2 === k) ? "lh-chip is-active" : "lh-chip";
            }
            for (var j3 = 0; j3 < #{HUONG.size}; j3++){
              document.getElementById("n" + j3).value = n[j3];
            }
            document.getElementById("tam").textContent = tam;
            var s = "";
            for (var j = 0; j < dem.length; j++){
              s += "<tr><td><span class=dot style=background:" + dem[j][2] + "></span>"
                 + dem[j][0] + "</td><td class=v>" + dem[j][1] + "</td></tr>";
            }
            document.getElementById("dem").innerHTML = s;
          }
        </script></body></html>
      HTML
    end

    # ── Bảng tổng kết khi thoát (khuôn Dim Nhanh: ESC → bảng kê) ──────

    def self.hex(color)
      format('#%02x%02x%02x', color.red, color.green, color.blue)
    end

    def self.esc_html(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
    end

    # trong_file = { tên_tag => tổng chi tiết đang đeo tag đó trong cả file }
    # con_lai    = số chi tiết chưa gắn tag chống bay nào
    # Bất biến kiểm được bằng mắt: số lớn + con_lai = tổng chi tiết của file.
    def self.show_summary(trong_file, con_lai)
      @dlg.close if @dlg && (@dlg.visible? rescue false)
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Chống Bay — đã gắn',
        preferences_key: 'tk.chongbay',
        width: 380, height: 400, min_width: 320, min_height: 300,
        resizable: true, style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dlg.add_action_callback('close_dlg') { |_ctx| @dlg.close }
      @dlg.set_html(build_summary_html(trong_file, con_lai))
      @dlg.show
    end

    def self.build_summary_html(trong_file, con_lai)
      da_gan = trong_file.values.inject(0) { |s, v| s + v }

      rows = sap_tag(trong_file.keys).map do |tag|
        mau = hex(color_for(tag))
        "<tr>" \
          "<td><span class='dot' style='background:#{mau}'></span>#{esc_html(tag)}</td>" \
          "<td class='v'>#{trong_file[tag].to_i}</td>" \
        "</tr>"
      end.join

      theme = File.exist?(THEME) ? File.read(THEME, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>#{theme}
          table{width:100%;border-collapse:collapse;font-size:13px}
          th{font-size:10px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;
             color:var(--lh-ink-soft);text-align:left;padding:6px 8px;
             border-bottom:1.5px solid var(--lh-line)}
          td{padding:7px 8px;border-bottom:1px solid var(--lh-line-2)}
          td.v{text-align:right;font-weight:700;font-variant-numeric:tabular-nums;
               color:var(--lh-amber)}
          .dot{display:inline-block;width:10px;height:10px;border-radius:3px;
               margin-right:8px;vertical-align:-1px}
          .tot{display:flex;justify-content:space-between;align-items:baseline;
               margin-top:14px;padding:12px 8px;background:var(--lh-fill);
               border-radius:var(--lh-radius)}
          .tot b{font-size:22px;color:var(--lh-amber-2)}
          .lh-copybtn{width:auto;padding:7px 13px;font-size:12px}
        </style></head>
        <body class="lh"><div class="lh-dialog">
          <div class="lh-eyebrow">LeHai's Decor Tools</div>
          <h1 class="lh-title">Đã gắn chống bay</h1>
          <div class="lh-card" style="padding:6px 8px 8px">
            <table>
              <thead><tr><th>Tag</th>
                <th style="text-align:right">Trong file</th></tr></thead>
              <tbody>#{rows}</tbody>
            </table>
          </div>
          <div class="tot">
            <span class="lh-label" style="margin:0">Đã gắn · còn #{con_lai} chi tiết chưa gắn</span>
            <b>#{da_gan}</b>
          </div>
          <div class="lh-hint">
            Tên tag đệm 0 ba chữ số (…001, …002) để Aspire sắp đúng thứ tự đường
            dao — Aspire sắp bằng chuỗi, không đệm là "10" chen trước "2".
          </div>
          <div style="margin-top:14px;text-align:right">
            <button class="lh-btn lh-btn--primary lh-copybtn"
                    onclick="sketchup.close_dlg()">Xong</button>
          </div>
          <div class="lh-foot"><span>LeHai Tools</span><span>Chống Bay</span></div>
        </div></body></html>
      HTML
    end

    # ── Duyệt (khuôn tim_tam_loi/main.rb:36) ─────────────────────

    # `moc` = [trục, giá_trị_giữa, tên_tấm] của TẤM VÁN đang đi qua, nil khi chưa
    # vào tấm nào. Tên tấm nằm trong mốc vì **mỗi tấm đếm số RIÊNG** — xem
    # SweepTool#khoa_dem. Truyền xuôi theo đệ quy chứ không đi ngược
    # lên tìm cha: `entity.parent` trả về ComponentDefinition, mà một definition
    # có thể nằm ở nhiều chỗ nên KHÔNG suy ra được instance nào — đo thật 23/07,
    # cha của chi tiết đầu là `ComponentDefinition Group2799#1`.
    def self.traverse(entities, accum_t, depth = 0, moc = nil, &blk)
      return if depth > MAX_DEPTH
      entities.each do |e|
        next unless container?(e)
        t_con = accum_t * e.transformation
        if ten_container(e) =~ SHEET_RE
          mc    = moc_chia(e, accum_t)
          m_con = mc && (mc + [ten_tam(ten_container(e))])
        else
          m_con = moc
        end
        blk.call(e, accum_t, m_con)
        traverse(kids_of(e), t_con, depth + 1, m_con, &blk)
      end
    end

    # Tên để nhận dạng: group đặt tên thì lấy tên, không thì lấy tên definition.
    # Cấu trúc đo thật 23/07: `__ABF_Nesting` › `__<vật liệu>-sheet-N` › chi tiết,
    # trong mỗi tấm có `__ABF_sheetBorder` (Curve 4 đoạn, chu vi 7320mm = tấm
    # 1220×2440).
    def self.ten_container(e)
      ten = e.name.to_s
      ten = e.definition.name.to_s if ten.empty? && e.respond_to?(:definition)
      ten
    end

    # Rút "__A03_Pink_Ember-sheet-3" → "sheet-3" để hiện lên bảng cho gọn.
    def self.ten_tam(ten_group)
      m = ten_group.to_s.match(/(sheet-\d+)\z/i)
      m ? m[1] : ten_group.to_s
    end

    # Mốc chia trái/phải của một tấm ván: [:x hoặc :y, giá trị giữa].
    # Chia theo CẠNH NGẮN (1220) — đường lằn chạy dọc theo cạnh dài, đúng như
    # hình Khoa vẽ 23/07. Lấy cạnh ngắn thay vì cứng trục X để tấm nằm ngang hay
    # đứng đều đúng. Tấm xoay chéo thì hộp bao không còn phản ánh cạnh — nesting
    # không xoay tấm nên chưa xử lý, nếu gặp thì phải đo lại chứ đừng đoán.
    def self.moc_chia(grp_tam, accum_t)
      vien = kids_of(grp_tam).find do |k|
        container?(k) && (ten_container(k) =~ BORDER_RE || tag_name(k) =~ BORDER_RE)
      end
      segs = vien ? world_segments(vien, accum_t * grp_tam.transformation) : nil
      segs = world_segments(grp_tam, accum_t) if segs.nil? || segs.empty?
      return nil if segs.empty?
      xs = segs.map { |a, _b| a.x }
      ys = segs.map { |a, _b| a.y }
      dx = xs.max - xs.min
      dy = ys.max - ys.min
      dx <= dy ? [:x, (xs.min + xs.max) / 2.0] : [:y, (ys.min + ys.max) / 2.0]
    end

    # Chi tiết nằm bên nào của mốc chia. nil = không biết (không thuộc tấm nào).
    # Chi tiết VẮT QUA đường lằn thì tính theo TÂM của nó — phần nào nhiều hơn
    # thì về bên đó. Muốn khác thì ép tay bằng nút Trái/Phải (Khoa 23/07:
    # "chi tiết nào nằm giữa tâm đường thì được phép trái hoặc phải tùy bọn
    # sử dụng").
    def self.huong_tu_dong(segs, moc)
      return nil if moc.nil? || segs.empty?
      truc, giua = moc
      gt = segs.map { |a, _b| truc == :x ? a.x : a.y }
      tam = (gt.min + gt.max) / 2.0
      tam < giua ? HUONG[0] : HUONG[1]
    end

    # Đoạn thẳng THẬT của chi tiết ở toạ độ thế giới → viền bám sát hình.
    # Dùng hộp bao thì chi tiết nằm xiên sẽ phình ra, vừa xấu vừa quét lẹm
    # sang cái bên cạnh. Khuôn: kiem_tra_khoang_cach/main.rb:131
    def self.world_segments(grp, accum_t)
      segs = []
      collect_edges(kids_of(grp), accum_t * grp.transformation, 0, segs)
      segs
    end

    def self.collect_edges(entities, t, depth, segs)
      return if depth > MAX_DEPTH
      entities.each do |e|
        if e.is_a?(Sketchup::Edge)
          segs << [t * e.start.position, t * e.end.position]
        elsif container?(e)
          collect_edges(kids_of(e), t * e.transformation, depth + 1, segs)
        end
      end
    end

    # ── Ứng viên để quét ─────────────────────────────────────────

    # tag = nil nếu chưa đổi (còn ABF_cuttingLines), ngược lại là tên tag chống bay
    # đang đeo. Gom CẢ chi tiết đã đổi sang tag chống bay KHÁC — nếu chỉ gom tag
    # đích thì mấy cái đã gắn tag khác biến mất khỏi màn hình, không nhìn thấy,
    # không sửa lại được (lỗi này đã xảy ra: quét sang PHAI thì 6 cái TRAI mất tăm).
    # auto = hướng tính sẵn từ vị trí trên tấm ván (nil nếu không thuộc tấm nào)
    # tam  = tên tấm ván chứa nó ("sheet-3"), nil nếu nằm ngoài mọi tấm
    Cand = Struct.new(:group, :segs, :tag, :auto, :tam)

    def self.collect_cands
      out = []
      traverse(Sketchup.active_model.entities, Geom::Transformation.new) do |e, t, moc|
        n = tag_name(e)
        next unless src?(e) || n =~ DST_RE
        segs = world_segments(e, t)
        out << Cand.new(e, segs, (src?(e) ? nil : n),
                        huong_tu_dong(segs, moc), moc && moc[2])
      end
      out
    end

    # ── Đổi tag ──────────────────────────────────────────────────

    def self.has_match?(entities, match, depth = 0)
      return false if depth > MAX_DEPTH
      entities.each do |e|
        return true if match.call(e)
        return true if container?(e) && has_match?(kids_of(e), match, depth + 1)
      end
      false
    end

    def self.apply(entities, match, mode, dst, depth, stats)
      return if depth > MAX_DEPTH
      entities.each do |e|
        if container?(e)
          if match.call(e) || has_match?(kids_of(e), match)
            if e.respond_to?(:make_unique)
              begin
                e.make_unique
                stats[:unique] += 1
              rescue => err
                stats[:unique_fail] += 1
                puts "[Chống Bay] không make_unique được một container: #{err.message}"
              end
            end
          end
          if match.call(e)
            set_tag(e, mode, dst)
            stats[:groups] += 1
          end
          apply(kids_of(e), match, mode, dst, depth + 1, stats)  # gọi SAU make_unique
        elsif match.call(e)
          set_tag(e, mode, dst)
          stats[:leaves] += 1
        end
      end
    end

    # Trả về stats, hoặc nil nếu không có gì để đổi
    # Mỗi chi tiết một SỐ riêng nên không gán chung một layer được nữa.
    # cap = [[group, layer_dich], ...] — cả mẻ nằm trong MỘT bậc undo, không thì
    # quét 5 chi tiết là 5 lần Ctrl+Z mới lùi hết.
    def self.retag_many(cap, mode)
      model = Sketchup.active_model
      stats = { :groups => 0, :leaves => 0, :unique => 0, :unique_fail => 0 }

      model.start_operation('Doi tag chong bay', true)
      begin
        cap.each do |grp, lay|
          match = if mode == :go
                    lambda { |e| tag_name(e) =~ DST_RE ? true : false }
                  else
                    # Gắn chỉ đụng thứ CHƯA gắn (còn ABF_cuttingLines). Không nhận
                    # tag chống bay khác — cấm dán đè ở cả tầng entity, không chỉ
                    # tầng group. Muốn đổi thì Gỡ trước.
                    lambda { |e| src?(e) }
                  end
          apply([grp], match, mode, lay, 0, stats)
        end
        if stats[:groups] + stats[:leaves] == 0
          model.abort_operation                 # không đổi gì → khỏi bậc undo rỗng
          return nil
        end
        model.commit_operation
      rescue => e
        model.abort_operation
        UI.messagebox("Lỗi: #{e.message}")
        return nil
      end
      stats
    end

    # ── Bộ quét ──────────────────────────────────────────────────

    class SweepTool

      # tags = danh sách tag chống bay, Tab xoay vòng qua chúng
      # Vòng Tab: các tag chống bay, rồi tới CHẾ ĐỘ GỠ (vị trí cuối cùng).
      # Gỡ = trả chi tiết về ABF_cuttingLines. Nhét vào cùng vòng Tab thay vì
      # thêm phím mới: Khoa đã quen Tab rồi, không phải học thêm gì.
      # Ô hướng, theo đúng thứ tự Tab xoay và thứ tự nút trên bảng:
      #   0            = TỰ ĐỘNG (mặc định) — đọc vị trí chi tiết trên tấm ván
      #   1 .. HUONG.size = ép tay Trái / Phải
      #   HUONG.size+1 = GỠ
      # Tự động đứng ĐẦU vì đó là cái thợ dùng 99% thời gian; Trái/Phải giữ lại
      # làm đường ép cho chi tiết nằm vắt qua đường lằn (Khoa 23/07).
      TU_DONG_I = 0
      EP_DAU_I  = 1
      GO_I      = TK::ChongBay::HUONG.size + 1
      SO_O      = TK::ChongBay::HUONG.size + 2   # tổng số nút hướng

      def initialize
        @huong_i = TU_DONG_I
        # Bộ đếm riêng cho mỗi cặp [TẤM VÁN, HƯỚNG].
        #   - Riêng theo HƯỚNG: một nét ở chế độ tự động vơ cả trái lẫn phải, mỗi
        #     bên phải giữ dãy liền mạch — T,P,T,P,T ra TRAI001, PHAI001, TRAI002…
        #   - Riêng theo TẤM: **mỗi tấm ván là một lần chạy máy riêng**, thứ tự cắt
        #     chỉ có nghĩa trong phạm vi tấm đó. Bản đầu đếm chung cả file nên quét
        #     sang sheet-3 số chạy tiếp 59, 60, 61 thay vì bắt đầu lại (Khoa 23/07).
        @so_ke   = {}       # [tấm, hướng] => đợt kế tiếp (dò lại trong activate)
        @tam_hien = nil     # tấm vừa quét — hai ô số trên bảng nói về tấm này
        @kieu_i  = 0        # chỉ số trong KIEU
        @net     = []       # nét đang vẽ (toạ độ MÀN HÌNH)
        @co_doi  = false    # phiên này có đổi được gì không (quyết định hiện bảng)
        # Tag gắn TRONG PHIÊN NÀY → chỉ những cái này mới vẽ số lên màn hình
        # (Khoa 23/07). Lưu theo TÊN TAG chứ không theo group: make_unique thay
        # entity nên tham chiếu group chết sau mỗi lần rescan, còn tên tag thì
        # sống. Mỗi số chỉ một chi tiết nên tên tag đủ để trỏ đúng một cái.
        @tag_phien = {}
        @do_chu    = nil   # nil = chưa thử text_bounds, false = máy không có
      end

      def kieu ; TK::ChongBay::KIEU[@kieu_i] end

      # ---- bảng điều khiển gọi vào (HtmlDialog → Tool) ----
      # Chỉ đổi trạng thái + vẽ lại; KHÔNG sửa model trong callback của dialog.

      def dat_huong(i)
        return unless i >= 0 && i < SO_O
        @huong_i = i
        bao_bang
        Sketchup.active_model.active_view.invalidate
      end

      def dat_kieu(i)
        return unless i >= 0 && i < TK::ChongBay::KIEU.size
        @kieu_i = i
        @net = []
        bao_bang
        Sketchup.active_model.active_view.invalidate
      end

      # i = chỉ số trong HUONG (0 = Trái, 1 = Phải) — bảng có một ô cho mỗi bên.
      # Ép cho TẤM ĐANG HIỆN trên bảng (@tam_hien) — hai ô số luôn nói về một tấm.
      def dat_so_ke(i, n)
        h = TK::ChongBay::HUONG[i.to_i]
        n = TK::ChongBay.kep_so(n)
        return if h.nil? || n.nil?
        @so_ke[[@tam_hien, h]] = n
        bao_bang
        Sketchup.active_model.active_view.invalidate
      end

      # Nút "Xong" trên bảng gọi vào đây (finish nằm trong private).
      def ket_thuc
        finish(Sketchup.active_model.active_view)
      end

      # ---- Tool → bảng điều khiển ----
      def bao_bang
        dem = Hash.new(0)
        @cands.each { |c| dem[c.tag] += 1 } if @cands
        hang = TK::ChongBay.sap_tag(dem.keys.compact).map { |t| [t, dem[t]] }
        hang << [nil, dem[nil]] if dem.key?(nil)   # chưa gắn xuống cuối
        so = TK::ChongBay::HUONG.map { |h| so_ke_cua(@tam_hien, h) }
        TK::ChongBay.sync_panel(@huong_i, @kieu_i, so,
                                @tam_hien || 'ngoài tấm', hang)
      end

      def erase?   ; @huong_i == GO_I end
      def tu_dong? ; @huong_i == TU_DONG_I end
      # Hướng ÉP TAY. nil khi đang tự động hoặc đang gỡ — lúc đó hướng của từng
      # chi tiết lấy từ `Cand#auto`, không phải từ nút.
      def huong
        return nil if erase? || tu_dong?
        TK::ChongBay::HUONG[@huong_i - EP_DAU_I]
      end

      # Đợt kế tiếp = số lớn nhất của HƯỚNG NÀY đang có trong file, + 1.
      # Đọc từ model chứ không nhớ trong tool: đóng tool mở lại, Gỡ rồi quét lại,
      # hay `load` lại file lúc dev — vẫn ra đúng. Trạng thái nhớ trong module đã
      # từng kẹt giá trị cũ và đè lên mặc định mới (bỏ 20/07, xem ChongBay.start).
      def so_ke_tu_model(tam, h)
        return 1 if h.nil?
        lon_nhat = 0
        (@cands || []).each do |c|
          next if c.tam != tam            # chỉ đếm trong CÙNG tấm ván
          hg, so = TK::ChongBay.tach_tag(c.tag)
          next if so.nil? || hg != h
          lon_nhat = so if so > lon_nhat
        end
        # CỐ Ý cho phép vượt trần một bậc (101 khi file đã dùng hết 100): đó là
        # trạng thái "hết dải", để apply_rect chặn thẳng. Kẹp về 100 thì lượt sau
        # gán đè trùng lên đúng số 100 mà không ai thấy.
        lon_nhat + 1
      end

      # Dò lại MỌI bộ đếm từ file — mỗi tấm × mỗi hướng. Gọi lúc mở tool và sau
      # khi Gỡ, hai lúc mà số lớn nhất trong file có thể khác cái tool đang nhớ.
      def do_lai_so_ke
        @so_ke = {}
        cac_tam.each do |t|
          TK::ChongBay::HUONG.each { |h| @so_ke[[t, h]] = so_ke_tu_model(t, h) }
        end
        @tam_hien = cac_tam.first unless cac_tam.include?(@tam_hien)
      end

      # Danh sách tấm ván có chi tiết quét được, sắp theo tên (sheet-1, sheet-2…).
      # nil = nhóm "nằm ngoài mọi tấm", xếp cuối.
      def cac_tam
        ds = (@cands || []).map(&:tam).uniq
        ds.compact.sort + (ds.include?(nil) ? [nil] : [])
      end

      def so_ke_cua(tam, h)
        @so_ke[[tam, h]] ||= so_ke_tu_model(tam, h)
      end

      def activate
        rescan
        do_lai_so_ke
        @drag = false
        @x0 = @y0 = @x1 = @y1 = 0
        TK::ChongBay.show_panel(self)
        bao_bang
        canh_bao_tag_cu
        Sketchup.active_model.active_view.invalidate
      end

      # Nói ngay lúc mở, không đợi tới lúc xuất DXF. Tag kiểu cũ trộn với tag mới
      # là sai thứ tự cắt mà nhìn màn hình không thấy gì — đúng loại lỗi chỉ lộ ra
      # ở máy cắt (bài học 19/07: tách 18 container dùng chung).
      # HOÃN qua timer: bảng vừa mới `show`, bắn execute_script ngay lúc này thì
      # HTML có thể chưa nạp xong và lời nhắc rơi vào chỗ không có ai nghe. Lời
      # nhắc này chỉ bắn MỘT lần nên không có lượt sau vá cho — khác bao_bang.
      # Khuôn hoãn: ha_nen/main.rb:66.
      def canh_bao_tag_cu
        n = (@cands || []).count { |c| TK::ChongBay.tag_cu?(c.tag) }
        return if n.zero?
        UI.start_timer(0.4, false) do
          TK::ChongBay.nhac(
            "File có #{n} chi tiết đeo tag kiểu cũ (chưa đệm 0). Gỡ hết rồi gắn " \
            "lại, để lẫn hai kiểu là Aspire sắp sai thứ tự cắt."
          )
        end
      end

      def deactivate(view)
        TK::ChongBay.dong_panel
        view.invalidate
      end

      def resume(view)
        view.invalidate
      end

      def onCancel(_reason, view)
        finish(view)
      end

      # Tab xoay vòng tag đích — khuôn dim_nhanh/main.rb:197 (key 9 = Tab)
      def onKeyDown(key, _rep, _flags, view)
        if key == 9
          @huong_i = (@huong_i + 1) % SO_O   # Tự động → Trái → Phải → Gỡ → …
          bao_bang
          view.invalidate
          return false
        end
        # Space đổi KIỂU QUÉT. Mã 32 CHƯA có tiền lệ chạy trong repo (repo mới
        # chứng minh 27=Esc, 9=Tab) → nếu máy không ăn phím này thì vẫn đổi được
        # bằng cách gõ "k"/"d"/"z" vào ô Measurements. Hai đường, không phụ thuộc
        # một giả định.
        if key == 32
          doi_kieu(view)
          return false
        end
        finish(view) if key == 27   # Esc
        false
      end

      # Gõ vào ô Measurements (VCB) để NHẢY TỚI một đợt — khuôn tim_tam_loi:157.
      #   "50"  → chi tiết quét tiếp theo mang số 50, rồi 51, 52…
      # Trước đây ô này nhận một KHOẢNG (đợt đầu–đợt cuối); khoảng đã bỏ 23/07 vì
      # nó vừa là dải số vừa là trần chi tiết mỗi lượt — đặt 1-1 là quét 10 cái chỉ
      # nhận 1, cắt 9 cái không nói gì.
      def enableVCB?
        true
      end

      def doi_kieu(view)
        @kieu_i = (@kieu_i + 1) % TK::ChongBay::KIEU.size
        @net = []
        bao_bang
        view.invalidate
      end

      def onUserText(text, view)
        t = text.to_s.strip.downcase
        # đường thoát khi phím Space không ăn: gõ chữ để đổi kiểu quét
        # ('d' = kiểu Đường, đã bỏ 23/07)
        if t =~ /\A[kz]\z/
          @kieu_i = { 'k' => 0, 'z' => 1 }[t]
          @net = []
          bao_bang
          view.invalidate
          return
        end
        so = text.to_s.scan(/\d+/).map(&:to_i)
        return if so.empty?
        n = TK::ChongBay.kep_so(so.first)
        return if n.nil?
        # Gõ số trong khung nhìn đặt cho hướng ĐANG ÉP. Đang ở chế độ tự động thì
        # không biết đặt cho bên nào — bắt gõ vào đúng ô Trái/Phải trên bảng, hơn
        # là đoán rồi sửa ngầm một bên.
        h = huong
        if h.nil?
          TK::ChongBay.nhac('Đang ở chế độ Tự động — gõ số vào ô Trái hoặc Phải trên bảng.')
          return
        end
        @so_ke[[@tam_hien, h]] = n
        bao_bang
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @drag = true
        @x0 = x; @y0 = y; @x1 = x; @y1 = y
        @net = [[x, y]]
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        return unless @drag
        @x1 = x; @y1 = y
        if kieu == :tu_do
          # chỉ ghi thêm điểm khi đi đủ xa — không thì một nét ra hàng nghìn điểm
          cx, cy = @net.last
          b = TK::ChongBay::BUOC_NET
          @net << [x, y] if (x - cx).abs >= b || (y - cy).abs >= b
        else
          @net = [[@x0, @y0], [x, y]]
        end
        view.invalidate
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @drag
        @drag = false
        @x1 = x; @y1 = y
        begin
          apply_rect(view)
        rescue => e
          # Surface lỗi thay vì để SketchUp ném backtrace cụt ra Console
          # (LUAT_NHA mục 4: thao tác sửa model luôn phải báo ra).
          msg = "Lỗi khi quét: #{e.class}: #{e.message}"
          puts msg
          puts e.backtrace.first(5).join("\n") if e.backtrace
          UI.messagebox("#{msg}\n\n#{(e.backtrace || []).first(3).join("\n")}")
        end
        view.invalidate
      end

      # Đa giác của chi tiết ở toạ độ màn hình: lấy điểm đầu mỗi cạnh rồi xếp
      # theo góc quanh tâm. Chi tiết nesting gần như đều là hình chữ nhật nên
      # cách này ra đúng hình; chi tiết khuyết góc thì nền hơi "đầy" hơn thật —
      # chỉ ảnh hưởng cái nhìn, không ảnh hưởng việc gán tag.
      #
      # 23/07 — chỗ "hơi đầy hơn thật" hoá ra nặng hơn tưởng: xem `loi?`.
      def da_giac(view, segs)
        pts = segs.map { |a, _b| view.screen_coords(a) }
        return [] if pts.size < 3
        n  = pts.size.to_f
        cx = pts.inject(0.0) { |s, p| s + p.x } / n
        cy = pts.inject(0.0) { |s, p| s + p.y } / n
        pts.sort_by { |p| Math.atan2(p.y - cy, p.x - cx) }
           .map { |p| Geom::Point3d.new(p.x, p.y, 0) }
      end

      # GL_POLYGON chỉ tô đúng đa giác LỒI. Chi tiết CONG/LÕM (lưỡi liềm, cung
      # tròn) sắp điểm theo góc quanh tâm thì ra hình sao, OpenGL tô thành nan
      # quạt xoè TRÀN RA NGOÀI chi tiết — Khoa bắt được qua ảnh chạy thật 23/07
      # ("loè hết màu ra"). Lỗi này đã có từ 20/07, chỉ không ai nhìn ra vì file
      # thử trước đó toàn chi tiết chữ nhật.
      #
      # Không tô nền cho loại lõm. Viền vẽ theo CẠNH THẬT nên luôn đúng, cộng
      # huy hiệu số là đủ nhận ra — thà thiếu nền còn hơn bôi màu ra chỗ không
      # có chi tiết, vì cái loè đó trông y như một chi tiết đã gắn.
      #
      # Ngưỡng 0.5 (px²) để bỏ qua ba điểm gần thẳng hàng: chi tiết cong được
      # xấp xỉ bằng cả trăm đoạn ngắn, không lọc thì nhiễu làm dấu đảo lung tung.
      def loi?(poly)
        n = poly.size
        return false if n < 3
        dau = 0
        n.times do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          c = poly[(i + 2) % n]
          z = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
          next if z.abs < 0.5
          d = z > 0 ? 1 : -1
          return false if dau != 0 && d != dau
          dau = d
        end
        true
      end

      def draw(view)
        # 1. TÔ NỀN chi tiết đã gắn. Đợt sau màu nhạt, chỉ tô viền thì nhìn không
        #    ra (Khoa 20/07) → tô cả mảng. GL_POLYGON không gộp nhiều hình vào
        #    một lệnh được nên phải vẽ từng cái.
        @cands.each do |c|
          next if c.tag.nil?
          next if (c.group.deleted? rescue true)
          poly = da_giac(view, c.segs)
          next if poly.size < 3
          next unless loi?(poly)      # lõm thì bỏ nền, xem loi?
          m = TK::ChongBay.color_for(c.tag)
          view.drawing_color =
            Sketchup::Color.new(m.red, m.green, m.blue, TK::ChongBay::FILL_ALPHA)
          view.draw2d(GL_POLYGON, poly)
        end

        # 2. VIỀN — gộp theo màu nên 50 chi tiết vẫn chỉ vài lệnh vẽ.
        by_tag = Hash.new { |h, k| h[k] = [] }
        @cands.each do |c|
          next if (c.group.deleted? rescue true)
          pts = by_tag[c.tag]
          c.segs.each do |a, b|
            pts << view.screen_coords(a) << view.screen_coords(b)
          end
        end
        todo = by_tag.delete(nil)
        if todo && !todo.empty?
          view.drawing_color = COL_TODO
          view.line_width    = 1
          view.draw2d(GL_LINES, todo)
        end
        by_tag.each do |tag, pts|
          next if pts.empty?
          view.drawing_color = TK::ChongBay.color_for(tag)
          view.line_width    = 2
          view.draw2d(GL_LINES, pts)
        end

        # 3. HUY HIỆU SỐ ĐỢT. Chỉ vẽ cái gắn TRONG PHIÊN NÀY (Khoa 23/07) — file
        #    đã gắn sẵn cả trăm cái mà vẽ hết thì màn hình đặc chữ, không đọc
        #    được cái mình vừa làm. Đây là chỗ ĐỌC THỨ TỰ; nền màu chỉ còn nói
        #    "đã gắn, hướng nào".
        ve_so(view)

        draw_band(view) if @drag
      end

      private

      COL_DONE = TK::ChongBay::COL_DONE
      COL_TODO = TK::ChongBay::COL_TODO
      COL_BAND = TK::ChongBay::COL_BAND
      COL_CHU_SO = TK::ChongBay::COL_CHU_SO
      COL_VANH   = TK::ChongBay::COL_VANH

      # Đĩa tròn ở toạ độ màn hình. GL_LINE_LOOP có tiền lệ trong repo (3 chỗ).
      def dia_tron(cx, cy, r)
        (0...TK::ChongBay::CANH_TRON).map do |i|
          g = 2 * Math::PI * i / TK::ChongBay::CANH_TRON
          Geom::Point3d.new(cx + r * Math.cos(g), cy + r * Math.sin(g), 0)
        end
      end

      # Vẽ HUY HIỆU SỐ ĐỢT lên giữa chi tiết — chỉ những tag gắn trong phiên này.
      # Đĩa đặc màu hướng + vành trắng + số trắng: đọc được trên mọi nền, và
      # không lẫn với nhãn ABF (chữ đen trần trong khung mũi tên).
      # Bỏ qua chi tiết quá bé trên màn hình: zoom xa thì huy hiệu chồng nhau
      # thành vệt, thà không vẽ còn hơn vẽ ra thứ không đọc được.
      # Khuôn draw_text (keyword options, SketchUp 2016+): dim_nhanh/main.rb:485.
      def ve_so(view)
        return if @tag_phien.nil? || @tag_phien.empty?
        @cands.each do |c|
          next if c.tag.nil? || !@tag_phien[c.tag]
          next if (c.group.deleted? rescue true)
          _h, so = TK::ChongBay.tach_tag(c.tag)
          next if so.nil?
          pts = c.segs.map { |a, _b| view.screen_coords(a) }
          next if pts.empty?
          xs = pts.map { |p| p.x }
          ys = pts.map { |p| p.y }
          # Ẩn theo chiều DÀI, không theo chiều ngắn (sửa 23/07 — Khoa: "phải zoom
          # lên mới thấy số"). Chi tiết nesting phần lớn là thanh dài mà mỏng:
          # dài 150px, cao 20px. Bắt cả hai chiều phải đủ rộng là ẩn mất đúng
          # loại phổ biến nhất, dù thừa chỗ đặt huy hiệu theo chiều dài.
          # Huy hiệu tràn nhẹ ra khỏi thanh mỏng thì vẫn đọc được và vẫn thấy rõ
          # nó thuộc thanh nào — mất hẳn số mới là cái không chữa được bằng mắt.
          dai = [xs.max - xs.min, ys.max - ys.min].max
          next if dai < 20
          s  = so.to_s
          cx = (xs.min + xs.max) / 2.0
          cy = (ys.min + ys.max) / 2.0
          # Chi tiết ngắn → huy hiệu nhỏ lại cho đỡ che nhau; số 3 chữ số cần đĩa
          # rộng hơn, nếu không chữ chạm mép.
          bk  = dai < 34 ? 8.0 : TK::ChongBay::BK_HUY_HIEU
          bk += 3.0 if s.length >= 3
          co  = bk >= 11.0 ? TK::ChongBay::CO_CHU_SO : 10
          vong = dia_tron(cx, cy, bk)

          view.drawing_color = TK::ChongBay.color_for(c.tag)
          view.draw2d(GL_POLYGON, vong)
          view.drawing_color = COL_VANH
          view.line_width    = 2
          view.draw2d(GL_LINE_LOOP, vong)
          opt = { color: COL_CHU_SO, font: 'Arial', size: co, bold: true }
          view.draw_text(neo_chu(view, cx, cy, s, opt), s, opt)
        end
      end

      # Điểm neo để chữ nằm ĐÚNG TÂM đĩa. `draw_text` neo vào góc trên-trái của
      # chữ, nên phải tự lùi lại nửa bề rộng/bề cao — mà "nửa bề rộng" đoán bằng
      # số ký tự thì sai (Khoa 23/07: số lệch tâm vòng tròn). `view.text_bounds`
      # đo hộp chữ thật nên căn đúng cho mọi cỡ chữ và mọi độ dài số.
      #
      # API này CHƯA có tiền lệ chạy trong repo → thử một lần, hỏng thì lùi về
      # ước lượng tay và **nhớ là đã hỏng**. Không nhớ thì mỗi khung hình lại ném
      # một dòng lỗi ra Ruby Console, vẽ 20 huy hiệu là 20 dòng mỗi lần rê chuột.
      def neo_chu(view, cx, cy, s, opt)
        unless @do_chu == false
          begin
            b = view.text_bounds(Geom::Point3d.new(cx, cy, 0), s, opt)
            @do_chu = true
            return Geom::Point3d.new(cx - b.width / 2.0, cy - b.height / 2.0, 0)
          rescue => e
            if @do_chu.nil?
              @do_chu = false
              puts "[Chống Bay] text_bounds không dùng được, căn chữ bằng ước lượng: #{e.message}"
            end
          end
        end
        Geom::Point3d.new(cx - s.length * 3.8, cy - 9, 0)
      end

      def rescan
        # make_unique thay entity cũ bằng entity mới → danh sách cũ thành rác,
        # phải quét lại từ đầu sau mỗi lần đổi.
        @cands = TK::ChongBay.collect_cands
        bao_bang
      end

      # Thoát tool. Có gắn được gì trong phiên thì mở bảng tổng kết; không gắn gì
      # thì im lặng, đừng bắt bấm thêm một hộp thoại vô nghĩa.
      # Khuôn: dim_nhanh/main.rb:301 (ESC → bảng kê).
      #
      # Bảng chỉ báo TRẠNG THÁI HIỆN TẠI của file, không báo "phiên này gắn bao
      # nhiêu". Cột đó từng có và đã bỏ (19/07): vừa sai — cộng dồn nên quét đi
      # quét lại thì đội số lên quá cả số chi tiết có thật — vừa không ai cần.
      def finish(view)
        view.model.select_tool(nil)
        return unless @co_doi

        trong_file = Hash.new(0)
        con_lai    = 0
        @cands.each { |c| c.tag ? trong_file[c.tag] += 1 : con_lai += 1 }
        TK::ChongBay.show_summary(trong_file, con_lai)
      end

      # ---- va chạm: khung quét vs CẠNH THẬT của chi tiết ----

      def in_rect?(p, r)
        p.x >= r[0] && p.x <= r[2] && p.y >= r[1] && p.y <= r[3]
      end

      def ccw(ax, ay, bx, by, cx, cy)
        (cy - ay) * (bx - ax) > (by - ay) * (cx - ax)
      end

      def seg_cross?(p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y)
        ccw(p1x, p1y, p3x, p3y, p4x, p4y) != ccw(p2x, p2y, p3x, p3y, p4x, p4y) &&
          ccw(p1x, p1y, p2x, p2y, p3x, p3y) != ccw(p1x, p1y, p2x, p2y, p4x, p4y)
      end

      def touches?(view, segs, r)
        x0, y0, x1, y1 = r
        edges = [[x0, y0, x1, y0], [x1, y0, x1, y1],
                 [x1, y1, x0, y1], [x0, y1, x0, y0]]
        segs.each do |a, b|
          pa = view.screen_coords(a)
          pb = view.screen_coords(b)
          return true if in_rect?(pa, r) || in_rect?(pb, r)
          edges.each do |e|
            return true if seg_cross?(pa.x, pa.y, pb.x, pb.y, e[0], e[1], e[2], e[3])
          end
        end
        false
      end

      # Nét cắt qua chi tiết ở đoạn thứ mấy? Trả về chỉ số đoạn ĐẦU TIÊN chạm,
      # nil nếu không chạm. Chỉ số này chính là thứ tự đánh số: vẽ nét đi qua
      # chi tiết nào trước thì nó vào đợt cắt sớm hơn.
      def net_cham(view, segs, net)
        return nil if net.size < 2
        canh = segs.map { |a, b| [view.screen_coords(a), view.screen_coords(b)] }
        net.each_cons(2).with_index do |(p1, p2), i|
          canh.each do |pa, pb|
            if seg_cross?(pa.x, pa.y, pb.x, pb.y, p1[0], p1[1], p2[0], p2[1])
              return i
            end
          end
        end
        nil
      end

      # Khoảng cách từ điểm bắt đầu kéo tới chi tiết (đo trên màn hình, lấy đỉnh
      # gần nhất) — dùng để xếp thứ tự đánh số trong một nhát quét.
      def xa_diem_dau(view, segs)
        gan = nil
        segs.each do |a, _b|
          p  = view.screen_coords(a)
          dx = p.x - @x0
          dy = p.y - @y0
          d  = dx * dx + dy * dy
          gan = d if gan.nil? || d < gan
        end
        gan || 0
      end

      # Trả về danh sách chi tiết trúng, ĐÃ SẮP theo thứ tự đánh số.
      #   :khung  → sắp theo khoảng cách tới điểm bắt đầu kéo
      #   :tu_do  → sắp theo thứ tự nét đi qua (chuẩn xác hơn hẳn)
      def tim_trung(view)
        song = @cands.reject { |c| c.group.deleted? rescue true }
        if kieu == :khung
          rect = [[@x0, @x1].min, [@y0, @y1].min, [@x0, @x1].max, [@y0, @y1].max]
          return [] if (rect[2] - rect[0]).abs < 4 && (rect[3] - rect[1]).abs < 4
          song.select { |c| touches?(view, c.segs, rect) }
              .sort_by { |c| xa_diem_dau(view, c.segs) }
        else
          return [] if @net.size < 2
          cham = []
          song.each do |c|
            i = net_cham(view, c.segs, @net)
            cham << [i, c] if i
          end
          cham.sort_by { |i, _c| i }.map { |_i, c| c }
        end
      end

      def apply_rect(view)
        trung = tim_trung(view)
        return if trung.empty?

        if erase?
          # GỠ: chỉ đụng cái đang đeo tag chống bay, trả về tag GỐC đã ghi nhớ.
          hits = trung.reject { |c| c.tag.nil? }
          return if hits.empty?
          cap  = hits.map { |c| [c.group, nil] }   # layer đích đọc từ ghi chú
          mode = :go
        else
          # KHÔNG DÁN ĐÈ. Chi tiết đã đeo tag chống bay thì bỏ qua — muốn đổi
          # phải Gỡ trước. Trước đây quét chồng là đè im lặng: đang từ TRÁI
          # chuyển sang PHẢI, quét trùm một cái là mất trình tự đã xếp mà không
          # hiện dấu hiệu gì. (Khoa 20/07.)
          hits   = trung.select { |c| c.tag.nil? }
          bo_qua = trung.size - hits.size
          if hits.empty?
            TK::ChongBay.nhac(
              "#{bo_qua} chi tiết đã gắn rồi — bấm Gỡ rồi quét lại nếu muốn đổi."
            )
            return
          end
          # Hướng của TỪNG chi tiết: ép tay thì cả lượt theo nút, tự động thì mỗi
          # cái đọc vị trí của nó trên tấm ván (Cand#auto, tính lúc quét).
          ep = huong
          lac = 0
          if ep.nil?
            truoc = hits.size
            hits  = hits.select { |c| !c.auto.nil? }
            lac   = truoc - hits.size    # không nằm trong tấm nào → không đoán bừa
          end
          if hits.empty?
            TK::ChongBay.nhac(
              "#{lac} chi tiết không nằm trong tấm ván nào — bấm Trái hoặc Phải " \
              "để ép tay."
            )
            return
          end

          # KHÔNG còn trần chi tiết mỗi lượt (bỏ 23/07). Trần duy nhất còn lại là
          # trần SỐ, và giờ đếm RIÊNG cho mỗi bên: nét vơ 30 cái trái + 20 cái
          # phải thì hai dãy số chạy độc lập, không bên nào ăn dải của bên kia.
          model   = Sketchup.active_model
          ten_moi = []
          cap     = []
          het     = 0
          luu     = @so_ke.dup   # gán hỏng thì trả lại, đừng để thủng dải số
          hits.each do |c|
            h  = ep || c.auto
            so = so_ke_cua(c.tam, h)          # số riêng của TẤM chứa chi tiết này
            if so > TK::ChongBay::SO_TOI_DA
              het += 1
              next
            end
            lay = TK::ChongBay.tag_theo_so(model, h, so)
            @so_ke[[c.tam, h]] = so + 1
            ten_moi << lay.name.to_s
            cap << [c.group, lay]
          end
          # Bảng nói về tấm vừa quét — quét sang tấm khác là hai ô số đổi theo.
          @tam_hien = hits.first.tam

          loi = []
          loi << "Bỏ qua #{bo_qua} chi tiết đã gắn (muốn đổi thì Gỡ trước)." if bo_qua > 0
          loi << "#{lac} chi tiết không nằm trong tấm ván nào — ép tay bằng nút " \
                 "Trái/Phải." if lac > 0
          loi << "Hết dải #{TK::ChongBay::SO_TOI_DA} đợt cho #{het} chi tiết — gỡ " \
                 "bớt hoặc gõ số nhỏ hơn vào ô Đợt kế tiếp." if het > 0
          TK::ChongBay.nhac(loi.join(' '))
          return if cap.empty?
          mode = :gan
        end

        stats = TK::ChongBay.retag_many(cap, mode)
        # Số đã nhích sẵn trong vòng lặp trên (phải nhích ngay để hai bên không
        # giẫm số nhau). Gán hỏng thì TRẢ LẠI — nhích mà không gắn được là để
        # thủng một khoảng số trống không ai giải thích được.
        if mode == :gan
          if stats
            ten_moi.each { |t| @tag_phien[t] = true }
          else
            @so_ke = luu
          end
        end
        @co_doi = true if stats && stats[:groups] > 0
        if stats && stats[:unique_fail] > 0
          UI.messagebox(
            "Cảnh báo: #{stats[:unique_fail]} nhóm không tách riêng được.\n\n" \
            "Những chi tiết này có thể dùng chung với tấm khác — kiểm lại các tấm " \
            "còn lại xem có bị đổi lây không."
          )
        end
        rescan
        # Gỡ xong thì số lớn nhất trong file tụt xuống → dò lại, nếu không thì
        # quét tiếp sẽ nhảy qua đúng những số vừa gỡ và để lỗ.
        do_lai_so_ke if mode == :go
        bao_bang
      end

      # ---- Bảng nhắc góc trên-trái (khuôn tim_tam_loi/main.rb:266) ----

      def draw_band(view)
        view.drawing_color = COL_BAND
        view.line_width    = 2
        if kieu == :khung
          r = [[@x0, @x1].min, [@y0, @y1].min, [@x0, @x1].max, [@y0, @y1].max]
          pts = [[r[0], r[1]], [r[2], r[1]], [r[2], r[1]], [r[2], r[3]],
                 [r[2], r[3]], [r[0], r[3]], [r[0], r[3]], [r[0], r[1]]]
                .map { |a, b| Geom::Point3d.new(a, b, 0) }
          view.draw2d(GL_LINES, pts)
        else
          return if @net.size < 2
          pts = []
          @net.each_cons(2) do |p1, p2|
            pts << Geom::Point3d.new(p1[0], p1[1], 0)
            pts << Geom::Point3d.new(p2[0], p2[1], 0)
          end
          view.draw2d(GL_LINES, pts)
        end
      end
    end

    # ── Cổng vào ─────────────────────────────────────────────────

    # Kẹp một số đợt về [1, SO_TOI_DA]. Trả nil nếu gõ vào thứ vô nghĩa.
    def self.kep_so(n)
      n = n.to_i
      return nil if n < 1
      n > SO_TOI_DA ? SO_TOI_DA : n
    end

    # KHÔNG hỏi gì lúc mở — vào thẳng bộ quét. Tag đánh số tạo LƯỜI khi quét tới,
    # không nhồi sẵn tag vào file.
    #
    # Từng có cơ chế "nhớ khoảng của lần dùng trước" (@khoang) — ĐÃ BỎ 20/07.
    # Nó bám vào module nên `load` không xoá, giá trị cũ 1-40 kẹt lại đè lên mặc
    # định mới và Khoa thấy sai ngay. Trạng thái ẩn sống dai hơn code sinh ra nó.
    # Nay "đợt kế tiếp" cũng không nhớ trong module — nó ĐỌC TỪ FILE mỗi lần mở
    # (SweepTool#so_ke_tu_model), nên không có gì kẹt lại được.
    def self.start
      Sketchup.active_model.select_tool(SweepTool.new)
    end

    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Chống Bay') { TK::ChongBay.start }
      cmd.tooltip         = 'Chống Bay — quét đổi chi tiết sang tag chống bay'
      cmd.status_bar_text = 'Kéo chuột quét qua chi tiết nhỏ để đổi sang tag chống bay. ESC thoát.'
      cmd.small_icon      = File.join(icons, 'chong_bay_16.png')
      cmd.large_icon      = File.join(icons, 'chong_bay_24.png')
      cmd
    end
  end
end
