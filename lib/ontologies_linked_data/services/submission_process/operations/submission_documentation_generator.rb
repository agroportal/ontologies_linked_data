module LinkedData
  module Services

    class SubmissionDocumentationGenerator < OntologySubmissionProcess

      def process(logger, options = nil)
        generate_documentation(logger)
      end

      private

      def generate_documentation(logger)
        status = LinkedData::Models::SubmissionStatus.find('DOCUMENTATION').first
        @submission.remove_submission_status(status)

        begin
          input_file = documentation_input_file
          output_folder = @submission.documentation_folder

          logger.info("Generating documentation (Widoco) for #{@submission.id} from #{input_file}")
          logger.flush

          LinkedData::Documentation::WidocoCommand.new(
            File.expand_path(input_file.to_s),
            File.expand_path(output_folder.to_s),
            logger: logger
          ).generate

          @submission.add_submission_status(status)
          logger.info("Documentation generated in #{output_folder}")
        rescue StandardError => e
          logger.error("Documentation generation failed: #{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
          logger.flush
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      def documentation_input_file
        rdf = @submission.rdf_path
        return rdf if rdf && File.exist?(rdf)

        @submission.bring(:uploadFilePath) if @submission.bring?(:uploadFilePath)
        @submission.uploadFilePath
      end

    end
  end
end
