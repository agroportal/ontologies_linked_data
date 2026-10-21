require 'fileutils'

module LinkedData
  module Vowl

    class VowlException < StandardError; end
    class InputFileNotFoundError < VowlException; end
    class OutputNotGeneratedException < VowlException; end

    class Owl2VowlCommand

      OUTPUT_FILE = 'ontology.json'.freeze
      TIMEOUT_SECONDS = 60 * 10

      # OWL2VOWL targets Java 8; its Guice and cglib dependencies use reflection
      # that the module system blocks from Java 9 onwards.
      JVM_OPTIONS = [
        '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
        '--add-opens', 'java.base/java.lang.reflect=ALL-UNNAMED',
        '--add-opens', 'java.base/java.util=ALL-UNNAMED'
      ].freeze

      def initialize(input_file, output_folder, opts = {})
        @jar_path      = LinkedData.bindir + '/owl2vowl.jar'
        @input_file    = input_file
        @output_folder = output_folder
        @logger        = opts[:logger] || Logger.new($stdout)
        @timeout       = opts[:timeout] || TIMEOUT_SECONDS
      end

      def generate
        setup_environment
        run_converter
        verify_output
        json_path
      end

      private

      def json_path
        File.join(@output_folder, OUTPUT_FILE)
      end

      def setup_environment
        if @input_file.nil? || !File.exist?(@input_file)
          raise InputFileNotFoundError, "OWL2VOWL input file not found: #{@input_file}"
        end

        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
        FileUtils.mkdir_p(@output_folder)
      end

      def run_converter
        runner = LinkedData::Execution::JavaJarRunner.new(
          jar: @jar_path, timeout: @timeout, logger: @logger, jvm_options: JVM_OPTIONS
        )
        runner.run(
          ['-file', File.expand_path(@input_file.to_s),
           '-output', File.expand_path(json_path)],
          label: 'OWL2VOWL'
        )
      end

      def verify_output
        return if File.exist?(json_path) && File.size(json_path).positive?

        raise OutputNotGeneratedException,
              "OWL2VOWL finished but output #{json_path} cannot be found."
      end
    end
  end
end
