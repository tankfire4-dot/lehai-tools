# encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'

module LeHai
  module Tools
    unless file_loaded?(__FILE__)
      ext             = SketchupExtension.new("LeHai's Decor Tools", 'LeHai_Tools/main')
      ext.description = 'Bo cong cu thiet ke noi that Le Hai: Dan Canh, Tao Canh CNC, Tao Tam Go, Ha Nen, Dien Ten, Thu Vien Component.'
      ext.version     = '1.9.55'
      ext.creator     = 'Le Hai Studio'

      begin
        Sketchup.register_extension(ext, true)
      rescue => e
        # main.rb crash → chạy emergency updater để tự sửa
        puts "[LeHai_Tools] CRASH khi load: #{e.class}: #{e.message}"
        puts e.backtrace.first(3).join("\n") if e.backtrace
        LeHai::Tools._emergency_update rescue nil
      end

      file_loaded(__FILE__)
    end

    # Emergency updater — chạy khi main.rb crash, tải bản mới về
    def self._emergency_update
      require 'net/http'
      require 'json'
      require 'fileutils'
      begin; require 'openssl'; rescue LoadError; end

      UI.start_timer(3, false) do
        begin
          # Đi qua trạm phát (URL cố định, repo hiện public) — đồng bộ với updater.rb
          version_url  = 'https://lehai-update.tankfire4.workers.dev/version.json'
          base_raw_url = 'https://lehai-update.tankfire4.workers.dev/'
          plugins_dir  = File.expand_path('..', File.dirname(__FILE__))
          version_file = File.join(File.dirname(__FILE__), 'LeHai_Tools', '_installed_version')

          uri  = URI.parse(version_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.verify_mode  = OpenSSL::SSL::VERIFY_NONE if defined?(OpenSSL)
          http.open_timeout = 8
          http.read_timeout = 30
          res  = http.get(uri.request_uri)
          body = res.code.to_i == 200 ? res.body : nil

          unless body
            UI.messagebox(
              "LeHai's Decor Tools bi loi khi khoi dong.\n\n" \
              "Vui long tai lai file .rbz tu developer va cai lai.",
              MB_OK
            )
            next
          end

          body  = body.dup.force_encoding('UTF-8').sub("﻿", '')  # lot BOM neu co
          data  = JSON.parse(body)
          files = data['ruby_files'] || []
          installed = File.read(version_file).strip rescue '0.0.0'
          remote    = data['version'].to_s.strip

          a_parts = remote.split('.').map(&:to_i)
          b_parts = installed.split('.').map(&:to_i)
          needs_update = (a_parts <=> b_parts) > 0

          if needs_update && !files.empty?
            failed = []
            files.each do |rel_path|
              file_uri  = URI.parse(base_raw_url + rel_path)
              file_http = Net::HTTP.new(file_uri.host, file_uri.port)
              file_http.use_ssl     = true
              file_http.verify_mode = OpenSSL::SSL::VERIFY_NONE if defined?(OpenSSL)
              file_http.open_timeout = 8
              file_http.read_timeout = 30
              file_res = file_http.get(file_uri.request_uri)
              if file_res.code.to_i == 200
                dest = File.join(plugins_dir, rel_path)
                FileUtils.mkdir_p(File.dirname(dest))
                File.open(dest, 'wb') { |f| f.write(file_res.body) }  # wb = binary
              else
                failed << rel_path
              end
            end

            if failed.empty?
              FileUtils.mkdir_p(File.dirname(version_file))
              File.write(version_file, remote)
              UI.messagebox(
                "LeHai's Decor Tools da tu sua loi va cap nhat len v#{remote}.\n\n" \
                "Vui long KHOI DONG LAI SketchUp.",
                MB_OK
              )
            else
              UI.messagebox(
                "LeHai's Decor Tools bi loi, cap nhat that bai mot phan.\n" \
                "Khong tai duoc: #{failed.join(', ')}\n\n" \
                "Vui long cai lai file .rbz tu developer.",
                MB_OK
              )
            end
          else
            UI.messagebox(
              "LeHai's Decor Tools bi loi khi khoi dong.\n\n" \
              "Phien ban da cap nhat. Vui long bao loi cho developer.",
              MB_OK
            )
          end
        rescue => e
          puts "[LeHai_Tools] Emergency update that bai: #{e.class}: #{e.message}"
        end
      end
    end

  end
end
