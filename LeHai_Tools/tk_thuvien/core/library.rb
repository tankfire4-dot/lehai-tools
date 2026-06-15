# frozen_string_literal: true

require 'digest'
require 'json'
require 'fileutils'

module TK
  module ThuVien
    module Library

      PREFS_SECTION = 'TK_ThuVien'
      PREFS_KEY_DIR = 'library_path'

      DEFAULT_DIR   = File.join(PATH, 'components').freeze
      CACHE_DIR     = File.join(PATH, 'cache').freeze
      UNCATEGORIZED = 'Chung'

      STYLES = [
        { key: 'hien_dai',     label: 'Hiện đại'    },
        { key: 'toi_gian',     label: 'Tối giản'    },
        { key: 'tan_co_dien',  label: 'Tân cổ điển' },
        { key: 'scandinavian', label: 'Scandinavian' },
        { key: 'japandi',      label: 'Japandi'      },
        { key: 'industrial',   label: 'Industrial'   },
      ].freeze

      PHONGS = [
        { key: 'bep',       label: 'Bếp'       },
        { key: 'khach',     label: 'Khách'     },
        { key: 'ngu',       label: 'Ngủ'       },
        { key: 'an',        label: 'Ăn'        },
        { key: 'lam_viec',  label: 'Làm việc'  },
        { key: 'wc',        label: 'WC'        },
        { key: 'hanh_lang', label: 'Hành lang' },
      ].freeze

      # Trả về Hash {root:, exists:, categories:, items:} cho UI.
      def self.scan
        dir = components_dir
        return { root: dir, exists: false, categories: [], items: [] } unless
          File.directory?(dir)

        ensure_cache_dir
        catalog = read_catalog
        items = skp_files(dir).map { |file| item_for(file, dir, catalog) }
        {
          root:       dir,
          exists:     true,
          categories: build_categories(items),
          items:      items.sort_by { |i| i[:name].downcase }
        }
      end

      def self.components_dir
        saved = Sketchup.read_default(PREFS_SECTION, PREFS_KEY_DIR)
        saved.is_a?(String) && !saved.empty? ? saved : DEFAULT_DIR
      end

      def self.choose_folder
        dir = UI.select_directory(
          title:     'Chọn thư mục thư viện component',
          directory: components_dir
        )
        return false unless dir.is_a?(String) && File.directory?(dir)
        Sketchup.write_default(PREFS_SECTION, PREFS_KEY_DIR, dir)
        true
      end

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
        { name: name, categories: category_tree, styles: STYLES, phongs: PHONGS }
      end

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
          update_catalog(path, params)
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

      def self.item_for(file, dir, catalog = {})
        category, subcategory = category_of(file, dir)
        thumb = thumbnail_for(file)
        rel   = relative_path(file, dir)
        meta  = catalog[rel] || {}
        {
          name:        File.basename(file, '.skp'),
          path:        file,
          category:    category,
          subcategory: subcategory,
          thumb:       thumb,
          thumb_v:     thumb ? File.mtime(thumb).to_i : 0,
          style:       Array(meta['style']),
          phong:       Array(meta['phong']),
          r:           meta['r'],
          c:           meta['c']
        }
      end
      private_class_method :item_for

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

      def self.thumbnail_for(file)
        png = File.join(CACHE_DIR, "#{Digest::MD5.hexdigest(file)}.png")
        if !File.exist?(png) || File.mtime(png) < File.mtime(file)
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

      def self.selected_definition
        entity = Sketchup.active_model.selection.find do |e|
          e.is_a?(Sketchup::ComponentInstance) ||
            (e.is_a?(Sketchup::Group) && e.respond_to?(:definition))
        end
        entity ? entity.definition : nil
      end
      private_class_method :selected_definition

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
        category    = sanitize_filename(category)
        subcategory = sanitize_filename(subcategory)
        return dir if category.empty? || category == UNCATEGORIZED
        dir = File.join(dir, category)
        subcategory.empty? ? dir : File.join(dir, subcategory)
      end
      private_class_method :target_dir

      def self.catalog_path
        File.join(components_dir, 'catalog.json')
      end
      private_class_method :catalog_path

      def self.read_catalog
        path = catalog_path
        return {} unless File.exist?(path)
        content = File.open(path, 'r:UTF-8') { |f| f.read }
        JSON.parse(content)
      rescue JSON::ParserError
        {}
      end
      private_class_method :read_catalog

      def self.write_catalog(catalog)
        File.open(catalog_path, 'w:UTF-8') { |f| f.write(JSON.pretty_generate(catalog)) }
      rescue IOError, Errno::EACCES => e
        UI.messagebox("Không ghi được catalog:\n#{e.message}")
      end
      private_class_method :write_catalog

      def self.update_catalog(path, params)
        style = Array(params['style']).reject { |s| s.to_s.strip.empty? }
        phong = Array(params['phong']).reject { |s| s.to_s.strip.empty? }
        r     = params['r'].to_s.strip
        c     = params['c'].to_s.strip
        return if style.empty? && phong.empty? && r.empty? && c.empty?

        catalog = read_catalog
        rel     = relative_path(path, components_dir)
        entry   = catalog[rel] || {}
        entry['style'] = style        unless style.empty?
        entry['phong'] = phong        unless phong.empty?
        entry['r']     = r.to_i       unless r.empty?
        entry['c']     = c.to_i       unless c.empty?
        catalog[rel]   = entry
        write_catalog(catalog)
      end
      private_class_method :update_catalog

      def self.relative_path(file, dir)
        file.sub(dir, '').tr('\\', '/').sub(%r{\A/}, '')
      end
      private_class_method :relative_path

    end # module Library
  end # module ThuVien
end # module TK
