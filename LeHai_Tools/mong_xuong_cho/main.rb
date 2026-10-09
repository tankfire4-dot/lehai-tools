# encoding: UTF-8
# Mộng xương chó: tạo mộng dương (dogbone) trên các TẤM NGÀM + dấu âm _ABF_Intersect trên các
# TẤM NHẬN áp vào chúng. Người dùng chỉ phân loại hai nhóm tấm; tool tự ghép cặp theo tiếp giáp.
# Tấm ngàm được GHI NHỚ việc đã làm (dict LeHai_MXC) để lần sau làm thêm: thêm đầu mới hoặc
# đóng dấu lên tấm nhận mới — không cho sửa mộng đã làm (dấu cũ sẽ lệch).
# Giữ mộng dương dày bằng thân ván; thông số dày/bên giữ chỉ đổi DẤU ÂM.
# Toolbar do LeHai_Tools/main.rb quản lý — file này chỉ expose create_cmd.
# Dấu âm ra layer DXF LEHAI_MONGAM: Khoa nghiệm thu 27/09/2026 (file sạch → nest → xuất ABF).
# Dấu phay mộng + viền (2mm, từ 03/10 là 3mm) ra LEHAI_PHAYMONG / LEHAI_PHAYVIENMONG: nghiệm thu 27/09 (Desktop/ketqua).
# Từ 04/10 tên layer thêm số mm dày sau phay: LEHAI_PHAYMONG_15 / _13 (xem TAG_PHAY).

require 'sketchup.rb'
require 'json'

