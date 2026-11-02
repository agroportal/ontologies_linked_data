require 'fileutils'
require 'net/http'
require 'uri'

module LinkedData
  module Quality

    class OopsException < StandardError; end
    class OopsInputFileNotFoundError < OopsException; end
    class OopsServiceError < OopsException; end

    class OopsService

      OUTPUT_FILE = 'report.rdf'.freeze
      DEFAULT_URL = 'https://oops.linkeddata.es/rest'.freeze
      TIMEOUT_SECONDS = 60 * 15

      FAILURE_MARKERS = %w[unexpected_error wrong_execution invalid_parameters].freeze

      def initialize(input_file, output_folder, opts = {})
        @input_file    = input_file
        @output_folder = output_folder
        @service_url   = opts[:service_url] || LinkedData.settings.oops_service_url || DEFAULT_URL
        @logger        = opts[:logger] || Logger.new($stdout)
        @timeout       = opts[:timeout] || TIMEOUT_SECONDS
      end

      def generate
        setup_environment
        body = post(build_request)
        verify(body)
        File.write(report_path, body)
        report_path
      end

      private

      def report_path
        File.join(@output_folder, OUTPUT_FILE)
      end

      def setup_environment
        if @input_file.nil? || !File.exist?(@input_file)
          raise OopsInputFileNotFoundError, "OOPS input file not found: #{@input_file}"
        end

        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
        FileUtils.mkdir_p(@output_folder)
      end

      def build_request
        content = File.read(@input_file, encoding: 'UTF-8')
        content = content.gsub(']]>', ']]]]><![CDATA[>')

        '<?xml version="1.0" encoding="UTF-8"?>' \
          '<OOPSRequest>' \
          '<OntologyUrl></OntologyUrl>' \
          "<OntologyContent><![CDATA[ #{content} ]]></OntologyContent>" \
          '<Pitfalls></Pitfalls>' \
          '<OutputFormat>RDF/XML</OutputFormat>' \
          '</OOPSRequest>'
      end

      def post(payload)
        uri = URI.parse(@service_url)
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/xml'
        request.body = payload

        @logger.info("Sending #{(payload.bytesize / 1024.0 / 1024.0).round(1)} MB to #{@service_url}")
        @logger.flush

        response = Net::HTTP.start(uri.host, uri.port,
                                   use_ssl: uri.scheme.eql?('https'),
                                   open_timeout: 30,
                                   read_timeout: @timeout) do |http|
          http.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise OopsServiceError, "#{@service_url} answered HTTP #{response.code}"
        end

        response.body.to_s.force_encoding('UTF-8')
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise OopsServiceError, "#{@service_url} is not reachable: #{e.class}: #{e.message}"
      end

      def verify(body)
        marker = FAILURE_MARKERS.find { |m| body.include?(m) }
        return if marker.nil?

        message = body[%r{<oops:hasMessage[^>]*>(.*?)</oops:hasMessage>}m, 1].to_s.strip
        raise OopsServiceError,
              "OOPS service could not analyse the ontology (#{marker})#{": #{message[0, 120]}" unless message.empty?}"
      end
    end
  end
end
