# encoding: UTF-8
require 'net/http'
require 'json'
require 'fileutils'
require 'openssl'

module LeHai
  module Tools

    VERSION_URL  = 'https://raw.githubusercontent.com/tankfire4-dot/lehai-tools/master/version.json'.freeze
    BASE_RAW_URL = 'https://raw.githubusercontent.com/tankfire4-dot/lehai-tools/master/'.freeze

    # File lưu version đang cài — nằm cạnh updater.rb
    VERSION_FILE = File.join(File.dirname(__FILE__), '_installed_version').freeze

    def self.installed_version
      File.read(VERSION_FILE).strip
    rescue
      '0.0.0'
    end

    def self.check_update
      UI.start_timer(5, false) { _do_check }
    end

    def self._do_check
      body = http_get(VERSION_URL)
      return unless body

      data           = JSON.parse(body)
      remote_version = data['version'].to_s.strip
      return if remote_version.empty?
      return unless newer?(remote_version, installed_version)

      files = data['ruby_files'] || []
      return if files.empty?

      # Thư mục Plugins = 1 cấp trên thư mục LeHai_Tools/
      plugins_dir = File.expand_path('..', File.dirname(__FILE__))

      failed = []
      files.each do |rel_path|
        content = http_get(BASE_RAW_URL + rel_path)
        if content
          dest = File.join(plugins_dir, rel_path)
          FileUtils.mkdir_p(File.dirname(dest))
          File.open(dest, 'w:UTF-8') { |f| f.write(content) }
        else
          failed << rel_path
        end
      end

      if failed.empty?
        File.write(VERSION_FILE, remote_version)
        UI.messagebox(
          "LeHai's Decor Tools đã cập nhật lên v#{remote_version}.\n\n" \
          "Vui lòng KHỞI ĐỘNG LẠI SketchUp để áp dụng.",
          MB_OK
        )
      else
        UI.messagebox(
          "Cập nhật v#{remote_version} chỉ một phần.\n" \
          "Không tải được: #{failed.join(', ')}",
          MB_OK
        )
      end
    rescue => e
      puts "[LeHai_Tools updater] #{e.message}"
    end

    def self.newer?(remote, current)
      (remote.split('.').map(&:to_i) <=> current.split('.').map(&:to_i)) > 0
    end

    def self.http_get(url_str)
      uri  = URI.parse(url_str)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl       = true
      http.verify_mode   = OpenSSL::SSL::VERIFY_NONE
      http.open_timeout  = 8
      http.read_timeout  = 30
      res = http.get(uri.request_uri)
      return http_get(res['location']) if [301, 302].include?(res.code.to_i)
      res.code.to_i == 200 ? res.body : nil
    rescue
      nil
    end

  end
end
