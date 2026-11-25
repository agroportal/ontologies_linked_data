require 'fileutils'

module LinkedData
  module Documentation
    class WidocoCommand

      OUTPUT_INDEX = 'index-en.html'
      TIMEOUT_SECONDS = 60 * 20

      def initialize(input_file, output_folder, opts = {})
        @widoco_jar_path = LinkedData.bindir + '/widoco.jar'
        @input_file      = input_file
        @output_folder   = output_folder
        @logger          = opts[:logger] || Documentation.logger || Logger.new($stdout)
      end

      def generate
        setup_environment
        call_widoco_java_cmd
        flatten_doc_subfolder
        verify_output
        @output_folder
      end

      private

      def index_path
        File.join(@output_folder, OUTPUT_INDEX)
      end

      def setup_environment
        if @input_file.nil? || !File.exist?(@input_file)
          raise InputFileNotFoundError, "Widoco input file not found: #{@input_file}"
        end
        if Utils::FileHelpers.exists_and_file(@output_folder)
          raise MkdirException, "Output folder is a file in the system: #{@output_folder}"
        end
        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
      end

      def widoco_options
        [
          '-ontFile', @input_file.to_s,
          '-outFolder', @output_folder.to_s,
          '-rewriteAll',
          '-getOntologyMetadata',
          '-includeAnnotationProperties',
          '-htaccess',
          '-licensius',
          '-noPlaceHolderText',
          '-lang', 'en'
        ]
      end

      def call_widoco_java_cmd
        runner = LinkedData::Execution::JavaJarRunner.new(
          jar: @widoco_jar_path, timeout: TIMEOUT_SECONDS, logger: @logger
        )
        runner.run(widoco_options, label: 'Widoco')
      end

      def verify_output
        return if File.exist?(index_path)

        raise OutputNotGeneratedException,
              "Widoco finished but output #{index_path} cannot be found."
      end

      def flatten_doc_subfolder
        nested_doc = File.join(@output_folder, 'doc')
        return unless File.directory?(nested_doc)

        Dir.children(nested_doc).each do |entry|
          FileUtils.mv(File.join(nested_doc, entry), File.join(@output_folder, entry))
        end
        FileUtils.rmdir(nested_doc)
      end
    end
  end
end
