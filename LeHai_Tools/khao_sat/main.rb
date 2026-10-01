# encoding: UTF-8
# ── Khảo Sát Hiện Trường → 3D ───────────────────────────────
# Bấm nút -> bảng chọn: lấy số đo từ app khảo sát trên điện thoại (Google Sheet qua link /exec, hoặc file
# JSON app xuất), chọn công trình + phòng, dựng hiện trạng 3D (sàn, tường dày, cửa, ổ điện, len, hộp trần...).
#
# Ruby CHỈ tải dữ liệu + VẼ. Mọi phép tính vị trí nằm ở js/dung3d.js (bảng chọn chạy), dùng chung lõi với app.
# NGUỒN JS: lab `projects/khao-sat-hien-truong/js/` — KHÔNG sửa tay 3 file trong js/ ở đây; sửa bên app rồi
# chạy `node tools/dong-bo-plugin.mjs` (test dung3d.test.cjs báo đỏ khi hai bên lệch nhau).
# Khoa chốt 01/10/2026: mở cho máy thợ (trước đó 28/09 chỉ chạy riêng máy Khoa, nút ở đây là nút chờ).
#
# Thử nhanh (Ruby Console):
#   load 'C:/Users/tankf/Desktop/agent_lab_khoa/projects/lehai-tools/LeHai_Tools/khao_sat/main.rb'
#   TK::KhaoSatHienTruong.show

require 'sketchup.rb'
require 'json'
require 'net/http'
require 'uri'
require 'openssl'

