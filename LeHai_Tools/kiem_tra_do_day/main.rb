# encoding: UTF-8
# Kiểm Tra Độ Dày: quét mọi tấm trong file, đo độ dày = chiều mỏng nhất của
# RIÊNG mặt phẳng tấm đó (bỏ qua group con lồng trong như rãnh phay ABF).
# Phân loại: xanh = chuẩn 9/10/17.5/18mm, đỏ = sai. Bấm 1 cột → CÔ LẬP: chỉ
# hiện tấm độ dày đó, ẩn hết phần còn lại + zoom tới.
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'
require 'json'

module TK
  module ThickCheck

    PATH   = File.dirname(__FILE__).freeze
    MARK   = 'TK_ThickCheck'.freeze
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
      dlg.add_action_callback('isolate')        { |_c, mm| isolate(mm.to_f) }
      dlg.add_action_callback('isolate_faulty') { isolate_faulty }
      dlg.add_action_callback('show_all')       { show_all; push_scan }
    end
    private_class_method :attach

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
      bins.keys.sort.map { |mm| { 'mm' => mm, 'count' => bins[mm], 'std' => standard?(mm) } }
    end
    private_class_method :scan_data

    def self.collect_leaves
      leaves = []
      walk(Sketchup.active_model.entities, 0, leaves)
      leaves
    end
    private_class_method :collect_leaves

    def self.walk(entities, depth, leaves)
      return if depth > 40
      entities.to_a.each do |e|
        next if e.deleted?
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        ents = ents_of(e)
        next unless ents
        th   = own_thickness_mm(ents)
        subs = ents.any? { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
        leaves << [e, th] if th && th >= MIN_MM
        walk(ents, depth + 1, leaves) if subs
      end
    end
    private_class_method :walk

    def self.own_thickness_mm(ents)
      bb = Geom::BoundingBox.new
      ents.each { |c| bb.add(c.bounds) if c.is_a?(Sketchup::Face) }
      return nil if bb.empty?
      [bb.width, bb.height, bb.depth].min.to_mm
    rescue StandardError
      nil
    end
    private_class_method :own_thickness_mm

    # ── Cô lập ─────────────────────────────────────────────────
    def self.isolate(target_mm)
      run_isolate { |mm| (mm - target_mm).abs < 0.05 }
    end
    private_class_method :isolate

    def self.isolate_faulty
      n = run_isolate { |mm| !standard?(mm) }
      UI.messagebox('✓ Không có tấm nào sai độ dày.') if n.zero?
    end
    private_class_method :isolate_faulty

    def self.run_isolate(&keep)
      model  = Sketchup.active_model
      leaves = collect_leaves
      shown  = []
      model.start_operation('Co lap do day', true)
      unhide_all_mine(leaves)
      leaves.each do |e, th|
        if keep.call(round1(th))
          e.hidden = false
          shown << e
        else
          hide_mine(e)
        end
      end
      model.commit_operation

      unless shown.empty?
        model.selection.clear
        model.selection.add(shown)
        model.active_view.zoom(shown)
      end
      shown.size
    end
    private_class_method :run_isolate

    def self.show_all
      model = Sketchup.active_model
      model.start_operation('Hien lai tat ca', true)
      unhide_all_mine(collect_leaves)
      model.commit_operation
      model.selection.clear
    end
    private_class_method :show_all

    def self.hide_mine(e)
      e.hidden = true
      e.set_attribute(MARK, 'hid', true)
    end
    private_class_method :hide_mine

    def self.unhide_all_mine(leaves)
      leaves.each do |e, _th|
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
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:14px;background:#fafafa;color:#222}
          h3{margin:0 0 10px;font-size:16px;text-align:center}
          .bar{display:flex;gap:8px;margin-bottom:14px}
          .bar button{flex:1;padding:9px;border:0;border-radius:7px;cursor:pointer;font-size:12px;color:#fff;font-weight:600}
          .b-faulty{background:#d62828}.b-all{background:#666}
          .bar button:hover{opacity:.88}
          .chart{display:flex;align-items:flex-end;justify-content:center;gap:20px;
                 height:300px;padding:6px 4px;background:#fff;border:1px solid #ececec;border-radius:10px}
          .col{display:flex;flex-direction:column;align-items:center;cursor:pointer;height:100%;justify-content:flex-end}
          .col:hover .barv{filter:brightness(1.08);box-shadow:0 0 0 2px rgba(41,98,168,.25)}
          .count{font-size:13px;font-weight:700;color:#1f6fc4;margin-bottom:5px}
          .count.bad{color:#d62828}
          .barv{width:50px;border-radius:6px 6px 0 0;background:linear-gradient(#4aa8ff,#16e0ff);transition:.15s}
          .barv.bad{background:linear-gradient(#ff7a7a,#d62828)}
          .label{margin-top:7px;font-size:12px;font-weight:600}
          .label.bad{color:#d62828}
          .mag{margin-top:3px;font-size:13px;opacity:.45}
          .hint{font-size:11px;color:#999;margin-top:12px;line-height:1.5;text-align:center}
          .empty{color:#888;text-align:center;padding:40px}
        </style></head><body>
        <h3>Độ dày các tấm trong file</h3>
        <div class="bar">
          <button class="b-faulty" onclick="sketchup.isolate_faulty()">Chỉ hiện tấm lỗi</button>
          <button class="b-all" onclick="sketchup.show_all()">Hiện lại tất cả</button>
        </div>
        <div id="list"></div>
        <div class="hint">Bấm 1 cột → chỉ hiện tấm dày đó, ẩn phần còn lại, tự zoom tới.<br>
        Cột xanh = đúng chuẩn (9/10/17.5/18mm), cột đỏ = sai.</div>
        <script>
          function render(data){
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

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Kiểm tra độ dày') { TK::ThickCheck.show }
      cmd.tooltip         = 'Kiểm tra độ dày các tấm, cô lập tấm sai chuẩn'
      cmd.status_bar_text = 'Quét độ dày mọi tấm, tô đỏ tấm sai, bấm để chỉ hiện tấm cần xem.'
      cmd.small_icon      = File.join(icons, 'check_16.png')
      cmd.large_icon      = File.join(icons, 'check_24.png')
      cmd
    end

  end
end
