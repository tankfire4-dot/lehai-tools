# encoding: UTF-8
require 'net/http'
require 'json'
require 'fileutils'
begin; require 'openssl'; rescue LoadError; end

module LeHai
  module Tools

    def self.check_update
      UI.start_timer(5, false) do
        begin
          _do_update_check
        rescue => e
          puts "[LeHai_Tools] Loi kiem tra cap nhat: #{e.message}"
        end
      end
    end

    def self._do_update_check
      version_url  = 'https://raw.githubusercontent.com/tankfire4-dot/lehai-tools/master/version.json'
      base_raw_url = 'https://raw.githubusercontent.com/tankfire4-dot/lehai-tools/master/'
      version_file = File.join(File.dirname(__FILE__), '_installed_version')

      body = _http_get(version_url)
      return unless body

      body = body.dup.force_encoding('UTF-8').sub("﻿", '')  # lot BOM neu co
      data           = JSON.parse(body)
      remote_version = data['version'].to_s.strip
      return if remote_version.empty?

      installed = File.read(version_file).strip rescue '0.0.0'
      return unless (_ver_cmp(remote_version, installed) > 0)

      files = data['ruby_files'] || []
      return if files.empty?

      plugins_dir = File.expand_path('..', File.dirname(__FILE__))

      failed = []
      files.each do |rel_path|
        content = _http_get(base_raw_url + rel_path)
        if content
          dest = File.join(plugins_dir, rel_path)
          FileUtils.mkdir_p(File.dirname(dest))
          File.open(dest, 'wb') { |f| f.write(content) }  # wb = binary, giữ nguyên bytes UTF-8
        else
          failed << rel_path
        end
      end

      if failed.empty?
        File.write(version_file, remote_version)
        UI.messagebox(
          "LeHai's Decor Tools da cap nhat len v#{remote_version}.\n\n" \
          "Vui long KHOI DONG LAI SketchUp de ap dung.",
          MB_OK
        )
      else
        UI.messagebox(
          "Cap nhat v#{remote_version} mot phan.\nKhong tai duoc: #{failed.join(', ')}",
          MB_OK
        )
      end
    end

    def self._ver_cmp(a, b)
      a.split('.').map(&:to_i) <=> b.split('.').map(&:to_i)
    end

    def self._http_get(url_str)
      uri  = URI.parse(url_str)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = (uri.scheme == 'https')
      http.verify_mode   = OpenSSL::SSL::VERIFY_NONE if defined?(OpenSSL)
      http.open_timeout  = 8
      http.read_timeout  = 30
      res = http.get(uri.request_uri)
      return _http_get(res['location']) if [301, 302].include?(res.code.to_i)
      res.code.to_i == 200 ? res.body : nil
    rescue
      nil
    end

  end
end
