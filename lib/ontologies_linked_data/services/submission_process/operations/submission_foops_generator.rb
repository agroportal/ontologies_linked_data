require 'json'

module LinkedData
  module Services

    class SubmissionFoopsGenerator < OntologySubmissionProcess

      def process(logger, options = nil)
        generate_foops(logger)
      end

      private

      def generate_foops(logger)
        status = LinkedData::Models::SubmissionStatus.find('FAIRNESS_FOOPS').first
        @submission.remove_submission_status(status)

        begin
          input_file = foops_input_file
          output_folder = @submission.foops_folder

          logger.info("Assessing FAIRness of #{@submission.id} from #{input_file}")
          logger.flush

          report_path = LinkedData::Quality::FoopsCommand.new(
            File.expand_path(input_file.to_s),
            File.expand_path(output_folder.to_s),
            logger: logger
          ).generate
          report = JSON.parse(File.read(report_path))

          @submission.add_submission_status(status)
          logger.info("FOOPS score #{(report['overall_score'].to_f * 100).round(1)}% stored in #{output_folder}")
        rescue StandardError => e
          logger.error("FOOPS assessment failed: #{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      def foops_input_file
        rdf = @submission.rdf_path
        return rdf if rdf && File.exist?(rdf)

        @submission.bring(:uploadFilePath) if @submission.bring?(:uploadFilePath)
        @submission.bring(:masterFileName) if @submission.bring?(:masterFileName)
        @submission.master_file_path
      end
    end
  end
end
