require 'open3'
require 'shellwords'
require 'tempfile'

module LinkedData
  module Documentation
    class WidocoCommand

      OUTPUT_INDEX = 'index-en.html'
      TIMEOUT_SECONDS = 60 * 20

      def initialize(input_file, output_folder, opts = {})
        @widoco_jar_path = LinkedData.bindir + '/widoco.jar'
        @java_heap_size  = LinkedData.settings.java_max_heap_size
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

      def index_path
        File.join(@output_folder, OUTPUT_INDEX)
      end

      private

      def setup_environment
        if @input_file.nil? || !File.exist?(@input_file)
          raise InputFileNotFoundError, "Widoco input file not found: #{@input_file}"
        end
        unless File.exist?(@widoco_jar_path)
          raise WidocoException, "Widoco jar not found: #{@widoco_jar_path}"
        end
        if Utils::FileHelpers.exists_and_file(@output_folder)
          raise MkdirException, "Output folder is a file in the system: #{@output_folder}"
        end
        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
      end

      def widoco_options
        [
          "-ontFile #{Shellwords.escape(@input_file.to_s)}",
          "-outFolder #{Shellwords.escape(@output_folder.to_s)}",
          '-rewriteAll',
          '-getOntologyMetadata',
          '-includeAnnotationProperties',
          '-htaccess',
          '-licensius',
          '-noPlaceHolderText',
          '-lang en'
        ].join(' ')
      end

      POLL_INTERVAL_SECONDS = 1

      def call_widoco_java_cmd
        command_call = "java -Xmx#{@java_heap_size} -jar #{@widoco_jar_path} #{widoco_options}"
        @logger.info("Widoco call [#{command_call}]")

        stdout_file = Tempfile.new('widoco-stdout')
        stderr_file = Tempfile.new('widoco-stderr')
        begin
          pid = Process.spawn(command_call, out: stdout_file.path, err: stderr_file.path, pgroup: true)
          status = wait_for_exit_or_kill(pid)

          stdout = File.read(stdout_file.path)
          stderr = File.read(stderr_file.path)

          unless status&.success?
            @logger.error("Widoco stdout: #{stdout}")
            @logger.error("Widoco stderr: #{stderr}")
            raise WidocoException,
                  "Widoco command exited with status #{status&.exitstatus}. Check logs for details."
          end
          @logger.info(stdout)
        ensure
          stdout_file.close!
          stderr_file.close!
        end
      end

      # Polls instead of relying on Timeout.timeout, which is unreliable
      # around blocking subprocess waits: it can fail to interrupt in time,
      # and even when it does, the underlying OS process is left running
      # (an orphan that keeps writing to @output_folder in the background,
      # racing a later retry's cleanup). Killing the whole process group
      # (pgroup: true + negative pid) reaches the actual java process, not
      # just a shell wrapper.
      def wait_for_exit_or_kill(pid)
        deadline = Time.now + TIMEOUT_SECONDS
        loop do
          _, status = Process.wait2(pid, Process::WNOHANG)
          return status if status

          if Time.now > deadline
            kill_process_group(pid)
            Process.wait2(pid)
            raise WidocoException, "Widoco command killed due to timeout (#{TIMEOUT_SECONDS}s)."
          end
          sleep POLL_INTERVAL_SECONDS
        end
      end

      def kill_process_group(pid)
        Process.kill('-TERM', pid)
      rescue Errno::ESRCH
        # process group already gone
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
