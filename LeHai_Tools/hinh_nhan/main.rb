# encoding: UTF-8
# Hình Nhân: dựng hình nhân khớp nối ĐÚNG KÍCH THƯỚC theo chiều cao + cân nặng, ở dáng
# một hoạt động (đứng nấu, với tủ trên, ngồi ghế/bàn, ngồi sofa, nằm giường) — để KIỂM
# CÔNG NĂNG tủ/bàn (mặt bếp so với khuỷu tay, tầm với tủ trên, khe gối dưới bàn…).
#
# Mọi con số nghiệp vụ (tỉ lệ Drillis & Contini, độ dày, góc khớp) nằm ở hinh_nhan.js —
# chạy trong hộp thoại và được test bằng Node (tests/hinh_nhan.test.cjs). File này CHỈ nhận
# lưới tam giác đã tính rồi dựng: mỗi khúc một group riêng (tránh SketchUp tự gộp mặt, xem
# sketchup-nen-tang.md mục 7), gom vào một component rồi để người dùng rê chuột đặt.
#
# Toolbar do LeHai_Tools/main.rb quản lý — file này chỉ expose create_cmd.
# CHƯA chạy trên SketchUp thật (dựng 24/09/2026).

require 'sketchup.rb'
require 'json'

module TK
  module HinhNhan

    PATH     = File.dirname(__FILE__).freeze
    MAU      = 'LeHai_HinhNhan'   # tên vật liệu + tên attribute dictionary
    MAU_RGB  = [236, 236, 232].freeze   # trắng ngà kiểu ma-nơ-canh — Khoa chọn 24/09 (ảnh mẫu bo tròn)

    # ── Hộp thoại ─────────────────────────────────────────────
    def self.show
      if @dlg&.visible? then @dlg.bring_to_front; return end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Hình Nhân',
        preferences_key: 'tk.hinhnhan.v2',   # đổi khoá: hộp thoại dài hơn từ bản 13 dáng
        width:           400, height: 960,
        min_width:       340, min_height: 600,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      # Nạp HTML cạnh file code (không theo hằng PATH) — sketchup-api.md mục 2.
      @dlg.set_file(File.join(File.dirname(__FILE__), 'hinh_nhan.html'))
      @dlg.add_action_callback('tao') { |_ctx, json| tao(json) }
      @dlg.show
    end

    def self.bao(ham, msg)
      @dlg&.execute_script("window.#{ham}(#{msg.to_json});")
    end
    private_class_method :bao

    # ── Dựng component từ toạ độ JS gửi sang ──────────────────
    def self.tao(json)
      data  = JSON.parse(json)
      model = Sketchup.active_model
      ten   = "Hinh nhan #{(data['cao'] / 10.0).round}cm #{data['nang'].round}kg #{data['key']}"
      # Tài liệu Trimble không nói definitions.add xử lý trùng tên thế nào → tự tránh trùng.
      goc_ten = ten
      i = 2
      while model.definitions[ten]
        ten = "#{goc_ten} ##{i}"
        i += 1
      end

      model.start_operation('Tao hinh nhan', true)
      begin
        defn = model.definitions.add(ten)
        mat  = vat_lieu(model)
        data['khoi'].each { |k| ve_khoi(defn.entities, k, mat) }
        # Ghi thông số vào component để sau này tra lại được (Entity Info không hiện, nhưng
        # attribute đi theo file).
        defn.set_attribute(MAU, 'cao_mm', data['cao'])
        defn.set_attribute(MAU, 'nang_kg', data['nang'])
        defn.set_attribute(MAU, 'dang', data['dang'])
        # Hai loại số tách riêng: CHUẨN (có nguồn, dùng thiết kế) và ƯỚC LƯỢNG theo dáng.
        defn.set_attribute(MAU, 'so_do_chuan_mm', JSON.generate(data['chuan'] || []))
        defn.set_attribute(MAU, 'uoc_luong_theo_dang_mm', JSON.generate(data['so']))
        model.commit_operation
      rescue => e
        model.abort_operation
        puts "[Hình Nhân] #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n") if e.backtrace
        bao('baoLoi', "Lỗi: #{e.message}")
        return
      end

      # Bộ đặt component của SketchUp tự lo bước undo đặt — người dùng rê chuột rồi bấm.
      model.place_component(defn)
      bao('baoXong', "Đã dựng #{data['dang']} (#{(data['cao'] / 10.0).round} cm). Bấm vào model để đặt; Esc để bỏ.")
    rescue => e
      puts "[Hình Nhân] #{e.class}: #{e.message}"
      bao('baoLoi', "Lỗi: #{e.message}")
    end

    def self.vat_lieu(model)
      return model.materials[MAU] if model.materials[MAU]
      m = model.materials.add(MAU)
      m.color = Sketchup::Color.new(*MAU_RGB)
      m
    end
    private_class_method :vat_lieu

    def self.diem(a)
      Geom::Point3d.new(a[0].to_f.mm, a[1].to_f.mm, a[2].to_f.mm)
    end
    private_class_method :diem

    # Một khúc = một group dựng từ LƯỚI tam giác do hinh_nhan.js tính sẵn (ống thuôn đầu tròn).
    # add_faces_from_mesh mặc định AUTO_SOFTEN | SMOOTH_SOFT_EDGES (tài liệu Trimble) → cạnh giữa
    # các tam giác tự làm mềm + mượt, nhìn ra khối bo tròn liền. Group riêng từng khúc để các
    # khúc gối lên nhau ở khớp mà không bị SketchUp gộp mặt (sketchup-nen-tang.md mục 7).
    def self.ve_khoi(ents, k, mat)
      luoi   = k['luoi']
      diem_l = luoi['diem']
      mat_l  = luoi['mat']
      mesh = Geom::PolygonMesh.new(diem_l.length, mat_l.length)
      diem_l.each { |q| mesh.add_point(diem(q)) }
      # JS đánh chỉ số từ 0; PolygonMesh đánh từ 1 (tài liệu Trimble).
      mat_l.each { |m| mesh.add_polygon(m.map { |i| i.to_i + 1 }) }

      g = ents.add_group
      g.name = k['ten'].to_s
      g.material = mat
      tra_ve = g.entities.add_faces_from_mesh(mesh)
      # 24/09 chạy thật: bản đầu tin giá trị trả về (tài liệu: số mặt tạo được) → báo 0 ở
      # khúc Thân. Chưa rõ là KHÔNG dựng được hay giá trị trả về khác tài liệu → không tin
      # nó nữa: ĐẾM mặt thật trong group, và in ra Console để lần sau biết đúng.
      so_mat = g.entities.grep(Sketchup::Face).length
      if so_mat.zero?
        puts "[Hình Nhân] #{k['ten']}: add_faces_from_mesh trả #{tra_ve.inspect}, 0 mặt → dựng từng tam giác"
        so_mat = dung_tung_mat(g.entities, diem_l, mat_l)
      elsif so_mat != mat_l.length
        puts "[Hình Nhân] #{k['ten']}: trả #{tra_ve.inspect}, #{so_mat} mặt / #{mat_l.length} tam giác"
      end
      raise "Không dựng được khúc #{k['ten']} (0 mặt, xem Ruby Console)." if so_mat.zero?
    end
    private_class_method :ve_khoi

    # Đường dự phòng: dựng từng tam giác bằng add_face (đã chạy thật ở bản khối 24/09), rồi
    # tự làm mềm + mượt mọi cạnh nằm giữa 2 mặt (tương đương AUTO_SOFTEN | SMOOTH_SOFT_EDGES).
    # add_face hỏng thì trả nil (tài liệu Trimble) — bỏ qua tam giác đó, đếm số dựng được.
    def self.dung_tung_mat(ents, diem_l, mat_l)
      pts = diem_l.map { |q| diem(q) }
      n = 0
      mat_l.each do |m|
        f = ents.add_face(m.map { |i| pts[i.to_i] })
        n += 1 if f
      end
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.faces.length == 2
        e.soft = true
        e.smooth = true
      end
      puts "[Hình Nhân] dựng từng mặt: #{n}/#{mat_l.length} tam giác"
      n
    end
    private_class_method :dung_tung_mat

    # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Hình Nhân') { TK::HinhNhan.show }
      cmd.tooltip         = 'Hình nhân kiểm công năng (cao/nặng + dáng hoạt động)'
      cmd.status_bar_text = 'Dựng hình nhân đúng kích thước ở dáng đứng nấu, với tủ, ngồi, nằm — để kiểm tủ có vừa người dùng không.'
      s16 = File.join(icons, 'hinh_nhan_16.png')
      s24 = File.join(icons, 'hinh_nhan_24.png')
      cmd.small_icon = s16 if File.exist?(s16)
      cmd.large_icon = s24 if File.exist?(s24)
      cmd
    end

  end
end
