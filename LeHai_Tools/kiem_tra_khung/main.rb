# encoding: UTF-8
# Soát Khung Tổng Thể (Khoa đặt hàng 30/09/2026).
# Công ty giao tủ Dài × Sâu × Cao → người vẽ nhập số → plugin dựng KHUNG CHUẨN (hộp dây) → đặt vào
# góc tủ → soát mọi tấm có TÂM nằm trong khung: tủ có lấp đúng khung không, tấm nào hở lẻ / lệch
# mép / bay / xéo / méo, chỗ nào ăn vào nhau. So TOẠ ĐỘ chứ không bắn tia: bắt được lệch 0,05 mm
# và thấy cả tấm bị che. Toán nằm ở phan_tich.rb (thuần Ruby, thử được ngoài SketchUp).
#
# Chỉ SỬA model ở 3 chỗ: tạo khung, xoá khung, ghi danh sách "bỏ qua" vào khung. Không đụng tấm ván.
# Khung là component chỉ có CẠNH (không mặt) → ABF và các check khác không coi là tấm.
# Chạy từ dashboard Check Chốt Sản Xuất (không có nút riêng).

require 'sketchup.rb'
require 'json'
require File.join(File.dirname(__FILE__), 'phan_tich')
require File.join(File.dirname(__FILE__), '..', 'shared', 'soi_noi')

