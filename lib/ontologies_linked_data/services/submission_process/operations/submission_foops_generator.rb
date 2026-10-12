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
        raise StandardError, 'SubmissionStatus FAIRNESS_FOOPS is not initialised' if status.nil?

        @submission.remove_submission_status(status)

        begin
          if portal_url.to_s.strip.empty?
            logger.info('Skipping FOOPS: LinkedData.settings.foops_portal_url is not configured')
            logger.flush
            return
          end

          if restricted?
            logger.info("Skipping FOOPS for #{@submission.id}: the ontology is not publicly reachable")
            logger.flush
            return
          end

          url = ontology_url
          output_folder = @submission.foops_folder

          logger.info("Assessing FAIRness of #{@submission.id} through #{url}")
          logger.flush

          report_path = LinkedData::Quality::FoopsCommand.new(url, output_folder, logger: logger).generate
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

      def restricted?
        ontology = @submission.ontology
        ontology.bring(:viewingRestriction) if ontology.bring?(:viewingRestriction)
        !ontology.viewingRestriction.to_s.eql?('public')
      end

      def portal_url
        LinkedData.settings.foops_portal_url
      end



      def ontology_url
        ontology = @submission.ontology
        ontology.bring(:acronym) if ontology.bring?(:acronym)
        "#{portal_url.to_s.chomp('/')}/ontologies/#{ontology.acronym}"
      end
    end
  end
end
