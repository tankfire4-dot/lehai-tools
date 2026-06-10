# =============================================================
#  canh_cnc.rb  —  Plugin tạo cánh CNC bằng chuột bắt điểm 2 góc
#  v4: Auto-detect mặt phẳng XZ/YZ, validate input, error rõ ràng
# =============================================================

require 'sketchup.rb'
require 'json'

module CanhCNC
  PLUGIN_NAME = "Tạo Cánh_LeHaiDecor".freeze
  MIN_SIZE_MM = 10.0  # 2 điểm cách nhau ít nhất 10mm

  # ----------------------------------------------------------
  # HELPER: Detect mặt phẳng vẽ dựa trên 2 điểm
  # Trả về :xz | :yz | :xy (mặt nằm — không hợp lý)
  # ----------------------------------------------------------
  def self.detect_plane(p1, p2)
    dx = (p2.x - p1.x).abs
    dy = (p2.y - p1.y).abs
    dz = (p2.z - p1.z).abs

    if dy <= dx && dy <= dz
      :xz  # mặt đứng nhìn theo trục Y (mặt trước phổ biến)
    elsif dx <= dy && dx <= dz
      :yz  # mặt đứng nhìn theo trục X (mặt hông)
    else
      :xy  # mặt nằm ngang — không hợp lý cho cánh tủ
    end
  end

  # Tạo 4 góc rectangle preview theo mặt phẳng
  def self.rect_corners(p1, p2, plane)
    case plane
    when :xz
      y = p1.y
      [Geom::Point3d.new(p1.x, y, p1.z),
       Geom::Point3d.new(p2.x, y, p1.z),
       Geom::Point3d.new(p2.x, y, p2.z),
       Geom::Point3d.new(p1.x, y, p2.z)]
    when :yz
      x = p1.x
      [Geom::Point3d.new(x, p1.y, p1.z),
       Geom::Point3d.new(x, p2.y, p1.z),
       Geom::Point3d.new(x, p2.y, p2.z),
       Geom::Point3d.new(x, p1.y, p2.z)]
    else
      nil
    end
  end

  # ----------------------------------------------------------
  # CÔNG CỤ BẮT ĐIỂM INTERACTIVE TOOL
  # ----------------------------------------------------------
  class ClickToDrawTool
    def initialize(params)
      @params  = params
      @ip1     = Sketchup::InputPoint.new
      @ip2     = Sketchup::InputPoint.new
      @state   = 0
      @mouse_x = nil
      @mouse_y = nil
      @snap1   = nil
      @snap2   = nil
      @pt1     = nil
    end

    def activate
      @state = 0
      @ip1.clear
      @ip2.clear
      @mouse_x = nil
      @mouse_y = nil
      Sketchup.status_text = "Click điểm 1: Chọn góc bắt đầu của khoang tủ."
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @mouse_x = x
      @mouse_y = y
      if @state == 0
        @ip1.pick(view, x, y)
        view.tooltip = @ip1.tooltip if @ip1.valid?
        @snap1 = face_center_snap(@ip1, x, y, view)
      else
        @ip2.pick(view, x, y, @ip1)
        view.tooltip = @ip2.tooltip if @ip2.valid?
        @snap2 = face_center_snap(@ip2, x, y, view)
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      if @state == 0
        @ip1.pick(view, x, y)
        if @ip1.valid?
          @pt1   = @snap1 || @ip1.position
          @state = 1
          Sketchup.status_text = "Click điểm 2: Chọn góc đối diện để dựng cánh tủ."
        end
      else
        @ip2.pick(view, x, y, @ip1)
        if @ip2.valid?
          pt2 = @snap2 || @ip2.position
          CanhCNC.process_geometry(@pt1, pt2, @params)
          @state = 0
          @ip1.clear
          @ip2.clear
          @pt1   = nil
          @snap1 = nil
          @snap2 = nil
          Sketchup.status_text = "Đã tạo cánh xong! Click điểm 1 để tiếp tục khoang mới..."
        end
      end
      view.invalidate
    end

    def face_center_snap(ip, x, y, view)
      face = ip.face
      return nil unless face
      center    = face.bounds.center
      threshold = view.pixels_to_model(15, center)
      ip.position.distance(center) < threshold ? center : nil
    end

    def draw_face_center_indicator(view, pt)
      view.draw_points([pt], 14, 4, Sketchup::Color.new(255, 200, 0))
    end

    # Vẽ crosshair 2D theo pixel màn hình (luôn hiện, không phụ thuộc snap)
    def draw_crosshair_2d(view, color)
      return unless @mouse_x && @mouse_y
      cx = @mouse_x
      cy = @mouse_y
      arm = 12       # chiều dài 4 cánh dấu +
      sq  = 7        # nửa cạnh ô vuông quanh chuột

      view.drawing_color = color
      view.line_width = 2
      view.line_stipple = ""

      # Dấu cộng
      view.draw2d(GL_LINES, [
        Geom::Point3d.new(cx - arm, cy, 0),
        Geom::Point3d.new(cx + arm, cy, 0),
        Geom::Point3d.new(cx, cy - arm, 0),
        Geom::Point3d.new(cx, cy + arm, 0)
      ])

      # Ô vuông xung quanh chuột
      view.draw2d(GL_LINE_LOOP, [
        Geom::Point3d.new(cx - sq, cy - sq, 0),
        Geom::Point3d.new(cx + sq, cy - sq, 0),
        Geom::Point3d.new(cx + sq, cy + sq, 0),
        Geom::Point3d.new(cx - sq, cy + sq, 0)
      ])
    end

    def draw(view)
      green  = Sketchup::Color.new(50, 220, 50)
      orange = Sketchup::Color.new(255, 150, 0)
      purple = Sketchup::Color.new(170, 100, 255)

      # Trạng thái 0: chưa click — chỉ vẽ crosshair theo chuột + snap indicator
      if @state == 0
        draw_crosshair_2d(view, green)
        @ip1.draw(view) if @ip1.valid? && @ip1.display?
        draw_face_center_indicator(view, @snap1) if @snap1
        return
      end

      # Trạng thái 1: đã có điểm 1, đang hover điểm 2
      return unless @pt1 && @ip2.valid?

      p1 = @pt1
      p2 = @snap2 || @ip2.position
      plane = CanhCNC.detect_plane(p1, p2)
      corners = CanhCNC.rect_corners(p1, p2, plane)

      # Preview rectangle tím
      if corners
        view.line_width = 3
        view.line_stipple = ""
        view.drawing_color = purple
        view.draw_polyline(corners + [corners.first])
      end

      # Marker cam đậm tại điểm 1 đã chốt (filled square)
      view.draw_points([p1], 16, 2, orange)

      # Crosshair xanh tại con trỏ + snap indicator
      draw_crosshair_2d(view, green)
      @ip2.draw(view) if @ip2.display? && !@snap2
      draw_face_center_indicator(view, @snap2) if @snap2
    end
  end

  # ----------------------------------------------------------
  # ĐIỀU KHIỂN GIAO DIỆN DIALOG
  # ----------------------------------------------------------
  def self.show_dialog
    dialog = UI::HtmlDialog.new(
      dialog_title:    PLUGIN_NAME,
      preferences_key: "com.canhcnc.v4",
      scrollable:      false,
      resizable:       true,
      width:           350,
      height:          560
    )

    dialog.set_html(html_content)

    dialog.add_action_callback("kich_hoat_chuot") do |_ctx, json|
      begin
        p = JSON.parse(json)
        n = [p['so_canh'].to_i, 1].max
        params = {
          so_canh:    n,
          chieu_canh: p['chieu_canh'].to_s,
          day:        p['day'].to_f,
          ho_tren:    p['ho_tren'].to_f,
          ho_duoi:    p['ho_duoi'].to_f,
          ho_trai:    p['ho_trai'].to_f,
          ho_phai:    p['ho_phai'].to_f,
          ho_giua:    p['ho_giua'].to_f
        }

        # Validate
        if params.values.any? { |v| v.is_a?(Float) && v < 0 }
          UI.messagebox("Các thông số không được âm. Kiểm tra lại các ô độ hở/độ dày.")
          next
        end
        if params[:day] <= 0
          UI.messagebox("Độ dày ván phải lớn hơn 0.")
          next
        end

        Sketchup.active_model.select_tool(ClickToDrawTool.new(params))
      rescue => e
        UI.messagebox("Lỗi cấu hình:\n#{e.message}")
      end
    end

    dialog.show
  end

  # ----------------------------------------------------------
  # XỬ LÝ TOẠ ĐỘ & DỰNG HÌNH KHÔNG GIAN
  # ----------------------------------------------------------
  def self.process_geometry(pt1, pt2, p)
    model = Sketchup.active_model

    # Detect mặt phẳng vẽ
    plane = detect_plane(pt1, pt2)
    if plane == :xy
      UI.messagebox("Plugin chỉ hỗ trợ vẽ cánh trên mặt đứng.\nCố gắng click 2 góc của mặt trước hoặc mặt hông khoang tủ.")
      return
    end

    model.start_operation(PLUGIN_NAME, true)

    begin
      tr_inverse = model.edit_transform.inverse
      local_pt1 = pt1.transform(tr_inverse)
      local_pt2 = pt2.transform(tr_inverse)

      bb = Geom::BoundingBox.new
      bb.add(local_pt1)
      bb.add(local_pt2)

      # Lấy kích thước theo plane
      # w_axis: chiều rộng cánh | h_axis: chiều cao cánh | d_axis: chiều dày (depth)
      if plane == :xz
        total_w = (bb.max.x - bb.min.x).to_mm
        total_h = (bb.max.z - bb.min.z).to_mm
        origin_w = bb.min.x.to_mm
        origin_h = bb.min.z.to_mm
        origin_d = bb.min.y.to_mm
      else # :yz
        total_w = (bb.max.y - bb.min.y).to_mm
        total_h = (bb.max.z - bb.min.z).to_mm
        origin_w = bb.min.y.to_mm
        origin_h = bb.min.z.to_mm
        origin_d = bb.min.x.to_mm
      end

      # Validate kích thước khoang
      if total_w < MIN_SIZE_MM || total_h < MIN_SIZE_MM
        model.abort_operation
        UI.messagebox("Khoang quá nhỏ hoặc 2 điểm trùng nhau.\nKhoang phát hiện: #{total_w.round(1)}mm × #{total_h.round(1)}mm")
        return
      end

      n            = p[:so_canh]
      ngang        = p[:chieu_canh] == 'ngang'
      avail_h_base = total_h - p[:ho_tren] - p[:ho_duoi]
      avail_w_base = total_w - p[:ho_trai] - p[:ho_phai]

      # Validate hở theo chiều chia
      if ngang
        need = p[:ho_tren] + p[:ho_duoi] + (n - 1) * p[:ho_giua]
        if need >= total_h
          model.abort_operation
          UI.messagebox("Khoảng hở dọc vượt quá chiều cao khoang!\nCần ≥ #{need.round(1)}mm, khoang chỉ #{total_h.round(1)}mm")
          return
        end
      else
        need = p[:ho_trai] + p[:ho_phai] + (n - 1) * p[:ho_giua]
        if need >= total_w
          model.abort_operation
          UI.messagebox("Khoảng hở ngang vượt quá chiều rộng khoang!\nCần ≥ #{need.round(1)}mm, khoang chỉ #{total_w.round(1)}mm")
          return
        end
      end

      # Dựng n cánh
      start_h = origin_h + p[:ho_duoi]
      start_w = origin_w + p[:ho_trai]

      if ngang
        # Chia theo chiều cao (Z): mỗi cánh rộng full, cao = avail_h / n
        door_h = (avail_h_base - (n - 1) * p[:ho_giua]) / n.to_f
        n.times do |i|
          z = start_h + i * (door_h + p[:ho_giua])
          draw_one(model.active_entities, plane, start_w, z, origin_d, avail_w_base, door_h, p[:day], "Canh_#{i + 1}")
        end
      else
        # Chia theo chiều rộng (X/Y): mỗi cánh cao full, rộng = avail_w / n
        door_w = (avail_w_base - (n - 1) * p[:ho_giua]) / n.to_f
        n.times do |i|
          w = start_w + i * (door_w + p[:ho_giua])
          draw_one(model.active_entities, plane, w, start_h, origin_d, door_w, avail_h_base, p[:day], "Canh_#{i + 1}")
        end
      end

      model.commit_operation
    rescue => e
      model.abort_operation
      UI.messagebox("Lỗi khi dựng cánh:\n#{e.message}")
    end
  end

  # Vẽ 1 cánh dạng group, kích thước w × h × thickness
  # Tham số tính bằng mm, sẽ convert sang inch nội bộ
  def self.draw_one(entities, plane, w_pos, h_pos, d_pos, width, height, thickness, name)
    group = entities.add_group
    group.name = name
    ents = group.entities

    # Tạo face nằm trên mặt XY (Z cố định = h_pos), sau đó push lên theo Z
    if plane == :xz
      # width theo X, thickness theo Y
      pts = [
        [w_pos.mm,           d_pos.mm,               h_pos.mm],
        [(w_pos + width).mm, d_pos.mm,               h_pos.mm],
        [(w_pos + width).mm, (d_pos + thickness).mm, h_pos.mm],
        [w_pos.mm,           (d_pos + thickness).mm, h_pos.mm]
      ]
    else # :yz
      # thickness theo X, width theo Y
      pts = [
        [d_pos.mm,               w_pos.mm,           h_pos.mm],
        [(d_pos + thickness).mm, w_pos.mm,           h_pos.mm],
        [(d_pos + thickness).mm, (w_pos + width).mm, h_pos.mm],
        [d_pos.mm,               (w_pos + width).mm, h_pos.mm]
      ]
    end

    face = ents.add_face(pts)
    face.reverse! if face.normal.z < 0
    face.pushpull(height.mm)
    group
  end

  # ----------------------------------------------------------
  # GIAO DIỆN HTML CSS GỌN GÀNG
  # ----------------------------------------------------------
  def self.html_content
    <<~HTML
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, 'Segoe UI', Arial, sans-serif; font-size: 13px;
                 background: #1e1e2e; color: #cdd6f4; padding: 12px; overflow: hidden; }
          h3 { font-size: 14px; color: #89b4fa; text-align: center; margin-bottom: 12px; }
          .row { display: flex; gap: 8px; margin-bottom: 8px; }
          .col { flex: 1; }
          label { display: block; margin-bottom: 3px; font-size: 11px; color: #a6adc8; font-weight: bold; }
          select, input[type=number] { width: 100%; padding: 6px 8px; border: 1px solid #45475a;
            border-radius: 4px; background: #11111b; color: #cdd6f4; outline: none; }
          select:focus, input[type=number]:focus { border-color: #89b4fa; }
          .divider { height: 1px; background: #313244; margin: 10px 0; }
          button { display: block; width: 100%; padding: 10px;
            background: linear-gradient(135deg, #a6e3a1, #89b4fa);
            color: #11111b; border: none; border-radius: 4px;
            font-size: 13px; font-weight: bold; cursor: pointer; margin-top: 8px; }
          button:hover { opacity: 0.9; }
          .credit { text-align: right; font-size: 10px; font-style: italic; color: #585b70; margin-top: 8px; letter-spacing: 0.5px; }
          .note { margin-top: 10px; font-size: 11px; color: #f9e2af; text-align: center; line-height: 1.5; }
        </style>
      </head>
      <body>
        <h3>🚪 Thiết Lập Độ Hở Cánh CNC</h3>
        <div class="row">
          <div class="col">
            <label>Số cánh</label>
            <input type="number" id="so_canh" value="2" min="1" max="20" step="1" oninput="toggleGap()">
          </div>
          <div class="col">
            <label>Độ dày ván</label>
            <select id="day">
              <option value="9">9 mm</option>
              <option value="17.5" selected>17.5 mm</option>
            </select>
          </div>
        </div>
        <div class="row">
          <div class="col">
            <label>Chiều cánh</label>
            <select id="chieu_canh">
              <option value="dung">↕ Đứng (chia trái-phải)</option>
              <option value="ngang">↔ Nằm ngang (chia trên-dưới)</option>
            </select>
          </div>
        </div>
        <div class="divider"></div>
        <div class="row">
          <div class="col"><label>Hở trên (mm)</label><input type="number" id="ho_tren" value="0" step="0.5" min="0"></div>
          <div class="col"><label>Hở dưới (mm)</label><input type="number" id="ho_duoi" value="0" step="0.5" min="0"></div>
        </div>
        <div class="row">
          <div class="col"><label>Hở trái (mm)</label><input type="number" id="ho_trai" value="2" step="0.5" min="0"></div>
          <div class="col"><label>Hở phải (mm)</label><input type="number" id="ho_phai" value="2" step="0.5" min="0"></div>
        </div>
        <div class="col" id="gap_row" style="display:block; margin-bottom: 8px;">
          <label>Hở giữa các cánh (mm)</label>
          <input type="number" id="ho_giua" value="2" step="0.5" min="0">
        </div>
        <button onclick="activateTool()">📐 Kích Hoạt Chuột Vẽ</button>
        <p class="credit">@lab by MK</p>
        <p class="note">💡 Bấm nút → ra ngoài click 2 điểm góc chéo của khoang tủ (Kiểm tra kĩ ĐIỂM CLICK khi bấm!).<br>
        Plugin tự nhận mặt phẳng XZ hoặc YZ.</p>
        <script>
          function toggleGap() {
            var n = parseInt(document.getElementById('so_canh').value) || 1;
            document.getElementById('gap_row').style.display = (n > 1) ? 'block' : 'none';
          }
          function v(id) { return parseFloat(document.getElementById(id).value) || 0; }
          function activateTool() {
            var data = {
              so_canh: parseInt(document.getElementById('so_canh').value) || 1,
              chieu_canh: document.getElementById('chieu_canh').value,
              day: v('day'), ho_tren: v('ho_tren'), ho_duoi: v('ho_duoi'),
              ho_trai: v('ho_trai'), ho_phai: v('ho_phai'), ho_giua: v('ho_giua')
            };
            sketchup.kich_hoat_chuot(JSON.stringify(data));
          }
        </script>
      </body>
      </html>
    HTML
  end

  def self.create_cmd
    icon_dir = File.join(File.dirname(__FILE__), 'icons')
    cmd = UI::Command.new(PLUGIN_NAME) { CanhCNC.show_dialog }
    cmd.small_icon      = File.join(icon_dir, 'canh_cnc_16.png')
    cmd.large_icon      = File.join(icon_dir, 'canh_cnc_24.png')
    cmd.tooltip         = PLUGIN_NAME
    cmd.status_bar_text = "Mở bảng vẽ cánh CNC bằng cách click 2 điểm góc"
    cmd.menu_text       = PLUGIN_NAME
    cmd
  end

end # module CanhCNC
