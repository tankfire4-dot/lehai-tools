# =============================================================
#  canh_cnc.rb  —  Plugin tạo cánh CNC bằng chuột bắt điểm 2 góc
#  v4: Auto-detect mặt phẳng XZ/YZ, validate input, error rõ ràng
# =============================================================

require 'sketchup.rb'
require 'json'
require File.join(File.dirname(__FILE__), '..', 'shared', 'laser_snap')
require File.join(File.dirname(__FILE__), '..', 'shared', 'huong_tu')

module CanhCNC
  PLUGIN_NAME = "Tạo Cánh_LeHaiDecor".freeze
  MIN_SIZE_MM = 10.0  # 2 điểm cách nhau ít nhất 10mm

  # ----------------------------------------------------------
  # HELPER: Detect mặt phẳng vẽ dựa trên 2 điểm, trong HỌ TRỤC của tủ (LUAT_NHA mục 9, 29/09):
  # ho = trục ngang của tủ lấy từ hình (LeHai::HuongTu), x = dọc ho, y = dọc Z × ho.
  # Tủ thẳng trục file thì ho = trục đỏ → y hệt bản cũ (x/y = trục đỏ/xanh lá).
  # Trả về :xz (mặt chứa ho, pháp tuyến Z×ho) | :yz (mặt chứa Z×ho, pháp tuyến ho) | :xy (mặt nằm)
  # ----------------------------------------------------------
  def self.detect_plane(p1, p2, ho = X_AXIS)
    d  = p2 - p1
    dx = d.dot(ho).abs
    dy = d.dot(Z_AXIS.cross(ho)).abs
    dz = d.z.abs

    if dy <= dx && dy <= dz
      :xz  # mặt đứng nhìn theo trục Y (mặt trước phổ biến)
    elsif dx <= dy && dx <= dz
      :yz  # mặt đứng nhìn theo trục X (mặt hông)
    else
      :xy  # mặt nằm ngang — không hợp lý cho cánh tủ
    end
  end

  # Pháp tuyến (ngang, đơn vị) của mặt phẳng cánh trong họ trục ho
  def self.phap_tuyen_mat(plane, ho)
    plane == :xz ? Z_AXIS.cross(ho) : ho.clone
  end

  # Chiếu p về mặt phẳng (o, n). n trùng trục file → thay đúng toạ độ như bản cũ (số y hệt).
  def self.chieu(p, o, n)
    return Geom::Point3d.new(p.x, o.y, p.z) if n.x.zero? && n.y.abs == 1
    return Geom::Point3d.new(o.x, p.y, p.z) if n.y.zero? && n.x.abs == 1
    k = (p - o).dot(n)
    Geom::Point3d.new(p.x - n.x * k, p.y - n.y * k, p.z - n.z * k)
  end

  # Tạo 4 góc rectangle preview theo mặt phẳng (chỉ để vẽ khung xem trước)
  def self.rect_corners(p1, p2, plane, ho = X_AXIS)
    return nil if plane == :xy
    u = Z_AXIS.cross(phap_tuyen_mat(plane, ho))   # dọc bề rộng
    k = (p2 - p1).dot(u)
    a = Geom::Point3d.new(p1.x + u.x * k, p1.y + u.y * k, p1.z)
    [p1, a, Geom::Point3d.new(a.x, a.y, p2.z), Geom::Point3d.new(p1.x, p1.y, p2.z)]
  end

  # ----------------------------------------------------------
  # MỘT LẦN TÍNH cho preview + dựng + thử (29/09): p1, p2 = điểm THẾ GIỚI (p2 đã chiếu về mặt
  # phẳng cánh), ho = họ trục tủ, nhin = hướng camera, plane = :xz/:yz/:xy.
  # Phía nào là LÒNG TỦ lấy theo hình (LeHai::HuongTu.huong_vao) — bản cũ luôn đắp bề dày về
  # phía + của trục file → tủ quay mặt về đỏ/xanh lá DƯƠNG thì cánh lòi ra ngoài.
  # Trả layout của door_layout, tính trong HỆ CÁNH (x dọc bề rộng từ trái sang theo mắt nhìn vào,
  # y vào lòng tủ, z lên), kèm :he (hệ cánh → thế giới) và :doan (lòng tủ phải đoán theo hướng nhìn).
  # ----------------------------------------------------------
  # lat = người dùng bấm Tab lật phía (chỉ có tác dụng khi lòng tủ phải ĐOÁN theo hướng nhìn).
  def self.tinh(model, p1, p2, p, ho, nhin, plane, lat = false)
    return { plane: :xy, error: :plane } if plane == :xy
    n = phap_tuyen_mat(plane, ho)
    u = Z_AXIS.cross(n)
    c = Geom::Point3d.new((p1.x + p2.x) / 2, (p1.y + p2.y) / 2, (p1.z + p2.z) / 2)
    vao = LeHai::HuongTu.huong_vao(model, c, n, u, (p2 - p1).dot(u).abs / 2, nhin)
    return { plane: plane, error: :huong } unless vao
    vao = [vao[0].reverse, true] if vao[1] && lat
    # Hai hông khoang lệch song song > 1° → không dựng (LUAT_NHA mục 9; Codex soát 29/09 bắt bản đầu
    # vẫn dựng khi một hông lệch 3°). Đo từ tâm khoang lùi vào lòng tủ 20mm.
    lech = LeHai::HuongTu.lech_hai_vach(model, c.offset(vao[0], 20.0 / 25.4))
    return { plane: plane, error: :lech, lech: lech } if lech && lech > 1.0
    he = LeHai::HuongTu.he(vao[0])
    hi = he.inverse
    door_layout(hi * p1, hi * p2, p).merge(he: he, doan: vao[1])
  end

  # ----------------------------------------------------------
  # CÔNG THỨC CHUNG: tính layout các cánh từ 2 điểm góc chéo.
  # Dùng cho CẢ preview lẫn dựng hình thật — 2 bên không bao giờ lệch nhau.
  # Trả về Hash:
  #   :plane   — :xz | :yz | :xy
  #   :doors   — mảng [w_pos, h_pos, d_pos, width, height] (mm), nil nếu lỗi
  #   :error   — :plane | :too_small | :gap_h | :gap_w
  #   :total_w, :total_h, :need — số liệu cho thông báo lỗi
  # ----------------------------------------------------------
  def self.door_layout(p1, p2, p)
    plane = detect_plane(p1, p2)
    return { plane: plane, error: :plane } if plane == :xy

    bb = Geom::BoundingBox.new
    bb.add(p1)
    bb.add(p2)

    if plane == :xz
      total_w  = (bb.max.x - bb.min.x).to_mm
      total_h  = (bb.max.z - bb.min.z).to_mm
      origin_w = bb.min.x.to_mm
      origin_h = bb.min.z.to_mm
      origin_d = bb.min.y.to_mm
    else # :yz
      total_w  = (bb.max.y - bb.min.y).to_mm
      total_h  = (bb.max.z - bb.min.z).to_mm
      origin_w = bb.min.y.to_mm
      origin_h = bb.min.z.to_mm
      origin_d = bb.min.x.to_mm
    end

    base = { plane: plane, total_w: total_w, total_h: total_h }
    if total_w < MIN_SIZE_MM || total_h < MIN_SIZE_MM
      return base.merge(error: :too_small)
    end

    n     = p[:so_canh]
    ngang = p[:chieu_canh] == 'ngang'
    avail_h = total_h - p[:ho_tren] - p[:ho_duoi]
    avail_w = total_w - p[:ho_trai] - p[:ho_phai]

    if ngang
      need = p[:ho_tren] + p[:ho_duoi] + (n - 1) * p[:ho_giua]
      return base.merge(error: :gap_h, need: need) if need >= total_h
    else
      need = p[:ho_trai] + p[:ho_phai] + (n - 1) * p[:ho_giua]
      return base.merge(error: :gap_w, need: need) if need >= total_w
    end

    doors   = []
    start_h = origin_h + p[:ho_duoi]
    start_w = origin_w + p[:ho_trai]

    if ngang
      door_h = (avail_h - (n - 1) * p[:ho_giua]) / n.to_f
      n.times do |i|
        z = start_h + i * (door_h + p[:ho_giua])
        doors << [start_w, z, origin_d, avail_w, door_h]
      end
    else
      door_w = (avail_w - (n - 1) * p[:ho_giua]) / n.to_f
      n.times do |i|
        w = start_w + i * (door_w + p[:ho_giua])
        doors << [w, start_h, origin_d, door_w, avail_h]
      end
    end

    base.merge(doors: doors)
  end

  # 8 đỉnh hộp 3D của 1 cánh (toạ độ mm -> inch) — cho preview vẽ wireframe
  def self.door_box_corners(plane, door, thickness)
    w, h, d, width, height = door
    if plane == :xz
      x0 = w.mm; x1 = (w + width).mm
      y0 = d.mm; y1 = (d + thickness).mm
      z0 = h.mm; z1 = (h + height).mm
    else # :yz
      x0 = d.mm; x1 = (d + thickness).mm
      y0 = w.mm; y1 = (w + width).mm
      z0 = h.mm; z1 = (h + height).mm
    end
    [
      Geom::Point3d.new(x0, y0, z0), Geom::Point3d.new(x1, y0, z0),
      Geom::Point3d.new(x1, y1, z0), Geom::Point3d.new(x0, y1, z0),
      Geom::Point3d.new(x0, y0, z1), Geom::Point3d.new(x1, y0, z1),
      Geom::Point3d.new(x1, y1, z1), Geom::Point3d.new(x0, y1, z1)
    ]
  end

  # ----------------------------------------------------------
  # CÔNG CỤ BẮT ĐIỂM INTERACTIVE TOOL
  # ----------------------------------------------------------
  class ClickToDrawTool
    # 12 cạnh của hộp wireframe (index vào mảng 8 đỉnh)
    BOX_EDGES = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7]
    ].freeze

    def initialize(params)
      @params     = params
      @ip1        = Sketchup::InputPoint.new
      @ip2        = Sketchup::InputPoint.new
      @state      = 0
      @mouse_x    = nil
      @mouse_y    = nil
      @pt1        = nil
      @laser      = nil
      @plane_lock = nil
      @preview    = nil
      @ho         = nil   # họ trục tủ quanh điểm 1 (LeHai::HuongTu)
      @lat        = false # Tab: lật phía lòng tủ khi phải đoán theo hướng nhìn
    end

    def activate
      @state = 0
      @ip1.clear
      @ip2.clear
      @mouse_x    = nil
      @mouse_y    = nil
      @laser      = nil
      @plane_lock = nil
      LeHai::LaserSnap.clear_cache!
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
        @laser = LeHai::LaserSnap.scan(view, x, y)
      else
        @ip2.pick(view, x, y, @ip1)
        view.tooltip = @ip2.tooltip if @ip2.valid?
        # Khoá laser theo mặt phẳng cánh — tia/điểm hút nằm đúng mặt đang vẽ
        @laser = LeHai::LaserSnap.scan(view, x, y, door_plane)
        update_preview
      end
      view.invalidate
    end

    # Tính trước các hộp cánh ma cho draw() — draw chỉ việc vẽ dữ liệu cache.
    # Có lưới an toàn: gặp lỗi bất kỳ thì bỏ preview, draw rút về khung tím cũ.
    def update_preview
      @preview = nil
      return unless @state == 1 && @pt1 && @ip2.valid?
      pt2    = project_to_door_plane(LeHai::LaserSnap.snapped_point(@laser) || @ip2.position)
      plane  = @plane_lock || CanhCNC.detect_plane(@pt1, pt2, @ho)
      view   = Sketchup.active_model.active_view
      layout = CanhCNC.tinh(view.model, @pt1, pt2, @params, @ho, view.camera.direction, plane, @lat)
      bao_trang_thai(layout)
      if layout[:doors]
        boxes = layout[:doors].map do |d|
          CanhCNC.door_box_corners(layout[:plane], d, @params[:day]).map { |q| layout[:he] * q }
        end
        @preview = { boxes: boxes }
      else
        @preview = { error: layout[:error] }
      end
    rescue StandardError
      @preview = nil
    end

    # Thanh trạng thái bước điểm 2: nói rõ khi lòng tủ phải ĐOÁN (Tab lật) hoặc hông lệch
    def bao_trang_thai(layout)
      Sketchup.status_text =
        if layout[:error] == :lech
          "Hai hông khoang lệch #{layout[:lech].round(1)}° — tool không dựng cánh trên khoang lệch.  |  ESC=Chọn lại điểm 1"
        elsif layout[:error] == :huong
          "Không rõ phía nào là lòng tủ — nhìn chính diện mặt trước khoang.  |  ESC=Chọn lại điểm 1"
        elsif layout[:doan]
          "⚠ Không phân được lòng tủ bằng hình — đang lấy theo hướng nhìn. Cánh ra sai phía thì bấm Tab để lật.  |  ESC=Chọn lại điểm 1"
        else
          "Click điểm 2: Chọn góc đối diện để dựng cánh tủ.  |  ESC=Chọn lại điểm 1"
        end
    end

    # Tab (chỉ ở bước điểm 2): lật phía lòng tủ — chỉ có tác dụng khi đang phải đoán theo hướng nhìn
    def onKeyDown(key, repeat, _flags, view)
      return false unless key == 9 && repeat == 1 && @state == 1
      @lat = !@lat
      update_preview
      view.invalidate
      false
    end

    # Mặt phẳng cánh ở bước điểm 2 (suy từ điểm 1 + con trỏ).
    # Giữ mặt cũ khi con trỏ gần đường chéo 45° để tránh nhấp nháy XZ/YZ.
    def door_plane
      return nil unless @pt1 && @ip2.valid?
      p2   = @ip2.position
      cand = CanhCNC.detect_plane(@pt1, p2, @ho)
      return nil if cand == :xy
      if @plane_lock && @plane_lock != cand
        d  = p2 - @pt1
        dx = d.dot(@ho).abs
        dy = d.dot(Z_AXIS.cross(@ho)).abs
        lo, hi = [dx, dy].minmax
        cand = @plane_lock if hi < 1.0e-9 || lo / hi > 0.8
      end
      @plane_lock = cand
      [@pt1, CanhCNC.phap_tuyen_mat(cand, @ho)]
    end

    def onLButtonDown(flags, x, y, view)
      if @state == 0
        @ip1.pick(view, x, y)
        if @ip1.valid?
          pt1 = LeHai::LaserSnap.snapped_point(@laser) || @ip1.position
          # Họ trục tủ quét quanh điểm 1, lùi 1mm về phía mắt cho khỏi đứng trên mặt tấm
          mat = view.camera.eye - pt1
          ho  = LeHai::HuongTu.ho_quanh(view.model, mat.length > 0 ? pt1.offset(mat, 1.0 / 25.4) : pt1)
          if ho
            @pt1        = pt1
            @ho         = ho
            @state      = 1
            @plane_lock = nil
            Sketchup.status_text = "Click điểm 2: Chọn góc đối diện để dựng cánh tủ.  |  ESC=Chọn lại điểm 1"
          else
            Sketchup.status_text = "Không nhận ra hướng tủ quanh điểm 1 — click đúng góc khoang tủ."
          end
        end
      else
        @ip2.pick(view, x, y, @ip1)
        if @ip2.valid?
          pt2 = LeHai::LaserSnap.snapped_point(@laser) || @ip2.position
          pt2 = project_to_door_plane(pt2)
          plane = @plane_lock || CanhCNC.detect_plane(@pt1, pt2, @ho)
          CanhCNC.process_geometry(@pt1, pt2, @params, @ho, view.camera.direction, plane, @lat)
          LeHai::LaserSnap.clear_cache!
          reset_to_pt1
          Sketchup.status_text = "Đã tạo cánh xong! Click điểm 1 để tiếp tục khoang mới..."
        end
      end
      view.invalidate
    end

    # ESC (và undo/đổi tool): đang chờ điểm 2 → quay lại chọn điểm 1;
    # đang ở điểm 1 → thoát tool
    def onCancel(reason, view)
      if @state == 1
        reset_to_pt1
        Sketchup.status_text = "Đã huỷ. Click điểm 1: Chọn góc bắt đầu của khoang tủ."
        view.invalidate
      else
        view.model.select_tool(nil)
      end
    end

    def reset_to_pt1
      @state      = 0
      @ip1.clear
      @ip2.clear
      @pt1        = nil
      @plane_lock = nil
      @preview    = nil
      @ho         = nil
      @lat        = false
    end

    # Chiếu điểm 2 về mặt phẳng cánh: click xuyên khoang trống trúng tấm hậu
    # hay đợt bên trong cũng không làm cánh chạy sâu vào thùng tủ
    def project_to_door_plane(pt2)
      plane = @plane_lock || CanhCNC.detect_plane(@pt1, pt2, @ho)
      return pt2 if plane == :xy
      CanhCNC.chieu(pt2, @pt1, CanhCNC.phap_tuyen_mat(plane, @ho))
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@pt1) if @pt1
      bb.add(@ip1.position) if @ip1.valid?
      bb.add(@ip2.position) if @ip2.valid?
      if @preview && @preview[:boxes]
        @preview[:boxes].each { |pts| pts.each { |pt| bb.add(pt) } }
      end
      LeHai::LaserSnap.add_extents(@laser, bb)
      bb
    rescue StandardError
      Geom::BoundingBox.new
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
        LeHai::LaserSnap.draw(view, @laser)
        return
      end

      # Trạng thái 1: đã có điểm 1, đang hover điểm 2
      return unless @pt1 && @ip2.valid?

      p1 = @pt1
      p2 = project_to_door_plane(LeHai::LaserSnap.snapped_point(@laser) || @ip2.position)
      plane = @plane_lock || CanhCNC.detect_plane(p1, p2, @ho)
      corners = CanhCNC.rect_corners(p1, p2, plane, @ho)

      if @preview && @preview[:boxes] && !@preview[:boxes].empty?
        # Khung khoang mờ nét đứt + các cánh ma 3D đúng khe hở/độ dày
        if corners
          view.line_width = 1
          view.line_stipple = "-"
          view.drawing_color = Sketchup::Color.new(170, 100, 255, 130)
          view.draw_polyline(corners + [corners.first])
          view.line_stipple = ""
        end
        view.line_width = 2
        view.drawing_color = purple
        @preview[:boxes].each do |pts|
          BOX_EDGES.each { |i, j| view.draw(GL_LINES, [pts[i], pts[j]]) }
        end
      elsif corners
        # Fallback: khung khoang như bản cũ — ĐỎ khi khe hở vượt khoang
        gap_error = @preview && [:gap_w, :gap_h].include?(@preview[:error])
        view.line_width = 3
        view.line_stipple = ""
        view.drawing_color = gap_error ? Sketchup::Color.new(230, 60, 60) : purple
        view.draw_polyline(corners + [corners.first])
      end

      # Marker cam đậm tại điểm 1 đã chốt (filled square)
      view.draw_points([p1], 16, 2, orange)

      # Crosshair xanh tại con trỏ + tia laser
      draw_crosshair_2d(view, green)
      @ip2.draw(view) if @ip2.display? && !LeHai::LaserSnap.snapped_point(@laser)
      LeHai::LaserSnap.draw(view, @laser)
    end
  end

  # ----------------------------------------------------------
  # ĐIỀU KHIỂN GIAO DIỆN DIALOG
  # ----------------------------------------------------------
  def self.show_dialog
    # Một bảng duy nhất (LUAT_NHA mục 2; soát 09/10: bấm nút lần nữa từng mở chồng thêm bảng)
    if @dlg&.visible?
      @dlg.bring_to_front
      return
    end
    @dlg = dialog = UI::HtmlDialog.new(
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
  def self.process_geometry(pt1, pt2, p, ho, nhin, plane, lat = false)
    model = Sketchup.active_model

    # Tính bằng CÙNG hàm với preview (tinh → door_layout) trong hệ cánh; tấm dựng thẳng trong hệ
    # cánh rồi xoay CẢ group vào chỗ → trục từng cánh theo cánh (tủ xiên ABF vẫn đọc đúng).
    layout = tinh(model, pt1, pt2, p, ho, nhin, plane, lat)
    dat = model.edit_transform.inverse * layout[:he] if layout[:he]

    case layout[:error]
    when :huong
      UI.messagebox("Không rõ phía nào là lòng tủ.\nNhìn chính diện mặt trước khoang tủ rồi vẽ lại.")
      return
    when :lech
      UI.messagebox("Hai hông khoang lệch #{layout[:lech].round(1)}° (không song song).\nTool không dựng cánh trên khoang lệch — sửa hông cho song song rồi vẽ lại.")
      return
    when :plane
      UI.messagebox("Plugin chỉ hỗ trợ vẽ cánh trên mặt đứng.\nCố gắng click 2 góc của mặt trước hoặc mặt hông khoang tủ.")
      return
    when :too_small
      UI.messagebox("Khoang quá nhỏ hoặc 2 điểm trùng nhau.\nKhoang phát hiện: #{layout[:total_w].round(1)}mm × #{layout[:total_h].round(1)}mm")
      return
    when :gap_h
      UI.messagebox("Khoảng hở dọc vượt quá chiều cao khoang!\nCần ≥ #{layout[:need].round(1)}mm, khoang chỉ #{layout[:total_h].round(1)}mm")
      return
    when :gap_w
      UI.messagebox("Khoảng hở ngang vượt quá chiều rộng khoang!\nCần ≥ #{layout[:need].round(1)}mm, khoang chỉ #{layout[:total_w].round(1)}mm")
      return
    end

    unless LeHai::HuongTu.cung?(dat)
      UI.messagebox("Đang vẽ trong một group bị Scale.\nThoát ra ngoài group đó rồi vẽ cánh.")
      return
    end

    model.start_operation('Tao canh CNC', true) # tên undo ASCII (LUAT_NHA mục 6)
    begin
      layout[:doors].each_with_index do |d, i|
        g = draw_one(model.active_entities, layout[:plane],
                     d[0], d[1], d[2], d[3], d[4], p[:day], "Canh_#{i + 1}")
        g.transform!(dat)
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
    raise "Không vẽ được mặt cánh #{name} (2 điểm trùng hoặc cánh quá mỏng)." unless face
    face.reverse! if face.normal.z < 0
    face.pushpull(height.mm)
    group
  end

  # ----------------------------------------------------------
  # GIAO DIỆN HTML CSS GỌN GÀNG
  # ----------------------------------------------------------
  def self.html_content
    theme_css = File.join(File.dirname(__FILE__), '..', 'shared', 'lehai_theme.css')
    theme = File.exist?(theme_css) ? File.read(theme_css, encoding: 'UTF-8') : ''
    <<~HTML
      <!DOCTYPE html>
      <html lang="vi">
      <head>
        <meta charset="UTF-8">
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>#{theme}
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-size: 13px; padding: 12px; overflow: hidden; }
          h3 { font-size: 14px; color: var(--lh-walnut); text-align: center; margin-bottom: 12px; }
          .row { display: flex; gap: 8px; margin-bottom: 8px; }
          .col { flex: 1; }
          label { display: block; margin-bottom: 3px; font-size: 11px; color: var(--lh-ink-soft); font-weight: bold; }
          select, input[type=number] { width: 100%; padding: 6px 8px; border: 1.5px solid var(--lh-line);
            border-radius: var(--lh-radius-sm); background: var(--lh-surface); color: var(--lh-ink);
            outline: none; font-family: inherit; }
          select:focus, input[type=number]:focus { border-color: var(--lh-amber);
            box-shadow: 0 0 0 3px rgba(180,83,9,.15); }
          .divider { height: 1px; background: var(--lh-line-2); margin: 10px 0; }
          button { display: block; width: 100%; padding: 10px;
            background: var(--lh-amber);
            color: #fff; border: none; border-radius: var(--lh-radius);
            font-size: 13px; font-weight: bold; cursor: pointer; margin-top: 8px; font-family: inherit; }
          button:hover { filter: brightness(1.06); }
          .credit { text-align: right; font-size: 10px; font-style: italic; color: var(--lh-muted); margin-top: 8px; letter-spacing: 0.5px; }
          .note { margin-top: 10px; font-size: 11px; color: var(--lh-amber-2); text-align: center; line-height: 1.5; }
        </style>
      </head>
      <body class="lh">
        <div class="lh-eyebrow" style="text-align:center">LeHai's Decor Tools</div>
        <h3>🚪 Thiết Lập Độ Hở Cánh CNC</h3>
        <div class="row">
          <div class="col">
            <label>Số cánh</label>
            <input type="number" id="so_canh" value="2" min="1" max="20" step="1" oninput="toggleGap()">
          </div>
          <div class="col">
            <label>Độ dày ván</label>
            <select id="day">
              <option value="9">9mm</option>
              <option value="17.5" selected>17,5mm</option>
              <option value="10">10mm AC</option>
              <option value="18">18mm AC</option>
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
        Hở TRÁI / PHẢI tính theo người đứng TRƯỚC mặt khoang nhìn vào — tủ quay hướng nào cũng vậy.
        Xem kĩ khung cánh xem trước rồi mới click điểm 2; thanh dưới báo "đang lấy theo hướng nhìn" thì bấm Tab để lật phía.</p>
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
