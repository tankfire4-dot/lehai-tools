# encoding: UTF-8
# Check Chốt Sản Xuất: dashboard gom các chốt chặn kiểm tra nesting ABF trước
# khi xuất DXF sản xuất — mỗi check tự expose adapter `audit`/`review`, tool này
# chỉ GỌI LẠI, không viết lại logic quét.
#
# Hợp đồng adapter mỗi check phải có:
#   .audit  -> { status: :pass/:fail/:na, count: Integer, message: String }  (CHỈ ĐỌC)
#   .review -> mở tool/dialog xem chi tiết lỗi đó
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'

module TK
  module PreExportCheck

    PATH  = File.dirname(__FILE__).freeze
    THEME = File.join(PATH, '..', 'shared', 'lehai_theme.css').freeze

    # Nạp các check phụ thuộc — rescue để 1 tool lỗi không chặn dashboard.
    %w[kiem_tra_do_day kiem_tra_khoang_cach trung_tam kiem_tra_ban_le kiem_tra_lien_ket kiem_tra_led kiem_tra_ten kiem_tra_dan_canh kiem_tra_r100 kiem_tra_ban_le_chan].each do |folder|
      begin
        require File.join(PATH, '..', folder, 'main')
      rescue LoadError, StandardError => e
        puts "[PreExportCheck] Không nạp được #{folder}: #{e.class}: #{e.message}"
      end
    end

    # ── Danh sách check (thêm check mới = thêm 1 dòng ở đây) ────
    def self.checks
      # Thứ tự = quy trình nên làm (Khoa chốt): Đặt Tên trước vì nhiều check dựa TÊN.
      [
        { key: 'ten',     name: 'Đặt Tên',          mod: mod_of(:NameCheck) },
        { key: 'day',     name: 'Độ Dày Ván',       mod: mod_of(:ThickCheck) },
        { key: 'trung',   name: 'Trùng Tấm',        mod: mod_of(:DuplicateCheck) },
        { key: 'dancanh', name: 'Dán Cạnh',         mod: mod_of(:EdgeBandCheck) },
        { key: 'ranhhau', name: 'Rãnh Hậu',         mod: mod_of(:JointCheck), kind: :ranhhau },
        { key: 'led',     name: 'Rãnh Led',         mod: mod_of(:LedCheck) },
        { key: 'ngam',    name: 'Ngàm',             mod: mod_of(:JointCheck), kind: :ngam },
        { key: 'banle',   name: 'Bản Lề Cánh',      mod: mod_of(:HingeCheck) },
        { key: 'chanbl',  name: 'Đợt Chắn Bản Lề',  mod: mod_of(:HingeBlockCheck) },
        { key: 'khoang',  name: 'Khoảng Cách 7mm',  mod: mod_of(:SpacingCheck) },
        # Cuối bảng: nhắc người xác nhận, không phải chốt chặn (vàng, không đỏ).
        { key: 'r100',    name: 'Cung R100',        mod: mod_of(:RadiusCheck) }
      ]
    end
    private_class_method :checks

    def self.mod_of(const)
      TK.const_defined?(const) ? TK.const_get(const) : nil
    end
    private_class_method :mod_of

    # ── Dialog ─────────────────────────────────────────────────
    def self.show
      if @dlg&.visible?
        @dlg.bring_to_front
        push_scan
        return
      end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Check Chốt Sản Xuất',
        preferences_key: 'tk.preexportcheck',
        width:           420, height: 480,
        min_width:       360, min_height: 360,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      attach(@dlg)
      @dlg.set_html(html)
      @dlg.show
    end

    def self.attach(dlg)
      dlg.add_action_callback('ready')  { push_scan }
      dlg.add_action_callback('rescan') { push_scan }
      dlg.add_action_callback('review') do |_ctx, key|
        c = checks.find { |x| x[:key] == key }
        if c && c[:mod]
          c[:kind] ? c[:mod].review(c[:kind]) : c[:mod].review
        end
      end
    end
    private_class_method :attach

    def self.push_scan
      return unless @dlg&.visible?
      # xóa cache JointCheck để mỗi lần quét lại tính đâm xuyên trên model mới nhất
      TK::JointCheck.clear_cache if defined?(TK::JointCheck) && TK::JointCheck.respond_to?(:clear_cache)
      @dlg.execute_script("render(#{scan_all.to_json});")
    end
    private_class_method :push_scan

    # ── Quét toàn bộ (chỉ đọc) ───────────────────────────────────
    def self.scan_all
      checks.map do |c|
        if c[:todo]
          { key: c[:key], name: c[:name], status: 'todo', count: 0,
            message: 'Cần Khoa giải thích + ví dụ dữ liệu trước khi làm.' }
        elsif c[:mod].nil?
          { key: c[:key], name: c[:name], status: 'na', count: 0,
            message: 'Tool chưa được nạp trong phiên này.' }
        else
          begin
            r = c[:kind] ? c[:mod].audit(c[:kind]) : c[:mod].audit
            { key: c[:key], name: c[:name], status: r[:status].to_s, count: r[:count].to_i,
              message: r[:message].to_s }
          rescue => e
            { key: c[:key], name: c[:name], status: 'error', count: 0,
              message: "Lỗi khi quét: #{e.message}" }
          end
        end
      end
    end
    private_class_method :scan_all

    # ── HTML ───────────────────────────────────────────────────
    def self.html
      theme = File.exist?(THEME) ? File.read(THEME, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          .summary{border-radius:var(--lh-radius);padding:14px 16px;margin-bottom:14px;font-weight:700;font-size:13px}
          .summary--ok{background:rgba(21,128,61,.12);color:#15803d}
          .summary--bad{background:rgba(185,28,28,.10);color:#b91c1c}
          .summary--warn{background:rgba(230,160,0,.14);color:#a16207}
          .row{display:flex;align-items:center;gap:12px;padding:11px 8px;border-bottom:1px solid var(--lh-line-2)}
          .row:last-child{border-bottom:0}
          .dot{width:11px;height:11px;border-radius:50%;flex:0 0 auto}
          .dot--pass{background:#16a34a}
          .dot--fail{background:#dc2626}
          .dot--warn{background:#e6a000}
          .dot--na{background:#a08060}
          .dot--todo{background:#c9c2b8}
          .dot--error{background:#dc2626}
          .rinfo{flex:1;min-width:0}
          .rname{font-weight:700;font-size:13px;color:var(--lh-ink)}
          .rmsg{font-size:11.5px;color:var(--lh-ink-soft);margin-top:2px}
          .rbtn{flex:0 0 auto;border:0;border-radius:var(--lh-radius-sm);padding:8px 12px;
                font-size:12px;font-weight:700;cursor:pointer;background:var(--lh-walnut);color:#fff}
          .rbtn:hover{filter:brightness(1.1)}
          .rbtn--ghost{background:var(--lh-surface);color:var(--lh-walnut);
                       border:1.5px solid var(--lh-line)}
          .rbtn--ghost:hover{border-color:var(--lh-amber);color:var(--lh-amber)}
          .rbtn[disabled]{background:var(--lh-line-2);color:var(--lh-muted);cursor:default;border:0}
          .rescan{margin-top:14px}
          .note{margin-top:12px;font-size:11.5px;color:var(--lh-ink-soft);
                background:var(--lh-fill);border-radius:var(--lh-radius);padding:0 12px}
          .note summary{cursor:pointer;padding:10px 0;font-weight:700;color:var(--lh-walnut);
                        list-style:none;outline:none}
          .note summary::-webkit-details-marker{display:none}
          .note summary::before{content:'▸  '}
          .note[open] summary::before{content:'▾  '}
          .note p{margin:0 0 10px;line-height:1.6}
          .note b{color:var(--lh-amber-2)}
        </style></head>
        <body class="lh"><div class="lh-dialog">
          <div class="lh-eyebrow">LeHai's Decor Tools</div>
          <h1 class="lh-title">Check Chốt Sản Xuất</h1>
          <div id="summary"></div>
          <div class="lh-card" style="padding:2px 8px">
            <div id="list"></div>
          </div>
          <button class="lh-btn lh-btn--ghost rescan" onclick="sketchup.rescan()">↻ Quét lại</button>
          <div class="lh-hint">Chỉ đọc — không sửa model. Bấm "Xem" để soi chi tiết (kể cả mục đã đạt, để kiểm chứng).</div>
          <details class="note">
            <summary>Lưu ý</summary>
            <p>Plugin <b>chỉ ĐỌC</b> mô hình 3D, dò dấu hiệu lỗi trước khi xuất DXF — <b>không sửa gì</b> trong file.</p>
            <p>Thứ tự các mục = <b>quy trình nên làm</b>: <b>Đặt Tên trước tiên</b>, vì nhiều mục check dựa vào <b>TÊN tấm</b>. Ví dụ <b>Bản Lề Cánh chỉ kiểm những tấm có tên chứa "cánh"</b> — nếu một cánh tủ chưa được đặt tên "cánh", nó sẽ bị <b>BỎ SÓT</b> (không báo thiếu bản lề dù thiếu thật). Nên đặt tên đúng chuẩn xong rồi mới soi các lỗi gia công thì mới chắc.</p>
          </details>
          <div class="lh-foot"><span>LeHai Tools</span><span>Check Chốt Sản Xuất</span></div>
        </div>
        <script>
          function badge(st){
            if(st==='pass') return 'dot--pass';
            if(st==='fail' || st==='error') return 'dot--fail';
            if(st==='warn') return 'dot--warn';
            if(st==='todo') return 'dot--todo';
            return 'dot--na';
          }
          function render(rows){
            var hasFail = false, hasWarn = false;
            var html = '';
            for(var i=0;i<rows.length;i++){
              var r = rows[i];
              var urgent = (r.status==='fail' || r.status==='error');
              if(urgent){ hasFail = true; }
              if(r.status==='warn'){ hasWarn = true; }
              // ĐẠT + CẢNH BÁO cũng xem được để kiểm chứng
              var canView = (r.status==='pass' || r.status==='warn' || urgent);
              var cls = urgent ? 'rbtn' : 'rbtn rbtn--ghost';
              html += '<div class="row">'+
                '<div class="dot '+badge(r.status)+'"></div>'+
                '<div class="rinfo"><div class="rname">'+r.name+'</div>'+
                '<div class="rmsg">'+r.message+'</div></div>'+
                '<button class="'+cls+'" '+(canView?'':'disabled')+' onclick="sketchup.review(\\''+r.key+'\\')">Xem</button>'+
                '</div>';
            }
            document.getElementById('list').innerHTML = html;
            var s = document.getElementById('summary');
            if(hasFail){
              s.className = 'summary summary--bad';
              s.innerHTML = '⚠ Có lỗi cần xử lý trước khi xuất DXF.';
            } else if(hasWarn){
              s.className = 'summary summary--warn';
              s.innerHTML = '⚠ Không có lỗi bắt buộc, nhưng có cảnh báo nên xem qua (vd rãnh led).';
            } else {
              s.className = 'summary summary--ok';
              s.innerHTML = '✓ Các mục đã kiểm tra đều đạt.';
            }
          }
          sketchup.ready();
        </script>
        </body></html>
      HTML
    end
    private_class_method :html

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Check chốt sản xuất') { TK::PreExportCheck.show }
      cmd.tooltip         = 'Check Chốt Sản Xuất — chốt chặn trước khi xuất DXF sản xuất'
      cmd.status_bar_text = 'Gom các check (Độ Dày, Khoảng Cách, Trùng Tấm, Bản Lề, Rãnh Hậu, Ngàm) vào 1 dashboard.'
      cmd.small_icon      = File.join(icons, 'gate_16.png')
      cmd.large_icon      = File.join(icons, 'gate_24.png')
      cmd
    end

  end
end
