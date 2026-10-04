# encoding: UTF-8
# Kiểm Tra Độ Dày: quét mọi tấm trong file, đo độ dày = chiều mỏng nhất của
# RIÊNG mặt phẳng tấm đó (bỏ qua group con lồng trong như rãnh phay ABF).
# Phân loại: xanh = chuẩn 9/10/17.5/18mm, đỏ = sai. Bấm 1 cột → SOI NỔI từng tấm độ dày đó
# (shared/soi_noi.rb — mờ phần còn lại, tấm đang xem sáng lên; ← → đổi tấm, Esc thoát).
# CHỈ VẼ, không sửa model. Trước 04/10 bấm cột là ẨN hết tấm khác (ghi hidden + thuộc tính TK_ThickCheck
# vào file — quên "Hiện lại" rồi lưu là lưu luôn nửa tủ đang ẩn); file còn dấu đó thì bảng hiện nút
# "Hiện lại" để người dùng tự bấm dọn.
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'
require 'json'
require File.join(File.dirname(__FILE__), '..', 'shared', 'soi_noi')
require File.join(File.dirname(__FILE__), '..', 'shared', 'huong_tu')

module TK
  module ThickCheck

    PATH   = File.dirname(__FILE__).freeze
    THEME  = File.join(PATH, '..', 'shared', 'lehai_theme.css').freeze
    MARK   = 'TK_ThickCheck'.freeze   # dấu "tấm do bản cũ ẩn" — chỉ còn dùng để dọn file cũ
    STD_MM = [9.0, 10.0, 17.5, 18.0].freeze
    TOL    = 0.3
    DEBUG  = false
    MIN_MM = 1.0    # bỏ qua thứ mỏng hơn (mặt dẹt, vạch phay — không phải ván)

    # ── Dialog ─────────────────────────────────────────────────
    def self.show
      if @dlg&.visible?
        @dlg.bring_to_front
        push_scan
        return
      end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Kiểm Tra Độ Dày',
        preferences_key: 'tk.thickcheck',
        width:           440, height: 520,
        min_width:       360, min_height: 380,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      @dlg.set_html(html)
      attach(@dlg)
      @dlg.show
    end

    def self.attach(dlg)
      dlg.add_action_callback('ready')          { push_scan }
      dlg.add_action_callback('isolate')        { |_c, mm| xem { |th| (th - mm.to_f).abs < 0.05 } }
      dlg.add_action_callback('isolate_faulty') { xem_tam_sai }
      dlg.add_action_callback('show_all')       { show_all; push_scan }   # chỉ dọn tấm bản cũ đã ẩn
    end
    private_class_method :attach

    # ── Adapter cho bộ "Check Chốt Sản Xuất" (TK::PreExportCheck) ───
    # audit: chỉ đọc, không mở dialog — trả trạng thái tóm tắt.
    def self.audit
      leaves = collect_leaves
      return { status: :na, count: 0, message: 'Không tìm thấy tấm nào để kiểm tra độ dày.' } if leaves.empty?
      bad = leaves.count { |_e, th| !standard?(round1(th)) }
      return { status: :pass, count: 0, message: "Đã soi #{leaves.size} tấm — tất cả đúng độ dày chuẩn." } if bad.zero?
      { status: :fail, count: bad, message: "#{bad}/#{leaves.size} tấm sai độ dày." }
    end

    # review: mở dialog biểu đồ độ dày (cột đỏ = sai). Bấm được cả khi ĐẠT để
    # xem tổng số tấm + phân bố độ dày mà tin tưởng. Bấm cột → soi nổi từng tấm.
    def self.review
      show
    end

    def self.push_scan
      return unless @dlg&.visible?
      @dlg.execute_script("render(#{scan_data.to_json});")
    end
    private_class_method :push_scan

    # ── Quét + phân loại ───────────────────────────────────────
    def self.scan_data
      leaves = collect_leaves
      bins = Hash.new(0)
      leaves.each { |_e, th| bins[round1(th)] += 1 }
      if DEBUG
        puts "[ThickCheck] Tổng số tấm: #{leaves.size}"
        puts "[ThickCheck] Phân loại: #{bins.sort.to_h.inspect}"
      end
      cols = bins.keys.sort.map { |mm| { 'mm' => mm, 'count' => bins[mm], 'std' => standard?(mm) } }
      { 'cols' => cols, 'an_cu' => leaves.count { |e, _th| e.get_attribute(MARK, 'hid', false) } }
    end
    private_class_method :scan_data

    def self.collect_leaves
      leaves = []
      walk(Sketchup.active_model.entities, 0, leaves, Geom::Transformation.new)
      leaves
    end
    private_class_method :collect_leaves

    # t = transform WORLD tích luỹ của cấp cha (01/10: mang theo để tính scale — xem own_thickness_mm)
    def self.walk(entities, depth, leaves, t)
      return if depth > 40
      entities.to_a.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        ents = ents_of(e)
        next unless ents
        te   = t * e.transformation
        th   = own_thickness_mm(ents, te)
        subs = ents.any? { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
        leaves << [e, th, te] if th && th >= MIN_MM   # te: để soi nổi dựng hộp riêng của tấm
        walk(ents, depth + 1, leaves, te) if subs
      end
    end
    private_class_method :walk

    # Hộp LOCAL các mặt của riêng tấm, mỗi chiều NHÂN hệ số scale world của trục đó (SOAT_LOI A2, soát 01/10):
    # thợ kéo Scale tool thì hình gốc không đổi, chỉ transform đổi → không nhân là đọc ra bề dày BẢN GỐC.
    # Hệ số = độ dài (te * trục) — sketchup-api.md "Lấy hệ số scale", đúng cả khi có xoay. Tấm không scale:
    # hệ số 1 → ra y hệt bản cũ.
    def self.own_thickness_mm(ents, te = Geom::Transformation.new)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return nil if bb.empty?
      k = [X_AXIS, Y_AXIS, Z_AXIS].map { |a| l = (te * a).length.to_f; (l - 1.0).abs < 1e-9 ? 1.0 : l }   # sai số máy khi tấm xoay (0.9999999999999999) ép về đúng 1 → tấm không scale ra SỐ Y HỆT bản cũ
      [bb.width * k[0], bb.height * k[1], bb.depth * k[2]].min.to_mm
    rescue StandardError
      nil   # helper thuần đọc: tấm không đo được = bỏ qua (nil là kết quả hợp lệ, walk lọc đi)
    end
    private_class_method :own_thickness_mm

    # ── Soi nổi (thay kiểu cô lập ẩn tấm, 04/10) ─────────────────
    # Mở công cụ xem lần lượt các tấm có độ dày thoả `keep`; tấm sai đỏ, tấm chuẩn xanh lá.
    def self.xem(&keep)
      items = collect_leaves.select { |_e, th, _te| keep.call(round1(th)) }.map { |e, th, te|
        h = LeHai::HuongTu.hop_rieng(ents_of(e), te)
        h ? Item.new(label(e), round1(th), standard?(round1(th)), LeHai::HuongTu.net_hop(h)) : nil
      }.compact
      return 0 if items.empty?
      # tấm sai trước, rồi theo tên — xem lỗi trước
      items.sort_by! { |it| [it.std ? 1 : 0, it.name] }
      Sketchup.active_model.select_tool(ReviewTool.new(items))
      items.size
    end
    private_class_method :xem

    def self.xem_tam_sai
      UI.messagebox('✓ Không có tấm nào sai độ dày.') if xem { |mm| !standard?(mm) }.zero?
    end
    private_class_method :xem_tam_sai

    Item = Struct.new(:name, :mm, :std, :segs)

    def self.label(e)
      n = e.name.to_s
      return n.sub(/\A__/, '') unless n.empty?
      if e.is_a?(Sketchup::ComponentInstance)
        dn = e.definition.name.to_s
        return dn unless dn.empty?
      end
      '(tấm không tên)'
    end
    private_class_method :label

    # Dọn file đã bị bản cũ ẩn tấm (người dùng bấm nút "Hiện lại"). Chỉ hiện tấm mang dấu MARK.
    def self.show_all
      model = Sketchup.active_model
      model.start_operation('Hien lai tat ca', true)
      begin
        unhide_all_mine(collect_leaves)
        model.commit_operation
      rescue => err
        model.abort_operation
        UI.messagebox("Lỗi: #{err.message}")
        return
      end
      model.selection.clear
    end
    private_class_method :show_all

    def self.unhide_all_mine(leaves)
      leaves.each do |e, _th, _te|
        next unless e.get_attribute(MARK, 'hid', false)
        e.hidden = false
        e.delete_attribute(MARK)
      end
    end
    private_class_method :unhide_all_mine

    # ── Helpers ────────────────────────────────────────────────
    def self.round1(mm)
      (mm * 10.0).round / 10.0
    end
    private_class_method :round1

    def self.standard?(mm)
      STD_MM.any? { |s| (s - mm).abs <= TOL }
    end
    private_class_method :standard?

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end
    private_class_method :ents_of

    # ── HTML ───────────────────────────────────────────────────
    def self.html
      theme = File.exist?(THEME) ? File.read(THEME, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          body{margin:0;padding:14px}
          h3{margin:0 0 10px;font-size:16px;text-align:center;color:var(--lh-walnut)}
          .bar{display:flex;gap:8px;margin-bottom:14px}
          .bar button{flex:1;padding:9px;border:0;border-radius:var(--lh-radius-sm);cursor:pointer;font-size:12px;color:#fff;font-weight:700;font-family:inherit}
          .b-faulty{background:#b91c1c}.b-all{background:var(--lh-walnut)}
          .bar button:hover{filter:brightness(1.1)}
          .chart{display:flex;align-items:flex-end;justify-content:center;gap:20px;
                 height:300px;padding:6px 4px;background:var(--lh-surface);border:1.5px solid var(--lh-line-2);border-radius:var(--lh-radius)}
          .col{display:flex;flex-direction:column;align-items:center;cursor:pointer;height:100%;justify-content:flex-end}
          .col:hover .barv{filter:brightness(1.08);box-shadow:0 0 0 2px rgba(180,83,9,.30)}
          .count{font-size:13px;font-weight:700;color:var(--lh-amber-2);margin-bottom:5px}
          .count.bad{color:#b91c1c}
          .barv{width:50px;border-radius:6px 6px 0 0;background:linear-gradient(#d97706,#92400e);transition:.15s}
          .barv.bad{background:linear-gradient(#f87171,#b91c1c)}
          .label{margin-top:7px;font-size:12px;font-weight:600;color:var(--lh-ink-soft)}
          .label.bad{color:#b91c1c}
          .mag{margin-top:3px;font-size:13px;opacity:.45}
          .hint{font-size:11px;color:var(--lh-muted);margin-top:12px;line-height:1.5;text-align:center}
          .empty{color:var(--lh-muted);text-align:center;padding:40px}
        </style></head><body class="lh">
        <div class="lh-eyebrow" style="text-align:center;margin-top:2px">LeHai's Decor Tools</div>
        <h3>Độ dày các tấm trong file</h3>
        <div class="bar">
          <button class="b-faulty" onclick="sketchup.isolate_faulty()">Xem tấm sai</button>
          <button class="b-all" id="anCu" style="display:none" onclick="sketchup.show_all()"></button>
        </div>
        <div id="list"></div>
        <div class="hint">Bấm 1 cột → soi lần lượt từng tấm dày đó (← → đổi tấm, Esc thoát).<br>
        Chỉ tô lên màn hình, không ẩn / sửa gì trong file.<br>
        Cột nâu = đúng chuẩn (9/10/17.5/18mm), cột đỏ = sai.</div>
        <script>
          function render(res){
            var data=res.cols, B=document.getElementById('anCu');
            // File từng bị bản cũ ẩn tấm (bấm cột = ẩn phần còn lại) → cho người dùng tự bấm hiện lại
            B.style.display=res.an_cu?'':'none';
            B.textContent='Hiện lại '+res.an_cu+' tấm bản cũ đã ẩn';
            var L=document.getElementById('list');
            if(!data.length){L.innerHTML='<div class="empty">Không tìm thấy tấm nào.</div>';return;}
            var max=1;
            for(var i=0;i<data.length;i++){ if(data[i].count>max)max=data[i].count; }
            var html='<div class="chart">';
            for(var j=0;j<data.length;j++){
              var d=data[j];
              var h=Math.max(10, Math.round(d.count/max*230));
              var bad=d.std?'':' bad';
              html+='<div class="col" onclick="sketchup.isolate('+d.mm+')">'+
                '<div class="count'+bad+'">'+d.count+'</div>'+
                '<div class="barv'+bad+'" style="height:'+h+'px"></div>'+
                '<div class="label'+bad+'">'+d.mm+'mm</div>'+
                '<div class="mag">&#128269;</div></div>';
            }
            html+='</div>';
            L.innerHTML=html;
          }
          sketchup.ready();
        </script></body></html>
      HTML
    end
    private_class_method :html

    # =========================================================
    #  SOI NỔI TỪNG TẤM (khuôn ReviewTool của kiem_tra_ten — 04/10 thay kiểu ẩn tấm)
    # =========================================================
    class ReviewTool
      COLOR_BAD = Sketchup::Color.new(220, 40, 40)
      COLOR_OK  = Sketchup::Color.new(0, 150, 60)

      def initialize(items)
        @items = items
        @idx   = 0
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
        return UI.messagebox("Chỉ có #{@items.size} tấm (1–#{@items.size}).") if i < 0 || i >= @items.size
        focus(i)
        view.invalidate
      end

      def draw(view)
        LeHai::SoiNoi.phu_mo(view)
        LeHai::SoiNoi.ve_nets(view, [[@draw, @items[@idx].std ? :la : :do]])
        draw_outline(view, @draw)
        draw_banner(view)
      end

      def focus(i)
        @idx = i
        @draw = flatten(@items[i].segs)
        bb = Geom::BoundingBox.new
        @draw.each { |p| bb.add(p) }
        @bounds = bb
        frame(bb)
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def step(dir, view)
        focus((@idx + dir) % @items.size)
        view.invalidate
      end

      def flatten(segs)
        pts = []
        segs.each { |a, b| pts << Geom::Point3d.new(*a) << Geom::Point3d.new(*b) }
        pts
      end

      def color; @items[@idx].std ? COLOR_OK : COLOR_BAD; end

      def draw_outline(view, pts)
        return if pts.empty?
        LeHai::SoiNoi.but(view, color, 3)
        view.draw(GL_LINES, pts)
        LeHai::SoiNoi.net2d(view, pts)
      end

      def draw_banner(view)
        v = @items[@idx]
        chuan = STD_MM.map { |m| m.to_s.sub(/\.0\z/, '') }.join(' / ')
        if v.std
          l1 = "Tấm đúng độ dày   (#{@idx + 1}/#{@items.size})"
          l3 = "Dày #{v.mm} mm — đúng chuẩn ✓"
          title_col = Sketchup::Color.new(120, 240, 160)
          info_col  = Sketchup::Color.new(150, 255, 190)
        else
          l1 = "Tấm SAI độ dày   (#{@idx + 1}/#{@items.size})"
          l3 = "Dày #{v.mm} mm — chuẩn là #{chuan} mm (lệch tối đa #{TOL} mm)"
          title_col = Sketchup::Color.new(255, 150, 140)
          info_col  = Sketchup::Color.new(255, 210, 60)
        end
        l2 = "Tấm: #{v.name}"
        l4 = '← → đổi tấm  ·  gõ số để nhảy  ·  ESC thoát'
        bg_w = 26 + [l1.length, l2.length, l3.length, l4.length].max * 8
        draw_box2d(view, 18, 18, bg_w, 100, Sketchup::Color.new(18, 22, 30, 215))
        draw_box2d(view, 18, 18, 6, 100, color)
        txt(view, 34, 26, l1, title_col, 14, true)
        txt(view, 34, 48, l2, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 68, l3, info_col, 12, false)
        txt(view, 34, 90, l4, Sketchup::Color.new(200, 200, 200), 11, false)
      end

      def draw_box2d(view, x, y, w, h, c)
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = c
        view.draw2d(GL_POLYGON, pts)
      end

      def txt(view, x, y, s, c, size, bold)
        view.draw_text(Geom::Point3d.new(x, y, 0), s, color: c, font: 'Arial', size: size, bold: bold)
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
        lbl = @items[@idx].std ? 'Tấm đúng độ dày' : 'Tấm sai độ dày'
        Sketchup.set_status_text("#{lbl} — #{@idx + 1}/#{@items.size} (← → đổi, ESC thoát)", SB_PROMPT)
        Sketchup.set_status_text('Số tấm', SB_VCB_LABEL)
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Kiểm tra độ dày') { TK::ThickCheck.show }
      cmd.tooltip         = 'Kiểm tra độ dày các tấm, soi tấm sai chuẩn'
      cmd.status_bar_text = 'Quét độ dày mọi tấm, cột đỏ = sai chuẩn, bấm cột để soi từng tấm.'
      cmd.small_icon      = File.join(icons, 'check_16.png')
      cmd.large_icon      = File.join(icons, 'check_24.png')
      cmd
    end

  end
end
