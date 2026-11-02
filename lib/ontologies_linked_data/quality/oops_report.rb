require 'json'
require 'rdf'
require 'rdf/rdfxml'

module LinkedData
  module Quality

    class UnusableOopsReportError < OopsException; end

    class OopsReport

      NAMESPACE = 'http://oops.linkeddata.es/def#'.freeze
      MAX_AFFECTED_ELEMENTS = 20
      IMPORTANCE_ORDER = { 'CRITICAL' => 0, 'IMPORTANT' => 1, 'MINOR' => 2 }.freeze
      CODE_PATTERN = /\A(P\d+(?:-[A-Z0-9]+)?)/.freeze

      class << self

        def parse(path, max_affected_elements: MAX_AFFECTED_ELEMENTS)
          pitfalls = read_pitfalls(path, max_affected_elements)
          raise UnusableOopsReportError, "No pitfall could be read from #{path}" if pitfalls.empty?

          pitfalls.sort_by! { |p| [IMPORTANCE_ORDER.fetch(p['importance'], 9), -p['affected_elements_total'].to_i] }

          {
            'total_pitfalls' => pitfalls.length,
            'total_critical' => pitfalls.count { |p| p['importance'].eql?('CRITICAL') },
            'total_important' => pitfalls.count { |p| p['importance'].eql?('IMPORTANT') },
            'total_minor' => pitfalls.count { |p| p['importance'].eql?('MINOR') },
            'pitfalls' => pitfalls
          }
        end

        def write(report, path)
          File.write(path, JSON.pretty_generate(report))
          path
        end

        private

        def read_pitfalls(path, limit)
          graph = RDF::Graph.new
          RDF::RDFXML::Reader.open(path) { |reader| graph << reader }

          graph.query([nil, RDF.type, RDF::URI("#{NAMESPACE}pitfall")]).map(&:subject).uniq.map do |subject|
            pitfall(graph, subject, limit)
          end.compact
        rescue UnusableOopsReportError
          raise
        rescue StandardError => e
          raise UnusableOopsReportError, "OOPS report #{path} cannot be read: #{e.class}: #{e.message}"
        end

        def pitfall(graph, subject, limit)
          props = Hash.new { |h, k| h[k] = [] }
          graph.query([subject, nil, nil]) { |st| props[st.predicate.to_s.sub(NAMESPACE, '')] << st.object.to_s }

          raw_code = props['hasCode'].first
          return nil if raw_code.nil?

          elements = props['hasAffectedElement']
          declared = props['hasNumberAffectedElements'].first

          {
            'code' => CODE_PATTERN.match(raw_code)&.captures&.first || raw_code,
            'title' => raw_code,
            'name' => props['hasName'].first,
            'description' => props['hasDescription'].first,
            'importance' => props['hasImportanceLevel'].first&.strip&.upcase,
            'affected_elements_total' => (declared || elements.length).to_i,
            'affected_elements' => elements.first(limit),
            'affected_elements_truncated' => elements.length > limit
          }
        end
      end
    end
  end
end
