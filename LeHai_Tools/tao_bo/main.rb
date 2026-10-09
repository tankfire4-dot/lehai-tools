# encoding: UTF-8
# TẠO BO (TK::TaoBo): trải phẳng cục bo thành tấm ván + vùng hạ nền. Thay module Hạ Nền cũ (bỏ 09/10, Khoa: đồ cũ sai)
# Cách dùng: bấm icon → bảng Tạo Bo mở → click vào cục 3D bo cong → chọn dài khúc bo → Tạo tấm
#
# 08/10/2026 làm lại theo mẫu Khoa đo từ plugin NTT (scratch/tao-bo/do_bo*.txt trong lab):
#   - Trải phẳng y như NTT: chiều dài = tổng các đoạn của chuỗi mặt nối trơn chứa khúc bo
#     (cung R50 20 đốt = 78,52 đúng số Entity Info ghi). Toán ở toan.rb, thử ngoài SketchUp:
#     node projects/lehai-tools/tests/tao_bo.test.mjs
#   - Vùng hạ nền = khúc bo (NTT lấn 13mm mỗi bên là sai). Khúc bo mặc định dài bằng cung; chọn được số
#     DƯỠNG BO (54, 81 — lưu thêm được) hoặc tự nhập: đoạn thẳng giữ nguyên, tổng tấm đổi theo. Lòi 3mm trên/dưới.
#   - Đủ dấu để ABF nhận: tấm mang ABF/is-board; vùng hạ nền mang is-intersect + setting-name +
#     b-id = persistent_id CỦA CHÍNH TẤM (NTT làm vậy) + tag ở cả MẶT (ABF lấy layer DXF từ tag mặt).
#   - Nhiều khúc bo (chữ U, chữ S) → mỗi khúc một vùng; khúc uốn ngược thì hạ nền mặt ngoài.

require 'sketchup.rb'
require 'json'
# `load` chứ không `require`: require chỉ nạp MỘT lần mỗi phiên SketchUp → `load main.rb` lại vẫn dùng toán CŨ
# (Khoa vấp 08/10: NoMethodError vung_theo_rong). Máy thợ nạp một lần nên hai cách như nhau.
load File.join(File.dirname(__FILE__), 'toan.rb')

