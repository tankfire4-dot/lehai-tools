# frozen_string_literal: true

require 'json'

module TK
  module ThuVien
    # Cửa sổ HtmlDialog hiển thị thư viện.
    # Mọi trao đổi dữ liệu dùng add_action_callback + execute_script
    # (không dùng fetch — bug treo trên SU2024, issue #991).
    module Dialog

      HTML_FILE = File.join(PATH, 'ui', 'html', 'index.html').freeze
      PREFS_KEY = 'tk.thuvien.dialog'

      def self.show
        if @dialog&.visible?
          @dialog.bring_to_front
          push_library
        else
          @dialog = create_dialog
          attach_callbacks(@dialog)
          @dialog.show
        end
      end

      # ── private ──────────────────────────────────────────────

      def self.create_dialog
        UI::HtmlDialog.new(
          dialog_title:    'Thư Viện Component',
          preferences_key: PREFS_KEY,
          width:           860,
          height:          600,
          min_width:       480,
          min_height:      360,
          resizable:       true,
          style:           UI::HtmlDialog::STYLE_DIALOG
        ).tap { |d| d.set_file(HTML_FILE) }
      end
      private_class_method :create_dialog

      def self.attach_callbacks(dialog)
        dialog.add_action_callback('ready')  { push_library }
        dialog.add_action_callback('refresh') { push_library }
        dialog.add_action_callback('insert') { |_ctx, path| Library.insert(path) }
        dialog.add_action_callback('open_folder') { Library.open_components_folder }
        dialog.add_action_callback('choose_folder') do
          push_library if Library.choose_folder
        end
        dialog.add_action_callback('save_dialog') do
          info = Library.save_dialog_info
          @dialog.execute_script("app.showSaveForm(#{info.to_json});") if info
        end
        dialog.add_action_callback('save_to_library') do |_ctx, json|
          result = Library.save_selected(JSON.parse(json))
          if result[:ok]
            push_library
          elsif result[:msg]
            UI.messagebox(result[:msg])
          end
        end
        dialog.add_action_callback('edit_dialog') do |_ctx, path|
          info = Library.edit_dialog_info(path)
          @dialog.execute_script("app.showEditForm(#{info.to_json});") if info
        end
        dialog.add_action_callback('edit_item') do |_ctx, json|
          result = Library.edit_item(JSON.parse(json))
          if result[:ok]
            push_library
          elsif result[:msg]
            UI.messagebox(result[:msg])
          end
        end
      end
      private_class_method :attach_callbacks

      def self.push_library
        return unless @dialog&.visible?
        data = Library.scan
        @dialog.execute_script("app.setLibrary(#{data.to_json});")
      end
      private_class_method :push_library

    end # module Dialog
  end # module ThuVien
end # module TK
