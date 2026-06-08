# encoding: UTF-8
module LeHai
  module Tools
    unless file_loaded?(__FILE__)
      ext             = SketchupExtension.new("LeHai's Decor Tools", 'LeHai_Tools/main')
      ext.description = 'Bo cong cu thiet ke noi that Le Hai: Dan Canh, Tao Canh CNC, Tao Tam Go, Ha Nen, Dien Ten.'
      ext.version     = '1.0.0'
      ext.creator     = 'Le Hai Studio'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
