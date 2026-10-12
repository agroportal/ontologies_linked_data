require 'shellwords'
require 'tempfile'

module LinkedData
  module Execution

    class CommandFailedError < StandardError; end
    class CommandTimeoutError < CommandFailedError; end
    class JarNotFoundError < CommandFailedError; end

    class JavaJarRunner

      POLL_INTERVAL_SECONDS = 1

      def initialize(jar:, timeout:, logger: nil, heap: nil, main_class: nil, jvm_options: [])
        @jar         = jar
        @timeout     = timeout
        @logger      = logger || Logger.new($stdout)
        @heap        = heap || LinkedData.settings.java_max_heap_size
        @main_class  = main_class
        @jvm_options = Array(jvm_options)
      end

      def run(args, label: File.basename(@jar.to_s))
        raise JarNotFoundError, "Jar not found: #{@jar}" unless File.exist?(@jar.to_s)

        command = build_command(args)
        @logger.info("#{label} call [#{command}]")

        stdout_file = Tempfile.new("#{label}-stdout")
        stderr_file = Tempfile.new("#{label}-stderr")
        begin
          pid = Process.spawn(command, out: stdout_file.path, err: stderr_file.path, pgroup: true)
          status = wait_for_exit_or_kill(pid, label)

          stdout = File.read(stdout_file.path)
          stderr = File.read(stderr_file.path)

          unless status&.success?
            @logger.error("#{label} stdout: #{stdout}")
            @logger.error("#{label} stderr: #{stderr}")
            raise CommandFailedError,
                  "#{label} exited with status #{status&.exitstatus}. Check logs for details."
          end

          [stdout, stderr]
        ensure
          stdout_file.close!
          stderr_file.close!
        end
      end

      private

      def build_command(args)
        options = Array(args).join(' ')
        jvm = @jvm_options.empty? ? '' : "#{@jvm_options.join(' ')} "
        target = @main_class ? "-cp #{Shellwords.escape(@jar.to_s)} #{@main_class}" : "-jar #{Shellwords.escape(@jar.to_s)}"
        "java -Xmx#{@heap} #{jvm}#{target} #{options}"
      end

      def wait_for_exit_or_kill(pid, label)
        deadline = Time.now + @timeout
        loop do
          _, status = Process.wait2(pid, Process::WNOHANG)
          return status if status

          if Time.now > deadline
            kill_process_group(pid)
            Process.wait2(pid)
            raise CommandTimeoutError, "#{label} killed due to timeout (#{@timeout}s)."
          end
          sleep POLL_INTERVAL_SECONDS
        end
      end

      def kill_process_group(pid)
        Process.kill('-TERM', pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