module TK
  module TaoBo

    OVERHANG_MM  = 3.0                     # vùng hạ nền lòi ra ngoài mép tấm trên + dưới (như NTT)
    THICKNESS_MM = 17.5                    # bề dày ván theo setup NTT của xưởng
    CACH_MM      = 150.0                   # tấm mới đặt cách mặt cục ngần này, phía ngoài
    TAG_HN       = 'NTT_SoiHaNen'.freeze   # giữ đúng tên NTT → Aspire nhận layer như cũ
    INST_HN      = 'ABF_hanenduong'.freeze
    SETTING_HN   = 'ABF_hanenduong'.freeze # setting-name NTT ghi, đo 08/10
    MAT_HN       = 'LeHai_HaNen'.freeze
    TEN_TAM      = 'Tam Uon Cong'.freeze
    # Kiểu RÃNH LIỀN — giữ đúng tag/setting NTT (đo 08/10) để template Aspire hiện có nhận; đổi họ LEHAI_ ở bản sau
    TAG_RANH      = 'NTT_RanhUonCong'.freeze
    TAG_BAOVE     = 'NTT_RanhBaoVe'.freeze
    SETTING_RANH  = 'ABF_RanhUonCong'.freeze
    SETTING_BAOVE = 'ABF_RanhBaoVe'.freeze
    DAO_MM        = 6.0                    # mặc định theo preset NTT xưởng (DUONGLIENCUAQUAN): dao D 6 · thịt S 5 · biên X 3
    THIT_MM       = 5.0
    BIEN_MM       = 3.0
    PREF         = 'LeHai_TaoBo'.freeze
    # Dưỡng bo xưởng đang có (Khoa 08/10): khúc bo R34 uốn bằng dưỡng 54, R50 bằng dưỡng 81 (góc 90°).
    # 'r' = bán kính khúc bo dùng dưỡng này (nil = không gắn R), 'dai' = dài khúc bo trên tấm phẳng. Thêm/bớt trong bảng.
    DUONG_GOC    = [{ 'r' => 34.0, 'dai' => 54.0 }, { 'r' => 50.0, 'dai' => 81.0 }].freeze

    # ── Tool: rê chuột sáng cục, click để chọn ─────────────────
    class ChonCucTool
      def initialize
        @hovered = nil
      end

      def activate
        update_status(nil)
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.model.selection.clear
        view.invalidate
        TK::TaoBo.het_chon
      end

      def onCancel(_reason, view)
        view.model.selection.clear
        view.model.select_tool(nil)
      end

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked

        new_hov = (entity.is_a?(Sketchup::Group) ||
                   entity.is_a?(Sketchup::ComponentInstance)) ? entity : nil

        if new_hov != @hovered
          @hovered = new_hov
          sel = view.model.selection
          sel.clear
          sel.add(@hovered) if @hovered
          view.invalidate
        end
        update_status(@hovered)
      end

      def onLButtonDown(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked

        unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          Sketchup.set_status_text('Không phải group — rê chuột tới cục 3D bo cong rồi click')
          return
        end

        view.model.select_tool(nil)
        UI.start_timer(0, false) { TK::TaoBo.da_chon(entity) }
      end

      def getInstructorContentDirectory; nil; end

      private

      def update_status(hov)
        if hov
          Sketchup.set_status_text('✓ Click để chọn cục này | ESC: thôi')
        else
          Sketchup.set_status_text('Rê chuột tới cục 3D bo cong rồi click | ESC: thôi')
        end
      end
    end

    # ── Bảng Tạo Bo ────────────────────────────────────────────
    def self.run
      show
    end

    def self.show
      if @dlg&.visible?
        @dlg.bring_to_front
        bat_chon
        return
      end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Tạo Bo',
        preferences_key: 'lehai.taobo',
        width:           460, height: 780,
        min_width:       400, min_height: 520,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      # Nạp HTML cạnh file code (không theo hằng PATH) — sketchup-api.md mục 2.
      @dlg.set_file(File.join(File.dirname(__FILE__), 'tao_bo.html'))
      @dlg.add_action_callback('ready')     { gui_trang_thai }
      @dlg.add_action_callback('chon')      { bat_chon }
      @dlg.add_action_callback('tao')       { |_c, json| tao(json) }
      @dlg.add_action_callback('luu_duong') { |_c, json| luu_duong(json) }
      @dlg.set_on_closed { Sketchup.active_model.select_tool(nil) if @dang_chon }
      @dlg.show
      bat_chon
    end

    def self.bat_chon
      @dang_chon = true
      Sketchup.active_model.select_tool(ChonCucTool.new)
      bao('dangChon', true)
    end

    def self.het_chon
      @dang_chon = false
      bao('dangChon', false)
    end

    # Click trúng cục: đo ngay để bảng vẽ hình tấm trải phẳng; lúc Tạo sẽ đo LẠI (cục có thể đã sửa).
    def self.da_chon(entity)
      @cuc = entity
      model = Sketchup.active_model
      model.selection.clear
      model.selection.add(entity)
      gui_trang_thai
    end

    def self.gui_trang_thai
      cuc = nil
      if @cuc && !@cuc.deleted?
        kq = do_cuc(@cuc, THICKNESS_MM, OVERHANG_MM)
        ten = @cuc.name.to_s.empty? ? @cuc.definition.name : @cuc.name
        cuc = if kq[:ok]
                { 'ten' => ten, 'ok' => true, 'dai' => kq[:dai], 'cao' => kq[:cao], 'doan' => kq[:doan],
                  'vung' => kq[:vung].map { |v| { 's0' => v[:s0], 's1' => v[:s1], 'loi' => v[:loi], 'r' => v[:r], 'goc' => v[:goc] } } }
              else
                { 'ten' => ten, 'ok' => false, 'loi' => kq[:loi] }
              end
      end
      bao('nhan', { 'cuc' => cuc, 'duong' => doc_duong, 'day' => THICKNESS_MM, 'loi_ra' => OVERHANG_MM,
                    'dao' => DAO_MM, 'thit' => THIT_MM, 'bien' => BIEN_MM, 'dang_chon' => @dang_chon ? true : false })
    end

    # Hạ nền:    {'kieu' => 'ha_nen', 'day', 'loi_ra', 'rong' => [mm khúc bo theo dưỡng / cung / tự nhập]}
    # Rãnh liền: {'kieu' => 'ranh', 'day', 'dao', 'thit', 'bien', 'bu' => [mm cộng vào từng khúc]}
    def self.tao(json)
      d = JSON.parse(json.to_s)
      return bao('baoLoi', 'Chưa chọn cục, hoặc cục đã bị xoá — bấm Chọn cục.') if @cuc.nil? || @cuc.deleted?
      ranh = d['kieu'] == 'ranh'
      day = d['day'].to_f
      return bao('baoLoi', 'Độ dày phải từ 1 tới 100 mm.') unless day >= 1 && day <= 100
      loi_ra = ranh ? d['bien'].to_f : d['loi_ra'].to_f # rãnh liền: rãnh lòi ra ngoài mép đúng bằng "mở rộng biên" X
      return bao('baoLoi', 'Lòi trên/dưới (mở rộng biên) phải từ 0 tới 50 mm.') unless loi_ra >= 0 && loi_ra <= 50
      kq = do_cuc(@cuc, day, loi_ra)
      return bao('baoLoi', kq[:loi]) unless kq[:ok]
      if ranh
        dao = d['dao'].to_f
        return bao('baoLoi', 'Đường kính dao phải từ 1 tới 30 mm.') unless dao >= 1 && dao <= 30
        rl = Toan.ranh_lien(kq, d: dao, s: d['thit'].to_f, x: loi_ra, bu: (d['bu'] || []).map(&:to_f))
        return bao('baoLoi', rl[:loi]) unless rl[:ok]
        kq = kq.merge(dai: rl[:dai])
        vung = rl[:khuc]
      else
        rv = Toan.vung_theo_rong(kq, (d['rong'] || []).map(&:to_f))
        return bao('baoLoi', rv[:loi]) unless rv[:ok]
        kq = kq.merge(dai: rv[:dai]) # tổng tấm theo khúc bo đã chọn
        vung = rv[:vung]
      end

      model = Sketchup.active_model
      tam = dung_tam(model, kq, vung, ranh ? :ranh : :ha_nen)
      model.selection.clear
      model.selection.add(tam)
      dong = vung.each_with_index.map do |v, i|
        them = ranh ? ", #{v[:xs].size} rãnh" : ''
        "khúc #{i + 1}: #{so(v[:s0])} → #{so(v[:s1])} (dài #{so(v[:s1] - v[:s0])}#{them})"
      end
      puts "==== LeHai Tạo Bo: tấm #{so(kq[:dai])} × #{so(kq[:cao])} × #{so(day)} · #{dong.join(' · ')}"
      bao('baoXong', "✓ Đã tạo tấm #{so(kq[:dai])} × #{so(kq[:cao])} × #{so(day)} mm — #{dong.join('; ')}. Ctrl+Z để huỷ.")
    rescue => e
      puts "[Tạo Bo] Lỗi: #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n") if e.backtrace
      bao('baoLoi', "Lỗi: #{e.message}")
    end

    # ── Dưỡng bo lưu theo máy (registry SketchUp; đổi bản SketchUp là về mặc định R34→54, R50→81) ──
    # Lưu dạng [{'r' => mm | nil, 'dai' => mm}]. Bản thử đầu lưu mảng số trơn → đọc thành dưỡng không gắn R.
    def self.doc_duong
      ds = JSON.parse(Sketchup.read_default(PREF, 'duong_r', '').to_s)
      return DUONG_GOC.map(&:dup) unless ds.is_a?(Array)
      chuan_duong(ds)
    rescue JSON::ParserError
      DUONG_GOC.map(&:dup) # nuốt được: chưa lưu lần nào (chuỗi rỗng) hoặc hỏng → dùng mặc định xưởng
    end

    def self.chuan_duong(ds)
      ds.map { |x| x.is_a?(Hash) ? { 'r' => x['r'] && x['r'].to_f, 'dai' => x['dai'].to_f } : { 'r' => nil, 'dai' => x.to_f } }
        .select { |x| x['dai'] > 0 && x['dai'] < 2000 && (x['r'].nil? || x['r'] > 0) }
        .map { |x| { 'r' => x['r'] && x['r'].round(2), 'dai' => x['dai'].round(2) } }
        .uniq.sort_by { |x| [x['r'] || 1e9, x['dai']] }.first(12)
    end

    def self.luu_duong(json)
      Sketchup.write_default(PREF, 'duong_r', chuan_duong(JSON.parse(json.to_s)).to_json)
      gui_trang_thai
    rescue => e
      bao('baoLoi', "Lỗi lưu dưỡng: #{e.message}")
    end

    def self.bao(ham, msg)
      @dlg&.execute_script("window.#{ham}(#{msg.to_json});") if @dlg&.visible?
    end

    def self.so(x)
      x.round(2).to_s.sub(/\.0\z/, '').tr('.', ',')
    end

    # Đo mặt cắt của cục (toạ độ cùng ngữ cảnh với cục) rồi giao cho lõi toán.
    def self.do_cuc(entity, day, loi_ra)
      tr   = entity.transformation
      ents = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
      faces = ents.grep(Sketchup::Face)
      if faces.empty?
        return { ok: false, loi: 'Cục không có mặt nào nằm ngay bên trong (hình nằm trong group con?). ' \
                                 'Chọn đúng group chứa trực tiếp hình cục bo.' }
      end
      # mặt cắt = mặt nhiều đỉnh nhất (mặt trên/dưới của khối đùn — mẫu NTT: 24 đỉnh, các mặt hông 4)
      cap = faces.max_by { |f| f.outer_loop.vertices.size }
      vs  = cap.outer_loop.vertices
      mm  = ->(v) { q = tr * v.position; [q.x.to_mm, q.y.to_mm, q.z.to_mm] }
      khoa = vs.each_index.map do |i|
        a = vs[i]
        b = vs[(i + 1) % vs.size]
        e = cap.edges.find { |x| (x.start == a && x.end == b) || (x.start == b && x.end == a) }
        e && e.curve ? e.curve.entityID : nil
      end
      moi_dinh = ents.grep(Sketchup::Edge).flat_map { |e| [e.start, e.end] }.uniq.map { |v| mm.(v) }
      Toan.phan_tich(vs.map { |v| mm.(v) }, khoa, moi_dinh, day: day, cach: CACH_MM, loi_ra: loi_ra)
    end

    # Dựng tấm thẳng trong hệ riêng (x = chiều trải, y = chiều cao, z = bề dày; z = 0 là mặt áp cục)
    # rồi xoay cả group vào chỗ (LUAT_NHA mục 9). kieu :ha_nen | :ranh. Một bước Ctrl+Z.
    def self.dung_tam(model, kq, vung, kieu)
      tag = nil
      tag = model.layers.to_a.find { |l| l.name == TAG_HN } || model.layers.add(TAG_HN) if kieu == :ha_nen
      mat = model.materials[MAT_HN]
      l = kq[:dai].mm
      h = kq[:cao].mm
      t = kq[:day].mm
      o = kq[:loi_ra].mm
      diem = ->(x, y, z) { Geom::Point3d.new(x, y, z) }

      model.start_operation('LeHai: Tao Bo', true)
      begin
        if kieu == :ha_nen && !mat
          mat = model.materials.add(MAT_HN)
          mat.color = Sketchup::Color.new(210, 140, 70)
        end
        tam = model.active_entities.add_group
        tam.name = TEN_TAM
        mat_tam = tam.entities.add_face(diem.(0, 0, 0), diem.(l, 0, 0), diem.(l, h, 0), diem.(0, h, 0))
        raise 'Không vẽ được mặt tấm.' unless mat_tam
        mat_tam.reverse! if mat_tam.normal.z < 0 # mặt ở z = 0 SketchUp hay úp xuống → lật lên rồi đùn +z
        mat_tam.pushpull(t)
        tam.transformation = Geom::Transformation.axes(
          diem.(*kq[:goc].map(&:mm)),
          Geom::Vector3d.new(*kq[:truc_x]), Geom::Vector3d.new(*kq[:truc_y]), Geom::Vector3d.new(*kq[:truc_z])
        )
        tam.set_attribute('ABF', 'is-board', true) # thiếu cái này ABF không coi là ván (sketchup-api.md 17/09)
        tam.set_attribute('ABF', 'label-rotation', 0)
        b_id = tam.persistent_id

        ve_ranh(model, tam, kq, vung, b_id) if kieu == :ranh
        (kieu == :ha_nen ? vung : []).each_with_index do |v, i|
          z = v[:loi] ? 0 : t # khúc lồi: hạ nền mặt áp cục; khúc uốn ngược: mặt ngoài
          x0 = v[:s0].mm
          x1 = v[:s1].mm
          dau = tam.entities.add_group
          dau.name = INST_HN
          dau.layer = tag
          f = dau.entities.add_face(diem.(x0, -o, z), diem.(x1, -o, z), diem.(x1, h + o, z), diem.(x0, h + o, z))
          raise "Không vẽ được vùng hạ nền #{i + 1}." unless f
          # pháp tuyến quay VÀO thân tấm như dấu NTT (đo 08/10: mặt áp cục, pháp tuyến hướng vào ván)
          f.reverse! if v[:loi] ? f.normal.z < 0 : f.normal.z > 0
          f.layer = tag # ABF đặt layer DXF theo tag MẶT
          f.material = mat
          f.back_material = mat
          dau.entities.grep(Sketchup::Edge).each { |e| e.layer = tag }
          dau.set_attribute('ABF', 'is-intersect', true)
          dau.set_attribute('ABF', 'intersect-offset', 0.0)
          dau.set_attribute('ABF', 'setting-name', SETTING_HN)
          dau.set_attribute('ABF', 'intersect-group-b-id', b_id)
        end
        model.commit_operation
      rescue => e
        model.abort_operation
        raise e
      end
      tam
    end

    # Rãnh liền (giống NTT, đo 08/10): MỘT đường dao zíc-zắc liền (add_curve → các nét "thuộc đường cong" như NTT):
    # lên rãnh 1, sang ngang ngoài mép, xuống rãnh 2… · 2 nét bảo vệ ngang ở mép trên + dưới (y = −X và cao + X).
    # Chỉ có NÉT, không mặt (NTT cũng vậy). Nằm ở mặt áp cục (z = 0); khúc uốn ngược thì mặt ngoài (z = dày).
    # Gọi BÊN TRONG thao tác của dung_tam — lỗi thì raise để huỷ cả lượt.
    def self.ve_ranh(model, tam, kq, khuc, b_id)
      tag_r = model.layers.to_a.find { |l| l.name == TAG_RANH } || model.layers.add(TAG_RANH)
      tag_b = model.layers.to_a.find { |l| l.name == TAG_BAOVE } || model.layers.add(TAG_BAOVE)
      h = kq[:cao].mm
      o = kq[:loi_ra].mm
      dau_abf = lambda do |g, setting|
        g.set_attribute('ABF', 'is-intersect', true)
        g.set_attribute('ABF', 'intersect-offset', 0.0)
        g.set_attribute('ABF', 'setting-name', setting)
        g.set_attribute('ABF', 'intersect-group-b-id', b_id)
      end
      khuc.each_with_index do |c, i|
        z = c[:loi] ? 0 : kq[:day].mm
        lo = -o
        hi = h + o
        pts = []
        c[:xs].each_with_index do |x, k|
          a, b = k.even? ? [lo, hi] : [hi, lo] # rãnh chẵn đi lên, lẻ đi xuống → nét nối luân phiên trên/dưới
          pts << Geom::Point3d.new(x.mm, a, z) << Geom::Point3d.new(x.mm, b, z)
        end
        g = tam.entities.add_group
        g.name = 'ABF_RanhUonCong'
        g.layer = tag_r
        canh = g.entities.add_curve(pts)
        # tài liệu hãng không hứa gì về nil / gộp cạnh → đếm lại: n rãnh = n nét dọc + (n − 1) nét nối
        so_canh = g.entities.grep(Sketchup::Edge).size
        unless canh && so_canh == 2 * c[:xs].size - 1
          raise "Khúc #{i + 1}: vẽ rãnh ra #{so_canh} nét, cần #{2 * c[:xs].size - 1}."
        end
        g.entities.grep(Sketchup::Edge).each { |e| e.layer = tag_r }
        dau_abf.(g, SETTING_RANH)

        bv = tam.entities.add_group
        bv.name = 'ABF_RanhBaoVe'
        bv.layer = tag_b
        [lo, hi].each do |y|
          e = bv.entities.add_line(Geom::Point3d.new(c[:b0].mm, y, z), Geom::Point3d.new(c[:b1].mm, y, z))
          raise "Khúc #{i + 1}: không vẽ được nét bảo vệ." unless e
          e.layer = tag_b
        end
        dau_abf.(bv, SETTING_BAOVE)
      end
    end

    def self.create_cmd
      icons_dir = File.dirname(__FILE__)
      cmd = UI::Command.new('Tạo Bo') { TK::TaoBo.show }
      cmd.tooltip         = 'Tạo Bo: trải phẳng cục bo cong thành tấm + vùng hạ nền'
      cmd.status_bar_text = 'Mở bảng Tạo Bo → click cục bo cong → chỉnh vùng hạ nền (bằng cung / dưỡng / tự nhập) → Tạo tấm'
      cmd.small_icon      = File.join(icons_dir, 'icons', 'tao_bo_16.png')
      cmd.large_icon      = File.join(icons_dir, 'icons', 'tao_bo_24.png')
      cmd
    end

  end
end
