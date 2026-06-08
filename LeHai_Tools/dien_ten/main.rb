# frozen_string_literal: true

module TuDong
  module DienTen
    PATH = File.dirname(__FILE__).freeze

    require File.join(PATH, 'core', 'namer')
    require File.join(PATH, 'ui',   'menu')
    require File.join(PATH, 'ui',   'dialog')

    def self.run
      model     = Sketchup.active_model
      selection = model.selection
      top_level = Namer.filter_top_level(selection)

      if top_level.empty?
        UI.messagebox(
          "Vui lòng chọn ít nhất một component hoặc group.\n\n" \
          "Các đối tượng bị khóa (locked) sẽ bị bỏ qua.",
          MB_OK
        )
        return
      end

      if top_level.size == 1
        targets = Namer.collect_all_nested(top_level)
        parent  = top_level.first
      else
        targets = top_level
        parent  = nil
      end

      Dialog.show(targets, parent)
    end
  end
end
