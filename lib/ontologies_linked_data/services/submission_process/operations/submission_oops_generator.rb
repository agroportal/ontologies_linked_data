module LinkedData
  module Services

    class SubmissionOopsGenerator < OntologySubmissionProcess

      def process(logger, options = nil)
        generate_oops(logger)
      end

      private

      def generate_oops(logger)
        status = LinkedData::Models::SubmissionStatus.find('PITFALLS_OOPS').first
        @submission.remove_submission_status(status)

        begin
          input_file = oops_input_file
          output_folder = @submission.oops_folder

          logger.info("Scanning #{@submission.id} for modelling pitfalls from #{input_file}")
          logger.flush

          raw = LinkedData::Quality::OopsService.new(
            File.expand_path(input_file.to_s),
            File.expand_path(output_folder.to_s),
            logger: logger
          ).generate
          report = LinkedData::Quality::OopsReport.parse(raw)
          LinkedData::Quality::OopsReport.write(report, @submission.oops_report_path)

          @submission.add_submission_status(status)
          logger.info("OOPS found #{report['total_pitfalls']} pitfalls " \
                      "(#{report['total_critical']} critical) stored in #{output_folder}")
        rescue StandardError => e
          logger.error("OOPS scan failed: #{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      def oops_input_file
        rdf = @submission.rdf_path
        return rdf if rdf && File.exist?(rdf)

        @submission.bring(:uploadFilePath) if @submission.bring?(:uploadFilePath)
        @submission.bring(:masterFileName) if @submission.bring?(:masterFileName)
        @submission.master_file_path
      end
    end
  end
end
