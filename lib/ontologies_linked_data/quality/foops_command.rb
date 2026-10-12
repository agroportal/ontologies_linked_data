require 'shellwords'
require 'fileutils'
require 'net/http'
require 'uri'

module LinkedData
  module Quality

    class FoopsException < StandardError; end
    class UnreachableOntologyError < FoopsException; end
    class OutputNotGeneratedException < FoopsException; end

    class FoopsCommand

      OUTPUT_FILE = 'report.json'.freeze
      TIMEOUT_SECONDS = 60 * 15

      LAUNCHER_CLASS = 'org.springframework.boot.loader.PropertiesLauncher'.freeze
      CLI_MAIN_CLASS = 'fair.FOOPS'.freeze
      PREFLIGHT_TIMEOUT_SECONDS = 60
      PREFLIGHT_MAX_REDIRECTS = 5
      RDF_ACCEPT_HEADER = 'application/rdf+xml'.freeze
      ACCEPTABLE_PREFLIGHT_CODES = [200, 206].freeze

      def initialize(ontology_url, output_folder, opts = {})
        @jar_path      = LinkedData.bindir + '/foops.jar'
        @ontology_url  = ontology_url.to_s.strip
        @output_folder = output_folder
        @logger        = opts[:logger] || Logger.new($stdout)
        @timeout       = opts[:timeout] || TIMEOUT_SECONDS
      end

      def generate
        setup_environment
        preflight
        run_assessment
        verify_output
        json_path
      end

      def json_path
        File.join(@output_folder, OUTPUT_FILE)
      end

      private

      def setup_environment
        raise UnreachableOntologyError, 'FOOPS ontology URL is blank' if @ontology_url.empty?

        FileUtils.rm_rf(@output_folder) if File.directory?(@output_folder)
        FileUtils.mkdir_p(@output_folder)
      end

      def preflight
        response = fetch_head(parse_http_uri(@ontology_url), PREFLIGHT_MAX_REDIRECTS)

        unless ACCEPTABLE_PREFLIGHT_CODES.include?(response.code.to_i)
          raise UnreachableOntologyError,
                "#{@ontology_url} answered HTTP #{response.code}, FOOPS would score an error page."
        end

        content_type = response['content-type'].to_s
        return unless content_type.start_with?('text/html')

        raise UnreachableOntologyError,
              "#{@ontology_url} served #{content_type} instead of RDF, FOOPS would score an error page."
      end

      def parse_http_uri(url)
        uri = URI.parse(url)
        return uri if uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?

        raise UnreachableOntologyError, "#{url} is not an http(s) URL, check LinkedData.settings.foops_portal_url"
      rescue URI::InvalidURIError => e
        raise UnreachableOntologyError, "#{url} is not a valid URL: #{e.message}"
      end

      def fetch_head(uri, redirects_left)
        raise UnreachableOntologyError, "Too many redirects for #{@ontology_url}" if redirects_left.negative?

        request = Net::HTTP::Get.new(uri.request_uri)
        request['Accept'] = RDF_ACCEPT_HEADER
        request['Range']  = 'bytes=0-1023'

        response = Net::HTTP.start(uri.host, uri.port,
                                   use_ssl: uri.scheme.eql?('https'),
                                   open_timeout: PREFLIGHT_TIMEOUT_SECONDS,
                                   read_timeout: PREFLIGHT_TIMEOUT_SECONDS) do |http|
          http.request(request)
        end

        if response.is_a?(Net::HTTPRedirection) && response['location']
          return fetch_head(URI.parse(response['location']), redirects_left - 1)
        end

        response
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise UnreachableOntologyError, "#{@ontology_url} is not reachable: #{e.class}: #{e.message}"
      end

      def run_assessment
        runner = LinkedData::Execution::JavaJarRunner.new(
          jar: @jar_path, main_class: LAUNCHER_CLASS, timeout: @timeout, logger: @logger,
          jvm_options: ["-Dloader.main=#{CLI_MAIN_CLASS}"]
        )
        runner.run(
          ["-ontURI #{Shellwords.escape(@ontology_url)}",
           "-out #{Shellwords.escape(File.expand_path(json_path))}"],
          label: 'FOOPS'
        )
      end

      def verify_output
        return if File.exist?(json_path) && File.size(json_path).positive?

        raise OutputNotGeneratedException,
              "FOOPS finished but output #{json_path} cannot be found."
      end
    end
  end
end
