module LinkedData
  module Services

    class SubmissionVowlGenerator < OntologySubmissionProcess

      def process(logger, options = nil)
        generate_vowl(logger)
      end

      private

      def generate_vowl(logger)
        status = LinkedData::Models::SubmissionStatus.find('VOWL').first
        @submission.remove_submission_status(status)

        begin
          input_file = vowl_input_file
          output_folder = @submission.vowl_folder

          logger.info("Generating VOWL visualisation of #{@submission.id} from #{input_file}")
          logger.flush

          json_path = LinkedData::Vowl::Owl2VowlCommand.new(
            File.expand_path(input_file.to_s),
            File.expand_path(output_folder.to_s),
            logger: logger
          ).generate

          @submission.add_submission_status(status)
          logger.info("VOWL visualisation stored in #{json_path} " \
                      "(#{(File.size(json_path) / 1048576.0).round(1)} MB)")
        rescue StandardError => e
          logger.error("VOWL generation failed: #{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      def vowl_input_file
        rdf = @submission.rdf_path
        return rdf if rdf && File.exist?(rdf)

        @submission.bring(:uploadFilePath) if @submission.bring?(:uploadFilePath)
        @submission.bring(:masterFileName) if @submission.bring?(:masterFileName)
        @submission.master_file_path
      end
    end
  end
end
