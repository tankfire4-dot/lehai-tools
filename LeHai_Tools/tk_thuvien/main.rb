# frozen_string_literal: true

module TK
  module ThuVien
    PATH = File.dirname(__FILE__.dup.force_encoding('UTF-8')).freeze

    if Sketchup.version.to_i >= 17
      require File.join(PATH, 'core', 'library')
      require File.join(PATH, 'ui', 'dialog')
      require File.join(PATH, 'ui', 'commands')
    end

    def self.create_cmd
      return nil unless Sketchup.version.to_i >= 17
      Commands.build_cmd
    end
  end
end
