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

    # Màu GỐC của từng hướng — số 1 đậm nhất, số càng lớn càng nhạt dần.
    # Nhìn cả tấm là đọc được trình tự cắt, khỏi bấm từng tag.
    MAU_GOC = {
      'CHONGBAYTRAI' => Sketchup::Color.new(0, 150, 60),     # xanh lá đậm
      'CHONGBAYPHAI' => Sketchup::Color.new(210, 90, 0)      # cam đậm
    }.freeze

    SO_DAU_MD  = 1
    SO_CUOI_MD = 9      # mặc định
    # TRẦN CỨNG **9** — Khoa chốt 20/07 (đổi từ 12 xuống).
    # Hai lý do, lý do sau mới là lý do thật:
    #   1. Mỗi số là một tag VÀ một đường dao phải dựng tay bên Aspire — gõ nhầm
    #      40 là đẻ ra 40 đường dao, dọn rất mệt.
    #   2. MỘT CHỮ SỐ thì sắp CHUỖI trùng sắp SỐ. Aspire sắp tên layer bằng chuỗi
    #      và không phải code mình để vá: hễ có số 2 chữ số là "TRAI10" chen lên
    #      trước "TRAI2", sai thứ tự cắt. Trần 9 làm lỗi đó không tồn tại được.
    # Đổi trần lên >9 thì BẮT BUỘC đệm 0 trong ten_tag, nếu không là tái phát.
    SO_TOI_DA  = 9
    NHAT_NHAT  = 0.72   # số cuối nhạt tới đâu (0 = giữ nguyên, 1 = trắng hẳn)

    # ── Kiểu quét ────────────────────────────────────────────────
    # :khung = kéo hình chữ nhật, trúng cả cụm (nhanh, thứ tự theo hướng kéo)
    # :duong = kéo một đường thẳng, đánh số theo thứ tự đường cắt qua
    # :tu_do = vẽ tay tự do, đánh số theo đúng thứ tự nét đi qua
    #          (trước gọi "zigzag" — Khoa 20/07: nét là do mình vẽ chứ không phải
    #           hình zigzag đều, gọi "vẽ tự do" đúng hơn)
    KIEU     = [:khung, :duong, :tu_do].freeze
    BUOC_NET = 4        # nét tự do chỉ ghi thêm điểm khi chuột đi quá 4px

    # Tô NỀN chi tiết thay vì chỉ tô viền: đợt sau màu nhạt, viền mảnh nhìn không
    # ra (Khoa 20/07). Khuôn alpha: tim_tam_loi/main.rb:211.
    FILL_ALPHA = 120

    MAX_DEPTH = 12

    COL_DONE  = Sketchup::Color.new(0, 190, 80)      # xanh lá = đã đổi
    COL_TODO  = Sketchup::Color.new(150, 150, 150)   # xám    = chưa đổi
    COL_BAND  = Sketchup::Color.new(255, 20, 200)    # hồng   = khung đang quét

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
    # ABF (đo thật 19/07: model có 8 tag, hộp thoại ABF liệt kê 31 layer). ABF chỉ
    # đẻ tag SketchUp thật khi có hình được gán vào. Nên tag tạo ở đây phải đặt
    # ĐÚNG tên đã khai bên ABF thì hai bên mới khớp — lệch tên là ABF không nhận
    # mà chẳng báo lỗi gì.
    # Tách tên tag thành [hướng, số]. Tag cũ chưa đánh số → số nil.
    def self.tach_tag(ten)
      m = ten.to_s.match(/\A(CHONGBAY(?:TRAI|PHAI))(\d*)\z/i)
      return [nil, nil] unless m
      [m[1].upcase, (m[2].empty? ? nil : m[2].to_i)]
    end

    # KHÔNG đệm 0: tên giữ nguyên "CHONGBAYTRAI1"… "CHONGBAYTRAI9" như đã khai
    # bên ABF. Đệm 0 chỉ cần khi trần >9 (xem SO_TOI_DA) — với trần 9 thì thừa,
    # mà đổi tên là phải khai lại toàn bộ bên ABF, lệch một ký tự là ABF im lặng
    # không nhận.
    def self.ten_tag(huong, so)
      format('%s%d', huong, so.to_i)
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

    # Màu overlay: số 1 đậm nhất, số càng lớn càng pha trắng nhiều.
    # so_cuoi truyền vào để dải màu co giãn theo khoảng Khoa đang đặt.
    def self.color_for(tag_name, so_dau = SO_DAU_MD, so_cuoi = SO_CUOI_MD)
      return COL_TODO if tag_name.nil? || tag_name == SRC_TAG
      huong, so = tach_tag(tag_name)
      goc = MAU_GOC[huong]
      return COL_TODO if goc.nil?
      return goc if so.nil?     # tag cũ chưa đánh số → màu gốc

      span = (so_cuoi - so_dau).to_f
      t    = span <= 0 ? 0.0 : ((so - so_dau) / span)
      t    = 0.0 if t < 0.0
      t    = 1.0 if t > 1.0
      pha  = t * NHAT_NHAT      # pha về phía trắng
      Sketchup::Color.new(
        (goc.red   + (255 - goc.red)   * pha).round,
        (goc.green + (255 - goc.green) * pha).round,
        (goc.blue  + (255 - goc.blue)  * pha).round
      )
    end

    # Tìm hoặc TẠO tag theo hướng+số, và sơn màu cho nó luôn để bảng Tags của
    # SketchUp cũng hiện đúng dải màu. Tạo LƯỜI — chỉ đẻ tag khi thật sự dùng
    # tới, không nhồi sẵn 80 tag vào mọi file.
    def self.tag_theo_so(model, huong, so, so_dau, so_cuoi)
      ten = ten_tag(huong, so)
      lay = find_tag(model, ten) || model.layers.add(ten)
      # Layer#color= CHƯA có tiền lệ chạy trong repo → bọc respond_to? + rescue.
      # Hỏng thì chỉ mất màu trong bảng Tags, overlay của tool vẫn đúng.
      begin
        lay.color = color_for(ten, so_dau, so_cuoi) if lay.respond_to?(:color=)
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
      @panel.add_action_callback('dat_khoang') do |_c, a, b|
        @tool.dat_khoang(a.to_i, b.to_i) if @tool
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
    def self.sync_panel(huong_i, kieu_i, so_dau, so_cuoi, dem)
      return unless @panel && (@panel.visible? rescue false)
      hang = dem.map do |ten, n|
        mau = hex(color_for(ten, so_dau, so_cuoi))
        "[\"#{esc_html(ten || 'chưa gắn')}\",#{n},\"#{mau}\"]"
      end.join(',')
      @panel.execute_script(
        "capNhat(#{huong_i},#{kieu_i},#{so_dau},#{so_cuoi},[#{hang}])"
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
              <button class="lh-chip is-active" id="h0" onclick="pick(0)">Trái</button>
              <button class="lh-chip" id="h1" onclick="pick(1)">Phải</button>
              <button class="lh-chip" id="h2" onclick="pick(2)">Gỡ</button>
            </div>
          </div>

          <div class="lh-field">
            <label class="lh-label">Kiểu quét</label>
            <div class="lh-chips">
              <button class="lh-chip is-active" id="k0" onclick="pickK(0)">Khung</button>
              <button class="lh-chip" id="k1" onclick="pickK(1)">Đường</button>
              <button class="lh-chip" id="k2" onclick="pickK(2)">Vẽ tự do</button>
            </div>
          </div>

          <div class="lh-row lh-field">
            <div>
              <label class="lh-label">Đợt đầu</label>
              <input class="lh-input" id="a" type="number" min="1" max="#{SO_TOI_DA}"
                     value="#{SO_DAU_MD}" onchange="gui()">
            </div>
            <div>
              <label class="lh-label">Đợt cuối</label>
              <input class="lh-input" id="b" type="number" min="1" max="#{SO_TOI_DA}"
                     value="#{SO_CUOI_MD}" onchange="gui()">
            </div>
          </div>
          <div class="lh-hint">
            Số là ĐỢT CẮT. Mỗi lượt kéo đánh lại từ đợt đầu, và chỉ nhận tối đa
            bấy nhiêu chi tiết — dư thì kéo lượt nữa. Bên Aspire mỗi số là một
            đường dao, nên trần là #{SO_TOI_DA} đợt.
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
          function gui(){
            var a = parseInt(document.getElementById("a").value, 10);
            var b = parseInt(document.getElementById("b").value, 10);
            if (!a || !b) { return; }
            sketchup.dat_khoang(a, b);
          }
          function nhac(s){
            var e = document.getElementById("nhac");
            e.innerHTML = s;
            e.style.display = s ? "block" : "none";
          }
          function capNhat(h, k, a, b, dem){
            for (var i = 0; i < 3; i++){
              document.getElementById("h" + i).className =
                (i === h) ? "lh-chip is-active" : "lh-chip";
              document.getElementById("k" + i).className =
                (i === k) ? "lh-chip is-active" : "lh-chip";
            }
            document.getElementById("a").value = a;
            document.getElementById("b").value = b;
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
            Nhớ khai đúng tên tag bên ABF (mục Layer) thì khâu xuất DXF mới nhận —
            hai bên là hai danh sách riêng, chỉ dính nhau qua tên.
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

    def self.traverse(entities, accum_t, depth = 0, &blk)
      return if depth > MAX_DEPTH
      entities.each do |e|
        next unless container?(e)
        blk.call(e, accum_t)
        traverse(kids_of(e), accum_t * e.transformation, depth + 1, &blk)
      end
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
    Cand = Struct.new(:group, :segs, :tag)

    def self.collect_cands
      out = []
      traverse(Sketchup.active_model.entities, Geom::Transformation.new) do |e, t|
        n = tag_name(e)
        if src?(e)
          out << Cand.new(e, world_segments(e, t), nil)
        elsif n =~ DST_RE
          out << Cand.new(e, world_segments(e, t), n)
        end
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
      def initialize(so_dau = TK::ChongBay::SO_DAU_MD, so_cuoi = TK::ChongBay::SO_CUOI_MD)
        @huong_i = 0        # 0..HUONG.size-1 = hướng; == HUONG.size = chế độ GỠ
        @so_dau  = so_dau
        @so_cuoi = so_cuoi
        @kieu_i  = 0        # chỉ số trong KIEU
        @net     = []       # nét đang vẽ (toạ độ MÀN HÌNH)
        @co_doi  = false    # phiên này có đổi được gì không (quyết định hiện bảng)
      end

      def kieu ; TK::ChongBay::KIEU[@kieu_i] end

      # ---- bảng điều khiển gọi vào (HtmlDialog → Tool) ----
      # Chỉ đổi trạng thái + vẽ lại; KHÔNG sửa model trong callback của dialog.

      def dat_huong(i)
        return unless i >= 0 && i <= TK::ChongBay::HUONG.size
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

      def dat_khoang(a, b)
        a, b = TK::ChongBay.kep_khoang(a, b)
        return if a.nil?
        @so_dau, @so_cuoi = a, b
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
        TK::ChongBay.sync_panel(@huong_i, @kieu_i, @so_dau, @so_cuoi, hang)
      end

      def erase?   ; @huong_i == TK::ChongBay::HUONG.size end
      def huong    ; erase? ? nil : TK::ChongBay::HUONG[@huong_i] end
      # Tên hiển thị: chỉ có HƯỚNG, vì số không cố định — mỗi lượt quét đánh lại
      # từ đầu khoảng.
      def dst_name ; erase? ? TK::ChongBay::SRC_TAG : huong end

      def chu_ky ; @so_cuoi - @so_dau + 1 end

      def activate
        rescan
        @drag = false
        @x0 = @y0 = @x1 = @y1 = 0
        TK::ChongBay.show_panel(self)
        bao_bang
        Sketchup.active_model.active_view.invalidate
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
          @huong_i = (@huong_i + 1) % (TK::ChongBay::HUONG.size + 1)  # +1 = ô GỠ
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

      # Gõ vào ô Measurements (VCB) để đặt KHOẢNG đợt cắt — khuôn tim_tam_loi:157.
      #   "9"     → khoảng 1-9   (gõ mỗi số cuối cho nhanh)
      #   "1-9"   → khoảng 1-9
      # Khoảng này vừa là số đợt cắt, vừa là dải màu đậm→nhạt.
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
        if t =~ /\A[kdz]\z/
          @kieu_i = { 'k' => 0, 'd' => 1, 'z' => 2 }[t]
          @net = []
          view.invalidate
          return
        end
        so = text.to_s.scan(/\d+/).map(&:to_i)
        return if so.empty?
        a, b = so.size >= 2 ? [so[0], so[1]] : [1, so[0]]
        a, b = TK::ChongBay.kep_khoang(a, b)
        return if a.nil?
        @so_dau, @so_cuoi = a, b
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
      def da_giac(view, segs)
        pts = segs.map { |a, _b| view.screen_coords(a) }
        return [] if pts.size < 3
        n  = pts.size.to_f
        cx = pts.inject(0.0) { |s, p| s + p.x } / n
        cy = pts.inject(0.0) { |s, p| s + p.y } / n
        pts.sort_by { |p| Math.atan2(p.y - cy, p.x - cx) }
           .map { |p| Geom::Point3d.new(p.x, p.y, 0) }
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
          m = TK::ChongBay.color_for(c.tag, @so_dau, @so_cuoi)
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
          view.drawing_color = TK::ChongBay.color_for(tag, @so_dau, @so_cuoi)
          view.line_width    = 2
          view.draw2d(GL_LINES, pts)
        end

        draw_band(view) if @drag
      end

      private

      COL_DONE = TK::ChongBay::COL_DONE
      COL_TODO = TK::ChongBay::COL_TODO
      COL_BAND = TK::ChongBay::COL_BAND

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
      #   :duong / :tu_do  → sắp theo thứ tự nét đi qua (chuẩn xác hơn hẳn)
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
          # MỘT LƯỢT KÉO = TỐI ĐA `chu_ky` CHI TIẾT. Quá thì CẮT BỚT phần dư,
          # KHÔNG quay vòng. Quay vòng thì số 1 xuất hiện hai lần trong cùng một
          # lượt: hai chi tiết khác nhau cùng màu, cùng đợt, nhìn không ra là cố ý
          # hay lỗi (Khoa 20/07 — "trùng lặp lại phiền chết mọe").
          # Số VẪN lặp giữa các LƯỢT khác nhau — đó mới là ý nghĩa "đợt cắt".
          du   = hits.size - chu_ky
          hits = hits.first(chu_ky) if du > 0

          loi = []
          loi << "Bỏ qua #{bo_qua} chi tiết đã gắn (muốn đổi thì Gỡ trước)." if bo_qua > 0
          loi << "Chỉ nhận #{chu_ky} chi tiết mỗi lượt kéo — bỏ #{du} cái cuối, " \
                 "kéo lượt nữa cho chúng." if du > 0
          TK::ChongBay.nhac(loi.join(' '))

          # Số là ĐỢT CẮT, không phải mã định danh. Bên Aspire layer 1 là một đường
          # dao chạy hết mọi chi tiết mang số 1, rồi mới tới layer 2.
          # (Bản đánh số độc nhất tăng mãi đã sai: quét 20 chi tiết ra 20 đường dao,
          # cái ngoài rìa lại bị cắt cuối cùng. Khoa sửa 20/07.)
          model = Sketchup.active_model
          cap   = hits.each_with_index.map do |c, i|
            so  = @so_dau + i
            lay = TK::ChongBay.tag_theo_so(model, huong, so, @so_dau, @so_cuoi)
            [c.group, lay]
          end
          mode = :gan
        end

        stats = TK::ChongBay.retag_many(cap, mode)
        @co_doi = true if stats && stats[:groups] > 0
        if stats && stats[:unique_fail] > 0
          UI.messagebox(
            "Cảnh báo: #{stats[:unique_fail]} nhóm không tách riêng được.\n\n" \
            "Những chi tiết này có thể dùng chung với tấm khác — kiểm lại các tấm " \
            "còn lại xem có bị đổi lây không."
          )
        end
        rescan
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

    # Kẹp khoảng về [1, SO_TOI_DA]. Trả [a, b] hợp lệ, hoặc [nil, nil] nếu vô nghĩa.
    def self.kep_khoang(a, b)
      a = a.to_i
      b = b.to_i
      a, b = b, a if a > b
      a = 1 if a < 1
      b = SO_TOI_DA if b > SO_TOI_DA
      a = b if a > b
      return [nil, nil] if b < 1
      [a, b]
    end

    # KHÔNG hỏi gì lúc mở — vào thẳng bộ quét. Tag đánh số tạo LƯỜI khi quét tới,
    # không nhồi sẵn tag vào file.
    #
    # Từng có cơ chế "nhớ khoảng của lần dùng trước" (@khoang) — ĐÃ BỎ 20/07.
    # Nó bám vào module nên `load` không xoá, giá trị cũ 1-40 kẹt lại đè lên mặc
    # định mới 1-9 và Khoa thấy sai ngay. Trạng thái ẩn sống dai hơn code sinh ra
    # nó. Mở tool giờ LUÔN về mặc định, muốn khác thì gõ — đoán được, không giấu.
    def self.start
      Sketchup.active_model.select_tool(SweepTool.new(SO_DAU_MD, SO_CUOI_MD))
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
