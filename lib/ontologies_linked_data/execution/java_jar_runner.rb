require 'tempfile'

module LinkedData
  module Execution

    class CommandFailedError < StandardError; end
    class CommandTimeoutError < CommandFailedError; end
    class JarNotFoundError < CommandFailedError; end

    class JavaJarRunner

      POLL_INTERVAL_SECONDS = 1
      TERM_GRACE_SECONDS = 10
      KILL_GRACE_SECONDS = 5

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
        @logger.info("#{label} call [#{command.join(' ')}]")

        stdout_file = Tempfile.new("#{label}-stdout")
        stderr_file = Tempfile.new("#{label}-stderr")
        begin
          pid = Process.spawn(*command, out: stdout_file.path, err: stderr_file.path, pgroup: true)
          begin
            status = wait_for_exit_or_kill(pid, label)
          rescue CommandTimeoutError
            log_output(:error, label, stdout_file, stderr_file)
            raise
          rescue Exception
            terminate(pid)
            raise
          end

          unless status.success?
            log_output(:error, label, stdout_file, stderr_file)
            raise CommandFailedError, "#{label} #{exit_description(status)}. Check logs for details."
          end

          log_output(:debug, label, stdout_file, stderr_file)
          [File.read(stdout_file.path), File.read(stderr_file.path)]
        ensure
          stdout_file.close!
          stderr_file.close!
        end
      end

      private

      def log_output(level, label, stdout_file, stderr_file)
        @logger.public_send(level, "#{label} stdout: #{File.read(stdout_file.path)}")
        @logger.public_send(level, "#{label} stderr: #{File.read(stderr_file.path)}")
      end

      def exit_description(status)
        return "exited with status #{status.exitstatus}" unless status.signaled?

        "was killed by signal #{Signal.signame(status.termsig) || status.termsig}"
      end

      def build_command(args)
        target = @main_class ? ['-cp', @jar.to_s, @main_class] : ['-jar', @jar.to_s]
        ['java', "-Xmx#{@heap}", *@jvm_options, *target, *Array(args).flatten.map(&:to_s)]
      end

      def wait_for_exit_or_kill(pid, label)
        deadline = monotonic_now + @timeout
        loop do
          _, status = Process.wait2(pid, Process::WNOHANG)
          return status if status

          if monotonic_now > deadline
            terminate(pid)
            raise CommandTimeoutError, "#{label} killed due to timeout (#{@timeout}s)."
          end
          sleep POLL_INTERVAL_SECONDS
        end
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # TERM first, KILL if the JVM ignores it: a blocking wait on a process that
      # never answers TERM would hang the worker for good.
      def terminate(pid)
        signal_process_group(pid, 'TERM')
        return if reaped?(pid, TERM_GRACE_SECONDS)

        signal_process_group(pid, 'KILL')
        reaped?(pid, KILL_GRACE_SECONDS)
      end

      def reaped?(pid, grace)
        deadline = monotonic_now + grace
        loop do
          reaped, = Process.wait2(pid, Process::WNOHANG)
          return true if reaped
          return false if monotonic_now > deadline

          sleep POLL_INTERVAL_SECONDS
        end
      rescue Errno::ECHILD
        true
      end

      def signal_process_group(pid, name)
        Process.kill("-#{name}", pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