module TK
module MongXuongCho

  PATH = File.dirname(__FILE__).freeze
  AXES = [X_AXIS, Y_AXIS, Z_AXIS].freeze
  # Chừa ít nhất 1mm giữa các đầu mộng và từ mép mộng tới đầu tấm để tránh
  # hình học chạm nhau/quá ngắn. Đây là giới hạn dựng hình, không phải tiêu chuẩn CNC.
  MIN_GAP = 1.mm
  MEM = 'LeHai_MXC'.freeze # dict ghi nhớ trên tấm ngàm: 'box' (hộp gốc) + 'edges' (JSON từng đầu)
  # Layer DXF riêng cho dấu mộng âm để Aspire gán dao mẫu riêng (Khoa chốt 27/09).
  TAG_MONG_AM = 'LEHAI_MONGAM'.freeze
  # Thu một mặt tấm ngàm sinh 2 dấu phay trên mặt bị thu (Khoa chốt 27/09): ô đúng đầu mộng và ô
  # viền tràn VIEN_PHAY ra hai hông + phía đầu mộng (chân giữ nguyên, không lẹm thân tấm) để dao ăn sạch mép.
  # Tên layer mang SỐ MM của dày sau phay (Khoa 04/10): Aspire gán dao mẫu + độ sâu THEO TÊN LAYER, nên mỗi
  # độ dày một cặp layer. Dày sau phay không có trong bảng → plan_edge CHẶN (Aspire không có dao mẫu → phay
  # sai sâu mà không ai báo). Thêm độ dày mới = thêm 1 dòng ở đây + PHAY_MM trong giao_dien.js + dao mẫu Aspire.
  TAG_PHAY = {
    15.0 => %w[LEHAI_PHAYMONG_15 LEHAI_PHAYVIENMONG_15],
    13.0 => %w[LEHAI_PHAYMONG_13 LEHAI_PHAYVIENMONG_13]
  }.freeze
  # Tên cũ (≤ 1.9.94, luôn là còn 15) — chỉ để NHẬN dấu phay của file đã làm (gỡ mộng, chặn khoan đầu tấm).
  TAG_PHAY_CU = %w[LEHAI_PHAYMONG LEHAI_PHAYVIENMONG].freeze
  VIEN_PHAY = 3.mm # Khoa đổi 2 → 3mm 03/10/2026 (file đã làm sửa bằng scratch/mong-xuong-cho/sua_vien_3mm.rb)
  # ── Tên layer DXF lấy từ TAG CỦA MẶT ──────
  # Exporter DXF của ABF đặt layer cho _ABF_Intersect theo tag của MẶT bên trong nhóm; tag của
  # group và của cạnh bị bỏ qua, hướng mặt không ảnh hưởng. Đo 27/09/2026 trên file sạch: cùng
  # 3 dấu, chỉ dấu được gắn tag cho mặt thoát LAYER0 (Desktop/testlayer/mxc → mxc2). NTT làm được
  # vì nó gắn tag cho cả cây con, kể cả mặt.
  SPEC_KEYS = %w[count head height neck bevel inset side fit slackT slackL cutter].freeze
  TEN_SO = {'count' => 'số mộng', 'head' => 'rộng đầu', 'height' => 'cao mộng', 'neck' => 'đường kính cổ',
            'bevel' => 'vát đỉnh', 'inset' => 'lùi tâm', 'fit' => 'dày sau phay', 'slackT' => 'dư dày',
            'slackL' => 'dư dài', 'cutter' => 'dao góc dấu âm'}.freeze
  TEN_CANH = {1 => 'trên', 2 => 'phải', 3 => 'dưới', 4 => 'trái'}.freeze

  # Biên đo từ mẫu Khoa: thân chữ nhật và bốn nửa đường tròn lồi ở hai đầu.
  # t = bề dày + tổng độ dư; length = rộng mộng + tổng độ dư chiều dài.
  # Hai nửa đường tròn mỗi đầu cần t > 4r để còn đoạn thẳng giữa chúng.
  def self.mortise_outline(t, length, r)
    points = [[0.0, 0.0], [0.0, length]]
    [[r, length, Math::PI, 0.0], [t - r, length, Math::PI, 0.0],
     [t - r, 0.0, 0.0, -Math::PI], [r, 0.0, 0.0, -Math::PI]].each_with_index do |(cx, cy, from, to), index|
      # Nối hai cung cùng đầu bằng đoạn thẳng; hai cạnh dài nối hai đầu dấu.
      points << [t - 2.0 * r, length] if index == 1
      points << [t, 0.0] if index == 2
      points << [2.0 * r, 0.0] if index == 3
      last = index == 3 ? 11 : 12 # Điểm cuối trùng điểm đầu, add_face tự đóng vòng.
      1.upto(last) do |i|
        angle = from + (to - from) * i / 12.0
        points << [cx + r * Math.cos(angle), cy + r * Math.sin(angle)]
      end
    end
    points
  end

  # ── Nhận dạng tấm ──────

  # Tấm nguyên: THÂN tấm (cạnh/mặt rời, không tính group con) là hộp 6 mặt/12 cạnh song song trục
  # local. Group con — dấu ABF khoét/khoan/rãnh, dấu âm của tấm khác — được phép (Khoa 02/10: mọc
  # mộng chỉ thêm răng ra ngoài mép, không đụng dấu), build_tenon giữ nguyên chúng.
  def self.plain_box?(group)
    ents = group.entities
    edges = ents.grep(Sketchup::Edge)
    ents.grep(Sketchup::Face).length == 6 && edges.length == 12 &&
      edges.all? { |e|
        d = e.end.position - e.start.position
        [d.x, d.y, d.z].count { |v| v.abs > 0.001.mm } == 1
      }
  end

  # Hộp 6 mặt/12 cạnh nguyên vẹn nhưng cạnh KHÔNG song song trục local = tấm xiên trong group
  # (LUAT_NHA mục 9, 29/09): trước đây rơi vào câu "đã có mộng/khoét" — sai lý do, thợ không biết sửa.
  def self.xien_trong_group?(group)
    ents = group.entities
    ents.grep(Sketchup::Face).length == 6 && ents.grep(Sketchup::Edge).length == 12 && !plain_box?(group)
  end

  # Không Scale, không xiên ở cấp group: thông số mm mới đúng với hình học.
  def self.rigid?(group)
    rigid_t?(group.transformation)
  end

  def self.rigid_t?(tr)
    t = AXES.map { |axis| tr * axis }
    t.all? { |axis| (axis.length - 1.0).abs < 0.000001 } &&
      [[0, 1], [0, 2], [1, 2]].all? { |a, b| t[a].dot(t[b]).abs < 0.000001 }
  end

  # Ba trục group có còn vuông góc không (Scale theo trục group thì còn; kéo méo thì không).
  def self.skew?(group)
    t = AXES.map { |axis| group.transformation * axis }
    [[0, 1], [0, 2], [1, 2]].any? { |a, b| (t[a].dot(t[b]) / (t[a].length * t[b].length)).abs > 0.000001 }
  end

  # Câu báo Scale/xiên ghi rõ bao nhiêu lần, theo trục nào (02/10: "Scale hoặc xiên" chung chung
  # làm thợ không biết sửa gì). nil nếu group không bị gì.
  def self.scale_problem(group)
    return nil if rigid?(group)
    return 'đang bị XIÊN (méo xéo) ở cấp group — không gỡ tự động được, vẽ lại tấm' if skew?(group)
    parts = %w[X Y Z].zip(AXES.map { |a| (group.transformation * a).length }).reject { |_n, l| (l - 1.0).abs < 0.000001 }
    "đang bị Scale ở cấp group (#{parts.map { |n, l| "#{n} ×#{l.round(4)}" }.join(', ')}) — bấm \"Gỡ Scale\" rồi đo lại bề dày ván"
  end

  # Đưa phần Scale của vỏ group vào hình bên trong: t = R·S (R cứng, S co giãn theo trục group)
  # → hình nhân S, vỏ còn R. Tấm đứng yên chỗ cũ, kích thước thật giữ nguyên như đang thấy.
  def self.go_scale(groups)
    model = Sketchup.active_model
    list = groups.select { |g| g.valid? && !rigid?(g) && !skew?(g) }
    raise 'Không có tấm nào bị Scale để gỡ (tấm XIÊN phải vẽ lại).' if list.empty?
    model.start_operation('Go Scale tam', true)
    begin
      list.each do |g|
        g.make_unique
        t = g.transformation
        l = AXES.map { |a| (t * a).length }
        g.entities.transform_entities(Geom::Transformation.scaling(*l), g.entities.to_a)
        g.transformation = t * Geom::Transformation.scaling(*l.map { |v| 1.0 / v })
      end
      raise 'Gỡ Scale chưa sạch.' unless list.all? { |g| rigid?(g) }
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end
    list.map { |g|
      b = board_bounds(g)
      "#{g.name.empty? ? 'tấm' : g.name}: #{[b.width, b.height, b.depth].map { |v| v.to_mm.round(2) }.sort.join(' × ')}"
    }
  end

  def self.dau_abf?(entity)
    entity.is_a?(Sketchup::Group) &&
      (entity.name == '_ABF_Intersect' || entity.get_attribute('ABF', 'is-intersect') == true)
  end

  # Kích thước tấm nhận lấy từ cạnh của CHÍNH nó, không từ definition.bounds: dấu âm cũ được
  # phép nhô khỏi mép nửa độ dư (0.05mm) nên hộp bao cả group sẽ phình và lệch lần ráp sau.
  # Tấm nhận có mộng sẵn vẫn đúng bề dày vì mộng dương luôn dày bằng thân ván.
  def self.board_bounds(group)
    box = Geom::BoundingBox.new
    group.entities.grep(Sketchup::Edge).each { |e| box.add(e.start.position, e.end.position) }
    box
  end

  # ── Ghi nhớ trên tấm ngàm ──────
  # 'box' = hộp tấm nguyên TRƯỚC khi mọc mộng (local, inch); 'edges' = {"2" => spec + 'nhan' (pid
  # các tấm đã đóng dấu) + 'phay_b' (pid tấm đối tác của dấu phay)}. Nằm trong cùng thao tác
  # dựng nên Ctrl+Z xóa luôn ghi nhớ.
  def self.memory(group)
    box = group.get_attribute(MEM, 'box')
    raw = group.get_attribute(MEM, 'edges')
    return nil unless box.is_a?(Array) && box.length == 6 && raw.is_a?(String)
    edges = JSON.parse(raw)
    bb = Geom::BoundingBox.new
    bb.add(Geom::Point3d.new(box[0, 3]), Geom::Point3d.new(box[3, 3]))
    {box: bb, edges: edges.map { |k, v| [k.to_i, v] }.to_h}
  rescue JSON::ParserError
    nil # ghi nhớ hỏng thì coi như không có: tấm sẽ bị từ chối nếu đã có mộng
  end

  def self.write_memory(group, box, edges)
    group.set_attribute(MEM, 'box', box.min.to_a + box.max.to_a)
    group.set_attribute(MEM, 'edges', JSON.generate(edges.map { |k, v| [k.to_s, v] }.to_h))
  end

  # Hộp gốc của tấm ngàm: ghi nhớ nếu đã làm, hộp nguyên nếu chưa; nil nếu không dùng được.
  def self.tenon_box(group)
    mem = memory(group)
    return mem[:box] if mem
    box = board_bounds(group)
    return nil unless than_tam(group, box)
    # Hộp theo cạnh THÂN tấm (hộp mới, không phải definition.bounds): dấu ABF con được phép nhô khỏi
    # mép, tính vào sẽ phình hộp và mộng lệch.
    box
  end

  # Lý do tấm không làm ngàm được, hoặc nil nếu được.
  def self.tenon_problem(group)
    scaled = scale_problem(group)
    return scaled if scaled
    mem = memory(group)
    if mem && !khop_ghi_nho?(group, mem)
      return 'đã bị sửa hình/kích thước sau khi làm mộng (không còn khớp ghi nhớ) — Undo về lúc vừa làm mộng, hoặc vẽ lại tấm nguyên'
    end
    box = tenon_box(group)
    return 'nằm XIÊN trong group (trục group không theo cạnh tấm — thường do Reset về Global hoặc vẽ xiên rồi mới gom group) — đặt trục group theo cạnh tấm rồi làm lại' if !box && xien_trong_group?(group)
    return 'thân tấm có rãnh/hốc KHÔNG xuyên hết bề dày (hoặc hình hở) — tool chỉ mọc mộng trên tấm phẳng; khoét xuyên và dấu ABF dạng group thì không sao' unless box
    nil
  end

  # Hình hiện tại = hộp ghi nhớ + răng các đầu đã làm? Lệch nghĩa là tấm bị Push/Pull/sửa sau lần
  # mộng trước: dựng lại từ ghi nhớ sẽ trả kích thước CŨ, đóng dấu theo hộp cũ sẽ lệch (soát 02/10).
  def self.khop_ghi_nho?(group, mem)
    box = mem[:box]
    want = Geom::BoundingBox.new.add(box.min, box.max)
    mem[:edges].each do |edge, spec|
      h = spec['height']
      return false unless h.is_a?(Numeric) && (1..4).include?(edge)
      fd = frame_for(group, edge, box)
      b = fd[:bounds]
      [[0, 0], [b.max.x, 0], [b.max.x, b.max.y], [0, b.max.y]].each { |x, y|
        want.add(fd[:frame] * Geom::Point3d.new(x, y, b.max.z + h.mm))
      }
    end
    have = board_bounds(group)
    (want.min.to_a + want.max.to_a).zip(have.min.to_a + have.max.to_a).all? { |a, b| (a - b).abs < 0.01.mm }
  end

  def self.dau_phay_cua_tool?(entity)
    dau_abf?(entity) && ((TAG_PHAY.values.flatten + TAG_PHAY_CU).include?(entity.layer.name) ||
                         entity.get_attribute('ABF', 'setting-name') == 'PHAYDAUMONG_KHOA')
  end

  # Dấu ABF (group con) nằm phẳng trên MẶT ĐẦU sắp mọc mộng — khoan/khoét đầu tấm: răng mọc đè lên
  # nên chặn. Dấu ở mặt lớn hay đầu khác không sao, build_tenon giữ nguyên (02/10).
  def self.dau_o_dau_tam?(group, box, edge)
    fd = frame_for(group, edge, box)
    inv = fd[:frame].inverse
    top = fd[:bounds].depth
    group.entities.any? { |e|
      next false unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      next false if dau_phay_cua_tool?(e)
      zs = (0..7).map { |i| (inv * e.bounds.corner(i)).z }
      zs.min > top - 0.01.mm && zs.max < top + 0.01.mm
    }
  end

  # ── Hình học một đầu ──────

  # Hệ cạnh: cạnh `edge` của hộp `box` thành cạnh trên, u chạy dọc cạnh, z hướng ra ngoài,
  # trục dày giữ nguyên (mặt A = mặt thấp của trục dày).
  # Tấm NẰM NGANG (dày theo Z local, vd đợt kệ — LUAT_NHA mục 9): xoay ảo 90° quanh X để thành
  # tấm đứng (Z local → +Y, giữ mặt A là mặt thấp của trục dày), tính như cũ rồi xoay về.
  # Mọi chỉ số :thin/:u trả ra là của HỆ CẠNH, không phải của tọa độ local tấm (02/10).
  def self.frame_for(group, edge, box = nil)
    raise 'Chọn cạnh từ 1 đến 4.' unless (1..4).include?(edge)
    b = box || group.definition.bounds
    upright = nil
    if [b.width, b.height, b.depth].each_with_index.min_by { |v, _i| v }[1] == 2
      upright = Geom::Transformation.axes(ORIGIN, X_AXIS, Z_AXIS.reverse, Y_AXIS)
      b = Geom::BoundingBox.new.add(upright * b.min, upright * b.max)
    end
    lengths = [b.width, b.height, b.depth]
    thin = lengths.each_with_index.min_by { |v, _i| v }[1]
    raise 'Tấm tạo mộng cần là tấm đứng với trục Z dọc mặt lớn.' if thin == 2
    u = 1 - thin
    axes = [X_AXIS, Y_AXIS, Z_AXIS]
    origin = b.min.to_a
    basis = axes.dup
    # Đổi cạnh 1/2/3/4 thành cạnh trên của hệ tính, giữ nguyên chiều dày A -> B.
    case edge
    when 2
      origin[2] += lengths[2]
      basis[u] = Z_AXIS.reverse
      basis[2] = axes[u]
    when 3
      origin[u] += lengths[u]
      origin[2] += lengths[2]
      basis[u] = axes[u].reverse
      basis[2] = Z_AXIS.reverse
    when 4
      origin[u] += lengths[u]
      basis[u] = Z_AXIS
      basis[2] = axes[u].reverse
    end
    dimensions = lengths.dup
    dimensions[u], dimensions[2] = lengths[2], lengths[u] if [2, 4].include?(edge)
    bounds = Geom::BoundingBox.new
    bounds.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(dimensions))
    frame = Geom::Transformation.axes(Geom::Point3d.new(origin), *basis)
    frame = upright.inverse * frame if upright
    {frame: frame, bounds: bounds,
     thin: thin, u: u, width: lengths[u].to_mm, height: lengths[2].to_mm, thickness: lengths[thin].to_mm}
  end

  # Đầu `edge` của tấm ngàm có áp phẳng vào một mặt lớn của tấm nhận VÀ nằm trong phạm vi mặt đó
  # không (tấm ở xa mà tình cờ cùng mặt phẳng thì không tính). Trả thông tin trong hệ tấm nhận.
  def self.contact_info(source, edge, receiver, box)
    fd = frame_for(source, edge, box)
    map = receiver.transformation.inverse * source.transformation * fd[:frame]
    rb = board_bounds(receiver)
    sizes = [rb.width, rb.height, rb.depth]
    axis = sizes.each_with_index.min_by { |v, _i| v }[1]
    plane_axes = [0, 1, 2] - [axis]
    upward = map * Z_AXIS
    up = upward.to_a
    return nil unless plane_axes.all? { |i| up[i].abs < 0.000001 }
    # Tấm nhận có thể xoay hoặc lật: chọn mặt min/max thực sự đối diện cạnh mộng.
    contact = up[axis] > 0 ? rb.min.to_a[axis] : rb.max.to_a[axis]
    fb = fd[:bounds]
    corners = [[0, 0, fb.max.z], [fb.max.x, 0, fb.max.z], [fb.max.x, fb.max.y, fb.max.z], [0, fb.max.y, fb.max.z]].map { |p|
      (map * Geom::Point3d.new(p)).to_a
    }
    return nil unless corners.all? { |c| (c[axis] - contact).abs <= 0.01.mm }
    return nil unless corners.all? { |c|
      plane_axes.all? { |i| c[i] >= rb.min.to_a[i] - 0.5.mm && c[i] <= rb.max.to_a[i] + 0.5.mm }
    }
    {map: map, bounds: rb, axis: axis, plane_axes: plane_axes, upward: upward, contact: contact,
     thickness: sizes[axis]}
  end

  # Tính một đầu trong hệ cạnh. Kiểm hết trước khi đụng model; sai thì raise câu tiếng Việt.
  # receiver = nil: chỉ tính răng mộng (đầu cũ dựng lại, hoặc đầu không có tấm nhận).
  def self.plan_edge(source, spec, receiver, box, label)
    edge = spec.fetch('edge').to_i
    number = lambda do |key|
      v = spec[key]
      raise "#{label}nhập #{TEN_SO[key]} bằng số." unless v.is_a?(Numeric) && v.finite?
      v
    end
    fd = frame_for(source, edge, box)
    thin = fd[:thin]
    u_axis = fd[:u]
    bb = fd[:bounds]
    size = [bb.width, bb.height, bb.depth]
    width = size[u_axis]
    thickness = size[thin]
    top = size[2]
    quantity = number.call('count')
    raise "#{label}số mộng phải là số nguyên từ 1 trở lên." unless quantity >= 1 && quantity == quantity.to_i
    quantity = quantity.to_i
    head, height, diameter, bevel = %w[head height neck bevel].map { |k| number.call(k).mm }
    side = spec.fetch('side', 'none')
    raise "#{label}chọn Không phay / Phay mặt A / Phay mặt B." unless %w[none A B].include?(side)
    # Chỉ thu/dịch dấu âm theo thông số này. Hình mộng dương luôn dày bằng thân ván.
    fit_thickness = thickness
    fit_offset = 0.0
    keep_low = true
    narrow_mark = false
    if side != 'none'
      fit_thickness = number.call('fit').mm
      unless fit_thickness >= 1.mm && fit_thickness <= thickness + 0.001.mm
        raise "#{label}dày sau phay cần từ 1mm đến bề dày ván #{thickness.to_mm.round(3)}mm."
      end
      narrow_mark = thickness - fit_thickness > 0.001.mm
      if narrow_mark
        # Cặp layer theo dày sau phay; nil = chưa có dao mẫu Aspire. Chỉ CHẶN ở đầu MỚI (apply_pairs) — đầu đã
        # làm (chỉ đóng thêm dấu âm) không sinh dấu phay nên dày cũ nào cũng được.
        tags_phay = TAG_PHAY.find { |mm, _t| (fit_thickness.to_mm - mm).abs < 0.01 }
        # Giữ A: dấu bắt đầu ở mặt thấp; giữ B: lùi dấu bằng phần giảm.
        keep_low = side == 'A'
        fit_offset = keep_low ? 0.0 : thickness - fit_thickness
      else
        fit_thickness = thickness
      end
    end
    # Cung cổ bán kính bằng nửa đường kính dao; hai cổ không được chạm nhau.
    radius = diameter / 2.0
    unless head > diameter && diameter > 0 && height > diameter + bevel && bevel >= 0 && bevel < head / 2.0
      raise "#{label}rộng đầu phải lớn hơn đường kính cổ; cổ và vát phải thấp hơn đầu."
    end
    if quantity == 1
      raise "#{label}đầu tấm quá ngắn: một mộng cũng cần chừa ít nhất 1mm mỗi bên." if width - head < 2.0 * MIN_GAP
      centers = [width / 2.0] # Một mộng đặt chính giữa, không dùng khoảng lùi hai đầu.
    else
      inset = number.call('inset').mm
      if inset - head / 2.0 < MIN_GAP || inset >= width / 2.0
        raise "#{label}mép mộng cần cách đầu tấm ít nhất 1mm; tâm ngoài cùng phải nằm trước giữa đầu tấm."
      end
      # Nhịp tâm = phần dài giữa hai tâm ngoài cùng / số khoảng giữa các mộng.
      span = width - 2.0 * inset
      maximum = (span / (head + MIN_GAP) + 1.0e-9).floor + 1
      if quantity > maximum
        raise "#{label}không đủ chỗ cho #{quantity} mộng trên đầu dài #{width.to_mm.round(2)}mm — tối đa #{maximum}."
      end
      pitch = span / (quantity - 1)
      centers = Array.new(quantity) { |i| inset + i * pitch }
    end
    # Răng mộng đi từ trái sang phải trên cạnh trên; cung lõm mỗi bên có 12 đoạn.
    teeth = []
    arc_seams = []
    centers.each do |center|
      left = center - head / 2.0
      right = center + head / 2.0
      teeth << [left, top]
      1.upto(12) do |i|
        angle = -Math::PI / 2.0 + Math::PI * i / 12.0
        teeth << [left + radius * Math.cos(angle), top + radius + radius * Math.sin(angle)]
        arc_seams << teeth.last if i < 12
      end
      teeth << [left, top + height - bevel]
      teeth << [left + bevel, top + height]
      teeth << [right - bevel, top + height]
      teeth << [right, top + height - bevel]
      teeth << [right, top + diameter]
      1.upto(12) do |i|
        angle = Math::PI / 2.0 - Math::PI * i / 12.0
        teeth << [right - radius * Math.cos(angle), top + radius + radius * Math.sin(angle)]
        arc_seams << teeth.last if i < 12
      end
    end
    # DẤU PHAY MỘNG (Khoa): khi THU MỘT MẶT, ô chữ nhật phủ đầu mộng (rộng đầu × cao mộng)
    # lên MẶT BỊ THU = mặt đối diện mặt giữ, để báo CNC phay bớt.
    phay_rects = []
    vien_rects = []
    if narrow_mark
      reduced = keep_low ? thickness : 0.0
      # Ô chữ nhật [u trái, u phải] × [chân mộng, đỉnh] trên mặt bị thu.
      rect = lambda do |u0, u1, z1|
        [[u0, top], [u1, top], [u1, z1], [u0, z1]].map do |u, z|
          p = [0.0, 0.0, z]
          p[thin] = reduced
          p[u_axis] = u
          Geom::Point3d.new(p)
        end
      end
      phay_rects = centers.map { |c| rect.call(c - head / 2.0, c + head / 2.0, top + height) }
      # Ô viền: mỗi mộng nới VIEN_PHAY hai hông; hai mộng sát nhau (khe < 2×VIEN_PHAY) thì ô chồng
      # nhau -> gộp thành một ô để CNC không phay chồng hai đường.
      spans = centers.map { |c| [c - head / 2.0 - VIEN_PHAY, c + head / 2.0 + VIEN_PHAY] }
      merged = spans.each_with_object([]) do |(a, b), out|
        if out.any? && a <= out.last[1]
          out.last[1] = [out.last[1], b].max
        else
          out << [a, b]
        end
      end
      vien_rects = merged.map { |a, b| rect.call(a, b, top + height + VIEN_PHAY) }
    end
    plan = {edge: edge, fd: fd, quantity: quantity, centers: centers, teeth: teeth, arc_seams: arc_seams,
            height: height, thickness: thickness, fit_thickness: fit_thickness, narrow_mark: narrow_mark,
            keep_low: keep_low, phay_rects: phay_rects, vien_rects: vien_rects, receiver: receiver, mortises: [],
            tag_phay: narrow_mark && tags_phay ? tags_phay[1] : nil}
    return plan unless receiver
    raise "#{label}tấm nhận đang bị Scale hoặc xiên ở cấp group." unless rigid?(receiver)
    info = contact_info(source, edge, receiver, box)
    raise "#{label}đầu này không còn áp phẳng vào tấm nhận. Bấm Làm mới rồi kiểm vị trí." unless info
    slack_t, slack_l, cutter = %w[slackT slackL cutter].map { |k| number.call(k).mm }
    # Độ dư nhập là tổng, không cộng lại hai lần; cung lồi làm bao dài thêm 2R.
    mortise_t = fit_thickness + slack_t
    mortise_l = head + slack_l
    if slack_t < 0 || slack_l < 0 || cutter <= 0 || mortise_t - 2.0 * cutter < 1.mm
      raise "#{label}độ dư phải không âm, dao phải dương. Với dấu rộng #{mortise_t.to_mm.round(3)}mm, dao cần không quá #{((mortise_t - 1.mm) / 2.0).to_mm.round(3)}mm."
    end
    raise "#{label}mộng cao bằng hoặc vượt bề dày tấm nhận." if height >= info[:thickness]
    # Khe dấu tính theo cả hai cung lồi, không chỉ theo rộng đầu mộng dương.
    if quantity > 1 && centers[1] - centers[0] < mortise_l + cutter + MIN_GAP - 0.000001.mm
      raise "#{label}các dấu mộng âm quá sát/chồng nhau với độ dư và dao này. Giảm số mộng."
    end
    axis = info[:axis]
    rb = info[:bounds]
    thickness_direction = (info[:map] * AXES[thin]).to_a
    to_receiver = lambda do |t, u|
      p = [0.0, 0.0, top]
      p[thin] = t
      p[u_axis] = u
      coords = (info[:map] * Geom::Point3d.new(p)).to_a
      coords[axis] = info[:contact]
      coords
    end
    # Mặt tiếp giáp của tấm nhận: chỉ mặt nằm đúng mặt phẳng áp. Tấm nhận được phép có mộng/dấu
    # sẵn ở chỗ khác, nhưng chỗ mộng mới cắm vào phải là mặt ván phẳng liền.
    contact_faces = receiver.entities.grep(Sketchup::Face).select { |f|
      f.normal.to_a[axis].abs > 0.999999 && (f.vertices.first.position.to_a[axis] - info[:contact]).abs < 0.001.mm
    }
    on_face = [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex]
    old_marks = receiver.entities.grep(Sketchup::Group).select { |g| dau_abf?(g) }.map(&:bounds).select { |b|
      (b.min.to_a[axis] - info[:contact]).abs < 0.01.mm && (b.max.to_a[axis] - info[:contact]).abs < 0.01.mm
    }
    base = mortise_outline(mortise_t, mortise_l, cutter / 2.0)
    plan[:mortises] = centers.each_with_index.map do |center, index|
      # Chân mộng (rộng đầu × dày tính dấu) phải nằm trọn trên mặt phẳng của tấm nhận.
      foot = [[0.0, -head / 2.0], [fit_thickness, -head / 2.0], [fit_thickness, head / 2.0],
              [0.0, head / 2.0], [fit_thickness / 2.0, 0.0]].map { |t, du|
        Geom::Point3d.new(to_receiver.call(fit_offset + t, center + du))
      }
      unless foot.all? { |pt| contact_faces.any? { |f| on_face.include?(f.classify_point(pt)) } }
        raise "#{label}mộng #{index + 1} rơi vào chỗ mặt tấm nhận không phẳng (mộng cũ, lỗ hoặc ngoài mép)."
      end
      polygon = base.map do |t, u|
        # Dấu bám bề dày tính toán và bên giữ; hình mộng dương không bị giảm.
        coords = to_receiver.call(fit_offset + t - slack_t / 2.0, center - mortise_l / 2.0 + u)
        # Mẫu thực có dấu nhô khỏi cạnh bên 0.05mm do độ dư bề dày 0.1mm.
        # Chỉ cho phép phần nhô bằng nửa độ dư ấy; theo chiều dài phải ở trong tấm.
        inside = info[:plane_axes].all? { |i|
          allowance = thickness_direction[i].abs * slack_t / 2.0
          coords[i] >= rb.min.to_a[i] - allowance - 0.001.mm && coords[i] <= rb.max.to_a[i] + allowance + 0.001.mm
        }
        raise "#{label}dấu mộng âm vượt mép tấm nhận." unless inside
        Geom::Point3d.new(coords)
      end
      # Chặn đóng dấu chồng lên dấu cũ (vd bấm áp dụng hai lần cho cùng cặp).
      lo = info[:plane_axes].map { |i| polygon.map { |pt| pt.to_a[i] }.min }
      hi = info[:plane_axes].map { |i| polygon.map { |pt| pt.to_a[i] }.max }
      clash = old_marks.any? { |b|
        info[:plane_axes].each_with_index.all? { |i, k| [hi[k], b.max.to_a[i]].min - [lo[k], b.min.to_a[i]].max > 0.01.mm }
      }
      raise "#{label}chỗ mộng #{index + 1} trên tấm nhận đã có dấu sẵn — không đóng chồng." if clash
      polygon
    end
    plan[:upward] = info[:upward]
    plan
  end

  # ── Ghép cặp ──────

  # Tên đầu tấm "trái/phải" khi NHÌN TỪ MẶT A (đứng phía mặt A, nhìn vào tấm, Z hướng lên).
  # Tấm mỏng theo Y: u = +X hướng sang phải. Tấm mỏng theo X: nhìn từ mặt A thì +Y lại
  # hướng sang TRÁI, nên đầu 2/4 đổi tên cho khớp với bản vẽ xem trước.
  def self.edge_name(edge, thin)
    edge = {2 => 4, 4 => 2}.fetch(edge, edge) if thin == 0
    TEN_CANH[edge]
  end

  def self.board_label(group, role, index)
    "#{role == :ngam ? 'Ngàm' : 'Nhận'} #{index + 1}#{group.name.empty? ? '' : " · #{group.name}"}"
  end

  # Mọi cặp (tấm ngàm, đầu) ↔ tấm nhận đang áp vào. Trạng thái:
  #   moi     — đầu chưa làm: dựng mộng + đóng dấu
  #   chi_dau — đầu đã có mộng, tấm nhận MỚI: chỉ đóng dấu theo thông số đã ghi
  #   da_lam  — đầu đã có mộng và đã đóng dấu lên tấm này: không làm gì
  def self.pairs(tenons, receivers)
    list = []
    tenons.each_with_index do |t, ti|
      next if tenon_problem(t)
      box = tenon_box(t)
      mem = memory(t)
      (1..4).each do |edge|
        # Tấm nhận bị Scale: hệ tọa độ không đúng mm, không ghép (chip tấm đó đã báo đỏ).
        r = receivers.find { |g| rigid?(g) && contact_info(t, edge, g, box) }
        next unless r
        stored = mem && mem[:edges][edge]
        state = if stored.nil? then 'moi'
                elsif (stored['nhan'] || []).include?(r.persistent_id) then 'da_lam'
                else 'chi_dau'
                end
        fd = frame_for(t, edge, box)
        # Khóa theo persistent_id, không theo thứ tự: bớt một tấm khỏi danh sách thì thông số
        # đã gõ không trượt sang đầu của tấm khác (soát 02/10).
        list << {key: "#{t.persistent_id}-#{edge}", tenon: t, ti: ti, edge: edge, receiver: r, ri: receivers.index(r),
                 state: state, stored: stored, length: edge_length(fd, edge), block: state == 'moi' && dau_o_dau_tam?(t, box, edge) ? 'có dấu ABF (khoan/khoét) ngay trên mặt đầu này — mộng sẽ mọc đè lên dấu' : nil,
                 thickness: fd[:thickness], edge_name: edge_name(edge, fd[:thin])}
      end
    end
    list
  end

  # Độ dài đầu tấm (mm) = chiều u của hệ cạnh.
  def self.edge_length(fd, edge)
    [1, 3].include?(edge) ? fd[:width] : fd[:height]
  end

  # ── Dựng ──────

  # THÂN tấm dạng lăng trụ: một mặt A (t = 0) + một mặt B (t = dày), mọi mặt khác vuông góc trục dày,
  # mọi đỉnh nằm trên A hoặc B. Khe/lỗ KHOÉT XUYÊN (ngàm âm dương, lỗ đi dây) vẫn là lăng trụ → làm
  # được; rãnh/hốc KHÔNG xuyên (đỉnh lưng chừng bề dày) → nil. Trả đường viền mặt A trong hệ cạnh đầu 1.
  # (02/10: dựng từ hộp chữ nhật lấp mất khe khoét — giờ dựng từ đường viền thật.)
  def self.than_tam(group, box)
    fd1 = frame_for(group, 1, box)
    thin = fd1[:thin]
    inv = fd1[:frame].inverse
    t_max = [fd1[:bounds].width, fd1[:bounds].height, fd1[:bounds].depth][thin]
    f1 = ->(pt) { (inv * pt).to_a }
    faces = group.entities.grep(Sketchup::Face)
    edges = group.entities.grep(Sketchup::Edge)
    return nil if faces.empty?
    on_ab = edges.flat_map(&:vertices).uniq.all? { |v|
      t = f1.call(v.position)[thin]
      t.abs < 0.001.mm || (t - t_max).abs < 0.001.mm
    }
    return nil unless on_ab
    dir = fd1[:frame] * AXES[thin]
    bigs = faces.select { |f| f.normal.parallel?(dir) }
    return nil unless (faces - bigs).all? { |f| f.normal.perpendicular?(dir) }
    a = bigs.select { |f| f1.call(f.vertices.first.position)[thin].abs < 0.001.mm }
    return nil unless a.length == 1 && (bigs - a).length == 1
    loop_pts = ->(lp) { lp.vertices.map { |v| f1.call(v.position) } }
    {fd1: fd1, thin: thin, thickness: t_max, outer: loop_pts.call(a[0].outer_loop),
     inner: a[0].loops.reject(&:outer?).map(&loop_pts)}
  end

  # Chèn răng của các đầu MỚI vào đường viền thật. Mỗi răng phải nằm trọn trên MỘT đoạn thẳng của
  # viền trùng mép đầu đó; rơi vào chỗ khoét/khe thì raise trước khi đụng model.
  def self.chen_rang(prof, plans, label)
    fd1 = prof[:fd1]
    pts = prof[:outer]
    plans.each do |plan|
      fd = plan[:fd]
      to_e = fd[:frame].inverse * fd1[:frame]
      from_e = fd1[:frame].inverse * fd[:frame]
      top = fd[:bounds].depth
      ue = fd[:u]
      teeth = plan[:teeth].each_slice(30).to_a # mỗi răng 30 điểm, từ (trái, top) tới (phải, top)
      raise "#{label}răng mộng sai cấu trúc." unless teeth.length == plan[:quantity] && teeth.all? { |t| t.length == 30 }
      used = Array.new(teeth.length, false)
      out = []
      pts.each_with_index do |pt, i|
        out << pt
        pe = (to_e * Geom::Point3d.new(pt)).to_a
        qe = (to_e * Geom::Point3d.new(pts[(i + 1) % pts.length])).to_a
        next unless (pe[2] - top).abs < 0.001.mm && (qe[2] - top).abs < 0.001.mm
        lo, hi = [pe[ue], qe[ue]].minmax
        inside = teeth.each_index.select { |k|
          !used[k] && teeth[k].first[0] >= lo - 0.001.mm && teeth[k].last[0] <= hi + 0.001.mm
        }
        next if inside.empty?
        inside.each { |k| used[k] = true }
        seq = inside.map { |k| teeth[k] }
        seq = seq.reverse.map(&:reverse) if qe[ue] < pe[ue]
        seq.flatten(1).each do |u, z|
          e = [0.0, 0.0, z]
          e[ue] = u
          out << (from_e * Geom::Point3d.new(e)).to_a
        end
      end
      miss = used.index(false)
      if miss
        raise "#{label}đầu #{edge_name(plan[:edge], fd[:thin])}: mộng #{miss + 1} rơi vào chỗ khoét/khe trên mép tấm — đổi lùi tâm hoặc số mộng."
      end
      pts = out
    end
    # Bỏ điểm trùng liền kề (răng bắt đầu đúng góc khe).
    pts = pts.chunk_while { |a, b| Geom::Point3d.new(a).distance(Geom::Point3d.new(b)) < 0.0001.mm }.map(&:first)
    pts.pop while pts.length > 1 && Geom::Point3d.new(pts.first).distance(Geom::Point3d.new(pts.last)) < 0.0001.mm
    pts
  end

  # Dựng lại THÂN tấm ngàm từ đường viền thật đã chèn răng các đầu mới (`outer`, hệ cạnh đầu 1),
  # giữ lỗ xuyên + mọi group con + dấu phay cũ; rồi thêm dấu phay cho các đầu mới thu mặt.
  def self.build_tenon(model, source, box, plans, prof, outer)
    dropped, softened = dung_than(source, box, prof, outer)
    # Mỗi mộng có hai cung, mỗi cung 12 đoạn nên có 11 cạnh chia bên trong.
    expected = plans.sum { |pl| pl[:quantity] * 2 * 11 }
    raise "Làm mềm thiếu cạnh cung: #{softened}/#{expected}." if softened < expected
    them_dau_phay(model, source, plans)
    dropped
  end

  # Dựng lại THÂN tấm từ đường viền `outer` (hệ cạnh đầu 1) — dùng chung cho mọc mộng và GỠ mộng.
  # Giữ lỗ xuyên + mọi group con; chép lại vật liệu/vân/dán cạnh theo mặt phẳng. Trả [số mặt bỏ dán cạnh,
  # số cạnh cung đã làm mềm].
  def self.dung_than(source, box, prof, outer)
    fd1 = prof[:fd1]
    thin = prof[:thin]
    thickness = prof[:thickness]
    to_local = ->(a) { fd1[:frame] * Geom::Point3d.new(a) }
    to_f1 = fd1[:frame].inverse
    thin_local = [box.width, box.height, box.depth].each_with_index.min_by { |v, _i| v }[1]
    # Vật liệu + dán cạnh + thuộc tính từng mặt: chép trước khi xóa, dán lại theo mặt phẳng.
    dress = nho_mat(source.entities.grep(Sketchup::Face), thin_local)
    # Chỉ thay THÂN tấm (cạnh/mặt rời). Group con — dấu ABF, dấu âm tấm khác, dấu phay đầu cũ —
    # giữ nguyên; group, transformation, tên, tag, thuộc tính vỏ giữ.
    source.entities.erase_entities(source.entities.select { |e| e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face) })
    face = source.entities.add_face(outer.map(&to_local))
    raise 'Không dựng được mặt biên mộng.' unless face
    # SOÁT 04/10 P2: lỗ dựng hỏng (add_face nil) trước đây bị bỏ qua im lặng → tấm mất lỗ. Nay báo lỗi để
    # thao tác ngoài abort, và đếm lại lỗ trên hai mặt đáy/nắp sau khi đùn.
    prof[:inner].each do |lp|
      hole = source.entities.add_face(lp.map(&to_local))
      raise 'Không dựng lại được lỗ xuyên của tấm — chưa đổi gì.' unless hole
      hole.erase! if hole.valid? && hole != face
    end
    truc = fd1[:frame] * AXES[thin]
    face.reverse! if face.normal.dot(truc) < 0
    face.pushpull(thickness)
    lo = source.entities.grep(Sketchup::Face).select { |f| f.normal.dot(truc).abs > 0.999999 }.sum { |f| f.loops.length - 1 }
    raise "Dựng lại mất lỗ xuyên (#{lo}/#{2 * prof[:inner].length} vòng lỗ trên đáy+nắp) — chưa đổi gì." unless lo == 2 * prof[:inner].length
    dropped = dan_mat(source.entities.grep(Sketchup::Face), dress)
    # Làm mềm cạnh chia cung (răng cũ + mới, cung khoét có sẵn): cạnh dọc bề dày giữa hai mặt lệch
    # nhau dưới 20° — cung 12 đoạn lệch 15°/đoạn, góc vuông khe/mép không bị đụng.
    softened = 0
    cos20 = Math.cos(20.0 * Math::PI / 180.0)
    source.entities.grep(Sketchup::Edge).each do |e|
      next unless e.faces.length == 2
      a = (to_f1 * e.start.position).to_a
      b = (to_f1 * e.end.position).to_a
      next unless (a[thin] - b[thin]).abs > 0.001.mm
      next unless e.faces[0].normal.dot(e.faces[1].normal) > cos20
      e.soft = true
      e.smooth = true
      softened += 1
    end
    raise 'Khối có cạnh hở hoặc cạnh nối hơn hai mặt.' unless source.entities.grep(Sketchup::Edge).all? { |e| e.faces.length == 2 }
    [dropped, softened]
  end

  # Dấu phay mộng + viền cho các đầu thu một mặt trong `plans`.
  def self.them_dau_phay(model, source, plans)
    plans.each do |plan|
      tag_mong, tag_vien = plan[:tag_phay]
      raise "Đầu #{plan[:edge]}: chưa có layer Aspire cho dày sau phay này." if plan[:narrow_mark] && !tag_mong
      marks = plan[:phay_rects].map { |r| [r, tag_mong, 'phay mộng'] } +
              (plan[:vien_rects] || []).map { |r| [r, tag_vien, 'phay viền mộng'] }
      marks.each_with_index do |(rect, tag_name, ten), index|
        phay_tag = model.layers.to_a.find { |l| l.name == tag_name } || model.layers.add(tag_name)
        mark = source.entities.add_group
        # DẤU PHAY = _ABF_Intersect chuẩn ABF. ABF chỉ công nhận intersect là CẶP A↔B:
        # b-id phải trỏ tấm ĐỐI TÁC, KHÔNG tự trỏ mình (đo thật 17/09 probes/soi_bid_intersect.rb:
        # dấu tự trỏ -> DXF rớt LAYER0). Phay đầu mộng do tấm NHẬN gây ra nên b-id trỏ tấm nhận.
        mark.name = '_ABF_Intersect'
        mark.layer = phay_tag
        mark_face = mark.entities.add_face(rect.map { |p| plan[:fd][:frame] * p })
        raise "Đầu #{plan[:edge]}: không tạo được dấu #{ten} #{index + 1}." unless mark_face
        mark_face.layer = phay_tag # ABF đọc tag MẶT để đặt layer DXF (xem ghi chú đầu file)
        mark.entities.grep(Sketchup::Edge).each { |e| e.layer = phay_tag }
        mark.set_attribute('ABF', 'is-intersect', true)
        mark.set_attribute('ABF', 'intersect-offset', 0.0)
        mark.set_attribute('ABF', 'intersect-x', (plan[:thickness] - plan[:fit_thickness]).to_mm)
        mark.set_attribute('ABF', 'intersect-group-b-id', plan[:phay_b] || source.persistent_id)
        mark.set_attribute('ABF', 'setting-name', 'PHAYDAUMONG_KHOA')
      end
    end
  end

  # ── GỠ MỘNG (Khoa 03/10: "mọc rồi không gỡ được, phải vẽ lại cả tấm" = điểm chết người) ──
  # Đường viền thật bỏ mọi điểm nằm NGOÀI mép đầu (z > mép — răng + cung cổ), bỏ điểm thẳng hàng, dựng lại
  # thân bằng ĐÚNG đường dựng khi mọc (dung_than). Dấu phay/viền của đầu đó (trên tấm ngàm) và dấu âm (trên
  # tấm nhận) tìm theo VỊ TRÍ, không theo pid (file copy/import đổi pid — vụ CCandy 03/10). Gỡ hết đầu →
  # xoá ghi nhớ, tấm thành tấm thường (làm mộng lại được). Mặt đầu từng bị bỏ dán cạnh lúc mọc thì không
  # tự có lại dán cạnh — báo người dùng dán lại.
  def self.tag_dau(mk)
    f = mk.entities.grep(Sketchup::Face).first
    [mk.layer.name, f && f.layer.name]
  end

  def self.diem_mat(mk, tr)
    mk.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map { |v| tr * v.position } }
  end

  def self.bo_thang_hang(pts)
    loop do
      n = pts.length
      bo = (0...n).find do |i|
        a = pts[(i - 1) % n]; b = pts[i]; c = pts[(i + 1) % n]
        ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
        bc = [c[0] - b[0], c[1] - b[1], c[2] - b[2]]
        cr = [ab[1] * bc[2] - ab[2] * bc[1], ab[2] * bc[0] - ab[0] * bc[2], ab[0] * bc[1] - ab[1] * bc[0]]
        la = Math.sqrt(ab.sum { |v| v * v }); lb = Math.sqrt(bc.sum { |v| v * v })
        la < 1e-9 || lb < 1e-9 || (Math.sqrt(cr.sum { |v| v * v }) / (la * lb) < 1e-7 && ab.zip(bc).sum { |x, y| x * y } > 0)
      end
      break pts unless bo && n > 3
      pts = pts.each_with_index.reject { |_p, i| i == bo }.map(&:first)
    end
  end

  # TÍNH (chưa đụng model): đường viền mới + các dấu phải xoá. Raise nếu không gỡ an toàn được.
  def self.tinh_go(tenon, edges)
    mem = memory(tenon)
    raise 'tấm không có mộng do tool này làm.' unless mem
    edges = edges.map(&:to_i) & mem[:edges].keys
    raise 'đầu này không có mộng để gỡ.' if edges.empty?
    raise 'đã bị sửa hình/kích thước sau khi làm mộng — không gỡ tự động được.' unless khop_ghi_nho?(tenon, mem)
    box = mem[:box]
    prof = than_tam(tenon, box)
    raise 'thân tấm có rãnh/hốc không xuyên — không gỡ tự động được.' unless prof
    fd1 = prof[:fd1]
    outer = prof[:outer]
    xoa = []
    nhan = []
    edges.each do |e|
      fd = frame_for(tenon, e, box)
      top = fd[:bounds].depth.to_f
      dims = [fd[:bounds].width, fd[:bounds].height, fd[:bounds].depth].map(&:to_f)
      len = dims[fd[:u]]
      tk = dims[fd[:thin]]
      to_e = fd[:frame].inverse * fd1[:frame]
      outer = outer.reject { |pt| (to_e * Geom::Point3d.new(pt)).z.to_f > top + 0.001.mm }
      h = (mem[:edges][e]['height'] || 10).to_f.mm
      # dấu phay + viền của đầu này: nằm giữa mép và đỉnh răng (+ viền), trên tấm ngàm
      inv = fd[:frame].inverse
      tenon.entities.each do |c|
        next unless dau_phay_cua_tool?(c)
        zs = diem_mat(c, inv * c.transformation).map { |q| q.z.to_f }
        xoa << c if !zs.empty? && zs.min > top - 0.01.mm && zs.max < top + h + VIEN_PHAY + 0.5.mm
      end
      # dấu âm trên tấm nhận: mặt dấu nằm ĐÚNG mặt phẳng mép đầu, trong phạm vi đầu
      wt = (tenon.transformation * fd[:frame]).inverse
      tenon.parent.entities.each do |b|
        next unless (b.is_a?(Sketchup::Group) || b.is_a?(Sketchup::ComponentInstance)) && b != tenon
        b.definition.entities.each do |mk|
          next unless dau_abf?(mk) && tag_dau(mk).include?(TAG_MONG_AM)
          pts = diem_mat(mk, wt * b.transformation * mk.transformation)
          next if pts.empty?
          next unless pts.all? { |q| (q.z.to_f - top).abs < 0.05.mm }
          next unless pts.all? { |q| a = q.to_a.map(&:to_f); a[fd[:thin]] > -1.mm && a[fd[:thin]] < tk + 1.mm }
          # Theo chiều dài xét TÂM dấu, không xét mọi điểm: cung dao + dư dài làm dấu nhô quá đầu răng ~3mm,
          # mộng sát mép (lùi tâm nhỏ) thì dấu lòi khỏi đầu tấm mà vẫn là của đầu này (soát 03/10).
          tam_u = pts.sum { |q| q.to_a[fd[:u]].to_f } / pts.length
          next unless tam_u > 0 && tam_u < len
          xoa << mk
          nhan << b
        end
      end
    end
    {tenon: tenon, edges: edges, box: box, prof: prof, outer: bo_thang_hang(outer), xoa: xoa.uniq, nhan: nhan.uniq, mem: mem}
  end

  # GỠ mộng: list = [[tấm ngàm, [đầu...]], ...]. Một thao tác Ctrl+Z. Trả câu báo.
  def self.go_mong(list)
    model = Sketchup.active_model
    list.each { |t, es| tinh_go(t, es) } # sai thì raise TRƯỚC khi đụng model
    model.start_operation('Go mong xuong cho', true)
    begin
      # Tách bản dùng chung TRƯỚC (tấm ngàm + tấm nhận có dấu sắp xoá), rồi tính lại trên entity mới:
      # xoá dấu trong definition dùng chung là xoá lây sang tấm copy.
      list.each { |t, es| ([t] + tinh_go(t, es)[:nhan]).each(&:make_unique) }
      kqs = list.map { |t, es| tinh_go(t, es) }

      so_dau = 0
      kqs.each do |k|
        t = k[:tenon]
        so_dau += k[:xoa].count { |mk| tag_dau(mk).include?(TAG_MONG_AM) }
        k[:xoa].each { |mk| mk.erase! if mk.valid? }
        dung_than(t, k[:box], k[:prof], k[:outer])
        con = k[:mem][:edges].reject { |e, _| k[:edges].include?(e) }
        if con.empty?
          t.attribute_dictionaries.delete(MEM)
          bb = board_bounds(t)
          ok = (bb.min.to_a + bb.max.to_a).zip(k[:box].min.to_a + k[:box].max.to_a).all? { |a, b| (a.to_f - b.to_f).abs < 0.01.mm }
          raise "#{t.name}: gỡ xong mà tấm không về đúng kích thước gốc — hủy." unless ok
        else
          write_memory(t, k[:box], con)
          raise "#{t.name}: gỡ xong mà hình không khớp ghi nhớ — hủy." unless khop_ghi_nho?(t, memory(t))
        end
      end
      model.commit_operation
      dau = kqs.sum { |k| k[:edges].length }
      "Đã gỡ #{dau} đầu mộng trên #{kqs.length} tấm ngàm, xoá #{so_dau} dấu âm trên tấm nhận." \
        ' Mặt đầu vừa gỡ không tự có lại dán cạnh (mất lúc mọc mộng) — dán lại nếu cần. Ctrl+Z để hoàn tác.'
    rescue StandardError
      model.abort_operation
      raise
    end
  end



  # Nhớ từng mặt thân tấm: mặt phẳng, vật liệu, vân (UV tại 3 điểm), mọi attribute dictionary
  # (ABF edge-band-id, Hung_EdgeBanding...). side = vật liệu mặt cạnh hay gặp nhất, cho mặt răng mới.
  def self.nho_mat(faces, thin)
    olds = faces.map do |f|
      uv = nil
      if f.material && f.material.texture
        vs = f.outer_loop.vertices.map(&:position)
        p0 = vs.first
        p1 = vs.max_by { |p| p.distance(p0) }
        p2 = vs.max_by { |p| ((p1 - p0) * (p - p0)).length }
        uvh = f.get_UVHelper(true, false)
        uv = [p0, p1, p2].flat_map { |p| q = uvh.get_front_UVQ(p); [p, Geom::Point3d.new(q.x / q.z, q.y / q.z, 1.0)] }
      end
      dicts = (f.attribute_dictionaries || []).map { |d| [d.name, d.keys.map { |k| [k, d[k]] }] }
      {normal: f.normal, point: f.vertices.first.position, mat: f.material, back: f.back_material, uv: uv,
       dicts: dicts, side: f.normal.to_a[thin].abs <= 0.999999}
    end
    sides = olds.select { |o| o[:side] }.map { |o| [o[:mat], o[:back]] }
    {olds: olds, side: sides.max_by { |m| sides.count(m) }}
  end

  # GIỚI HẠN ĐÃ BIẾT (SOÁT Codex 04/10, Khoa chấp nhận vì dán chỉ là công đoạn sau cùng — bảng có dòng nhắc):
  # ghép theo mặt phẳng nên hai mép ĐỒNG PHẲNG (khe chữ U) bị coi là một → mất dán cạnh, đoạn sau nhận vật liệu
  # đoạn đầu; mặt cũ lật hướng không nhận lại dán cạnh. Bản ghép theo miền (f607bca) bị trả lại vì sinh lỗi mới.
  # Dán lại: mặt mới trùng mặt phẳng mặt cũ nhận vật liệu/vân; attribute chỉ chép khi mặt phẳng đó còn
  # ĐÚNG MỘT mặt (mặt lớn, đầu không mộng). Đầu mọc mộng bị răng chia nhiều mặt → bỏ dán cạnh ở đầu
  # đó (đầu đã cắm vào tấm nhận). Mặt răng mới nhận vật liệu mặt cạnh chung. Trả số mặt bỏ dán cạnh.
  def self.dan_mat(faces, dress)
    olds = dress[:olds]
    match = faces.map { |f|
      p = f.vertices.first.position
      olds.index { |o| f.normal.dot(o[:normal]) > 0.999999 && (p - o[:point]).dot(o[:normal]).abs < 0.001.mm }
    }
    dropped = []
    faces.zip(match).each do |f, i|
      o = i && olds[i]
      mat, back = o ? [o[:mat], o[:back]] : (dress[:side] || [nil, nil])
      if o && o[:uv]
        begin
          f.position_material(mat, o[:uv], true)
        rescue ArgumentError => ex
          puts "XUONG CHO vân: #{ex.message}"
          f.material = mat
        end
      else
        f.material = mat
      end
      f.back_material = back
      next unless o && !o[:dicts].empty?
      if match.count(i) == 1
        o[:dicts].each { |name, pairs| pairs.each { |k, v| f.set_attribute(name, k, v) } }
      else
        dropped << i
      end
    end
    dropped.uniq.length
  end

  # DẤU MỘNG ÂM = hốc khoét trên tấm NHẬN do mộng dương tấm NGÀM đâm vào; b-id trỏ tấm ngàm.
  # intersect-x = độ sâu hốc = cao mộng.
  def self.stamp_marks(model, source, plan)
    receiver = plan[:receiver]
    tag = model.layers.to_a.find { |l| l.name == TAG_MONG_AM } || model.layers.add(TAG_MONG_AM)
    plan[:mortises].each_with_index do |polygon, index|
      mark = receiver.entities.add_group
      mark.name = '_ABF_Intersect'
      mark.layer = tag
      mark_face = mark.entities.add_face(polygon)
      raise "Đầu #{plan[:edge]}: không tạo được dấu âm #{index + 1}." unless mark_face
      mark_face.reverse! if mark_face.normal.dot(plan[:upward]) > 0
      mark_face.layer = tag # ABF đọc tag MẶT để đặt layer DXF (xem ghi chú đầu file)
      mark_edges = mark.entities.grep(Sketchup::Edge)
      raise "Đầu #{plan[:edge]}: dấu âm #{index + 1} không đủ 52 cạnh." unless mark_edges.length == 52
      mark_edges.each { |e| e.layer = tag }
      mark.set_attribute('ABF', 'is-intersect', true)
      mark.set_attribute('ABF', 'intersect-offset', 0.0)
      mark.set_attribute('ABF', 'intersect-x', plan[:height].to_mm)
      mark.set_attribute('ABF', 'setting-name', 'PHÂY RÃNH HẬU 10LY')
      mark.set_attribute('ABF', 'intersect-group-b-id', source.persistent_id)
    end
  end

  # data = {'shape' => {head, height, neck, bevel, slackT, slackL, cutter},
  #         'rows' => [{'key' => "ti-edge", 'count', 'inset', 'side', 'fit'}, ...]}
  # Chỉ các cặp moi/chi_dau có trong rows mới được làm. Tất cả trong MỘT thao tác Ctrl+Z.
  # rieng_thao_tac = false: người gọi (vd Tạo Hộc Kéo) đã mở thao tác — không start/commit/abort ở đây,
  # lỗi thì raise để người gọi hủy cả lượt (hộc + mộng + rãnh là một lần Ctrl+Z).
  def self.apply_pairs(data, tenons, receivers, rieng_thao_tac = true)
    model = Sketchup.active_model
    shape = data.fetch('shape')
    rows = data.fetch('rows').map { |r| [r.fetch('key'), r] }.to_h
    todo = pairs(tenons, receivers).select { |p| p[:state] != 'da_lam' && rows.key?(p[:key]) }
    raise 'Không có cặp nào cần làm.' if todo.empty?
    raise 'Danh sách tấm đã đổi so với bảng. Bấm Làm mới rồi áp dụng lại.' unless todo.length == rows.length
    # Tính hết mọi đầu trước khi đụng model: một đầu sai thì không đầu nào bị sửa.
    jobs = todo.group_by { |p| p[:tenon] }.map do |tenon, list|
      box = tenon_box(tenon)
      mem = memory(tenon)
      edges = mem ? mem[:edges].dup : {}
      name = board_label(tenon, :ngam, list.first[:ti])
      mark_plans = []
      fresh = []
      list.each do |p|
        label = "#{name}, đầu #{p[:edge_name]} → #{board_label(p[:receiver], :nhan, p[:ri])}: "
        if p[:state] == 'moi'
          spec = shape.merge(rows[p[:key]].slice('count', 'inset', 'side', 'fit')).merge('edge' => p[:edge])
          plan = plan_edge(tenon, spec, p[:receiver], box, label)
          if plan[:narrow_mark] && !plan[:tag_phay]
            raise "#{label}chưa có layer Aspire cho dày sau phay #{plan[:fit_thickness].to_mm.round(2)}mm — chỉ làm #{TAG_PHAY.keys.map(&:to_i).join(' hoặc ')}mm."
          end
          plan[:phay_b] = p[:receiver].persistent_id
          fresh << plan
          edges[p[:edge]] = spec.slice(*SPEC_KEYS).merge('edge' => p[:edge], 'nhan' => [p[:receiver].persistent_id],
                                                            'phay_b' => p[:receiver].persistent_id)
        else
          # Đầu đã làm: đóng dấu theo đúng thông số đã ghi, không theo bảng.
          plan = plan_edge(tenon, p[:stored], p[:receiver], box, label)
          edges[p[:edge]] = p[:stored].merge('nhan' => (p[:stored]['nhan'] || []) + [p[:receiver].persistent_id])
        end
        mark_plans << plan
      end
      # Có đầu mới thì dựng lại cả tấm: đầu cũ tính lại từ thông số đã ghi (không đóng dấu lại).
      rebuild = nil
      prof = nil
      outer = nil
      unless fresh.empty?
        fresh.each do |pl|
          raise "#{name}: đầu #{edge_name(pl[:edge], pl[:fd][:thin])} có dấu ABF ngay trên mặt đầu — mộng sẽ đè lên dấu." if dau_o_dau_tam?(tenon, box, pl[:edge])
        end
        # Đầu cũ giữ nguyên răng + dấu phay; chỉ chèn răng đầu mới vào đường viền thật hiện tại.
        prof = than_tam(tenon, box)
        raise "#{name}: thân tấm có rãnh/hốc KHÔNG xuyên hết bề dày — tool chỉ mọc mộng trên tấm phẳng (khoét xuyên thì được)." unless prof
        outer = chen_rang(prof, fresh, "#{name}, ")
        rebuild = fresh
      end
      {tenon: tenon, box: box, edges: edges, marks: mark_plans, rebuild: rebuild, prof: prof, outer: outer}
    end
    model.start_operation('Tao mong xuong cho', true) if rieng_thao_tac
    begin
      # Group copy có thể dùng chung definition. Tách trước khi sửa để không đổi các bản khác.
      touched = (jobs.map { |j| j[:tenon] } + jobs.flat_map { |j| j[:marks].map { |pl| pl[:receiver] } }).uniq
      touched.each(&:make_unique)
      raise 'Group không còn hợp lệ sau khi tách bản dùng chung.' unless touched.all?(&:valid?)
      # ABF chỉ NHẬN + GÁN NHÃN group nào đeo ABF/is-board ở vỏ tấm (đo thật 17/09/2026).
      touched.each { |g| dam_bao_la_van(g) }
      teeth = 0
      marks = 0
      dropped = 0
      jobs.each do |job|
        if job[:rebuild]
          dropped += build_tenon(model, job[:tenon], job[:box], job[:rebuild], job[:prof], job[:outer])
          teeth += job[:rebuild].sum { |pl| pl[:quantity] }
        end
        job[:marks].each do |plan|
          stamp_marks(model, job[:tenon], plan)
          marks += plan[:mortises].length
        end
        write_memory(job[:tenon], job[:box], job[:edges])
      end
      model.commit_operation if rieng_thao_tac
      puts "XUONG CHO: #{jobs.length} tấm ngàm, #{jobs.count { |j| j[:rebuild] }} tấm dựng lại (#{teeth} mộng), #{marks} dấu âm."
      "Đã làm #{todo.length} cặp: #{marks} dấu âm#{teeth > 0 ? ", dựng lại #{jobs.count { |j| j[:rebuild] }} tấm ngàm" : ''}#{dropped > 0 ? " (bỏ dán cạnh/thuộc tính ở #{dropped} mặt đầu mọc mộng)" : ''}. Ctrl+Z một lần để hoàn tác cả lượt."
    rescue => ex
      model.abort_operation if rieng_thao_tac
      puts "LOI: #{ex.class}: #{ex.message}"
      raise
    end
  end

  # Mọc mộng KHÔNG THU cho mọi cặp mới giữa `tenons` ↔ `receivers` (cùng entities cha), dùng cho tool khác
  # (Tạo Hộc Kéo 03/10). shape = hình mộng chung; theo_dau.(pair) → {'count'=>, 'inset'=>} cho từng đầu.
  # Không mở thao tác riêng. Trả số cặp đã làm.
  def self.tu_dong(tenons, receivers, shape, theo_dau)
    list = pairs(tenons, receivers).select { |p| p[:state] == 'moi' }
    return 0 if list.empty?
    rows = list.map { |p| d = theo_dau.call(p); {'key' => p[:key], 'count' => d['count'], 'inset' => d['inset'], 'side' => 'none', 'fit' => 0} }
    apply_pairs({'shape' => shape, 'rows' => rows}, tenons, receivers, false)
    list.length
  end

  # Đóng dấu "đây là tấm ván" mà ABF dùng để nhận + gán nhãn (is-board ở vỏ tấm).
  # Chỉ ghi key CÒN THIẾU, không đè giá trị ABF có thể đã có. board-index để ABF tự
  # đánh khi nesting nên không set ở đây (set cứng dễ trùng số giữa các tấm).
  def self.dam_bao_la_van(group)
    return unless group && group.valid?
    dict = (group.attribute_dictionary('ABF') rescue nil)
    group.set_attribute('ABF', 'is-board', true)    unless dict && dict.keys.include?('is-board')
    group.set_attribute('ABF', 'label-rotation', 0) unless dict && dict.keys.include?('label-rotation')
  end

  # ── Vẽ trên model + bắt cú bấm ──────
  # Công cụ chiếm chuột trong lúc bảng mở, nên nó tự bắt cú bấm: bấm tấm = thêm/bớt tấm đó
  # vào nhóm đang chọn trên bảng (ngàm/nhận). Vẽ bằng draw2d để luôn nổi trên hình.
  class RoleTool
    ORANGE = Sketchup::Color.new(234, 88, 12)
    BLUE   = Sketchup::Color.new(37, 99, 235)
    HOT    = Sketchup::Color.new(219, 39, 119)

    def initialize
      @lines = []
      @texts = []
      @focus = []
    end

    # lines: [[color, width, [p1, p2, ...]]]; texts: [[point, text, color, size]] (world)
    def set(lines, texts, focus)
      @lines, @texts = lines, texts
      self.focus = focus
    end

    def focus=(lines)
      @focus = lines
      view = Sketchup.active_model.active_view
      view.invalidate if view
    end

    def draw(view)
      (@lines + @focus).each do |color, width, pts|
        next if pts.empty?
        view.line_width = width
        view.drawing_color = color
        view.draw2d(GL_LINES, pts.map { |p| view.screen_coords(p) })
      end
      @texts.each do |pt, text, color, size|
        s = view.screen_coords(pt)
        view.draw_text(Geom::Point3d.new(s.x, s.y, 0), text, color: color, size: size, bold: true, align: TextAlignCenter)
      end
    rescue => ex
      puts "XUONG CHO vẽ: #{ex.message}" unless @failed
      @failed = true
    end

    def onLButtonDown(_flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      active = Sketchup.active_model.active_entities.to_a
      group = nil
      ph.count.times do |i|
        group = ph.path_at(i).find { |e| e.is_a?(Sketchup::Group) && active.include?(e) }
        break if group
      end
      TK::MongXuongCho.toggle_board(group) if group
    rescue => ex
      puts "XUONG CHO bấm tấm: #{ex.message}"
    end

    def deactivate(view); view.invalidate; end
    def resume(view); view.invalidate; end
  end

  # ── Bảng ──────

  def self.check_context
    raise 'Model đã đổi. Đóng bảng rồi mở lại.' unless Sketchup.active_model == @model
    raise 'Đã đổi cấp chỉnh sửa (mở/đóng group). Đóng bảng rồi mở lại.' unless (@model.active_path || []) == @path
    # Group/module đang mở bị Scale: mm trong tấm không còn là mm thật, mộng ra méo mà tấm vẫn "lành".
    unless rigid_t?(path_transform)
      raise "Group/module đang mở (#{@path.map { |i| i.name.empty? ? i.definition.name : i.name }.join(' › ')}) bị Scale — thoát ra ngoài, gỡ Scale module rồi làm lại."
    end
    @tenons.select!(&:valid?)
    @receivers.select!(&:valid?)
  end

  def self.toggle_board(group)
    check_context
    mine, other = @mode == :ngam ? [@tenons, @receivers] : [@receivers, @tenons]
    if mine.include?(group)
      mine.delete(group)
    else
      other.delete(group)
      mine << group
    end
    refresh
  rescue => ex
    show_error(ex.message)
  end

  def self.take_selection(role)
    check_context
    picked = @model.selection.grep(Sketchup::Group)
    raise 'Chưa chọn group tấm nào trên model (bấm phím Space để quét chọn, rồi bấm lại nút này).' if picked.empty?
    mine, other = role == :ngam ? [@tenons, @receivers] : [@receivers, @tenons]
    # THAY danh sách bằng vùng chọn, không cộng dồn (Khoa 09/10: làm xong cặp cũ, chọn tấm mới vẫn dính tấm
    # cũ, phải "Xóa hết" trước — LUAT_NHA mục 10). Muốn thêm từng tấm: click tấm trên model.
    mine.clear
    picked.each do |g|
      other.delete(g)
      mine << g unless mine.include?(g)
    end
    @focus = nil
    @mode = role
    @model.select_tool(@tool)
    refresh
  rescue => ex
    show_error(ex.message)
  end

  # Bọc callback của bảng: lỗi hiện lên dòng trạng thái thay vì chết im trong Console.
  def self.safely
    yield
  rescue => ex
    puts "XUONG CHO UI: #{ex.class}: #{ex.message}"
    show_error(ex.message)
  end

  def self.show_error(message)
    @dlg.execute_script("window.showMessage(#{("Lỗi: " + message).to_json}, true)") if @dlg
  end

  def self.path_transform
    (@model.active_path || []).inject(Geom::Transformation.new) { |t, g| t * g.transformation }
  end

  # Tính lại toàn bộ: cặp, dữ liệu bảng, hình vẽ trên model.
  def self.refresh
    check_context
    world = path_transform
    @pairs = pairs(@tenons, @receivers)
    lines = []
    texts = []
    board_lines = lambda do |g, color|
      tr = world * g.transformation
      pts = g.entities.grep(Sketchup::Edge).flat_map { |e| [tr * e.start.position, tr * e.end.position] }
      lines << [color, 3, pts]
    end
    tenon_rows = @tenons.each_with_index.map do |g, i|
      problem = tenon_problem(g)
      board_lines.call(g, problem ? RoleTool::HOT : RoleTool::ORANGE)
      box = tenon_box(g) || g.definition.bounds
      tr = world * g.transformation
      texts << [tr * box.center, "Ngàm #{i + 1}", RoleTool::ORANGE, 16]
      sizes = [box.width, box.height, box.depth]
      thin = sizes.each_with_index.min_by { |v, _i| v }[1]
      row = {label: board_label(g, :ngam, i), problem: problem, scaled: !rigid?(g) && !skew?(g)}
      # Chữ A/B đặt NGOÀI hai mặt lớn, cách mặt 60mm theo pháp tuyến: nhìn xiên là tách hẳn
      # hai phía, không đè lên nhãn "Ngàm" ở giữa tấm.
      { 'A' => box.min.to_a[thin] - 60.mm, 'B' => box.max.to_a[thin] + 60.mm }.each do |name, v|
        c = box.center.to_a
        c[thin] = v
        texts << [tr * Geom::Point3d.new(c), "mặt #{name}", Sketchup::Color.new(36, 98, 124), 14]
      end
      # Dữ liệu vẽ xem trước: mặt tấm (u × z) nhìn từ mặt A + các đầu đã làm từ trước.
      fd = frame_for(g, 1, box)
      mem = memory(g)
      row.merge(faceW: fd[:width], faceH: fd[:height], thickness: fd[:thickness], mirror: fd[:thin] == 0,
                done: mem ? mem[:edges].map { |e, spec| spec.merge('edge' => e) } : [])
    end
    receiver_rows = @receivers.each_with_index.map do |g, i|
      board_lines.call(g, RoleTool::BLUE)
      texts << [world * g.transformation * board_bounds(g).center, "Nhận #{i + 1}", RoleTool::BLUE, 16]
      {label: board_label(g, :nhan, i), problem: scale_problem(g), scaled: !rigid?(g) && !skew?(g)}
    end
    @tool.set(lines, texts, focus_lines(@focus))
    rows = @pairs.map do |p|
      {key: p[:key], ti: p[:ti], tenon: board_label(p[:tenon], :ngam, p[:ti]), edge: p[:edge], edgeName: p[:edge_name],
       receiver: board_label(p[:receiver], :nhan, p[:ri]), state: p[:state], length: p[:length],
       thickness: p[:thickness], stored: p[:stored], block: p[:block]}
    end
    data = {mode: @mode.to_s, tenons: tenon_rows, receivers: receiver_rows, pairs: rows, live: true}
    @dlg.execute_script("window.receiveModel(#{JSON.generate(data)})") if @dlg
  end

  # Cặp đang chọn trên bảng: tô hồng đậm đầu tấm ngàm + viền tấm nhận.
  def self.focus_lines(key)
    pair = (@pairs || []).find { |p| p[:key] == key }
    return [] unless pair
    world = path_transform
    fd = frame_for(pair[:tenon], pair[:edge], tenon_box(pair[:tenon]))
    b = fd[:bounds]
    tr = world * pair[:tenon].transformation * fd[:frame]
    edge_pts = [[0, 0], [b.max.x, 0], [b.max.x, b.max.y], [0, b.max.y]].map { |x, y| tr * Geom::Point3d.new(x, y, b.max.z) }
    rtr = world * pair[:receiver].transformation
    rpts = pair[:receiver].entities.grep(Sketchup::Edge).flat_map { |e| [rtr * e.start.position, rtr * e.end.position] }
    [[RoleTool::HOT, 7, edge_pts.each_cons(2).to_a.flatten + [edge_pts.last, edge_pts.first]], [RoleTool::HOT, 4, rpts]]
  end

  def self.run
    if @dlg && @dlg.visible?
      @dlg.bring_to_front
      return
    end
    @model = Sketchup.active_model
    @path = (@model.active_path || []).dup
    @tenons = []
    @receivers = []
    @pairs = []
    @focus = nil
    @mode = :ngam
    @tool = RoleTool.new
    @dlg = UI::HtmlDialog.new(dialog_title: 'Mộng xương chó', preferences_key: 'khoa.mong.visual.v2',
      width: 1000, height: 780, min_width: 760, min_height: 560, resizable: true)
    dialog = @dlg
    dialog.set_file(File.join(PATH, 'giao_dien.html'))
    dialog.add_action_callback('ready') do |_c|
      @model.select_tool(@tool)
      safely { refresh }
    end
    dialog.add_action_callback('mode') { |_c, m| @mode = m == 'nhan' ? :nhan : :ngam; @model.select_tool(@tool) }
    dialog.add_action_callback('take') { |_c, m| take_selection(m == 'nhan' ? :nhan : :ngam) }
    dialog.add_action_callback('clear') do |_c, m|
      (m == 'nhan' ? @receivers : @tenons).clear
      @focus = nil
      safely { refresh }
    end
    dialog.add_action_callback('refresh') { |_c| safely { refresh } }
    dialog.add_action_callback('focus') do |_c, key|
      @focus = key
      safely { @tool.focus = focus_lines(key) }
    end
    dialog.add_action_callback('apply') do |_c, json|
      begin
        check_context
        message = apply_pairs(JSON.parse(json), @tenons, @receivers)
        # Xong việc thì NHẢ danh sách (LUAT_NHA mục 10): lượt sau chọn tấm mới không dính cặp vừa làm.
        @tenons.clear
        @receivers.clear
        @focus = nil
        refresh
        message = "#{message} Đã nhả danh sách — chọn tấm mới để làm tiếp."
        dialog.execute_script("window.applyFinished(true, #{message.to_json})")
      rescue => ex
        puts "XUONG CHO UI: #{ex.class}: #{ex.message}"
        dialog.execute_script("window.applyFinished(false, #{("Lỗi: " + ex.message).to_json})")
      end
    end
    dialog.add_action_callback('unscale') do |_c|
      safely do
        check_context
        done = go_scale(@tenons + @receivers)
        refresh
        @dlg.execute_script("window.showMessage(#{("Đã gỡ Scale — ĐO LẠI BỀ DÀY: " + done.join(' · ') + ' (mm). Ctrl+Z để hoàn tác.').to_json}, false)") if @dlg
      end
    end
    # GỠ mộng (03/10): một đầu (nút Gỡ trên dòng cặp đã làm) hoặc mọi đầu của các tấm ngàm đang chọn
    dialog.add_action_callback('go') do |_c, key|
      begin
        check_context
        p = (@pairs || []).find { |x| x[:key] == key }
        raise 'Không thấy cặp này nữa — bấm Làm mới.' unless p
        message = go_mong([[p[:tenon], [p[:edge]]]])
        refresh
        dialog.execute_script("window.applyFinished(true, #{message.to_json})")
      rescue => ex
        puts "XUONG CHO gỡ: #{ex.class}: #{ex.message}"
        dialog.execute_script("window.applyFinished(false, #{("Lỗi gỡ mộng: " + ex.message).to_json})")
      end
    end
    dialog.add_action_callback('go_tam') do |_c|
      begin
        check_context
        list = @tenons.map { |t| m = memory(t); m && [t, m[:edges].keys] }.compact
        raise 'Các tấm ngàm đang chọn không có mộng nào do tool làm.' if list.empty?
        ten = list.map { |t, es| "• #{t.name.empty? ? '(không tên)' : t.name}: #{es.length} đầu" }.first(12).join("\n")
        if UI.messagebox("Gỡ HẾT mộng của #{list.length} tấm ngàm?\n\n#{ten}\n\nCắt răng, xoá dấu phay + dấu âm trên tấm nhận. Ctrl+Z để hoàn tác.", MB_YESNO) == IDYES
          message = go_mong(list)
          refresh
          dialog.execute_script("window.applyFinished(true, #{message.to_json})")
        end
      rescue => ex
        puts "XUONG CHO gỡ: #{ex.class}: #{ex.message}"
        dialog.execute_script("window.applyFinished(false, #{("Lỗi gỡ mộng: " + ex.message).to_json})")
      end
    end
    dialog.add_action_callback('cancel') { |_c| dialog.close }
    dialog.set_on_closed do
      @model.select_tool(nil) if Sketchup.active_model == @model
      @dlg = nil if @dlg == dialog
    end
    dialog.show
    nil
  rescue => ex
    UI.messagebox("Không mở được giao diện: #{ex.message}")
  end

  # ── Command (toolbar do LeHai_Tools/main.rb quản lý chung) ──
  def self.create_cmd
    icons = File.join(PATH, 'icons')
    cmd = UI::Command.new('Mộng xương chó') { TK::MongXuongCho.run }
    cmd.tooltip         = 'Tạo mộng xương chó (dogbone) + dấu âm trên các tấm nhận'
    cmd.status_bar_text = 'Phân loại tấm ngàm / tấm nhận; tool tự ghép cặp theo tiếp giáp rồi mọc mộng + đóng dấu.'
    s16 = File.join(icons, 'mong_xuong_cho_16.png')
    s24 = File.join(icons, 'mong_xuong_cho_24.png')
    cmd.small_icon = s16 if File.exist?(s16)
    cmd.large_icon = s24 if File.exist?(s24)
    cmd
  end

end
end
