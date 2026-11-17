require 'fileutils'

module LinkedData
  module Quality

    class OopsException < StandardError; end
    class OopsCommandError < OopsException; end
    class OopsCommandInputFileNotFoundError < OopsCommandError; end
    class OopsCommandOutputNotGeneratedException < OopsCommandError; end

    # Runs OOPS! locally from its runnable jar, the way owlapi and FOOPS! are
    # run, instead of posting the ontology to the external OOPS! web service.
    class OopsCommand

      OUTPUT_FILE = 'report.rdf'.freeze
      TIMEOUT_SECONDS = 60 * 15

      def initialize(input_file, output_folder, opts = {})
        @jar_path      = LinkedData.bindir + '/oops.jar'
        @input_file    = input_file
        @output_folder = output_folder
        @logger        = opts[:logger] || Logger.new($stdout)
        @timeout       = opts[:timeout] || TIMEOUT_SECONDS
      end

      def generate
        setup_environment
        run_scan
        verify_output
        report_path
      end

      private

      def report_path
        File.join(@output_folder, OUTPUT_FILE)
      end

      def setup_environment
        if @input_file.nil? || !File.exist?(@input_file)
          raise OopsCommandInputFileNotFoundError, "OOPS input file not found: #{@input_file}"
        end

        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
        FileUtils.mkdir_p(@output_folder)
      end

      def run_scan
        runner = LinkedData::Execution::JavaJarRunner.new(
          jar: @jar_path, timeout: @timeout, logger: @logger
        )
        runner.run(
          ['--input-file', File.expand_path(@input_file.to_s),
           '--out', File.expand_path(report_path)],
          label: 'OOPS'
        )
      end

      def verify_output
        return if File.exist?(report_path) && File.size(report_path).positive?

        raise OopsCommandOutputNotGeneratedException,
              "OOPS finished but output #{report_path} cannot be found."
      end
    end
  end
end
