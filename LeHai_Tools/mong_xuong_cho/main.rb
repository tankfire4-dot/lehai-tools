# encoding: UTF-8
# Mộng xương chó: tạo mộng dương (dogbone) trên các TẤM NGÀM + dấu âm _ABF_Intersect trên các
# TẤM NHẬN áp vào chúng. Người dùng chỉ phân loại hai nhóm tấm; tool tự ghép cặp theo tiếp giáp.
# Tấm ngàm được GHI NHỚ việc đã làm (dict LeHai_MXC) để lần sau làm thêm: thêm đầu mới hoặc
# đóng dấu lên tấm nhận mới — không cho sửa mộng đã làm (dấu cũ sẽ lệch).
# Giữ mộng dương dày bằng thân ván; thông số dày/bên giữ chỉ đổi DẤU ÂM.
# Toolbar do LeHai_Tools/main.rb quản lý — file này chỉ expose create_cmd.
# CHƯA nghiệm thu ABF/nesting/DXF trên máy thật (đưa vào 16/09/2026).

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
  SPEC_KEYS = %w[count head height neck bevel inset side fit slackT slackL cutter].freeze
  TEN_SO = {'count' => 'số mộng', 'head' => 'rộng đầu', 'height' => 'cao mộng', 'neck' => 'đường kính cổ',
            'bevel' => 'vát đỉnh', 'inset' => 'lùi tâm', 'fit' => 'dày tính dấu', 'slackT' => 'dư dày',
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

  # Tấm nguyên: hộp 6 mặt/12 cạnh song song trục local, không có gì khác bên trong.
  def self.plain_box?(group)
    ents = group.entities
    edges = ents.grep(Sketchup::Edge)
    ents.to_a.length == 18 && ents.grep(Sketchup::Face).length == 6 && edges.length == 12 &&
      edges.all? { |e|
        d = e.end.position - e.start.position
        [d.x, d.y, d.z].count { |v| v.abs > 0.001.mm } == 1
      }
  end

  # Không Scale, không xiên ở cấp group: thông số mm mới đúng với hình học.
  def self.rigid?(group)
    t = AXES.map { |axis| group.transformation * axis }
    t.all? { |axis| (axis.length - 1.0).abs < 0.000001 } &&
      [[0, 1], [0, 2], [1, 2]].all? { |a, b| t[a].dot(t[b]).abs < 0.000001 }
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
    return nil unless plain_box?(group)
    # Chép ra hộp mới: hộp gốc phải giữ nguyên dù hình tấm đổi ngay sau đó.
    b = group.definition.bounds
    Geom::BoundingBox.new.add(b.min, b.max)
  end

  # Lý do tấm không làm ngàm được, hoặc nil nếu được.
  def self.tenon_problem(group)
    box = tenon_box(group)
    return 'đã có mộng/khoét nhưng không phải do tool này làm (hoặc làm bằng bản cũ) — Undo về tấm nguyên rồi làm lại' unless box
    return 'đang bị Scale hoặc xiên ở cấp group' unless rigid?(group)
    sizes = [box.width, box.height, box.depth]
    return 'là tấm nằm ngang — tool chỉ mọc mộng trên tấm đứng (trục Z local là chiều cao)' if sizes.each_with_index.min_by { |v, _i| v }[1] == 2
    nil
  end

  # ── Hình học một đầu ──────

  # Hệ cạnh: cạnh `edge` của hộp `box` thành cạnh trên, u chạy dọc cạnh, z hướng ra ngoài,
  # trục dày giữ nguyên (mặt A = mặt thấp của trục dày).
  def self.frame_for(group, edge, box = nil)
    raise 'Chọn cạnh từ 1 đến 4.' unless (1..4).include?(edge)
    b = box || group.definition.bounds
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
    {frame: Geom::Transformation.axes(Geom::Point3d.new(origin), *basis), bounds: bounds,
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
    raise "#{label}chọn Không thu / Giữ mặt A / Giữ mặt B." unless %w[none A B].include?(side)
    # Chỉ thu/dịch dấu âm theo thông số này. Hình mộng dương luôn dày bằng thân ván.
    fit_thickness = thickness
    fit_offset = 0.0
    keep_low = true
    narrow_mark = false
    if side != 'none'
      fit_thickness = number.call('fit').mm
      unless fit_thickness >= 1.mm && fit_thickness <= thickness + 0.001.mm
        raise "#{label}dày tính dấu cần từ 1mm đến bề dày ván #{thickness.to_mm.round(3)}mm."
      end
      narrow_mark = thickness - fit_thickness > 0.001.mm
      if narrow_mark
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
    if narrow_mark
      reduced = keep_low ? thickness : 0.0
      phay_rects = centers.map do |center|
        [[center - head / 2.0, top], [center + head / 2.0, top],
         [center + head / 2.0, top + height], [center - head / 2.0, top + height]].map do |u, z|
          p = [0.0, 0.0, z]
          p[thin] = reduced
          p[u_axis] = u
          Geom::Point3d.new(p)
        end
      end
    end
    plan = {edge: edge, fd: fd, quantity: quantity, centers: centers, teeth: teeth, arc_seams: arc_seams,
            height: height, thickness: thickness, fit_thickness: fit_thickness, narrow_mark: narrow_mark,
            keep_low: keep_low, phay_rects: phay_rects, receiver: receiver, mortises: []}
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
        r = receivers.find { |g| contact_info(t, edge, g, box) }
        next unless r
        stored = mem && mem[:edges][edge]
        state = if stored.nil? then 'moi'
                elsif (stored['nhan'] || []).include?(r.persistent_id) then 'da_lam'
                else 'chi_dau'
                end
        fd = frame_for(t, edge, box)
        list << {key: "#{ti}-#{edge}", tenon: t, ti: ti, edge: edge, receiver: r, ri: receivers.index(r),
                 state: state, stored: stored, length: edge_length(fd, edge),
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

  # Dựng lại biên tấm ngàm từ hộp gốc với mọi đầu trong `plans`, rồi dấu phay các đầu thu mặt.
  def self.build_tenon(model, source, box, plans)
    fd1 = frame_for(source, 1, box)
    thin = fd1[:thin]
    u_axis = fd1[:u]
    thickness = [box.width, box.height, box.depth][thin]
    # Biên chung: đi vòng 4 cạnh theo chiều kim đồng hồ (cạnh 1 trái→phải, cạnh 2 trên→dưới…);
    # đoạn u tăng dần của mỗi cạnh trong hệ cạnh trùng đúng chiều đi vòng này.
    # Điểm (u, z) hệ cạnh nằm trên mặt A (trục dày = 0) rồi đổi về tọa độ local của tấm.
    local = lambda do |fd, u, z|
      p = [0.0, 0.0, z]
      p[u_axis] = u
      fd[:frame] * Geom::Point3d.new(p)
    end
    ring = []
    seams = []
    (1..4).each do |edge|
      fd = frame_for(source, edge, box)
      top = [fd[:bounds].width, fd[:bounds].height, fd[:bounds].depth][2]
      plan = plans.find { |pl| pl[:edge] == edge }
      ring << local.call(fd, 0.0, top)
      next unless plan
      plan[:teeth].each { |u, z| ring << local.call(fd, u, z) }
      plan[:arc_seams].each { |u, z| seams << local.call(fd, u, z) }
    end
    ring = ring.chunk_while { |a, b| a == b }.map(&:first)
    # Giữ group, transformation, tên, tag và thuộc tính cấp group; chỉ thay hình bên trong.
    source.entities.erase_entities(source.entities.to_a)
    face = source.entities.add_face(ring)
    raise 'Không dựng được mặt biên mộng.' unless face
    face.reverse! if face.normal.dot(AXES[thin]) < 0
    face.pushpull(thickness)
    softened = 0
    source.entities.grep(Sketchup::Edge).each do |e|
      a = e.start.position.to_a
      b = e.end.position.to_a
      next unless (a[thin] - b[thin]).abs > 0.001.mm
      next unless (a[u_axis] - b[u_axis]).abs < 0.001.mm && (a[2] - b[2]).abs < 0.001.mm
      next unless seams.any? { |s| (a[u_axis] - s[u_axis]).abs < 0.001.mm && (a[2] - s.z).abs < 0.001.mm }
      e.soft = true
      e.smooth = true
      softened += 1
    end
    # Mỗi mộng có hai cung, mỗi cung 12 đoạn nên có 11 cạnh chia bên trong.
    expected = plans.sum { |pl| pl[:quantity] * 2 * 11 }
    raise "Làm mềm thiếu cạnh cung: #{softened}/#{expected}." unless softened == expected
    raise 'Khối có cạnh hở hoặc cạnh nối hơn hai mặt.' unless source.entities.grep(Sketchup::Edge).all? { |e| e.faces.length == 2 }
    phay_tag = nil
    plans.each do |plan|
      plan[:phay_rects].each_with_index do |rect, index|
        phay_tag ||= model.layers.to_a.find { |l| l.name == 'ABF_PHAYDAUMONG_K' } || model.layers.add('ABF_PHAYDAUMONG_K')
        mark = source.entities.add_group
        # DẤU PHAY = _ABF_Intersect chuẩn ABF. ABF chỉ công nhận intersect là CẶP A↔B:
        # b-id phải trỏ tấm ĐỐI TÁC, KHÔNG tự trỏ mình (đo thật 17/09 probes/soi_bid_intersect.rb:
        # dấu tự trỏ -> DXF rớt LAYER0). Phay đầu mộng do tấm NHẬN gây ra nên b-id trỏ tấm nhận.
        mark.name = '_ABF_Intersect'
        mark.layer = phay_tag
        mark_face = mark.entities.add_face(rect.map { |p| plan[:fd][:frame] * p })
        raise "Đầu #{plan[:edge]}: không tạo được dấu phay mộng #{index + 1}." unless mark_face
        mark.entities.grep(Sketchup::Edge).each { |e| e.layer = phay_tag }
        mark.set_attribute('ABF', 'is-intersect', true)
        mark.set_attribute('ABF', 'intersect-offset', 0.0)
        mark.set_attribute('ABF', 'intersect-x', (plan[:thickness] - plan[:fit_thickness]).to_mm)
        mark.set_attribute('ABF', 'intersect-group-b-id', plan[:phay_b] || source.persistent_id)
        mark.set_attribute('ABF', 'setting-name', 'PHAYDAUMONG_KHOA')
      end
    end
    softened
  end

  # DẤU MỘNG ÂM = hốc khoét trên tấm NHẬN do mộng dương tấm NGÀM đâm vào; b-id trỏ tấm ngàm.
  # intersect-x = độ sâu hốc = cao mộng.
  def self.stamp_marks(model, source, plan)
    receiver = plan[:receiver]
    tag = model.layers.to_a.find { |l| l.name == 'ABF_PHAYRANHHAU10LY' } || model.layers.add('ABF_PHAYRANHHAU10LY')
    plan[:mortises].each_with_index do |polygon, index|
      mark = receiver.entities.add_group
      mark.name = '_ABF_Intersect'
      mark.layer = tag
      mark_face = mark.entities.add_face(polygon)
      raise "Đầu #{plan[:edge]}: không tạo được dấu âm #{index + 1}." unless mark_face
      mark_face.reverse! if mark_face.normal.dot(plan[:upward]) > 0
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
  def self.apply_pairs(data, tenons, receivers)
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
      unless fresh.empty?
        old = (mem ? mem[:edges] : {}).reject { |e, _| fresh.any? { |pl| pl[:edge] == e } }.map { |e, s|
          pl = plan_edge(tenon, s, nil, box, "#{name}, đầu #{edge_name(e, frame_for(tenon, 1, box)[:thin])} (đã làm): ")
          pl[:phay_b] = s['phay_b']
          pl
        }
        rebuild = old + fresh
      end
      {tenon: tenon, box: box, edges: edges, marks: mark_plans, rebuild: rebuild}
    end
    model.start_operation('Tao mong xuong cho', true)
    begin
      # Group copy có thể dùng chung definition. Tách trước khi sửa để không đổi các bản khác.
      touched = (jobs.map { |j| j[:tenon] } + jobs.flat_map { |j| j[:marks].map { |pl| pl[:receiver] } }).uniq
      touched.each(&:make_unique)
      raise 'Group không còn hợp lệ sau khi tách bản dùng chung.' unless touched.all?(&:valid?)
      # ABF chỉ NHẬN + GÁN NHÃN group nào đeo ABF/is-board ở vỏ tấm (đo thật 17/09/2026).
      touched.each { |g| dam_bao_la_van(g) }
      teeth = 0
      marks = 0
      jobs.each do |job|
        if job[:rebuild]
          build_tenon(model, job[:tenon], job[:box], job[:rebuild])
          teeth += job[:rebuild].sum { |pl| pl[:quantity] }
        end
        job[:marks].each do |plan|
          stamp_marks(model, job[:tenon], plan)
          marks += plan[:mortises].length
        end
        write_memory(job[:tenon], job[:box], job[:edges])
      end
      model.commit_operation
      puts "XUONG CHO: #{jobs.length} tấm ngàm, #{jobs.count { |j| j[:rebuild] }} tấm dựng lại (#{teeth} mộng), #{marks} dấu âm."
      "Đã làm #{todo.length} cặp: #{marks} dấu âm#{teeth > 0 ? ", dựng lại #{jobs.count { |j| j[:rebuild] }} tấm ngàm" : ''}. Ctrl+Z một lần để hoàn tác cả lượt."
    rescue => ex
      model.abort_operation
      puts "LOI: #{ex.class}: #{ex.message}"
      raise
    end
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
    picked.each do |g|
      other.delete(g)
      mine << g unless mine.include?(g)
    end
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
      row = {label: board_label(g, :ngam, i), problem: problem}
      next row if thin == 2
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
      row.merge(faceW: fd[:width], faceH: fd[:height], thickness: fd[:thickness], mirror: thin == 0,
                done: mem ? mem[:edges].map { |e, spec| spec.merge('edge' => e) } : [])
    end
    receiver_rows = @receivers.each_with_index.map do |g, i|
      board_lines.call(g, RoleTool::BLUE)
      texts << [world * g.transformation * board_bounds(g).center, "Nhận #{i + 1}", RoleTool::BLUE, 16]
      {label: board_label(g, :nhan, i)}
    end
    @tool.set(lines, texts, focus_lines(@focus))
    rows = @pairs.map do |p|
      {key: p[:key], ti: p[:ti], tenon: board_label(p[:tenon], :ngam, p[:ti]), edge: p[:edge], edgeName: p[:edge_name],
       receiver: board_label(p[:receiver], :nhan, p[:ri]), state: p[:state], length: p[:length],
       thickness: p[:thickness], stored: p[:stored]}
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
        refresh
        dialog.execute_script("window.applyFinished(true, #{message.to_json})")
      rescue => ex
        puts "XUONG CHO UI: #{ex.class}: #{ex.message}"
        dialog.execute_script("window.applyFinished(false, #{("Lỗi: " + ex.message).to_json})")
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
