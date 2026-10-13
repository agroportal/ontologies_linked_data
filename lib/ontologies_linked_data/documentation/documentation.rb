module LinkedData
  module Documentation
    class << self
      attr_accessor :logger
    end

    class DocumentationException < StandardError
    end
    class MkdirException < DocumentationException
    end
    class InputFileNotFoundError < DocumentationException
    end
    class WidocoException < DocumentationException
    end
    class OutputNotGeneratedException < DocumentationException
    end
  end
end

require_relative "widoco_command"