module TK
  module FrameCheck

    PATH      = File.dirname(__FILE__).freeze
    MM        = 25.4
    DICT      = 'LH_KHUNG'.freeze            # attribute trên definition khung (dai/sau/cao) + instance (bo_qua)
    NEST_HINT = '__ABF_Nesting'.freeze
    ABF_RE    = /\A_+ABF/.freeze               # dấu ABF (_ABF_Intersect, _ABF_hingeCup...) không phải tấm
    # Bộ phận DI ĐỘNG (cánh, hộc kéo): khe quanh nó là cố ý → vàng; không đỡ được thân tủ.
    # Tên tấm có chữ cánh / hộc / ngăn kéo (cùng gốc NAME_RE + DRAWER_RE của kiem_tra_ban_le).
    # 30/09 Khoa thử thật: tấm tên "229. Hộc 1 · mặt phủ" lọt vì bản đầu chỉ nhận "hộc kéo"/"mặt hộc"
    # → cả bộ hộc bị báo "tủ đứt". "hộc" đứng riêng thành chữ (không dính chữ cái trước/sau).
    CUA_RE    = /c[aá]nh|(?<!\p{L})h[oôộ]c(?!\p{L})|ng[aă]n\s*k[eé]o/i.freeze
    # Group CHA tên bắt đầu bằng Cánh/Hộc ("Hộc 1" chứa "hông trái", "đáy"...) → mọi tấm bên trong
    # là di động. Chỉ nhận khi tên BẮT ĐẦU bằng chữ đó: group vỏ "Tủ hộc kéo" không bị tính.
    CHA_DD_RE = /\A[\d.\s·_-]*(c[aá]nh|h[oôộ]c(?!\p{L})|ng[aă]n\s*k[eé]o)/i.freeze

    # Nhận diện TẤM (mm, sau scale): chiều mỏng nhất 2–60, chiều giữa ≥ 20. Ngoài khoảng này
    # (ốc, bản lề 3D, tay nắm, khối đặc) không soát.
    DAY_MIN  = 2.0
    DAY_MAX  = 60.0
    CANH_MIN = 20.0

    GOC8   = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].freeze
    CANH12 = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].freeze

    PT = PhanTich

    # ── Dialog ─────────────────────────────────────────────────
    def self.show
      if @dlg&.visible?
        @dlg.bring_to_front
        gui_ket_qua
        return
      end
      @dlg = UI::HtmlDialog.new(
        dialog_title:    'Soát Khung Tổng Thể',
        preferences_key: 'tk.kiemtrakhung',
        width:           460, height: 720,
        min_width:       380, min_height: 420,
        resizable:       true,
        style:           UI::HtmlDialog::STYLE_DIALOG
      )
      # Nạp HTML cạnh file code (không theo hằng PATH) — sketchup-api.md mục 2.
      @dlg.set_file(File.join(File.dirname(__FILE__), 'khung.html'))
      @dlg.add_action_callback('ready')   { gui_ket_qua }
      @dlg.add_action_callback('soat')    { gui_ket_qua }
      @dlg.add_action_callback('tao')     { |_c, json| tao(json) }
      @dlg.add_action_callback('xem')     { |_c, duong| xem(duong) }
      @dlg.add_action_callback('bo_qua')  { |_c, json| bo_qua(json) }
      @dlg.add_action_callback('hien_lai') { |_c, i| hien_lai(i.to_i) }
      @dlg.add_action_callback('chon')    { |_c, i| chon(i.to_i) }
      @dlg.add_action_callback('xoa')     { |_c, i| xoa(i.to_i) }
      @dlg.show
    end

    def self.bao(ham, msg)
      @dlg&.execute_script("window.#{ham}(#{msg.to_json});")
    end
    private_class_method :bao

    # ── Adapter cho dashboard Check Chốt Sản Xuất (TK::PreExportCheck) ──
    def self.audit
      ds = quet
      if ds.empty?
        return { status: :na, count: 0,
                 message: 'Chưa đặt khung — bấm Xem, nhập Dài × Sâu × Cao công ty giao rồi đặt khung vào tủ.' }
      end
      do_  = ds.sum { |x| x[:kq]['ds'].count { |f| f['muc'] == 'do' } }
      vang = ds.sum { |x| x[:kq]['ds'].count { |f| f['muc'] == 'vang' } }
      so   = ds.sum { |x| x[:kq]['so_tam'] }
      kh   = ds.size > 1 ? "#{ds.size} khung · " : ''
      them = vang > 0 ? " · #{vang} nhóm vàng nên xem" : ''
      return { status: :fail, count: do_, message: "#{kh}#{do_} lỗi đỏ (lệch/hở/bay/lồi khung)#{them}." } if do_ > 0
      return { status: :warn, count: vang, message: "#{kh}Không lỗi đỏ; #{vang} nhóm vàng (khe cánh, ngàm...) nên xem qua." } if vang > 0
      { status: :pass, count: 0, message: "#{kh}Tủ lấp đúng khung, không lệch/hở/bay (đã soi #{so} tấm)." }
    end

    def self.review
      show
    end

    # =========================================================
    #  QUÉT — chỉ đọc
    # =========================================================
    # Trả mỗi khung: { khung:, he:, tams: {id => tấm}, kq: (PhanTich.soat) }
    def self.quet
      tams = []
      khungs = []
      # Lượt nhẹ: chỉ tìm khung. Chưa có khung thì thôi — dashboard mở ra không phải đo hình cả file
      # (soát chéo 30/09 điểm 7). Có khung mới duyệt lại đo tấm.
      duyet(Sketchup.active_model.entities, Geom::Transformation.new, 0, [], khungs, false, '', true)
      return [] if khungs.empty?
      khungs = []
      duyet(Sketchup.active_model.entities, Geom::Transformation.new, 0, tams, khungs)
      khungs.map do |k|
        h = he_khung(k)
        ts = tam_trong(h, tams)
        kq = PT.soat(h[:kich], ts, doc_bo_qua(k[:e]))
        if ts.empty?
          kq['ds'] << PT.moi('do', 'rong', 'Khung không chứa tấm nào',
                             'Khung đặt lệch khỏi tủ? Bấm Chọn rồi dời khung vào góc tủ.', [],
                             h[:kich].map { |x| x / 2.0 }, 0, 'rong')
        end
        ids = ts.map { |t| t[:id] }
        { khung: k, he: h, tams: tams.select { |t| ids.include?(t[:id]) }.map { |t| [t[:id], t] }.to_h, kq: kq }
      end
    end

    # Duyệt model: gom KHUNG + TẤM (toạ độ thế giới). te = biến đổi dồn từ gốc model.
    # duong = chuỗi persistent_id các group/component cha → mã tấm DUY NHẤT: hai tủ dùng chung một
    # component thì tấm bên trong là CÙNG một entity (soát chéo 30/09 điểm 2: trùng id → Xem chỉ nhầm tủ,
    # khoá Bỏ qua dính cả hai). chi_khung = chỉ tìm khung, không đo tấm.
    def self.duyet(ents, t, sau, tams, khungs, di_dong = false, duong = '', chi_khung = false)
      return if sau > 40
      ents.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.deleted?
        te = t * e.transformation
        if khung?(e)
          khungs << { e: e, te: te }
          next
        end
        ten = e.name.to_s
        next if ten.include?(NEST_HINT) || ten =~ ABF_RE   # bản trải nesting + dấu ABF: không phải tấm 3D
        con = ents_of(e)
        next unless con
        dd = di_dong || !(nhan(e) =~ CHA_DD_RE).nil?
        ma = "#{duong}#{e.persistent_id}"
        unless chi_khung
          mat = con.grep(Sketchup::Face)
          dang_ky(e, te, mat, tams, dd, ma) unless mat.empty?
        end
        duyet(con, te, sau + 1, tams, khungs, dd, "#{ma}/", chi_khung)
      end
    end

    def self.khung?(e)
      e.is_a?(Sketchup::ComponentInstance) && !e.definition.get_attribute(DICT, 'dai').nil?
    end

    def self.ents_of(e)
      if e.is_a?(Sketchup::Group)                then e.entities
      elsif e.is_a?(Sketchup::ComponentInstance) then e.definition.entities
      end
    end

    # Ghi một tấm: 8 góc thế giới từ hộp bao LOCAL của mặt (không dùng bounds thế giới — tấm
    # xoay thì hộp thế giới phình ra, sketchup-nen-tang mục 3a) + đo hình (méo / cong).
    def self.dang_ky(e, te, mat, tams, di_dong = false, ma = nil)
      bb = Geom::BoundingBox.new
      mat.each { |f| bb.add(f.bounds) }
      return if bb.empty?
      mn = bb.min
      mx = bb.max
      lo = [mn.x, mn.y, mn.z]
      hi = [mx.x, mx.y, mx.z]
      goc = GOC8.map { |cx, cy, cz| te * Geom::Point3d.new(cx.zero? ? lo[0] : hi[0], cy.zero? ? lo[1] : hi[1], cz.zero? ? lo[2] : hi[2]) }
      canh = [goc[1] - goc[0], goc[3] - goc[0], goc[4] - goc[0]]   # 3 cạnh thế giới (inch)
      dai = canh.map { |v| v.length * MM }                       # mm thật (đã nhân scale)
      s = dai.sort
      return unless s[0] >= DAY_MIN && s[0] <= DAY_MAX && s[1] >= CANH_MIN
      # mm thế giới trên 1 inch local, theo từng trục local (tấm bị Scale thì khác 25,4)
      he = (0..2).map { |k| (hi[k] - lo[k]) > 1e-9 ? dai[k] / (hi[k] - lo[k]) : MM }
      meo, la = do_hinh(mat, lo, hi, he)
      ten = nhan(e)
      tams << { e: e, id: ma || e.persistent_id.to_s, ten: ten, goc: goc, canh: canh,
                cua: di_dong || !(ten =~ CUA_RE).nil?, meo_mm: meo, hinh_la: la }
    end

    # Hình tấm trong hệ RIÊNG: mọi mặt phải vuông trục và nằm đúng trên 6 mặt hộp bao.
    #   mặt vuông trục nhưng cách mặt hộp 0,05–3 mm   → MÉO (đỏ): tấm bị kéo lệch một chút
    #   mặt nghiêng nhẹ 0,01°–3°                      → MÉO (đỏ): đo độ lệch đỉnh ra mm
    #   mặt nghiêng ≥ 3° / mặt nằm sâu trong hộp ≥ 3mm → HÌNH LẠ (vàng): cong, vát, khoét cố ý
    # Mặt bị chẻ nhỏ (intersect) vẫn nằm trên mặt hộp → không báo.
    def self.do_hinh(mat, lo, hi, he)
      meo = 0.0
      la = false
      mat.each do |f|
        n = f.normal
        nv = [n.x.abs, n.y.abs, n.z.abs]
        k = nv.index(nv.max)
        goc = Math.acos([nv.max, 1.0].min) * 180 / Math::PI
        if goc >= PT::XEO
          la = true
          next
        end
        # khoảng cách (mm) từ các đỉnh của mặt tới mặt hộp gần nhất theo trục pháp tuyến k
        d = f.vertices.map { |v| c = v.position.to_a[k]; [(c - lo[k]).abs, (c - hi[k]).abs].min * he[k] }.max.to_f
        next if d <= PT::TOL
        if d < PT::LE then meo = d if d > meo
        else la = true
        end
      end
      [meo > PT::TOL ? meo : nil, la]
    end

    def self.nhan(e)
      n = e.name.to_s
      return n.sub(/\A__/, '') unless n.empty?
      if e.is_a?(Sketchup::ComponentInstance)
        dn = e.definition.name.to_s
        return dn unless dn.empty?
      end
      '(tấm không tên)'
    end

    # Hệ khung: gốc + 3 trục đơn vị + kích thước THẬT (khung bị Scale thì theo scale)
    def self.he_khung(k)
      te = k[:te]
      d = k[:e].definition
      so = %w[dai sau cao].map { |x| d.get_attribute(DICT, x).to_f }
      ax = [X_AXIS, Y_AXIS, Z_AXIS].map { |a| te * a }
      { o: te * Geom::Point3d.new(0, 0, 0), u: ax.map(&:normalize),
        kich: (0..2).map { |i| so[i] * ax[i].length } }
    end

    # Điểm thế giới → toạ độ hệ khung (mm)
    def self.vao_khung(h, p)
      v = p - h[:o]
      h[:u].map { |a| v.dot(a) * MM }
    end

    # Toạ độ hệ khung (mm) → điểm thế giới
    def self.ra_the_gioi(h, q)
      o = h[:o].to_a
      u = h[:u].map(&:to_a)
      Geom::Point3d.new(*(0..2).map { |c| o[c] + (0..2).sum { |i| u[i][c] * q[i] / MM } })
    end

    # Tấm có TÂM nằm trong khung → quy về hệ khung cho lõi
    def self.tam_trong(h, tams)
      tams.map do |t|
        f = t[:goc].map { |p| vao_khung(h, p) }
        lo = (0..2).map { |k| f.map { |q| q[k] }.min }
        hi = (0..2).map { |k| f.map { |q| q[k] }.max }
        next unless (0..2).all? { |k| c = (lo[k] + hi[k]) / 2.0; c >= 0 && c <= h[:kich][k] }
        { id: t[:id], ten: t[:ten], lo: lo, hi: hi, cua: t[:cua], lech_do: lech_truc(h, t[:canh]),
          meo_mm: t[:meo_mm], hinh_la: t[:hinh_la] }
      end.compact
    end

    # Góc lệch (độ) lớn nhất giữa 3 cạnh tấm và trục khung gần nhất
    def self.lech_truc(h, canh)
      canh.map do |v|
        l = v.length
        next 0.0 if l < 1e-9
        m = h[:u].map { |a| (v.dot(a) / l).abs }.max
        Math.acos([m, 1.0].min) * 180 / Math::PI
      end.max
    end

    def self.doc_bo_qua(e)
      JSON.parse(e.get_attribute(DICT, 'bo_qua') || '[]')
    rescue JSON::ParserError
      [] # thuần đọc: chuỗi hỏng (sửa tay) thì coi như chưa bỏ qua gì — soát lại đủ, không mất lỗi
    end

    # ── Đẩy kết quả lên bảng ────────────────────────────────────
    def self.gui_ket_qua
      return unless @dlg&.visible?
      model = Sketchup.active_model
      canh_bao = (model.active_path || []).empty? ? nil :
        'Đang ở TRONG một group — toạ độ có thể lệch. Bấm Esc tới khi ra ngoài cùng rồi Soát lại.'
      @lan = quet
      data = @lan.each_with_index.map do |x, i|
        { 'ten' => "Khung #{i + 1}", 'kich' => x[:he][:kich].map { |v| PT.so(v) },
          'so_tam' => x[:kq]['so_tam'], 'so_bo_qua' => x[:kq]['so_bo_qua'],
          'ds' => x[:kq]['ds'].map { |f| gon(f) } }
      end
      @dlg.execute_script("window.nhan(#{JSON.generate('khung' => data, 'canh_bao' => canh_bao)});")
    rescue => e
      puts "[Soát Khung] #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n") if e.backtrace
      bao('baoLoi', "Lỗi: #{e.message}")
    end

    def self.gon(f)
      g = f.slice('muc', 'loai', 'tieu_de', 'chi_tiet', 'khoa')
      g['con'] = f['con'].map { |c| gon(c) } if f['con']
      g
    end

    # ── Tạo khung ──────────────────────────────────────────────
    def self.tao(json)
      d = JSON.parse(json)
      kich = %w[dai sau cao].map { |k| d[k].to_f }
      return bao('baoLoi', 'Nhập đủ Dài, Sâu, Cao (mm, lớn hơn 0).') unless kich.all? { |x| x > 0 }
      model = Sketchup.active_model
      unless (model.active_path || []).empty?
        return bao('baoLoi', 'Đang ở TRONG một group. Bấm Esc tới khi ra ngoài cùng rồi Tạo khung lại.')
      end
      dat = vi_tri_tu_chon(model, kich)

      model.start_operation('Tao khung kiem', true)
      begin
        defn = model.definitions.add(ten_moi(model, kich))
        pts = GOC8.map { |cx, cy, cz| Geom::Point3d.new(cx * kich[0].mm, cy * kich[1].mm, cz * kich[2].mm) }
        CANH12.each { |a, b| defn.entities.add_line(pts[a], pts[b]) }
        %w[dai sau cao].each_with_index { |k, i| defn.set_attribute(DICT, k, kich[i]) }
        model.entities.add_instance(defn, dat) if dat
        model.commit_operation
      rescue => e
        model.abort_operation
        puts "[Soát Khung] #{e.class}: #{e.message}"
        puts e.backtrace.first(5).join("\n") if e.backtrace
        return bao('baoLoi', "Lỗi: #{e.message}")
      end

      if dat
        bao('baoXong', 'Đã đặt khung vào góc tủ đang chọn và soát.')
        gui_ket_qua
      else
        # Bộ đặt component của SketchUp tự bắt điểm + tự lo bước undo đặt (như Hình Nhân).
        model.place_component(defn)
        bao('baoXong', 'Rê chuột, bấm vào góc TRÁI-TRƯỚC-DƯỚI của tủ để đặt khung (Esc bỏ). Đặt xong bấm Soát lại.')
      end
    rescue => e
      puts "[Soát Khung] #{e.class}: #{e.message}"
      bao('baoLoi', "Lỗi: #{e.message}")
    end

    # Đang chọn tủ và tủ thẳng trục file (quay 0/90/180/270° — thợ không vẽ tủ xiên, LUAT_NHA mục 9)
    # → đặt khung vào góc hộp bao của các tấm đang chọn. Tủ nằm ngang theo trục xanh lá (dài theo
    # xanh lá) thì xoay khung 90°. Không chọn / tủ xiên → nil (người vẽ tự đặt bằng chuột).
    def self.vi_tri_tu_chon(model, kich)
      sel = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      return nil if sel.empty?
      tams = []
      duyet(sel, Geom::Transformation.new, 0, tams, [])
      return nil if tams.empty?
      return nil unless tams.all? { |t| t[:canh].all? { |v| thang_truc?(v) } }
      bb = Geom::BoundingBox.new
      tams.each { |t| t[:goc].each { |p| bb.add(p) } }
      mn = bb.min
      mx = bb.max
      rong = (mx.x - mn.x) * MM
      sau = (mx.y - mn.y) * MM
      if (rong - kich[1]).abs + (sau - kich[0]).abs < (rong - kich[0]).abs + (sau - kich[1]).abs
        # dài theo +xanh lá, sâu theo −đỏ: gốc ở góc (max đỏ, min xanh lá, min lam)
        Geom::Transformation.axes(Geom::Point3d.new(mx.x, mn.y, mn.z), Y_AXIS, X_AXIS.reverse, Z_AXIS)
      else
        Geom::Transformation.new(mn)
      end
    end

    def self.thang_truc?(v)
      v.to_a.count { |c| c.abs < 1e-6 } >= 2
    end

    def self.ten_moi(model, kich)
      goc = "LH Khung kiem #{kich.map { |x| PT.so(x) }.join('x')}"
      ten = goc
      i = 2
      while model.definitions[ten]
        ten = "#{goc} ##{i}"
        i += 1
      end
      ten
    end

    # ── Bỏ qua / hiện lại / chọn / xoá ──────────────────────────
    def self.bo_qua(json)
      d = JSON.parse(json)
      x = (@lan || [])[d['khung'].to_i]
      return gui_ket_qua unless x && !x[:khung][:e].deleted?
      e = x[:khung][:e]
      ds = (doc_bo_qua(e) + [d['khoa'].to_s]).uniq
      sua(e, 'Bo qua loi khung') { e.set_attribute(DICT, 'bo_qua', JSON.generate(ds)) }
      gui_ket_qua
    end

    def self.hien_lai(i)
      x = (@lan || [])[i]
      return gui_ket_qua unless x && !x[:khung][:e].deleted?
      e = x[:khung][:e]
      sua(e, 'Hien lai loi khung') { e.set_attribute(DICT, 'bo_qua', '[]') }
      gui_ket_qua
    end

    def self.chon(i)
      x = (@lan || [])[i]
      return unless x && !x[:khung][:e].deleted?
      sel = Sketchup.active_model.selection
      sel.clear
      sel.add(x[:khung][:e])
      bao('baoXong', 'Đã chọn khung — dùng Move (M) / Rotate (Q) để dời vào góc tủ, rồi Soát lại.')
    end

    def self.xoa(i)
      x = (@lan || [])[i]
      return gui_ket_qua unless x && !x[:khung][:e].deleted?
      e = x[:khung][:e]
      sua(e, 'Xoa khung kiem') { e.erase! }
      gui_ket_qua
    end

    def self.sua(_e, ten)
      model = Sketchup.active_model
      model.start_operation(ten, true)
      begin
        yield
        model.commit_operation
      rescue => e
        model.abort_operation
        puts "[Soát Khung] #{e.class}: #{e.message}"
        bao('baoLoi', "Lỗi: #{e.message}")
      end
    end
    private_class_method :sua

    # ── Xem một phát hiện: tô nổi tấm liên quan + đánh dấu chỗ lỗi ──
    # duong = "khung/dòng" hoặc "khung/dòng/con"
    def self.xem(duong)
      so = duong.to_s.split('/').map(&:to_i)
      x = (@lan || [])[so[0]]
      return unless x
      f = x[:kq]['ds'][so[1]]
      f = f['con'][so[2]] if f && so[2] && f['con']
      return unless f
      h = x[:he]
      tam = f['tam'].map { |id| x[:tams][id] }.compact.map { |t| t[:goc] }
      khung = GOC8.map { |c| ra_the_gioi(h, (0..2).map { |k| c[k] * h[:kich][k] }) }
      diem = f['diem'] && ra_the_gioi(h, f['diem'])
      doan = f['doan'] && f['doan'].map { |q| ra_the_gioi(h, q) }
      gio = f['giong'] && ve_giong(h, x[:tams], f['giong'])
      Sketchup.active_model.select_tool(XemTool.new(khung, tam, diem, doan, f, gio))
    rescue => e
      puts "[Soát Khung] #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n") if e.backtrace
      bao('baoLoi', "Lỗi: #{e.message}")
    end

    # Các CHỖ xem của một dòng gióng, đổi sang thế giới: điểm gặp nhau, đoạn mép đỏ (lệch) và
    # xanh lá (chuẩn), 3 hướng của chỗ đó, tấm lệch + tấm bạn (để tô và để chọn sẵn tấm lệch).
    def self.ve_giong(h, tams, g)
      g['cho'].map do |c|
        t = tams[c['id']]
        next unless t
        b = c['ban'] && tams[c['ban']]
        r = c['nua'] * 2.5
        { o: ra_the_gioi(h, c['o']), do: c['do'].map { |q| ra_the_gioi(h, q) },
          xanh: c['xanh'].map { |q| ra_the_gioi(h, q) }, nua: c['nua'] / MM,
          u_k: h[:u][c['truc']], u_chay: h[:u][c['chay']], u_ke: h[:u][c['ke']], dau: c['dau'],
          nhan: c['nhan'], chu: c['chu'], e: t[:e],
          hop: cat_hop(h, t[:goc], c['o'], r), hop_ban: b && cat_hop(h, b[:goc], c['o'], r) }
      end.compact
    end

    # Phần tấm nằm trong khối lập phương cạnh 2r quanh chỗ lệch (hệ khung, mm) → 8 góc thế giới.
    # Vẽ cả tấm 2 m khi camera đứng sát thì một phần tấm ra SAU camera → hình vỡ; cắt gọn là hết.
    # Khối này nhỏ hơn khoảng cách camera (toi_cho: ~4,8×nua) nên luôn nằm trước mắt.
    def self.cat_hop(h, goc, o, r)
      f = goc.map { |p| vao_khung(h, p) }
      lo = (0..2).map { |i| [f.map { |q| q[i] }.min, o[i] - r].max }
      hi = (0..2).map { |i| [f.map { |q| q[i] }.max, o[i] + r].min }
      return nil if (0..2).any? { |i| hi[i] <= lo[i] }
      GOC8.map { |cx, cy, cz| ra_the_gioi(h, [cx.zero? ? lo[0] : hi[0], cy.zero? ? lo[1] : hi[1], cz.zero? ? lo[2] : hi[2]]) }
    end

    # =========================================================
    #  TOOL XEM — vẽ nổi, không sửa model. Esc thoát.
    # =========================================================
    class XemTool
      XANH    = Sketchup::Color.new(30, 110, 230)
      XANH_LA = Sketchup::Color.new(0, 170, 60)
      DO      = Sketchup::Color.new(255, 40, 40)
      VANG    = Sketchup::Color.new(230, 160, 0)
      HONG    = Sketchup::Color.new(255, 0, 200)   # đánh dấu chỗ lỗi — đồng bộ SpacingCheck

      def initialize(khung, tams, diem, doan, f, cho = nil)
        @cho = cho && !cho.empty? ? cho : nil
        @i = 0
        @khung = khung
        @tams = tams
        @diem = diem
        @doan = doan
        @f = f
        @mau = f['muc'] == 'vang' ? VANG : DO
        @bb = Geom::BoundingBox.new
        (tams.empty? ? [khung] : tams).each { |g| g.each { |p| @bb.add(p) } }
        @bb.add(diem) if diem
        @ext = Geom::BoundingBox.new
        khung.each { |p| @ext.add(p) }
        tams.each { |g| g.each { |p| @ext.add(p) } }
      end

      def activate
        @cho ? toi_cho(0) : frame(@bb)
        trang_thai
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        view.invalidate
      end

      def getExtents
        @ext
      end

      def onCancel(_r, view)
        view.model.select_tool(nil)
        Sketchup.set_status_text('', SB_PROMPT)
        view.invalidate
      end

      # ← → (hoặc ↑ ↓) đổi chỗ khi một dòng gióng có nhiều mép lệch
      def onKeyDown(key, _rep, _flags, view)
        return false unless @cho && @cho.size > 1
        case key
        when 39, 38 then toi_cho((@i + 1) % @cho.size)
        when 37, 40 then toi_cho((@i - 1) % @cho.size)
        else return false
        end
        trang_thai
        view.invalidate
        true
      end

      def trang_thai
        them = @cho && @cho.size > 1 ? " — chỗ #{@i + 1}/#{@cho.size}, ← → đổi chỗ" : ''
        Sketchup.set_status_text("#{@f['tieu_de']}#{them} — Esc thoát", SB_PROMPT)
      end

      def draw(view)
        view.line_width = 2
        view.drawing_color = XANH
        view.draw(GL_LINES, net(@khung))
        @cho ? ve_cho(view) : ve_thuong(view)
        ve_bang(view)
      end

      def ve_thuong(view)
        LeHai::SoiNoi.phu_mo(view)
        LeHai::SoiNoi.ve_khois(view, @tams.map { |g| [g, @f['muc'] == 'vang' ? :vang : :do] })
        view.line_width = 3
        view.drawing_color = @mau
        @tams.each do |g|
          pts = net(g)
          view.draw(GL_LINES, pts)
          LeHai::SoiNoi.net2d(view, pts)   # soi nổi: đoạn thấy liền, đoạn khuất đứt (30/09)
        end
        ve_dau(view)
      end

      # Mờ phần còn lại + hai tấm thành khối (tấm lệch đỏ, tấm chuẩn xanh lá) — shared/soi_noi.rb.
      # Làm ra ở đây trước (Khoa 30/09: "làm mờ và sáng nhẹ rất hay") rồi đưa về dùng chung.
      def ve_cho(view)
        c = @cho[@i]
        LeHai::SoiNoi.phu_mo(view)
        LeHai::SoiNoi.ve_khois(view, [[c[:hop_ban], :la], [c[:hop], :do]].select(&:first))
        view.line_width = 4
        view.drawing_color = XANH_LA
        LeHai::SoiNoi.net2d(view, c[:xanh])   # soi nổi: đoạn thấy liền, đoạn khuất đứt (30/09)
        view.drawing_color = DO
        LeHai::SoiNoi.net2d(view, c[:do])
        s = view.screen_coords(c[:o])
        ve_huong(view, c, s)
        LeHai::SoiNoi.chip(view, s.x + 18, s.y + 18, c[:nhan])
      end

      # Mũi tên MỜ chỉ hướng mép đã đi (từ mép đúng sang mép lệch) — Khoa 30/09 muốn biết "thụt về phía
      # nào" mà không quá nổi. Độ lệch có khi 0,06 mm nên không vẽ theo độ dài thật: lấy HƯỚNG của trục
      # lệch chiếu lên màn, vẽ mũi tên dài cố định 70 px, đặt lệch sang bên để không che mép.
      MUI = Sketchup::Color.new(60, 60, 60, 110)

      def ve_huong(view, c, s)
        q = view.screen_coords(c[:o].offset(c[:u_k], c[:nua] * c[:dau]))
        dx = q.x - s.x
        dy = q.y - s.y
        l = Math.sqrt(dx * dx + dy * dy)
        return if l < 1                               # nhìn dọc đúng trục lệch: không có hướng để vẽ
        ux = dx / l
        uy = dy / l
        px = -uy                                      # pháp tuyến 2D: dời mũi tên ra cạnh mép
        py = ux
        x0 = s.x + px * 34 - ux * 35
        y0 = s.y + py * 34 - uy * 35
        x1 = x0 + ux * 70
        y1 = y0 + uy * 70
        view.line_width = 3
        view.drawing_color = MUI
        view.draw2d(GL_LINES, [Geom::Point3d.new(x0, y0, 0), Geom::Point3d.new(x1 - ux * 10, y1 - uy * 10, 0)])
        view.draw2d(GL_POLYGON, [Geom::Point3d.new(x1, y1, 0),
                                 Geom::Point3d.new(x1 - ux * 16 + px * 8, y1 - uy * 16 + py * 8, 0),
                                 Geom::Point3d.new(x1 - ux * 16 - px * 8, y1 - uy * 16 - py * 8, 0)])
      end

      # Tới chỗ lệch: khung nhìn ≈ 3×nua (lệch 1 mm → ~120 mm): thấy hình khối hai tấm, hai mép vẫn tách
      # ~8 px; muốn sát hơn thì lăn chuột (Khoa 30/09: dí sát quá mất hình, "nhìn khó chịu"). Nhìn chéo dọc mặt tiếp xúc (trục ke), vuông góc với hướng
      # lệch (trục k) → độ lệch nằm ngang mắt. Giữ phía camera đang đứng, không lật ra sau tủ.
      def toi_cho(i)
        @i = i
        c = @cho[i]
        m = Sketchup.active_model
        m.selection.clear
        m.selection.add(c[:e])                    # chọn sẵn tấm lệch: bấm M là dời được ngay
        cam = m.active_view.camera
        dau = cam.direction.dot(c[:u_ke]) >= 0 ? 1.0 : -1.0
        ke = c[:u_ke].to_a
        ch = c[:u_chay].to_a
        huong = Geom::Vector3d.new(*(0..2).map { |j| ke[j] * 0.85 * dau + ch[j] * 0.35 }).normalize
        len = Geom::Vector3d.new(0, 0, 1)
        len = c[:u_chay] if huong.dot(len).abs > 0.9
        nua = c[:nua]
        if cam.perspective?
          fov = cam.fov * Math::PI / 180.0
          xa = nua / Math.tan(fov / 2.0) * 1.5
          cam.set(c[:o].offset(huong.reverse, xa), c[:o], len)
        else
          cam.set(c[:o].offset(huong.reverse, nua * 6), c[:o], len)
          cam.height = nua * 2.4
        end
      end

      def net(g)
        CANH12.flat_map { |a, b| [g[a], g[b]] }
      end

      # Chữ thập hồng ở chỗ lỗi + đoạn nối hai mép lệch (nếu có)
      def ve_dau(view)
        return unless @diem
        s = view.screen_coords(@diem)
        view.line_width = 3
        view.drawing_color = HONG
        view.draw2d(GL_LINES, [[s.x - 14, s.y], [s.x + 14, s.y], [s.x, s.y - 14], [s.x, s.y + 14]].map { |a, b| Geom::Point3d.new(a, b, 0) })
        view.draw2d(GL_LINES, @doan.map { |p| view.screen_coords(p) }) if @doan
      end

      def ve_bang(view)
        dong = if @cho
                 c = @cho[@i]
                 so = @cho.size > 1 ? "Chỗ #{@i + 1}/#{@cho.size}: " : ''
                 [@f['tieu_de'], "#{so}#{c[:chu]}",
                  "Xanh lá = mép đúng · Đỏ = mép lệch · mũi tên mờ = hướng mép đã đi · lăn chuột phóng/thu#{@cho.size > 1 ? ' · ← → đổi chỗ' : ''} · Esc thoát"]
               else
                 [@f['tieu_de'], @f['chi_tiet'], 'Xanh = khung chuẩn · Esc thoát']
               end
        w = 26 + dong.map(&:length).max * 7
        h = 22 * dong.size + 14
        o_vuong(view, 18, 18, w, h, Sketchup::Color.new(18, 22, 30, 215))
        o_vuong(view, 18, 18, 6, h, @mau)
        chu(view, 34, 26, dong[0], Sketchup::Color.new(255, 255, 255), 13, true)
        chu(view, 34, 48, dong[1], Sketchup::Color.new(225, 225, 225), 11, false)
        chu(view, 34, 70, dong[2], Sketchup::Color.new(255, 210, 60), 11, false)
      end

      def o_vuong(view, x, y, w, h, mau)
        view.drawing_color = mau
        view.draw2d(GL_POLYGON, [[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map { |a, b| Geom::Point3d.new(a, b, 0) })
      end

      def chu(view, x, y, s, mau, co, dam)
        view.draw_text(Geom::Point3d.new(x, y, 0), s.to_s, color: mau, font: 'Arial', size: co, bold: dam)
      end

      # Đóng khung camera, giữ hướng nhìn hiện tại (mẫu kiem_tra_ban_le/main.rb — View#zoom không nhận BoundingBox)
      def frame(bb)
        cam = Sketchup.active_model.active_view.camera
        ctr = bb.center
        diag = bb.diagonal
        diag = 100.0 if diag < 1.0
        if cam.perspective?
          fov = cam.fov * Math::PI / 180.0
          dist = (diag / 2.0) / Math.tan(fov / 2.0) * 1.4
          cam.set(ctr.offset(cam.direction.reverse, dist), ctr, cam.up)
        else
          cam.set(ctr.offset(cam.direction.reverse, diag * 3.0), ctr, cam.up)
          cam.height = diag * 1.4
        end
      end
    end

  end
end