module TK
  module KhaoSatHienTruong
    PATH = File.dirname(__FILE__.dup.force_encoding('UTF-8')).freeze
    PREF = 'LeHai_KhaoSat3D'.freeze
    # Màu theo khoá `mat` trong kế hoạch dựng: [r, g, b, độ đục]
    MAU = {
      'san' => [214, 196, 168, 1.0], 'tran' => [245, 245, 245, 0.35], 'tuong' => [236, 236, 232, 1.0],
      'dien' => [56, 97, 140, 1.0], 'nuoc' => [40, 150, 190, 1.0], 'do' => [196, 112, 58, 1.0],
      'len' => [150, 120, 90, 1.0], 'dosan' => [120, 90, 160, 1.0], 'hop' => [201, 168, 106, 0.6],
      'loi' => [191, 83, 64, 1.0], 'hoc' => [205, 205, 195, 1.0]
    }.freeze
    # Tag vừa tạo thì ẩn sẵn: trần che mất mặt bằng khi nhìn từ trên xuống. Tag đã có thì để nguyên ý người dùng.
    TAG_AN = %w[KS_Tran].freeze

    # ── Bảng chọn ──────────────────────────────────────────────
    def self.show
      if @dlg&.visible? then @dlg.bring_to_front; return end
      @dlg = UI::HtmlDialog.new(dialog_title: 'Khảo sát hiện trường → 3D', preferences_key: PREF,
                                width: 460, height: 680, min_width: 380, min_height: 480, resizable: true)
      @dlg.set_file(File.join(PATH, 'dialog.html'))   # nạp cạnh file code
      gan_callbacks(@dlg)
      @dlg.show
    end

    def self.gan_callbacks(d)
      d.add_action_callback('ready') { |_c| gui('KS.cauHinh', { 'url' => Sketchup.read_default(PREF, 'url', '').to_s }) }
      d.add_action_callback('luu_url') { |_c, url| Sketchup.write_default(PREF, 'url', url.to_s.strip) }
      d.add_action_callback('goi_sheet') { |_c, tag, body| goi_sheet(tag.to_s, body.to_s) }
      d.add_action_callback('mo_file') { |_c| mo_file }
      d.add_action_callback('dung') { |_c, plan| dung_tu_json(plan.to_s) }
    end

    # Gọi hàm JS trong bảng với dữ liệu Ruby (sinh JSON -> luôn là literal JS hợp lệ).
    # Bọc mảng rồi bóc ngoặc: gem json cũ không cho generate chuỗi/số trần.
    def self.gui(fn, *args)
      return unless @dlg
      @dlg.execute_script("#{fn}(#{JSON.generate(args)[1...-1]})")
    end

    # ── Tải dữ liệu ───────────────────────────────────────────
    def self.goi_sheet(tag, body)
      url = Sketchup.read_default(PREF, 'url', '').to_s
      return gui('KS.loi', 'Chưa có link Sheet — dán link /exec rồi bấm Lưu.') if url.empty?
      gui('KS.nhanSheet', tag, post_json(url, body))
    rescue StandardError => e
      gui('KS.loi', "Lỗi tải Sheet: #{e.message}")
    end

    # Apps Script đôi lúc trả trang 404 / lạc sang cửa GET ngay sau khi cập nhật bản (đo 28/09) -> thử lại 3 lần.
    def self.post_json(url, body, lan = 3)
      lan.times do |i|
        obj = doc_json(http_post(url, body))
        return obj if obj.is_a?(Hash) && obj['err'] != 'GET'
        sleep(1.5 * (i + 1)) if i < lan - 1
      end
      raise 'Google không trả dữ liệu sau 3 lần thử — kiểm lại link Sheet (đuôi /exec).'
    end

    # Helper thuần đọc: chữ không phải JSON (trang lỗi HTML) -> nil để vòng ngoài thử lại, nên nuốt lỗi ở đây được.
    def self.doc_json(txt)
      JSON.parse(txt)
    rescue JSON::ParserError
      nil
    end

    def self.http_post(url, body)
      uri = URI.parse(url)
      req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'text/plain;charset=utf-8')
      req.body = body
      res = http_for(uri).request(req)
      3.times do # Apps Script trả 302 sang script.googleusercontent.com -> đi theo bằng GET
        break unless [301, 302, 303, 307].include?(res.code.to_i) && res['location']
        uri = URI.parse(res['location'])
        res = http_for(uri).request(Net::HTTP::Get.new(uri.request_uri))
      end
      res.body.to_s.dup.force_encoding('UTF-8')
    end

    # Cấu hình mạng chép theo LeHai_Tools/updater.rb (đã chạy thật trên máy thợ). VERIFY_NONE = nợ SSL chung của repo.
    def self.http_for(uri)
      h = Net::HTTP.new(uri.host, uri.port)
      h.use_ssl      = (uri.scheme == 'https')
      h.verify_mode  = OpenSSL::SSL::VERIFY_NONE if defined?(OpenSSL)
      h.open_timeout = 10
      h.read_timeout = 60
      h
    end

    def self.mo_file
      path = UI.openpanel('Chọn file JSON xuất từ app khảo sát', '', 'JSON|*.json||')
      return unless path
      gui('KS.nhanFile', JSON.parse(File.read(path, encoding: 'bom|utf-8')))
    rescue StandardError => e
      gui('KS.loi', "Lỗi đọc file: #{e.message}")
    end

    # ── Vẽ ────────────────────────────────────────────────────
    def self.dung_tu_json(plan_txt)
      loi = []
      goc = dung(JSON.parse(plan_txt), loi)
      Sketchup.active_model.active_view.zoom(goc) if goc&.valid?
      gui('KS.xong', { 'loi' => loi })
    rescue StandardError => e
      gui('KS.loi', "Lỗi: #{e.message}")
    end

    # Cả công trình = 1 group, mỗi phòng 1 group con, mỗi khối 1 group riêng (khối không dính vào nhau).
    # Một lần bấm = một bước Undo. Khối nào hỏng thì ghi vào `loi` và dựng tiếp khối khác.
    def self.dung(plan, loi)
      model = Sketchup.active_model
      model.start_operation('Dung khao sat 3D', true)
      begin
        goc = model.active_entities.add_group
        goc.name = "Khảo sát · #{plan['project']}"
        (plan['rooms'] || []).each { |ph| dung_phong(model, goc.entities, ph, loi) }
        model.commit_operation
        goc
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    def self.dung_phong(model, ents, ph, loi)
      g = ents.add_group
      g.name = ph['name'].to_s
      g.set_attribute('KhaoSat', 'room_id', ph['id'].to_s)
      (ph['items'] || []).each { |it| ve_khoi(model, g.entities, it, loi, ph['name']) }
    end

    def self.ve_khoi(model, ents, it, loi, phong)
      g = ents.add_group
      g.name = it['name'].to_s
      g.layer = tag(model, it['tag']) if it['tag']
      g.material = mau(model, it['mat']) if it['mat']
      ok = ve_theo_loai(model, g.entities, it)
      g.set_attribute('KhaoSat', 'raw', JSON.generate(it['raw'])) if ok && it['raw']
      return true if ok
      loi << "#{phong} · #{it['name']}: không dựng được"
      g.erase! if g.valid?
      false
    rescue StandardError => e
      loi << "#{phong} · #{it['name']}: #{e.message}"
      g.erase! if g&.valid?
      false
    end

    def self.ve_theo_loai(model, ents, it)
      case it['t']
      when 'face'  then !ents.add_face(pts(it['pts'])).nil?
      when 'wall'  then ve_tuong(model, ents, it)
      when 'prism' then ve_lang_tru(ents, it)
      when 'line'  then !ents.add_line(pt(it['pts'][0]), pt(it['pts'][1])).nil?
      when 'text'  then !ents.add_text(it['text'].to_s, pt(it['pos'])).nil?
      else false
      end
    end

    # Tường dày (30/09): đế 4 góc ở sàn -> đẩy lên cao trần thành khối. Cửa/cửa sổ: vẽ chữ nhật lên mặt trong
    # (SketchUp tự chẻ mặt) rồi đẩy xuyên đúng bề dày T ra phía ngoài -> lỗ thủng, như thợ làm tay bằng Push/Pull.
    # Hốc có số sâu: đẩy lõm vào d; hốc chưa có số sâu: chỉ tô màu trên mặt tường.
    def self.ve_tuong(model, ents, it)
      de = ents.add_face(pts(it['foot']))
      return false if de.nil?
      day(de, [0, 0, it['pts'][2][2]])
      out = it['out']
      (it['holes'] || []).each do |h|
        lo = ents.add_face(pts(h))
        day(lo, out.map { |x| x.to_f * it['T'].to_f }) if lo
      end
      (it['recesses'] || []).each do |rc|
        f = ents.add_face(pts(rc['pts']))
        next unless f
        f.material = mau(model, 'hoc')
        day(f, out.map { |x| x.to_f * rc['d'].to_f })
      end
      (it['marks'] || []).each do |m|
        f = ents.add_face(pts(m))
        f.material = mau(model, 'hoc') if f
      end
      true
    end

    # Đẩy mặt theo vector (mm) mà KHÔNG lật mặt: pushpull đo theo pháp tuyến, nên pháp tuyến ngược chiều
    # vector thì đẩy số âm — cùng cách tao_modul_nhanh/main.rb (mặt nằm trong khối, lật sẽ làm lệch mặt kề).
    def self.day(f, vec)
      v = Geom::Vector3d.new(*vec.map { |x| x.to_f.mm })
      f.pushpull(f.normal.dot(v) >= 0 ? v.length : -v.length)
    end

    # Lăng trụ: mặt đáy đẩy theo vector. add_face có thể úp mặt ngược hướng -> lật cho pháp tuyến cùng chiều vector.
    def self.ve_lang_tru(ents, it)
      f = ents.add_face(pts(it['base']))
      return false if f.nil?
      v = Geom::Vector3d.new(*it['vec'].map { |x| x.to_f.mm })
      return false if v.length < 0.001
      f.reverse! if f.normal.dot(v) < 0
      f.pushpull(v.length)
      true
    end

    # ── Tiện ích ──────────────────────────────────────────────
    def self.pt(p)
      Geom::Point3d.new(p[0].to_f.mm, p[1].to_f.mm, p[2].to_f.mm)
    end

    def self.pts(list)
      list.map { |p| pt(p) }
    end

    def self.tag(model, ten)
      moi = model.layers.at(ten).nil?
      l = model.layers.add(ten)
      l.visible = false if moi && TAG_AN.include?(ten)
      l
    end

    def self.mau(model, key)
      c = MAU[key]
      return nil unless c
      ten = "KS_#{key}"
      m = model.materials.at(ten) || model.materials.add(ten)
      m.color = Sketchup::Color.new(c[0], c[1], c[2])
      m.alpha = c[3]
      m
    end

    def self.create_cmd
      icons = File.join(PATH, 'icons')
      cmd = UI::Command.new('Khảo Sát Hiện Trường') { TK::KhaoSatHienTruong.show }
      cmd.tooltip         = 'Khảo sát hiện trường → 3D'
      cmd.status_bar_text = 'Dựng hiện trạng 3D từ số đo app khảo sát trên điện thoại (Google Sheet hoặc file JSON).'
      s16 = File.join(icons, 'khao_sat_16.png')
      s24 = File.join(icons, 'khao_sat_24.png')
      cmd.small_icon = s16 if File.exist?(s16)
      cmd.large_icon = s24 if File.exist?(s24)
      cmd
    end
  end
end
