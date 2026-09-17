# encoding: UTF-8
# Mộng xương chó: tạo mộng dương (dogbone) trên tấm đứng + dấu âm _ABF_Intersect
# trên tấm ngang tiếp giáp. Giao diện sơ đồ 2D (HtmlDialog) để chỉnh thông số.
# Giữ mộng dương dày bằng thân ván; thông số dày/bên giữ chỉ đổi DẤU ÂM.
# Toolbar do LeHai_Tools/main.rb quản lý — file này chỉ expose create_cmd.
# CHƯA nghiệm thu ABF/nesting/DXF trên máy thật (đưa vào 16/09/2026).

require 'sketchup.rb'
require 'json'

module TK
module MongXuongCho

  PATH = File.dirname(__FILE__).freeze
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

  def self.plain_box?(group)
    ents = group.entities
    edges = ents.grep(Sketchup::Edge)
    ents.to_a.length == 18 && ents.grep(Sketchup::Face).length == 6 && edges.length == 12 &&
      edges.all? { |e|
        d = e.end.position - e.start.position
        [d.x, d.y, d.z].count { |v| v.abs > 0.001.mm } == 1
      }
  end

  def self.apply_geometry(input = nil, context = nil)
    model = Sketchup.active_model
    picked = context ? context[:groups] : model.selection.to_a
    source = picked.first
    receiver = nil
    if picked.length == 2 && picked.all? { |g| g.is_a?(Sketchup::Group) }
      horizontal = picked.select { |g|
        b = g.definition.bounds
        b.depth < b.width && b.depth < b.height
      }
      if horizontal.length == 1
        receiver = horizontal.first
        source = (picked - horizontal).first
      end
    end
    if context
      source = context[:source]
      receiver = context[:receiver]
    end
    unless (picked.length == 1 && source.is_a?(Sketchup::Group)) || receiver
      UI.messagebox('Chọn một tấm đứng, hoặc chọn cả tấm đứng và tấm ngang tiếp giáp. Dùng group tấm nguyên chưa có mộng.')
      return
    end
    entities = source.entities
    faces = entities.grep(Sketchup::Face)
    edges = entities.grep(Sketchup::Edge)
    unless faces.length == 6 && edges.length == 12 && entities.to_a.length == 18
      UI.messagebox('Bản thử chỉ nhận tấm hộp chữ nhật: 6 mặt, 12 cạnh, không có group con.')
      return
    end
    bb = source.definition.bounds
    size = [bb.width, bb.height, bb.depth]
    thick_axis = size.each_with_index.min_by { |v, _i| v }[1]
    if thick_axis == 2
      UI.messagebox('Chọn tấm đứng có trục Z local là chiều cao; không chọn tấm ngang.')
      return
    end
    # Tấm đứng: trục mỏng là X hoặc Y; trục ngang còn lại là chiều đặt mộng.
    width_axis = 1 - thick_axis
    width = size[width_axis]
    thickness = size[thick_axis]
    # Chỉ nhận hộp song song các trục local; không suy kích thước từ hộp bao tấm xiên.
    rectangular = edges.all? do |edge|
      d = edge.end.position - edge.start.position
      [d.x, d.y, d.z].count { |v| v.abs > 0.001.mm } == 1
    end
    axes = [X_AXIS, Y_AXIS, Z_AXIS]
    unit_scale = axes.all? { |axis| ((source.transformation * axis).length - 1.0).abs < 0.000001 }
    unless rectangular && unit_scale
      UI.messagebox('Bản thử cần hộp vuông theo trục local, chưa Scale. Hãy dùng tấm mẫu ban đầu.')
      return
    end
    # Chuẩn hóa cạnh được chọn về cạnh trên của hệ tính toán; không xoay group thật.
    frame_data = frame_for(source, input ? input.fetch('edge', 1).to_i : 1)
    frame = frame_data[:frame]
    bb = frame_data[:bounds]
    size = [bb.width, bb.height, bb.depth]
    width = size[width_axis]
    source_tr = source.transformation * frame
    if receiver
      unless plain_box?(receiver)
        re = receiver.entities
        detail = "Tấm ngang: #{re.grep(Sketchup::Face).length} mặt, #{re.grep(Sketchup::Edge).length} cạnh, #{re.to_a.length} đối tượng."
        puts "KIEM TAM NGANG: #{detail}"
        UI.messagebox("#{detail}\nCần hộp nguyên 6 mặt/12 cạnh song song trục local, không có dấu/group con. Nếu đúng tấm nguyên, gửi dòng KIEM TAM NGANG cho tao.")
        return
      end
      # Cho phép xoay/lật group; vẫn chặn scale/xiên để thông số mm không bị đổi.
      rigid = [source, receiver].all? { |g|
        transformed = axes.map { |axis| g.transformation * axis }
        transformed.all? { |axis| (axis.length - 1.0).abs < 0.000001 } &&
          [[0, 1], [0, 2], [1, 2]].all? { |a, b| transformed[a].dot(transformed[b]).abs < 0.000001 }
      }
      unless rigid
        UI.messagebox('Một tấm đang bị Scale hoặc xiên ở cấp group. Bản thử chưa xử lý hệ số Scale; cần tấm đúng kích thước hình học.')
        return
      end
      # Kiểm tra tiếp giáp trong hệ tọa độ tấm nhận, không dùng hộp bao world.
      # Tấm nhận có thể xoay hoặc lật: chọn mặt min/max Z thực sự tiếp xúc.
      map_to_receiver = receiver.transformation.inverse * source_tr
      rb = receiver.definition.bounds
      receiver_sizes = [rb.width, rb.height, rb.depth]
      receiver_axis = receiver_sizes.each_with_index.min_by { |v, _i| v }[1]
      receiver_plane_axes = [0, 1, 2] - [receiver_axis]
      top_corners = [[bb.min.x, bb.min.y, bb.max.z], [bb.max.x, bb.min.y, bb.max.z],
                     [bb.max.x, bb.max.y, bb.max.z], [bb.min.x, bb.max.y, bb.max.z]].map { |p|
        map_to_receiver * Geom::Point3d.new(p)
      }
      upward = map_to_receiver * Z_AXIS
      up_components = [upward.x, upward.y, upward.z]
      contact_z = up_components[receiver_axis] > 0 ? rb.min.to_a[receiver_axis] : rb.max.to_a[receiver_axis]
      if receiver_plane_axes.any? { |i| up_components[i].abs > 0.000001 } ||
          top_corners.any? { |p| (p.to_a[receiver_axis] - contact_z).abs > 0.01.mm }
        error_mm = top_corners.map { |p| (p.to_a[receiver_axis] - contact_z).abs.to_mm }.max
        puts "KIEM TIEP GIAP: lệch mặt tối đa #{error_mm.round(4)}mm; hướng=#{[upward.x, upward.y, upward.z].inspect}"
        UI.messagebox('Đỉnh tấm đứng chưa trùng mặt tiếp giáp của tấm ngang, hoặc hai trục chiều cao không song song. Gửi dòng KIEM TIEP GIAP trong Console.')
        return
      end
    end
    values = input ? [input['count'], input['head'], input['height'], input['neck'], input['bevel'], input['inset'],
                      {'none' => 'Không giảm', 'A' => 'Giữ mặt A', 'B' => 'Giữ mặt B'}[input['side']], input['fit']] : UI.inputbox(
      ['Số lượng mộng (số nguyên)', 'Rộng đầu mộng (mm)', 'Cao mộng (mm)', 'Đường kính khoét cổ (mm)',
       'Vát đỉnh (mm)', 'Tâm mộng ngoài cùng cách đầu tấm (mm; bỏ qua khi có 1 mộng)',
       'Thu dấu âm — chọn bên giữ bằng mặt ván', 'Dày dùng tính dấu âm (mm; Không giảm thì bỏ qua)'],
      [3.0, 35.0, 10.0, 6.0, 1.0, 50.0, 'Không giảm', [14.0, thickness.to_mm].min],
      ['', '', '', '', '', '', 'Không giảm|Giữ mặt đang nhìn|Giữ mặt đối diện', ''],
      'Mộng xương chó — chia đều')
    return unless values
    mode = values[6]
    unless (values.first(6) + (mode == 'Không giảm' ? [] : [values[7]])).all? { |v| v.is_a?(Numeric) && v.finite? }
      UI.messagebox('Nhập các kích thước bằng số.')
      return
    end
    quantity = values.first
    unless quantity >= 1 && quantity == quantity.to_i
      UI.messagebox('Số lượng mộng phải là số nguyên từ 1 trở lên.')
      return
    end
    quantity = quantity.to_i
    head, height, diameter, bevel, inset = values[1, 5].map { |v| v.mm }
    unless ['Không giảm', 'Giữ mặt đang nhìn', 'Giữ mặt đối diện', 'Giữ mặt A', 'Giữ mặt B'].include?(mode)
      UI.messagebox('Chọn một trong ba chế độ tính dấu âm có sẵn.')
      return
    end
    fit_thickness = mode == 'Không giảm' ? thickness : values[7].mm
    unless fit_thickness >= 1.mm && fit_thickness <= thickness
      UI.messagebox("Dày dùng tính dấu âm cần từ 1mm đến bề dày ván #{thickness.to_mm.round(3)}mm.")
      return
    end
    # Chỉ thu/dịch dấu âm theo thông số này. Hình mộng dương luôn dày bằng thân ván.
    narrow_mark = thickness - fit_thickness > 0.001.mm
    keep_low = true
    fit_offset = 0.0
    if narrow_mark
      if ['Giữ mặt A', 'Giữ mặt B'].include?(mode)
        keep_low = mode == 'Giữ mặt A'
      else
      # Phía đang nhìn được xác định theo hướng camera lúc chạy, kể cả trong group lồng.
      path_tr = (model.active_path || []).inject(Geom::Transformation.new) { |t, inst| t * inst.transformation }
      world_tr = path_tr * source.transformation
      thickness_world = world_tr * axes[thick_axis]
      camera = model.active_view.camera
      # Phối cảnh dùng tia từ tâm tấm tới mắt; chiếu song song dùng ngược hướng nhìn.
      toward_eye = camera.perspective? ? camera.eye - (world_tr * bb.center) : camera.direction.reverse
      facing = toward_eye.dot(thickness_world)
      if toward_eye.length < 0.001.mm || facing.abs < 0.05 * thickness_world.length * toward_eye.length
        UI.messagebox('Đang nhìn gần như dọc cạnh tấm nên chưa phân biệt được hai mặt. Xoay nhìn rõ mặt lớn tấm đứng rồi chạy lại.')
        return
      end
      near_is_low = facing < 0
      keep_low = mode == 'Giữ mặt đang nhìn' ? near_is_low : !near_is_low
      end
      # Giữ mặt nhỏ: dấu bắt đầu ở 0 trước khi cộng dư. Giữ mặt lớn: lùi dấu bằng phần giảm.
      fit_offset = keep_low ? 0.0 : thickness - fit_thickness
    else
      fit_thickness = thickness
    end
    # Cung cổ bán kính bằng nửa đường kính dao; hai cổ không được chạm nhau.
    radius = diameter / 2.0
    unless head > diameter && diameter > 0 && height > diameter + bevel &&
        bevel >= 0 && bevel < head / 2.0
      UI.messagebox('Kích thước không hợp lệ: rộng đầu phải lớn hơn đường kính cổ; cổ và vát phải thấp hơn đầu.')
      return
    end
    # Chừa ít nhất 1mm giữa các đầu mộng và từ mép mộng tới đầu tấm để tránh
    # hình học chạm nhau/quá ngắn. Đây là giới hạn dựng hình, không phải tiêu chuẩn CNC.
    min_gap = 1.mm
    if quantity == 1
      if width - head < 2.0 * min_gap
        UI.messagebox('Tấm quá ngắn: một mộng cũng cần chừa ít nhất 1mm ở mỗi đầu tấm.')
        return
      end
      centers = [width / 2.0] # Một mộng đặt chính giữa, không dùng khoảng lùi hai đầu.
    else
      if inset - head / 2.0 < min_gap || inset >= width / 2.0
        UI.messagebox('Khoảng lùi không hợp lệ: mép mộng cần cách đầu tấm ít nhất 1mm; tâm ngoài cùng phải nằm trước giữa tấm.')
        return
      end
      # Nhịp tâm = phần dài giữa hai tâm ngoài cùng / số khoảng giữa các mộng.
      # Số mộng tối đa = số nhịp đủ rộng đầu + khe 1mm, cộng một tâm đầu tiên.
      span = width - 2.0 * inset
      maximum = (span / (head + min_gap) + 1.0e-9).floor + 1
      if quantity > maximum
        UI.messagebox("Không đủ chỗ cho #{quantity} mộng. Với cạnh #{width.to_mm.round(2)}mm, đầu #{head.to_mm.round(2)}mm và lùi tâm #{inset.to_mm.round(2)}mm: tối đa #{maximum} mộng trong cách chia này (khe tối thiểu 1mm). Giảm số lượng, giảm rộng đầu hoặc giảm khoảng lùi.")
        return
      end
      pitch = span / (quantity - 1)
      centers = Array.new(quantity) { |i| inset + i * pitch }
    end
    mortise_points = []
    if receiver
      options = input ? [input['slackT'], input['slackL'], input['cutter']] : UI.inputbox(
        ['Dư bề dày TỔNG (mm; chia đôi mỗi bên)', 'Dư chiều dài TỔNG (mm; chia đôi mỗi đầu)',
         'Đường kính khoét góc mộng âm (mm)'],
        [0.1, 0.5, 6.0], 'Dấu mộng âm trên tấm ngang')
      return unless options
      unless options.all? { |v| v.is_a?(Numeric) && v.finite? }
        UI.messagebox('Nhập độ dư và đường kính bằng số.')
        return
      end
      slack_t, slack_l, cutter = options.map { |v| v.mm }
      # Độ dư nhập là tổng, không cộng lại hai lần; cung lồi làm bao dài thêm 2R.
      mortise_t = fit_thickness + slack_t
      mortise_l = head + slack_l
      mortise_r = cutter / 2.0
      if slack_t < 0 || slack_l < 0 || cutter <= 0 || mortise_t - 2.0 * cutter < 1.mm
        UI.messagebox("Độ dư phải không âm, đường kính phải dương. Với dấu rộng #{mortise_t.to_mm.round(3)}mm, dao cần không quá #{((mortise_t - 1.mm) / 2.0).to_mm.round(3)}mm để bốn cung không chạm nhau. Giảm dao hoặc tăng dày mộng.")
        return
      end
      if height >= receiver_sizes[receiver_axis]
        UI.messagebox('Mộng cao bằng hoặc vượt bề dày tấm ngang; bản thử mộng âm cần thấp hơn bề dày tấm.')
        return
      end
      # Khe dấu tính theo cả hai cung lồi, không chỉ theo rộng đầu mộng dương.
      if quantity > 1 && centers[1] - centers[0] < mortise_l + cutter + min_gap - 0.000001.mm
        limit = ((width - 2.0 * inset) / (mortise_l + cutter + min_gap) + 1.0e-9).floor + 1
        UI.messagebox("Các dấu mộng âm quá sát/chồng nhau. Với độ dư và dao này, tối đa #{limit} mộng trong khoảng tâm đã chọn. Giảm số lượng rồi chạy lại.")
        return
      end
      base = mortise_outline(mortise_t, mortise_l, mortise_r)
      rb = receiver.definition.bounds
      thickness_direction = map_to_receiver * axes[thick_axis]
      thickness_components = [thickness_direction.x, thickness_direction.y, thickness_direction.z]
      mortise_points = centers.map do |center|
        base.map do |t, u|
          # Dấu bám bề dày tính toán và bên giữ; hình mộng dương không bị giảm.
          p = [bb.min.x, bb.min.y, bb.max.z]
          p[thick_axis] += fit_offset + t - slack_t / 2.0
          p[width_axis] += center - mortise_l / 2.0 + u
          point = map_to_receiver * Geom::Point3d.new(p)
          # Mẫu thực có dấu nhô khỏi cạnh bên 0.05mm do độ dư bề dày 0.1mm.
          # Chỉ cho phép phần nhô bằng nửa độ dư ấy; theo chiều dài phải ở trong tấm.
          coords = point.to_a
          lower = rb.min.to_a
          upper = rb.max.to_a
          inside = receiver_plane_axes.all? { |axis|
            allowance = thickness_components[axis].abs * slack_t / 2.0
            coords[axis] >= lower[axis] - allowance - 0.001.mm &&
              coords[axis] <= upper[axis] + allowance + 0.001.mm
          }
          unless inside
            UI.messagebox('Dấu mộng âm vượt mép tấm ngang. Kiểm tra vị trí hai tấm, khoảng lùi và kích thước dấu.')
            return
          end
          coords[receiver_axis] = contact_z
          Geom::Point3d.new(coords)
        end
      end
    end
    # Biên 2D đi qua các mộng từ trái sang phải; cung lõm mỗi bên có 12 đoạn.
    outline = [[0, 0], [0, size[2]]]
    arc_seams = []
    top = size[2]
    centers.each do |center|
      left = center - head / 2.0
      right = center + head / 2.0
      outline << [left, top]
      1.upto(12) do |i|
        angle = -Math::PI / 2.0 + Math::PI * i / 12.0
        outline << [left + radius * Math.cos(angle), top + radius + radius * Math.sin(angle)]
        arc_seams << outline.last if i < 12
      end
      outline << [left, top + height - bevel]
      outline << [left + bevel, top + height]
      outline << [right - bevel, top + height]
      outline << [right, top + height - bevel]
      outline << [right, top + diameter]
      1.upto(12) do |i|
        angle = Math::PI / 2.0 - Math::PI * i / 12.0
        outline << [right - radius * Math.cos(angle), top + radius + radius * Math.sin(angle)]
        arc_seams << outline.last if i < 12
      end
    end
    outline.concat([[width, top], [width, 0]])
    points = outline.chunk_while { |a, b| a == b }.map(&:first).map do |u, z|
      p = [bb.min.x, bb.min.y, bb.min.z]
      p[width_axis] += u
      p[2] += z
      Geom::Point3d.new(p)
    end
    model.start_operation('Tao mong xuong cho truc tiep', true)
    begin
      # Group copy có thể dùng chung definition. Tách trước khi sửa để không đổi
      # các bản khác; lấy lại entities sau make_unique, không dùng danh sách cũ.
      source.make_unique
      receiver.make_unique if receiver
      raise 'Group không còn hợp lệ sau khi tách bản dùng chung.' unless source.valid? && (!receiver || receiver.valid?)
      # ABF chỉ NHẬN + GÁN NHÃN group nào đeo ABF/is-board ở vỏ tấm (đo thật 17/09/2026,
      # probes/so_sanh_ranh_tag.rb). Tấm thiếu dấu này bị nesting bỏ qua dù tag và dấu
      # rãnh _ABF_Intersect đều đúng — đó là gốc "nesting không gán nhãn được tấm mình".
      dam_bao_la_van(source)
      dam_bao_la_van(receiver) if receiver
      result = source
      # Đã kiểm đầu vào là hộp nguyên 6 mặt/12 cạnh, nên chỉ thay hình học tấm này.
      # Giữ group, transformation, tên, tag và thuộc tính cấp group của người dùng.
      result.entities.erase_entities(result.entities.to_a)
      # Theo yêu cầu 16/09: giữ hình mộng dương đủ bề dày để thử nhận dạng ABF.
      # Không dùng fit_thickness/fit_offset cho hình khối; chỉ dùng cho dấu âm.
      face = result.entities.add_face(points)
      raise 'Không dựng được mặt biên mộng.' unless face
      face.reverse! if face.normal.dot(axes[thick_axis]) < 0
      face.pushpull(thickness)
      softened = 0
      result.entities.grep(Sketchup::Edge).each do |edge|
        a = edge.start.position
        b = edge.end.position
        ac = [a.x, a.y, a.z]
        bc = [b.x, b.y, b.z]
        next unless (ac[thick_axis] - bc[thick_axis]).abs > 0.001.mm
        next unless (ac[width_axis] - bc[width_axis]).abs < 0.001.mm && (a.z - b.z).abs < 0.001.mm
        next unless arc_seams.any? { |u, z|
          (ac[width_axis] - [bb.min.x, bb.min.y][width_axis] - u).abs < 0.001.mm &&
            (a.z - bb.min.z - z).abs < 0.001.mm
        }
        edge.soft = true
        edge.smooth = true
        softened += 1
      end
      # Mỗi mộng có hai cung, mỗi cung 12 đoạn nên có 11 cạnh chia bên trong.
      expected_soft = quantity * 2 * 11
      raise "Làm mềm thiếu cạnh cung: #{softened}/#{expected_soft}." unless softened == expected_soft
      new_edges = result.entities.grep(Sketchup::Edge)
      raise 'Khối có cạnh hở hoặc cạnh nối hơn hai mặt.' unless new_edges.all? { |edge| edge.faces.length == 2 }
      # DẤU PHAY MỘNG (Khoa): khi THU MỘT MẶT, đánh ô chữ nhật phủ đầu mộng (rộng đầu × cao mộng)
      # lên MẶT BỊ THU = mặt đối diện mặt giữ, để báo CNC phay bớt. Tag riêng 'khoa_phaymong'
      # (khác dấu âm). Thêm TRƯỚC transform_entities để dấu đi theo cùng khung với mộng.
      if narrow_mark
        phay_tag = model.layers.to_a.find { |layer| layer.name == 'ABF_PHAYDAUMONG_K' } || model.layers.add('ABF_PHAYDAUMONG_K')
        # keep_low = giữ mặt thấp (bb.min trục dày) -> phay mặt CAO (bb.min+dày); ngược lại -> mặt THẤP.
        reduced_coord = keep_low ? bb.min.to_a[thick_axis] + thickness : bb.min.to_a[thick_axis]
        centers.each_with_index do |center, index|
          rect = [[center - head / 2.0, top], [center + head / 2.0, top],
                  [center + head / 2.0, top + height], [center - head / 2.0, top + height]].map do |u, z|
            p = [bb.min.x, bb.min.y, bb.min.z]
            p[thick_axis] = reduced_coord
            p[width_axis] = bb.min.to_a[width_axis] + u
            p[2] = bb.min.z + z
            Geom::Point3d.new(p)
          end
          mark = result.entities.add_group
          # DẤU PHAY = _ABF_Intersect chuẩn ABF. ABF chỉ công nhận intersect là CẶP A↔B:
          # b-id phải trỏ tấm ĐỐI TÁC, KHÔNG tự trỏ mình (đo thật 17/09 probes/soi_bid_intersect.rb:
          # dấu tự trỏ -> DXF rớt LAYER0; rãnh hậu thật trỏ tấm khác -> layer đúng). Phay đầu mộng
          # do tấm NHẬN gây ra nên b-id trỏ receiver. Không có receiver thì không thành cặp hợp lệ.
          mark.name = '_ABF_Intersect'
          mark.layer = phay_tag
          mark_face = mark.entities.add_face(rect)
          raise "Không tạo được dấu phay mộng #{index + 1}." unless mark_face
          mark.entities.grep(Sketchup::Edge).each { |edge| edge.layer = phay_tag }
          mark.set_attribute('ABF', 'is-intersect', true)
          mark.set_attribute('ABF', 'intersect-offset', 0.0)
          mark.set_attribute('ABF', 'intersect-x', (thickness - fit_thickness).to_mm)
          mark.set_attribute('ABF', 'intersect-group-b-id', receiver ? receiver.persistent_id : result.persistent_id)
          mark.set_attribute('ABF', 'setting-name', 'PHAYDAUMONG_KHOA')
        end
      end
      result.entities.transform_entities(frame, result.entities.to_a)
      if receiver
        # DẤU MỘNG ÂM = hốc khoét trên tấm NHẬN do mộng dương tấm ĐỨNG (source) đâm vào. ABF chỉ công
        # nhận intersect là CẶP A↔B: mark trên tấm nhận phải trỏ b-id sang tấm ĐỨNG (source), không tự
        # trỏ mình (đo thật 17/09 probes/soi_bid_intersect.rb). intersect-x = độ sâu hốc = cao mộng.
        tag = model.layers.to_a.find { |layer| layer.name == 'ABF_PHAYRANHHAU10LY' } || model.layers.add('ABF_PHAYRANHHAU10LY')
        mortise_points.each_with_index do |polygon, index|
          mark = receiver.entities.add_group
          mark.name = '_ABF_Intersect'
          mark.layer = tag
          mark_face = mark.entities.add_face(polygon)
          raise "Không tạo được dấu âm #{index + 1}." unless mark_face
          mark_face.reverse! if mark_face.normal.dot(upward) > 0
          mark_edges = mark.entities.grep(Sketchup::Edge)
          raise "Dấu âm #{index + 1} không đủ 52 cạnh." unless mark_edges.length == 52
          mark_edges.each { |edge| edge.layer = tag }
          mark.set_attribute('ABF', 'is-intersect', true)
          mark.set_attribute('ABF', 'intersect-offset', 0.0)
          mark.set_attribute('ABF', 'intersect-x', height.to_mm)
          mark.set_attribute('ABF', 'setting-name', 'PHÂY RÃNH HẬU 10LY')
          mark.set_attribute('ABF', 'intersect-group-b-id', result.persistent_id)
        end
      end
      model.commit_operation
      puts "XUONG CHO: sửa trực tiếp tấm đã chọn, #{quantity} mộng; #{result.entities.grep(Sketchup::Face).length} mặt; #{new_edges.length} cạnh; mọi cạnh có 2 mặt."
      puts "Tâm mộng tính từ đầu cạnh (mm): #{centers.map { |c| c.to_mm.round(3) }.join(', ')}"
      puts "DAY MONG 3D: thân và mộng dương đều #{thickness.to_mm.round(3)}mm; không tạo bậc."
      puts "TINH DAU AM: dày #{fit_thickness.to_mm.round(3)}mm trước dư; #{narrow_mark ? mode : 'Không giảm'}; lùi #{fit_offset.to_mm.round(3)}mm."
      puts 'Giữ vị trí các tấm, không tạo cặp bản sao. Ctrl+Z một lần để hoàn tác cả mộng và dấu âm.'
      puts "CUNG MUOT: #{softened}/#{expected_soft} cạnh trong cung đã soft + smooth; giữ cạnh biên và vát."
      puts "PHAY MONG: #{quantity} dấu _ABF_Intersect (tag ABF_PHAYDAUMONG_K, setting PHAYDAUMONG_KHOA) ở mặt #{keep_low ? 'B (thu)' : 'A (thu)'}; intersect-x #{(thickness - fit_thickness).to_mm.round(3)}mm." if narrow_mark
      if receiver
        puts "MONG AM: #{quantity} dấu _ABF_Intersect (tag ABF_PHAYRANHHAU10LY, setting PHÂY RÃNH HẬU, b-id tấm nhận, sâu #{height.to_mm.round(3)}mm) — coi như hốc phay."
        puts "Bao dấu (mm): #{mortise_t.to_mm.round(3)} x #{(mortise_l + cutter).to_mm.round(3)}; ABF nesting/DXF chưa nghiệm thu."
      end
      return true
    rescue => ex
      model.abort_operation
      puts "LOI: #{ex.class}: #{ex.message}"
      UI.messagebox("Không tạo được mộng: #{ex.message}")
    end
    nil
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

  def self.frame_for(group, edge)
    raise 'Chọn cạnh từ 1 đến 4.' unless (1..4).include?(edge)
    b = group.definition.bounds
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
    box = Geom::BoundingBox.new
    box.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(dimensions))
    {frame: Geom::Transformation.axes(Geom::Point3d.new(origin), *basis), bounds: box,
     thin: thin, u: u, width: lengths[u].to_mm, height: lengths[2].to_mm, thickness: lengths[thin].to_mm}
  end

  def self.dialog_context(index)
    raise 'Model đã đổi. Đóng bảng và chọn lại tấm.' unless Sketchup.active_model == @dialog_model
    raise 'Đã đổi cấp chỉnh sửa. Đóng bảng và mở lại.' unless (Sketchup.active_model.active_path || []) == @dialog_path
    raise 'Tấm đã bị xóa.' unless @dialog_groups.all?(&:valid?)
    raise 'Chỉ số tấm không hợp lệ.' unless index >= 0 && index < @dialog_groups.length
    source = @dialog_groups[index]
    {groups: @dialog_groups, source: source, receiver: (@dialog_groups - [source]).first}
  end

  def self.dialog_data(index = 0)
    context = dialog_context(index)
    group = context[:source]
    base = frame_for(group, 1)
    available = (1..4).map do |edge|
      next true unless context[:receiver]
      receiver = context[:receiver]
      fd = frame_for(group, edge)
      relative = receiver.transformation.inverse * group.transformation * fd[:frame]
      rb = receiver.definition.bounds
      dims = [rb.width, rb.height, rb.depth]
      raxis = dims.each_with_index.min_by { |v, _i| v }[1]
      direction = (relative * Z_AXIS).to_a
      contact = direction[raxis] > 0 ? rb.min.to_a[raxis] : rb.max.to_a[raxis]
      fb = fd[:bounds]
      points = [[0, 0, fb.max.z], [fb.max.x, 0, fb.max.z],
                [fb.max.x, fb.max.y, fb.max.z], [0, fb.max.y, fb.max.z]]
      ([0, 1, 2] - [raxis]).all? { |i| direction[i].abs < 0.000001 } &&
        points.all? { |p| ((relative * Geom::Point3d.new(p)).to_a[raxis] - contact).abs <= 0.01.mm }
    end
    {width: base[:width], height: base[:height], thickness: base[:thickness], source: index,
     boards: @dialog_groups.each_with_index.map { |g, i| "#{i + 1}. #{g.name.empty? ? 'Tấm chưa đặt tên' : g.name}" },
     receiver: !!context[:receiver], available: available, live: true}
  end

  def self.send_dialog(data)
    @dlg.execute_script("window.receiveModel(#{JSON.generate(data)})") if @dlg
  end

  class EdgeTool
    attr_accessor :index, :edge, :side
    def initialize(dialog)
      @dlg, @index, @edge, @side = dialog, 0, 1, 'none'
    end
    def corners(face_side = 'A')
      context = TK::MongXuongCho.dialog_context(@index)
      group = context[:source]
      b = group.definition.bounds
      fd = TK::MongXuongCho.frame_for(group, 1)
      t = fd[:thin]; u = fd[:u]
      path = (Sketchup.active_model.active_path || []).inject(Geom::Transformation.new) { |tr, g| tr * g.transformation }
      [[0,1],[1,1],[1,0],[0,0]].map do |x,z|
        p = b.min.to_a
        p[t] = face_side == 'B' ? b.max.to_a[t] : b.min.to_a[t]
        p[u] = x == 0 ? b.min.to_a[u] : b.max.to_a[u]
        p[2] = z == 0 ? b.min.z : b.max.z
        path * group.transformation * Geom::Point3d.new(p)
      end
    end
    def draw(view)
      pts = corners(@side == 'B' ? 'B' : 'A').map { |p| view.screen_coords(p) }
      4.times do |i|
        view.line_width = @edge == i + 1 ? 5 : 2
        view.drawing_color = @edge == i + 1 ? '#b45309' : '#718096'
        a, b = pts[i], pts[(i + 1) % 4]
        view.draw2d(GL_LINES, [a, b])
        view.draw_text(Geom::Point3d.new((a.x+b.x)/2, (a.y+b.y)/2, 0), "  #{i+1}", color: '#7c2d12', size: 15, bold: true)
      end
      a, b = pts[0], pts[2]
      view.draw_text(Geom::Point3d.new((a.x+b.x)/2, (a.y+b.y)/2, 0), @side == 'B' ? 'MẶT B' : 'MẶT A', color: '#24627c', size: 17, bold: true)
    rescue => ex
      puts "XUONG CHO overlay: #{ex.message}" unless @failed
      @failed = true
    end
    def onLButtonDown(_flags, x, y, view)
      pts = corners(@side == 'B' ? 'B' : 'A').map { |p| view.screen_coords(p) }
      distances = 4.times.map do |i|
        a,b = pts[i],pts[(i+1)%4]
        dx,dy = b.x-a.x,b.y-a.y
        denominator = dx*dx+dy*dy
        ratio = denominator > 0 ? [[((x-a.x)*dx+(y-a.y)*dy)/denominator, 0].max, 1].min : 0
        [(x-a.x-ratio*dx)**2+(y-a.y-ratio*dy)**2, i+1]
      end
      distance, selected = distances.min
      if distance < 24**2
        @edge = selected
        @dlg.execute_script("window.chooseEdge(#{selected})")
        view.invalidate
      end
    rescue => ex
      puts "XUONG CHO chọn cạnh: #{ex.message}"
    end
    def deactivate(view); view.invalidate; end
    def resume(view); view.invalidate; end
  end

  def self.run
    @dlg.close if @dlg
    @dialog_model = Sketchup.active_model
    @dialog_path = (@dialog_model.active_path || []).dup
    @dialog_groups = @dialog_model.selection.to_a
    unless (1..2).include?(@dialog_groups.length) && @dialog_groups.all? { |g| g.is_a?(Sketchup::Group) && plain_box?(g) }
      UI.messagebox('Chọn 1–2 group tấm nguyên. Nếu tấm đã có mộng, Undo về trước khi tạo rồi mở lại bảng.')
      return
    end
    @dialog_groups.sort_by! { |g| b=g.definition.bounds; b.depth < [b.width,b.height].min ? 1 : 0 }
    initial = dialog_data
    @dlg = UI::HtmlDialog.new(dialog_title: 'Mộng xương chó', preferences_key: 'khoa.mong.visual.v1',
      width: 1130, height: 860, min_width: 900, min_height: 700, resizable: true)
    dialog = @dlg
    @edge_tool = EdgeTool.new(dialog)
    dialog.set_file(File.join(File.dirname(__FILE__), 'giao_dien.html'))
    dialog.add_action_callback('ready') { |_c| send_dialog(initial); @dialog_model.select_tool(@edge_tool) }
    dialog.add_action_callback('preview') do |_c, json|
      begin
        data = JSON.parse(json)
        @edge_tool.index = data.fetch('source').to_i
        @edge_tool.edge = data.fetch('edge').to_i
        @edge_tool.side = data.fetch('side')
        @dialog_model.active_view.invalidate
      rescue => ex
        dialog.execute_script("window.showMessage(#{ex.message.to_json}, true)")
      end
    end
    dialog.add_action_callback('source') do |_c, index|
      begin
        send_dialog(dialog_data(Integer(index)))
      rescue => ex
        dialog.execute_script("window.showMessage(#{ex.message.to_json}, true)")
      end
    end
    dialog.add_action_callback('pick') { |_c| @dialog_model.select_tool(@edge_tool) }
    dialog.add_action_callback('apply') do |_c, json|
      begin
        data = JSON.parse(json)
        context = dialog_context(data.fetch('source').to_i)
        result = apply_geometry(data, context)
        dialog.execute_script("window.applyFinished(#{!!result})")
        @dialog_model.select_tool(nil) if result
      rescue => ex
        puts "XUONG CHO UI: #{ex.class}: #{ex.message}"
        dialog.execute_script("window.showMessage(#{ex.message.to_json}, true); window.applyFinished(false)")
      end
    end
    dialog.add_action_callback('cancel') { |_c| dialog.close }
    dialog.set_on_closed do
      @dialog_model.select_tool(nil) if Sketchup.active_model == @dialog_model
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
    cmd.tooltip         = 'Tạo mộng xương chó (dogbone) + dấu âm trên tấm nhận'
    cmd.status_bar_text = 'Chọn 1–2 tấm nguyên rồi chỉnh trên sơ đồ; tạo mộng dương + dấu âm ABF.'
    s16 = File.join(icons, 'mong_xuong_cho_16.png')
    s24 = File.join(icons, 'mong_xuong_cho_24.png')
    cmd.small_icon = s16 if File.exist?(s16)
    cmd.large_icon = s24 if File.exist?(s24)
    cmd
  end

end
end
