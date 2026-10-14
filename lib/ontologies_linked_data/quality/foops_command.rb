require 'shellwords'
require 'fileutils'

module LinkedData
  module Quality

    class FoopsException < StandardError; end
    class InputFileNotFoundError < FoopsException; end
    class OutputNotGeneratedException < FoopsException; end

    class FoopsCommand

      OUTPUT_FILE = 'report.json'.freeze
      TIMEOUT_SECONDS = 60 * 15

      LAUNCHER_CLASS = 'org.springframework.boot.loader.PropertiesLauncher'.freeze
      CLI_MAIN_CLASS = 'fair.FOOPS'.freeze

      # Runs the 8 URI checks on the IRI declared in the file, on top of the 15
      # file checks. URI2 stays out: it compares against that same IRI.
      CHECK_IRI_FLAG = '-checkIri'.freeze

      def initialize(input_file, output_folder, opts = {})
        @jar_path      = LinkedData.bindir + '/foops.jar'
        @input_file    = input_file
        @output_folder = output_folder
        @logger        = opts[:logger] || Logger.new($stdout)
        @timeout       = opts[:timeout] || TIMEOUT_SECONDS
      end

      def generate
        setup_environment
        run_assessment
        verify_output
        json_path
      end

      def json_path
        File.join(@output_folder, OUTPUT_FILE)
      end

      private

      def setup_environment
        if @input_file.nil? || !File.exist?(@input_file)
          raise InputFileNotFoundError, "FOOPS input file not found: #{@input_file}"
        end

        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
        FileUtils.mkdir_p(@output_folder)
      end

      def run_assessment
        runner = LinkedData::Execution::JavaJarRunner.new(
          jar: @jar_path, main_class: LAUNCHER_CLASS, timeout: @timeout, logger: @logger,
          jvm_options: ["-Dloader.main=#{CLI_MAIN_CLASS}"]
        )
        runner.run(
          ["-ontFile #{Shellwords.escape(File.expand_path(@input_file.to_s))}",
           CHECK_IRI_FLAG,
           "-out #{Shellwords.escape(File.expand_path(json_path))}"],
          label: 'FOOPS'
        )
      end

      def verify_output
        return if File.exist?(json_path) && File.size(json_path).positive?

        raise OutputNotGeneratedException,
              "FOOPS finished but output #{json_path} cannot be found."
      end
    end
  end
end
