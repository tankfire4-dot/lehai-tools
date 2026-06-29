# encoding: UTF-8
# Dim Nhanh: cong cu tuong tac (nhu Dimension mac dinh nhung tien hon).
#   - Re chuot vao canh -> canh SANG LEN (biet se dim canh nao).
#   - Click -> bat dau dim canh do; re chuot -> dat vi tri/khoang cach dim.
#   - Click lan 2 -> dat xong; tu dong quay lai cho canh tiep theo (khong phai chay lai).
#   - Esc -> thoat; neu da dim >=1 canh thi hien BANG KE chieu dai + tong (cho bao gia).
# Dim tao ra la dimension that cua SketchUp -> keo doi sau nay thoai mai.
#
# Toolbar do LeHai_Tools/main.rb quan ly chung — file nay chi expose create_cmd.

require 'sketchup.rb'

module TK
  module QuickDim

    PATH    = File.dirname(__FILE__).freeze
    THEME   = File.join(PATH, '..', 'shared', 'lehai_theme.css').freeze
    WALNUT  = Sketchup::Color.new(124, 45, 18)
    AMBER   = Sketchup::Color.new(180, 83, 9)

    def self.run
      Sketchup.active_model.select_tool(DimTool.new)
    end

    # =========================================================
    #  TOOL tuong tac
    # =========================================================
    class DimTool
      def initialize
        @state = :pick      # :pick (re chon canh) | :place (dat vi tri dim)
        @hover = nil        # canh dang re toi
        @hover_tr = nil     # phep bien doi -> toa do that cua canh do
        @hover_arc = nil    # neu canh re toi thuoc 1 CUNG TRON (ArcCurve)
        @is_arc = false     # dang dat nhan R (cung) hay dim thuong
        @arc = nil; @arc_tr = nil; @radius_mm = 0
        @anchor = nil       # diem leader bam vao cung
        @leader = nil       # diem chu (theo con tro)
        @edge = nil         # canh da chon
        @a = @b = nil       # 2 dau canh
        @mid = nil
        @pn = nil           # phap tuyen mat phang dat dim
        @ov = nil           # vector offset hien tai
        @mode = :sum        # :sum = Bao gia (cong don) | :note = Ghi chu (dim + R)
        @blocked = false    # dang re vao cung o che do Bao gia (khong dim duoc)
        @done = []          # chieu dai cac canh da dim (Length) — chi che do :sum
        @dims = []          # cac entity dim/text da tao (de don)
      end

      def activate
        @state = :pick
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view) view.invalidate end
      def resume(view) update_status; view.invalidate end
      def onSetCursor; UI.set_cursor(0) end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(hp(@hover.start), hp(@hover.end)) if @hover && @hover_tr
        if @state == :place
          if @is_arc && @anchor && @leader
            bb.add(@anchor, @leader)
          elsif @ov
            bb.add(@a, @b, off(@a), off(@b))
          end
        end
        bb.add(Sketchup.active_model.bounds) if bb.empty?
        bb
      end

      # ── chuot ──
      def onMouseMove(_flags, x, y, view)
        if @state == :pick
          @hover, @hover_tr = pick_edge(view, x, y)
          curve = (@hover && @hover.curve.is_a?(Sketchup::Curve)) ? @hover.curve : nil
          @hover_arc = (@mode == :note) ? curve : nil    # R chi o che do Ghi chu (moi loai cong)
          @blocked   = (@mode == :sum && !curve.nil?)     # che do Bao gia khong dim cung
        elsif @is_arc
          cur = Geom.intersect_line_plane(view.pickray(x, y), [@anchor, @pn])
          @leader = cur if cur
        else
          cur = Geom.intersect_line_plane(view.pickray(x, y), [@mid, @pn])
          @ov = cur ? axis_offset(cur) : @ov
        end
        view.invalidate
      end

      # nhat canh duoi con tro + phep bien doi cua khoi chua no
      def pick_edge(view, x, y)
        ph = view.pick_helper(x, y)
        ph.count.times do |i|
          leaf = ph.leaf_at(i)
          return [leaf, ph.transformation_at(i)] if leaf.is_a?(Sketchup::Edge)
        end
        [nil, nil]
      end

      # toa do THAT cua 1 dau canh dang hover
      def hp(vertex) @hover_tr * vertex.position end

      def onLButtonDown(_flags, _x, _y, view)
        if @state == :pick
          start_place if @hover && !@hover.deleted? && !@blocked
        else
          place(view)
        end
        view.invalidate
      end

      def onKeyDown(key, _r, _f, view)
        if key == 9 && @state == :pick   # Tab -> doi che do
          @mode = (@mode == :sum ? :note : :sum)
          @hover_arc = nil; @blocked = false
          update_status
          view.invalidate
          return false
        end
        return false unless key == 27 # Esc
        if @state == :place
          @state = :pick                 # huy dat, quay ve chon canh
          update_status
        else
          finish(view)                   # thoat tool (+ bang ke neu che do Bao gia)
        end
        view.invalidate
        false
      end

      def onCancel(_r, view) onKeyDown(27, 0, 0, view) end

      # ── logic ──
      def start_place
        @pn = Sketchup.active_model.active_view.camera.direction # mat phang huong ve camera
        if @hover_arc
          @is_arc = true
          @arc = @hover_arc; @arc_tr = @hover_tr
          @radius_mm = radius_of(@arc, @arc_tr)
          @anchor = arc_anchor
          @leader = @anchor
        else
          @is_arc = false
          @edge = @hover
          @a = hp(@edge.start); @b = hp(@edge.end)
          @mid = Geom::Point3d.linear_combination(0.5, @a, 0.5, @b)
          @ov = Geom::Vector3d.new(0, 0, 0)
        end
        @state = :place
        update_status
      end

      # diem giua cung (toa do that) de leader bam vao
      def arc_anchor
        vs = @arc.vertices
        @arc_tr * vs[vs.size / 2].position
      end

      # ban kinh (mm): cung that thi lay .radius; cong tay thi fit vong tron qua 3 diem
      def radius_of(curve, tr)
        return curve.radius.to_mm if curve.is_a?(Sketchup::ArcCurve)
        vs = curve.vertices
        return 0 if vs.size < 3
        r = circumradius(tr * vs.first.position, tr * vs[vs.size / 2].position, tr * vs.last.position)
        r ? r * 25.4 : 0 # r tinh bang inch -> mm
      end

      # ban kinh vong tron ngoai tiep tam giac ABC (inch)
      def circumradius(a, b, c)
        ab = a.distance(b); bc = b.distance(c); ca = c.distance(a)
        area2 = (b - a).cross(c - a).length # = 2 * dien tich
        return nil if area2 < 1e-9
        (ab * bc * ca) / (2.0 * area2)
      end

      def place(view)
        model = view.model
        model.start_operation('Dim', true)
        begin
          if @is_arc
            t = model.active_entities.add_text("R#{TK::QuickDim.fmt(@radius_mm)}", @anchor, @leader - @anchor)
            @dims << t if t
          else
            d = model.active_entities.add_dimension_linear(@a, @b, @ov)
            @dims << d if d
            @done << @a.distance(@b) if @mode == :sum # chi che do Bao gia moi cong don
          end
          model.commit_operation
        rescue => e
          model.abort_operation
          UI.messagebox("Lỗi: #{e.message}")
        end
        @state = :pick
        @edge = nil
        update_status
      end

      def finish(view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        # Bang ke + nut Don dim chi o che do Bao gia (dim tam de lay so).
        # Che do Ghi chu: dim/R la chu thich -> giu lai, khong bang ke.
        TK::QuickDim.show_summary(@done, @dims) if @mode == :sum && !@done.empty?
      end

      # offset KHOA THEO TRUC X/Y/Z (nhu Dimension xin) -> dim ngay ngan.
      # Chon truc con tro keo nhieu nhat, bo qua truc trung huong canh.
      def axis_offset(cur)
        edir = (@b - @a); return @ov if edir.length < 1e-6
        edir.normalize!
        v = cur - @mid
        best = nil; score = -1.0
        [X_AXIS, Y_AXIS, Z_AXIS].each do |ax|
          next if edir.dot(ax).abs > 0.95 # truc gan trung huong canh -> bo
          c = v.dot(ax)
          if c.abs > score
            score = c.abs; best = [ax, c]
          end
        end
        return @ov unless best
        ax, c = best
        Geom::Vector3d.new(ax.x * c, ax.y * c, ax.z * c)
      end

      def off(pt) pt.offset(@ov) end

      # ── ve ──
      def draw(view)
        draw_hover(view) if @state == :pick && @hover && !@hover.deleted?
        if @state == :place
          @is_arc ? draw_arc_preview(view) : (draw_preview(view) if @ov)
        end
        draw_hud(view)
      end

      def draw_hover(view)
        return unless @hover_tr
        if @blocked # cung o che do Bao gia -> to xam, bao khong dim duoc
          view.line_width = 3
          view.drawing_color = Sketchup::Color.new(150, 150, 150)
          (@hover.curve ? @hover.curve.edges : [@hover]).each { |e| draw_world_edge(view, e) }
          return
        end
        view.line_width = 4
        view.drawing_color = AMBER
        (@hover_arc ? @hover_arc.edges : [@hover]).each { |e| draw_world_edge(view, e) }
      end

      def draw_world_edge(view, e)
        a = @hover_tr * e.start.position; b = @hover_tr * e.end.position
        view.draw(GL_LINES, [a, b])
        view.draw2d(GL_LINES, [view.screen_coords(a), view.screen_coords(b)])
      end

      # preview nhan ban kinh: duong leader + chu "R…"
      def draw_arc_preview(view)
        view.line_width = 2
        view.drawing_color = WALNUT
        view.draw(GL_LINES, [@anchor, @leader])
        s = view.screen_coords(@leader)
        txt_chip(view, s.x, s.y, "R#{TK::QuickDim.fmt(@radius_mm)}")
      end

      def draw_preview(view)
        da = off(@a); db = off(@b)
        view.line_width = 2
        view.drawing_color = WALNUT
        view.draw(GL_LINES, [@a, da, @b, db, da, db]) # 2 duong giong + duong dim
        # so mm tren chip toi
        mid = Geom::Point3d.linear_combination(0.5, da, 0.5, db)
        s = view.screen_coords(mid)
        txt_chip(view, s.x, s.y, "#{TK::QuickDim.fmt(@a.distance(@b).to_mm)} mm")
      end

      def draw_hud(view)
        mode = @mode == :sum ? 'BÁO GIÁ (cộng dồn)' : 'GHI CHÚ (dim + R)'
        line0 = "● Chế độ: #{mode}    [Tab] đổi"
        line1 = hud_action
        line2 = if @mode == :sum
                  @done.empty? ? 'ESC để thoát' :
                    "Đã dim #{@done.size} cạnh · tổng #{TK::QuickDim.fmt(@done.sum(&:to_mm))} mm · ESC = bảng kê"
                else
                  'ESC để thoát (dim/R giữ lại trên bản vẽ)'
                end
        w = 26 + [line0.length, line1.length, line2.length].max * 8
        accent = @mode == :sum ? AMBER : Sketchup::Color.new(110, 200, 150)
        box2d(view, 18, 18, w, 78, Sketchup::Color.new(18, 22, 30, 222))
        box2d(view, 18, 18, 6, 78, accent)
        txt(view, 34, 25, line0, accent, 12, true)
        txt(view, 34, 45, line1, Sketchup::Color.new(255, 255, 255), 12, false)
        txt(view, 34, 64, line2, Sketchup::Color.new(200, 200, 205), 11, false)
      end

      def hud_action
        if @state == :place
          @is_arc ? 'Rê đặt nhãn R → click đặt · ESC huỷ' : 'Rê đặt vị trí dim → click đặt · ESC huỷ'
        elsif @blocked
          'Cung tròn — bấm [Tab] sang Ghi chú để ghi R'
        elsif @hover_arc
          'Cung tròn → click để TỰ GHI R'
        else
          'Rê vào cạnh → click để dim'
        end
      end

      def txt_chip(view, cx, cy, s)
        w = 16 + s.length * 8
        box2d(view, cx - w / 2.0, cy - 26, w, 22, Sketchup::Color.new(18, 22, 30, 235))
        txt(view, cx - w / 2.0 + 9, cy - 22, s, Sketchup::Color.new(255, 255, 255), 12, true)
      end

      def box2d(view, x, y, w, h, color)
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = color
        view.draw2d(GL_POLYGON, pts)
      end

      def txt(view, x, y, s, color, size, bold)
        view.draw_text(Geom::Point3d.new(x, y, 0), s, color: color, font: 'Arial', size: size, bold: bold)
      end

      def update_status
        m = @mode == :sum ? 'Báo giá' : 'Ghi chú'
        Sketchup.set_status_text(
          @state == :pick ? "Dim Nhanh [#{m}]: rê cạnh→click dim · Tab=đổi chế độ · ESC thoát"
                          : "Dim Nhanh [#{m}]: rê đặt vị trí, click đặt, ESC huỷ", SB_PROMPT
        )
      end
    end

    # =========================================================
    #  BANG KE (giao dien LeHai)
    # =========================================================
    def self.show_summary(lengths, dims = [])
      @last_dims = dims
      mm    = lengths.map { |l| l.to_mm }
      total = mm.sum
      @dlg  = UI::HtmlDialog.new(
        dialog_title: 'Dim Nhanh — Bảng kê', preferences_key: 'tk.quickdim',
        width: 320, height: 480, min_width: 260, min_height: 320,
        resizable: true, style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dlg.add_action_callback('clean_dims') do |_ctx|
        n = clean_dims
        @dlg.execute_script("cleaned(#{n})")
      end
      @dlg.set_html(html(mm, total))
      @dlg.show
    end

    # xoa cac dim vua tao trong phien (dim tay nguoi dung KHONG dung toi)
    def self.clean_dims
      dims = (@last_dims || []).reject { |d| d.nil? || d.deleted? }
      return 0 if dims.empty?
      model = Sketchup.active_model
      model.start_operation('Don dim nhanh', true)
      dims.each(&:erase!)
      model.commit_operation
      @last_dims = []
      dims.size
    end

    def self.fmt(v)
      r = v.round(1)
      (r == r.to_i ? r.to_i : r).to_s
    end

    def self.html(mm, total)
      rows = mm.each_with_index.map do |v, i|
        "<tr><td class='n'>#{i + 1}</td><td class='v'>#{fmt(v)}</td></tr>"
      end.join
      theme = File.exist?(THEME) ? File.read(THEME, encoding: 'UTF-8') : ''
      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          table{width:100%;border-collapse:collapse;font-size:13px}
          th{font-size:10px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;
             color:var(--lh-ink-soft);text-align:left;padding:6px 8px;border-bottom:1.5px solid var(--lh-line)}
          td{padding:6px 8px;border-bottom:1px solid var(--lh-line-2)}
          td.n{color:var(--lh-muted);width:36px}
          td.v{text-align:right;font-weight:600;font-variant-numeric:tabular-nums}
          .tot{display:flex;justify-content:space-between;align-items:baseline;
               margin-top:14px;padding:12px 8px;background:var(--lh-fill);border-radius:var(--lh-radius)}
          .tot b{font-size:20px;color:var(--lh-amber-2)}
          .tot-right{display:flex;align-items:center;gap:10px}
          .lh-copybtn{width:auto;padding:7px 13px;font-size:12px}
          .lh-hidden{position:absolute;left:-9999px;top:0;width:1px;height:1px;opacity:0}
        </style></head>
        <body class="lh"><div class="lh-dialog">
          <div class="lh-eyebrow">LeHai Decor Tools</div>
          <h1 class="lh-title">📐 Bảng kê chiều dài</h1>
          <div class="lh-card" style="padding:6px 8px 8px">
            <table><thead><tr><th>#</th><th style="text-align:right">Dài (mm)</th></tr></thead>
            <tbody>#{rows}</tbody></table>
          </div>
          <div class="tot">
            <span class="lh-label" style="margin:0">Tổng · #{mm.size} cạnh</span>
            <span class="tot-right">
              <b>#{fmt(total)} mm</b>
              <button id="lh-copy" class="lh-btn lh-btn--ghost lh-copybtn" onclick="lhCopy()">⧉ Copy</button>
            </span>
          </div>
          <textarea id="lh-data" class="lh-hidden">#{fmt(total)}</textarea>
          <div style="margin-top:10px;display:flex;align-items:center;gap:10px">
            <button id="lh-clean" class="lh-btn lh-btn--ghost lh-copybtn" onclick="sketchup.clean_dims()">🧹 Dọn dim</button>
            <span class="lh-hint" style="margin:0">Xoá các dim vừa tạo (dim tay giữ nguyên)</span>
          </div>
          <div class="lh-foot"><span>LeHai Tools</span><span>Dim Nhanh</span></div>
        </div>
        <script>
          function lhCopy(){
            var t=document.getElementById('lh-data');
            t.focus(); t.select(); try{ t.setSelectionRange(0,999999); }catch(e){}
            var ok=false; try{ ok=document.execCommand('copy'); }catch(e){}
            if(!ok && navigator.clipboard){ navigator.clipboard.writeText(t.value); }
            var b=document.getElementById('lh-copy'), o=b.innerHTML;
            b.innerHTML='✓ Đã copy'; setTimeout(function(){ b.innerHTML=o; }, 1200);
          }
          function cleaned(n){
            var b=document.getElementById('lh-clean');
            b.innerHTML = n>0 ? ('✓ Đã dọn '+n+' dim') : 'Không còn dim';
            b.disabled=true; b.style.opacity=.55; b.style.cursor='default';
          }
        </script>
        </body></html>
      HTML
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quan ly chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Dim nhanh') { TK::QuickDim.run }
      cmd.tooltip         = 'Dim nhanh — rê vào cạnh, click để dim'
      cmd.status_bar_text = 'Rê chuột vào cạnh để sáng, click để dim, rê đặt vị trí. ESC ra bảng kê.'
      cmd.small_icon      = File.join(icons, 'dim_16.png')
      cmd.large_icon      = File.join(icons, 'dim_24.png')
      cmd
    end

  end
end
