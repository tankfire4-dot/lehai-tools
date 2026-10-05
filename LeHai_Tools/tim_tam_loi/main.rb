# encoding: UTF-8
# Tìm Tấm Lỗi: gõ board-index (số máy CNC báo lỗi) → tô sáng tấm đó trên cả
# bản NESTING (đỏ) lẫn TỦ 3D (xanh), zoom thẳng vào mặt tấm tủ 3D. Vẽ overlay
# nổi trên cùng nên dù tấm nằm sau tấm khác vẫn thấy. Tìm thì CHỈ ĐỌC.
# Khớp bằng thuộc tính ẩn ABF (is-board + board-index), không đọc tên.
#
# Sao ra gốc (Khoa 05/10): đang sáng mà bấm Tab → sao y hệt các tấm đó ra gốc
# toạ độ (một bậc Undo). Đây là chỗ DUY NHẤT tool này ghi vào model.
#
# Toolbar do LeHai_Tools/main.rb quản lý chung — file này chỉ expose create_cmd.

require 'sketchup.rb'
require File.join(File.dirname(__FILE__), '..', 'shared', 'soi_noi')

module TK
  module ABFFinder

    PATH      = File.dirname(__FILE__).freeze
    DICT      = 'ABF'.freeze
    NEST_HINT = '__ABF_Nesting'.freeze
    COLOR_NEST = Sketchup::Color.new(255, 40, 40)   # do  = tren nesting
    COLOR_CAB  = Sketchup::Color.new(30, 144, 255)  # xanh = tren tu 3D
    FILL_ALPHA = 95                                 # do trong suot mat to (0-255)
    BOX_WIDTH  = 7
    KHE_SAO_MM = 10                                 # khe giữa các bản sao, mm (Khoa chốt 05/10)
    DICT_SAO   = 'LeHai_TimTamLoi'.freeze           # dấu bản sao → lần tìm sau bỏ qua, khỏi sao chồng
    PHIM_TAB   = 9

    # ---- 1 ket qua khop: entity + 8 goc the gioi + thuoc nesting hay tu ----
    # world_t = biến đổi tích luỹ từ gốc model tới tấm; mat_cha = vật liệu group cha gần nhất
    # (tấm không tô riêng thì ăn màu cha) — hai thứ này dùng khi sao ra gốc
    Match = Struct.new(:entity, :corners, :in_nesting, :name, :board_index, :world_t, :mat_cha)

    # ── Thu thap: duyet ca model, tinh toa do that, gom cac board ──
    def self.collect_boards
      boards = []
      traverse(Sketchup.active_model.entities,
               Geom::Transformation.new, false, &lambda { |e, t, in_nest, mat|
                 m = board_match(e, t, in_nest, mat)
                 boards << m if m
               })
      boards
    end

    def self.traverse(entities, accum_t, in_nest, depth = 0, mat = nil, &blk)
      return if depth > 10
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.get_attribute(DICT_SAO, 'ban-sao')   # bản sao do tool đặt ở gốc: không tìm lại
        nm = e.name.to_s
        here_nest = in_nest || nm.include?(NEST_HINT)
        blk.call(e, accum_t, here_nest, mat)
        child_t = accum_t * e.transformation
        children = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
        traverse(children, child_t, here_nest, depth + 1, e.material || mat, &blk)
      end
    end

    # tra ve Match neu e la board co board-index, nguoc lai nil
    def self.board_match(e, accum_t, in_nest, mat_cha = nil)
      d = e.attribute_dictionary(DICT)
      return nil unless d
      return nil unless d['is-board'] == true
      idx = d['board-index']
      return nil if idx.nil?
      Match.new(e, world_corners(e, accum_t), in_nest, e.name.to_s, idx.to_i, accum_t * e.transformation, mat_cha)
    end

    # 8 goc bounding-box LOCAL doi sang toa do the gioi (om sat tam du bi xoay)
    def self.world_corners(e, accum_t)
      bb = e.bounds
      (0..7).map { |i| accum_t * bb.corner(i) }
    end

    # ── Loc board theo danh sach so → tra ve [hits, wanted, missing] ──
    def self.resolve(numbers)
      wanted = numbers.map(&:to_i).uniq
      hits   = collect_boards.select { |m| wanted.include?(m.board_index) }
      missing = wanted - hits.map(&:board_index).uniq
      [hits, wanted, missing]
    end

    # ── Tim theo danh sach board-index (mo tool moi) ──
    def self.find(numbers)
      hits, wanted, missing = resolve(numbers)
      if hits.empty?
        UI.messagebox("Không tìm thấy tấm nào có board-index: #{wanted.join(', ')}")
        return
      end
      Sketchup.active_model.select_tool(HighlightTool.new(hits, wanted, missing))
    end

    # ── Hop thoai nhap so ──
    def self.prompt
      res = UI.inputbox(
        ['Số tấm lỗi (board-index, cách nhau dấu phẩy):'],
        [''],
        'Tìm tấm lỗi'
      )
      return unless res # bam Cancel
      raw = res[0].to_s.scan(/\d+/)
      return UI.messagebox('Chưa nhập số nào.') if raw.empty?

      find(raw)
    end

    # ── Sao y hệt các tấm đang sáng ra gốc toạ độ (Khoa 05/10) ──────
    # Hàng 1 = tấm tủ 3D, hàng 2 = tấm nesting, mỗi hàng xếp theo số tấm tăng dần.
    # Đã có bản sao lượt trước ở gốc → lượt này lùi ra sau chúng theo trục xanh lá, không đè.
    # Chỉ TỊNH TIẾN, giữ nguyên hướng xoay → mặt khoan/phay/vân y bản gốc.
    # Bản sao dùng chung definition với bản gốc như Ctrl+C/Ctrl+V tay, chép đủ
    # tên/tag/vật liệu/thuộc tính (ABF nằm ở thuộc tính vỏ tấm). Trả mảng bản sao, lỗi → nil.
    def self.sao_ra_goc(matches)
      model = Sketchup.active_model
      unless (model.active_path || []).empty?
        UI.messagebox('Đang ở TRONG một group. Bấm Esc tới khi ra ngoài cùng rồi bấm Tab lại.')
        return nil
      end
      hangs = [matches.reject(&:in_nesting), matches.select(&:in_nesting)]
                .map { |h| h.sort_by(&:board_index) }.reject(&:empty?)
      cu = model.entities.to_a.select { |e| e.get_attribute(DICT_SAO, 'ban-sao') }
      y0 = cu.empty? ? 0.0 : cu.map { |e| hop_bao(e.definition.bounds, e.transformation)[1][1] }.max + KHE_SAO_MM.mm
      doi = xep_hang(hangs.map { |h| h.map { |m| hop_the_gioi(m) } }, KHE_SAO_MM.mm, y0)

      model.start_operation('Sao tam loi ra goc', true)
      begin
        bans = hangs.flatten.zip(doi.flatten(1)).map { |m, d| sao_mot(model, m, d) }
        model.commit_operation
        bans
      rescue => e
        model.abort_operation
        puts "[Tìm Tấm Lỗi] #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n") if e.backtrace
        UI.messagebox("Lỗi: #{e.message}")
        nil
      end
    end

    # Xếp hàng từ gốc: tấm đầu có góc nhỏ nhất hộp bao đặt đúng (0,0,0); tấm sau nối tiếp
    # theo trục đỏ, cách tấm trước `khe`; hàng sau lùi theo trục xanh lá, cách hàng trước `khe`
    # (hàng trước sâu bao nhiêu thì lùi bấy nhiêu + khe). Vào: mỗi hàng là mảng [lo, hi] hộp bao
    # thế giới; y0 = trục xanh lá bắt đầu hàng đầu (0 = sát gốc). Ra: độ dời [dx, dy, dz] cho
    # từng tấm. Đơn vị inch như SketchUp.
    def self.xep_hang(hangs, khe, y0 = 0.0)
      y = y0
      hangs.map do |hop|
        x = 0.0
        doi = hop.map do |lo, hi|
          d = [x - lo[0], y - lo[1], -lo[2]]
          x += hi[0] - lo[0] + khe            # chiều dài tấm theo trục đỏ + khe
          d
        end
        y += hop.map { |lo, hi| hi[1] - lo[1] }.max + khe   # bề sâu tấm sâu nhất hàng + khe
        doi
      end
    end

    # Hộp bao thế giới [lo, hi] của tấm: hộp bản gốc (definition) qua biến đổi tích luỹ.
    # Không lấy e.bounds: hộp đó theo hệ của cha, cha xoay thì phình to.
    def self.hop_the_gioi(m)
      hop_bao(m.entity.definition.bounds, m.world_t)
    end

    # 8 góc hộp `bb` qua biến đổi `t` → [lo, hi] thẳng trục
    def self.hop_bao(bb, t)
      pts = (0..7).map { |i| (t * bb.corner(i)).to_a }
      [(0..2).map { |k| pts.map { |p| p[k] }.min }, (0..2).map { |k| pts.map { |p| p[k] }.max }]
    end

    def self.sao_mot(model, m, d)
      e = m.entity
      t = Geom::Transformation.translation(Geom::Point3d.new(*d)) * m.world_t
      ban = model.entities.add_instance(e.definition, t)
      raise "Không sao được tấm #{m.board_index}" unless ban
      ban.name = e.name
      ban.layer = e.layer
      ban.material = e.material || m.mat_cha   # tấm ăn màu tủ → bản sao ở gốc mang màu đó (vật liệu ABF xếp sheet)
      (e.attribute_dictionaries || []).each do |dict|
        dict.keys.each { |k| ban.set_attribute(dict.name, k, dict[k]) }
      end
      ban.set_attribute(DICT_SAO, 'ban-sao', m.in_nesting ? 'nesting' : 'tu-3d')
      ban
    end

    # =========================================================
    #  TOOL ve khung sang + zoom (overlay, khong sua model)
    # =========================================================
    class HighlightTool
      BOTTOM = [[0, 1], [1, 3], [3, 2], [2, 0]].freeze
      TOP    = [[4, 5], [5, 7], [7, 6], [6, 4]].freeze
      SIDES  = [[0, 4], [1, 5], [2, 6], [3, 7]].freeze
      EDGES  = (BOTTOM + TOP + SIDES).freeze
      # 6 mat cua hop (to mau trong suot cho noi)
      FACES = [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4],
               [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]].freeze

      def initialize(matches, wanted, missing)
        @matches = matches
        @wanted  = wanted
        @missing = missing
        @bounds  = combined_bounds(zoom_matches)
      end

      # Uu tien zoom vao tam TU 3D (xanh); neu khong co thi lay tat ca
      def zoom_matches
        cab = @matches.reject(&:in_nesting)
        cab.empty? ? @matches : cab
      end

      def activate
        zoom_to_target
        update_status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def getExtents
        @bounds
      end

      BB_GOC = [0, 1, 3, 2, 4, 5, 7, 6].freeze   # BoundingBox#corner → thứ tự góc của SoiNoi

      def draw(view)
        # Soi nổi (shared/soi_noi.rb, 30/09): mờ phần còn lại + khối sáng nhẹ tấm liên quan; nét cũ vẽ sau nằm trên
        LeHai::SoiNoi.phu_mo(view)
        LeHai::SoiNoi.ve_khois(view, @matches.map { |m| [BB_GOC.map { |i| m.corners[i] }, m.in_nesting ? :do : :xanh] })
        @matches.each { |m| draw_box(view, m) }          # 3D: thay khi khong bi che
        @matches.each { |m| draw_screen_marker(view, m) } # 2D: luon noi tren cung
        draw_banner(view)
      end

      def onCancel(_reason, view)
        quit(view)
      end

      def onKeyDown(key, _rep, _flags, view)
        quit(view) if key == 27 # Esc
        if key == TK::ABFFinder::PHIM_TAB
          begin
            sao(view)
          rescue => e
            puts "[Tìm Tấm Lỗi] #{e.class}: #{e.message}"
            puts e.backtrace.first(5).join("\n") if e.backtrace
            UI.messagebox("Lỗi: #{e.message}")
          end
          return true
        end
        false
      end

      # Cho phep go so vao o do (VCB) goc duoi-phai de doi tam ngay
      def enableVCB?
        true
      end

      # Go so + Enter -> doi sang tam khac ma khong can Esc
      def onUserText(text, view)
        nums = text.to_s.scan(/\d+/)
        return if nums.empty?
        retarget(nums, view)
      end

      def getStatusText
        msg = "Sáng tấm: #{@wanted.join(', ')}  —  gõ số khác để đổi · Tab: sao ra gốc toạ độ · ESC để thoát"
        msg += "  |  KHÔNG thấy: #{@missing.join(', ')}" unless @missing.empty?
        msg
      end

      private

      # Tab: sao các tấm đang sáng ra gốc, chọn sẵn bản sao, thoát tool rồi phóng tới chúng
      def sao(view)
        bans = TK::ABFFinder.sao_ra_goc(@matches)
        return unless bans
        sel = view.model.selection
        sel.clear
        bans.each { |b| sel.add(b) }
        quit(view)
        view.zoom(sel)
        tu   = @matches.count { |m| !m.in_nesting }
        nest = @matches.count(&:in_nesting)
        msg  = "Đã sao ra gốc toạ độ: #{tu} tấm tủ 3D + #{nest} tấm nesting (đang chọn sẵn).\nCtrl+Z để hủy."
        msg += "\n\nKHÔNG thấy tấm: #{@missing.join(', ')}" unless @missing.empty?
        msg += "\n\nBản sao vẫn là tấm thật với ABF: XÓA bản sao trước khi nesting lại cả file hoặc chạy Check Chốt Sản Xuất."
        UI.messagebox(msg)
      end

      # Doi muc tieu sang board-index khac, cap nhat tool tai cho
      def retarget(numbers, view)
        hits, wanted, missing = TK::ABFFinder.resolve(numbers)
        if hits.empty?
          UI.messagebox("Không tìm thấy tấm nào có board-index: #{wanted.join(', ')}")
          return
        end
        @matches = hits
        @wanted  = wanted
        @missing = missing
        @bounds  = combined_bounds(zoom_matches)
        zoom_to_target
        update_status
        view.invalidate
      end

      def quit(view)
        view.model.select_tool(nil)
        view.invalidate
      end

      def update_status
        Sketchup.set_status_text(getStatusText, SB_PROMPT)
        Sketchup.set_status_text('Số tấm', SB_VCB_LABEL) # nhan o nhap VCB
      end

      def draw_box(view, match)
        base = match.in_nesting ? TK::ABFFinder::COLOR_NEST : TK::ABFFinder::COLOR_CAB
        c = match.corners
        draw_fill(view, c, base)
        draw_outline(view, c, base)
      end

      # to 6 mat bang mau trong suot -> tam sang han len
      def draw_fill(view, c, base)
        fill = Sketchup::Color.new(base.red, base.green, base.blue,
                                   TK::ABFFinder::FILL_ALPHA)
        view.drawing_color = fill
        FACES.each { |f| view.draw(GL_POLYGON, f.map { |i| c[i] }) }
      end

      def draw_outline(view, c, base)
        view.line_width = TK::ABFFinder::BOX_WIDTH
        view.drawing_color = base
        EDGES.each { |a, b| view.draw(GL_LINES, [c[a], c[b]]) }
      end

      # ---- Dau 2D: chieu mat lon cua tam len man hinh, LUON noi tren cung ----
      # Nho vay du tam nam sau tam khac, van thay duoc o dung vi tri.
      def draw_screen_marker(view, match)
        base = match.in_nesting ? TK::ABFFinder::COLOR_NEST : TK::ABFFinder::COLOR_CAB
        quad = big_face(match.corners, view.camera.eye)
        return unless in_front?(view, quad_center(match.corners, quad)) # bo qua tam sau lung camera
        spts = quad.map { |i| view.screen_coords(match.corners[i]) }
        view.drawing_color = Sketchup::Color.new(base.red, base.green, base.blue, 70)
        view.draw2d(GL_POLYGON, spts)
        LeHai::SoiNoi.but(view, base, 3)   # bút: nét khuất tự nhạt hơn (01/10)
        LeHai::SoiNoi.day2d(view, (quad + [quad.first]).map { |i| match.corners[i] })   # soi nổi: đoạn thấy liền, đoạn khuất đứt (30/09)
      end

      # 4 goc cua MAT LON gan camera nhat (mat lon = vuong goc voi chieu mong nhat)
      def big_face(c, eye)
        lx = (c[1] - c[0]).length
        ly = (c[2] - c[0]).length
        lz = (c[4] - c[0]).length
        faces = if lx <= ly && lx <= lz
                  [[0, 2, 6, 4], [1, 3, 7, 5]]
                elsif ly <= lx && ly <= lz
                  [[0, 1, 5, 4], [2, 3, 7, 6]]
                else
                  [[0, 1, 3, 2], [4, 5, 7, 6]]
                end
        faces.min_by { |f| quad_center(c, f).distance(eye) }
      end

      def quad_center(c, f)
        pts = f.map { |i| c[i] }
        n = pts.size.to_f
        Geom::Point3d.new(
          pts.sum(&:x) / n, pts.sum(&:y) / n, pts.sum(&:z) / n
        )
      end

      # diem co nam phia truoc camera khong (de tranh chieu 2D bi meo)
      def in_front?(view, pt)
        (pt - view.camera.eye).dot(view.camera.direction) > 0
      end

      # ---- Bang nhac noi goc tren-trai man hinh ----
      def draw_banner(view)
        line1 = "Đang sáng tấm: #{@wanted.join(', ')}"
        line2 = @missing.empty? ? 'Gõ số khác để đổi tấm  ·  Tab: sao ra gốc  ·  ESC để thoát' :
                "KHÔNG thấy: #{@missing.join(', ')}  ·  Gõ số / Tab sao / ESC"
        x = 18
        y = 18
        w = 26 + [line1.length, line2.length].max * 9
        draw_banner_bg(view, x, y, w)
        draw_banner_text(view, x, y, line1, line2)
      end

      def draw_banner_bg(view, x, y, w)
        h = 58
        pts = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
                .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = Sketchup::Color.new(18, 22, 30, 210)
        view.draw2d(GL_POLYGON, pts)
        # vach mau xanh ben trai cho noi
        bar = [[x, y], [x + 6, y], [x + 6, y + h], [x, y + h]]
                .map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = TK::ABFFinder::COLOR_CAB
        view.draw2d(GL_POLYGON, bar)
      end

      def draw_banner_text(view, x, y, line1, line2)
        white  = Sketchup::Color.new(255, 255, 255)
        yellow = Sketchup::Color.new(255, 210, 60)
        view.draw_text(Geom::Point3d.new(x + 16, y + 8, 0), line1,
                       color: white, font: 'Arial', size: 13, bold: true)
        view.draw_text(Geom::Point3d.new(x + 16, y + 32, 0), line2,
                       color: yellow, font: 'Arial', size: 11)
      end

      def combined_bounds(matches)
        bb = Geom::BoundingBox.new
        matches.each { |m| m.corners.each { |pt| bb.add(pt) } }
        bb
      end

      def zoom_to_target
        targets = zoom_matches
        if targets.size == 1
          aim_face_on(targets.first)   # 1 tam: nhin thang vao mat tam
        else
          frame_bounds                 # nhieu tam: lui ra om het
        end
        Sketchup.active_model.active_view.invalidate
      end

      # Ngam camera vuong goc mat lon cua tam, dat o phia camera dang dung
      def aim_face_on(match)
        cam    = Sketchup.active_model.active_view.camera
        c      = match.corners
        center = Geom::Point3d.linear_combination(0.5, c[0], 0.5, c[7]) # tam hop = trung diem 2 goc cheo
        ax     = face_axes(c)
        ndir   = outward_normal(ax[:normal], center, cam.eye)
        place_camera(cam, center, ndir, ax[:up], ax[:size])
      end

      # tra ve { normal: vec mong nhat, up: vec phang dung nhat, size: be ngang lon nhat }
      def face_axes(c)
        v = [c[1] - c[0], c[2] - c[0], c[4] - c[0]].sort_by(&:length)
        plane = [v[1], v[2]]
        { normal: v[0], up: plane.max_by { |w| w.z.abs },
          size: plane.map(&:length).max }
      end

      def outward_normal(normal, center, eye)
        n = normal.clone
        n.normalize!
        n.reverse! if n.dot(eye - center) < 0 # huong ve phia camera
        n
      end

      def place_camera(cam, center, ndir, up_vec, size)
        size = 100.0 if size < 1.0
        up = up_vec.clone
        up.normalize!
        up.reverse! if up.z < 0
        margin = 1.5
        if cam.perspective?
          fov  = cam.fov * Math::PI / 180.0
          dist = (size / 2.0) / Math.tan(fov / 2.0) * margin
          cam.set(center.offset(ndir, dist), center, up)
        else
          cam.set(center.offset(ndir, size * 3.0), center, up)
          cam.height = size * margin
        end
      end

      def frame_bounds
        cam  = Sketchup.active_model.active_view.camera
        ctr  = @bounds.center
        diag = @bounds.diagonal
        diag = 100.0 if diag < 1.0
        if cam.perspective?
          fov  = cam.fov * Math::PI / 180.0
          dist = (diag / 2.0) / Math.tan(fov / 2.0) * 1.3
          cam.set(ctr.offset(cam.direction.reverse, dist), ctr, cam.up)
        else
          cam.set(ctr.offset(cam.direction.reverse, diag * 3.0), ctr, cam.up)
          cam.height = diag * 1.3
        end
      end
    end

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Tìm tấm lỗi') { TK::ABFFinder.prompt }
      cmd.tooltip         = 'Tìm tấm lỗi theo board-index'
      cmd.status_bar_text = 'Gõ board-index (số máy CNC báo) để sáng & zoom tới tấm đó.'
      cmd.small_icon      = File.join(icons, 'tim_tam_loi_16.png')
      cmd.large_icon      = File.join(icons, 'tim_tam_loi_24.png')
      cmd
    end

  end
end
