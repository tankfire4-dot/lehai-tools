# frozen_string_literal: true

require 'digest'
require 'json'
require 'fileutils'

module TK
  module ThuVien
    # Quản lý dữ liệu thư viện: quét file .skp, sinh thumbnail, chèn component.
    # Module thuần dữ liệu — không phụ thuộc HtmlDialog.
    #
    # Đường dẫn thư viện cấu hình được (lưu bằng write_default) để cả
    # phòng thiết kế trỏ về cùng một thư mục trên ổ mạng / Drive.
    # Danh mục 2 cấp: thư mục con cấp 1 = danh mục, cấp 2 = danh mục con.
    module Library

      PREFS_SECTION = 'TK_ThuVien'
      PREFS_KEY_DIR = 'library_path'

      DEFAULT_DIR   = File.join(PATH, 'components').freeze
      CACHE_DIR     = File.join(PATH, 'cache').freeze
      UNCATEGORIZED = 'Chung'

      # Trả về Hash {root:, exists:, categories: [...], items: [...]} cho UI.
      def self.scan
        dir = components_dir
        return { root: dir, exists: false, categories: [], items: [] } unless
          File.directory?(dir)

        ensure_cache_dir
        items = skp_files(dir).map { |file| item_for(file, dir) }
        {
          root:       dir,
          exists:     true,
          categories: build_categories(items),
          items:      items.sort_by { |i| i[:name].downcase }
        }
      end

      # Thư mục thư viện hiện tại: đường dẫn đã lưu, hoặc mặc định trong plugin.
      def self.components_dir
        saved = Sketchup.read_default(PREFS_SECTION, PREFS_KEY_DIR)
        saved.is_a?(String) && !saved.empty? ? saved : DEFAULT_DIR
      end

      # Mở hộp thoại chọn thư mục thư viện. Trả về true nếu có thay đổi.
      def self.choose_folder
        dir = UI.select_directory(
          title:     'Chọn thư mục thư viện component',
          directory: components_dir
        )
        return false unless dir.is_a?(String) && File.directory?(dir)
        Sketchup.write_default(PREFS_SECTION, PREFS_KEY_DIR, dir)
        true
      end

      # Thông tin cho form "Lưu vào thư viện": tên gợi ý + cây danh mục.
      # Trả về nil (kèm thông báo) nếu chưa chọn component/group nào.
      def self.save_dialog_info
        defn = selected_definition
        unless defn
          UI.messagebox(
            'Hãy chọn một component hoặc group trong model trước, ' \
            'rồi bấm "Lưu vào thư viện".'
          )
          return nil
        end
        name = defn.name.to_s.strip
        name = 'Component' if name.empty?
        { name: name, categories: category_tree }
      end

      # Lưu component đang chọn vào thư viện bằng save_as
      # (SketchUp tự sinh thumbnail góc iso chuẩn).
      # Trả về {ok:, msg:}.
      def self.save_selected(params)
        defn = selected_definition
        return { ok: false, msg: 'Chưa chọn component hoặc group nào trong model.' } unless defn

        name = sanitize_filename(params['name'].to_s)
        return { ok: false, msg: 'Tên file không hợp lệ.' } if name.empty?

        dir = target_dir(params['category'].to_s, params['subcategory'].to_s)
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "#{name}.skp")

        if File.exist?(path)
          choice = UI.messagebox("File đã tồn tại:\n#{path}\n\nGhi đè?", MB_YESNO)
          return { ok: false, msg: nil } unless choice == IDYES
        end

        if defn.save_as(path)
          { ok: true, msg: nil }
        else
          { ok: false, msg: "Không lưu được file:\n#{path}" }
        end
      rescue IOError, RuntimeError, Errno::EACCES => e
        { ok: false, msg: "Lỗi khi lưu:\n#{e.message}" }
      end

      def self.insert(path)
        return unless valid_skp?(path)
        model = Sketchup.active_model
        definition = model.definitions.load(path)
        # place_component để người dùng click đặt vị trí — giống tool gốc
        model.place_component(definition)
      rescue IOError, RuntimeError => e
        UI.messagebox("Không thể chèn component:\n#{e.message}")
      end

      def self.open_components_folder
        dir = components_dir
        unless File.directory?(dir)
          UI.messagebox("Không tìm thấy thư mục thư viện:\n#{dir}")
          return
        end
        UI.openURL("file:///#{dir.tr('\\', '/')}")
      end

      # ── private ──────────────────────────────────────────────

      def self.ensure_cache_dir
        Dir.mkdir(CACHE_DIR) unless File.directory?(CACHE_DIR)
      end
      private_class_method :ensure_cache_dir

      def self.skp_files(dir)
        pattern = File.join(dir, '**', '*.skp')
        Dir.glob(pattern).reject { |f| File.basename(f).start_with?('~') }
      end
      private_class_method :skp_files

      def self.item_for(file, dir)
        category, subcategory = category_of(file, dir)
        thumb = thumbnail_for(file)
        {
          name:        File.basename(file, '.skp'),
          path:        file,
          category:    category,
          subcategory: subcategory,
          thumb:       thumb,
          # mtime làm cache-buster: file đổi -> URL ảnh đổi -> trình duyệt
          # nhúng buộc phải đọc lại PNG thay vì dùng ảnh cũ trong cache
          thumb_v:     thumb ? File.mtime(thumb).to_i : 0
        }
      end
      private_class_method :item_for

      # Đường dẫn tương đối so với thư mục gốc:
      #   file.skp                  -> ['Chung', nil]
      #   01_Bep/file.skp           -> ['01_Bep', nil]
      #   01_Bep/Tu Duoi/file.skp   -> ['01_Bep', 'Tu Duoi']
      def self.category_of(file, dir)
        relative = file.sub(dir, '').tr('\\', '/').sub(%r{\A/}, '')
        parts = relative.split('/')
        case parts.size
        when 1 then [UNCATEGORIZED, nil]
        when 2 then [parts[0], nil]
        else        [parts[0], parts[1]]
        end
      end
      private_class_method :category_of

      # Gom items thành cây danh mục: [{name:, children: [...]}, ...]
      def self.build_categories(items)
        tree = {}
        items.each do |item|
          tree[item[:category]] ||= []
          tree[item[:category]] << item[:subcategory] if item[:subcategory]
        end
        tree.keys.sort.map do |name|
          { name: name, children: tree[name].uniq.sort }
        end
      end
      private_class_method :build_categories

      # Trích thumbnail nhúng trong file .skp, cache theo mtime.
      # Cache luôn nằm trên máy cục bộ kể cả khi thư viện ở ổ mạng.
      def self.thumbnail_for(file)
        png = File.join(CACHE_DIR, "#{Digest::MD5.hexdigest(file)}.png")
        if !File.exist?(png) || File.mtime(png) < File.mtime(file)
          # Xóa PNG cũ trước: nếu trích thumbnail thất bại thì hiện
          # placeholder thay vì âm thầm dùng lại ảnh cũ sai
          File.delete(png) if File.exist?(png)
          Sketchup.save_thumbnail(file, png)
        end
        File.exist?(png) ? png : nil
      end
      private_class_method :thumbnail_for

      def self.valid_skp?(path)
        path.is_a?(String) &&
          File.exist?(path) &&
          File.extname(path).casecmp('.skp').zero?
      end
      private_class_method :valid_skp?

      # Definition của component/group đầu tiên trong selection.
      def self.selected_definition
        entity = Sketchup.active_model.selection.find do |e|
          e.is_a?(Sketchup::ComponentInstance) ||
            (e.is_a?(Sketchup::Group) && e.respond_to?(:definition))
        end
        entity ? entity.definition : nil
      end
      private_class_method :selected_definition

      # Cây danh mục lấy từ cấu trúc thư mục (không quét file, nhanh).
      def self.category_tree
        dir = components_dir
        return [] unless File.directory?(dir)
        subdirs(dir).map do |cat|
          { name: cat, children: subdirs(File.join(dir, cat)) }
        end
      end
      private_class_method :category_tree

      def self.subdirs(dir)
        (Dir.entries(dir) - %w[. ..])
          .select { |e| File.directory?(File.join(dir, e)) }
          .sort
      end
      private_class_method :subdirs

      def self.sanitize_filename(name)
        name.gsub(%r{[\\/:*?"<>|]}, '').strip
      end
      private_class_method :sanitize_filename

      def self.target_dir(category, subcategory)
        dir = components_dir
        category = sanitize_filename(category)
        subcategory = sanitize_filename(subcategory)
        return dir if category.empty? || category == UNCATEGORIZED
        dir = File.join(dir, category)
        subcategory.empty? ? dir : File.join(dir, subcategory)
      end
      private_class_method :target_dir


    end # module Library
  end # module ThuVien
end # module TK
