# frozen_string_literal: true

module LinkedData
  module Parser
    # Converts Crop Ontology Template XLSX files to OWL/RDF XML.
    class XlsxConverter
      # Raised when the uploaded file does not conform to the TDV5 template
      # (missing sheet, missing required columns) — as opposed to downstream
      # RDF/OWLAPI errors. Mapped to the ERROR_TDV5 submission status.
      class TemplateValidationError < ArgumentError; end

      SHEET_NAME = "Template for submission"

      # Dublin Core Terms vocabulary
      DCTERMS = RDF::Vocabulary.new("http://purl.org/dc/terms/")

      # SKOS vocabulary
      SKOS = RDF::Vocabulary.new("http://www.w3.org/2004/02/skos/core#")

      # Header column names that should never appear as data values.
      HEADER_VALUES = [
        "Variable name", "Trait name", "Method name", "Scale name",
        "Variable ID", "Trait ID", "Method ID", "Scale ID"
      ].freeze

      REQUIRED_COLUMNS = [
        "Variable name", "Trait name", "Method name", "Scale name", "Variable ID"
      ].freeze

      # Main entry point. Returns OWL/RDF XML string.
      def self.convert(file_path, ontology_id, base_uri)
        require "rdf"
        require "rdf/rdfxml"
        require "roo"
        new(file_path, ontology_id, base_uri).call
      end

      def initialize(file_path, ontology_id, base_uri)
        @file_path = file_path
        @ontology_id = ontology_id
        base_uri = base_uri.to_s.strip
        raise ArgumentError, "A base URI (submission URI) is required to convert the XLSX" if base_uri.empty?
        @base_uri = base_uri.chomp("/") + "/"
      end

      def call
        rows = parse_xlsx
        result = build_owl(rows)
        result.to_s
      end

      private

      # === PHASE 1: Parse XLSX ===

      def parse_xlsx
        spreadsheet = Roo::Spreadsheet.open(@file_path)
        unless spreadsheet.sheets.include?(SHEET_NAME)
          raise TemplateValidationError, "XLSX must contain a sheet named '#{SHEET_NAME}' (found: #{spreadsheet.sheets.join(', ')})"
        end
        sheet = spreadsheet.sheet(SHEET_NAME)

        parsed = sheet.parse(headers: true)
        return [] if parsed.nil? || parsed.empty?

        rows = parsed.map { |row| normalize_row(row) }

        # Replace empty/whitespace-only strings with nil
        rows.each do |row|
          row.each_key do |col|
            val = row[col]
            row[col] = nil if val.is_a?(String) && val.strip.empty?
          end
        end

        # Drop rows that are all nil/empty
        rows.reject! { |row| row.values.all? { |v| v.nil? || (v.is_a?(String) && v.empty?) } }

        # Validate required columns are not empty (per the TDV5 template spec).
        # Trait/Method/Scale ID are intentionally excluded: the spec allows leaving
        # them blank for auto-generation, which auto_generate_ids! still does.
        missing_cols = REQUIRED_COLUMNS.select do |col|
          rows.any? { |row| row[col].to_s.strip.empty? }
        end
        if missing_cols.any?
          raise TemplateValidationError, "Required columns must not be empty: #{missing_cols.join(', ')}"
        end

        # Fill nil with empty string, remove quotes
        rows.each do |row|
          row.each_key do |col|
            val = row[col]
            if val.nil?
              row[col] = ""
            elsif val.is_a?(String)
              row[col] = val.strip.gsub(/\A["']+|["']+\z/, "")
            end
          end
        end

        # Auto-generate IDs for missing ones
        auto_generate_ids!(rows)

        # Filter out duplicate header rows
        rows.reject! { |row| header_row?(row) }

        rows
      end

      def header_row?(row)
        HEADER_VALUES.any? { |h| row[h] == h }
      end

      def normalize_row(row)
        normalized = {}
        row.each do |key, value|
          normalized[key.to_s.strip] = value
        end
        normalized
      end

      SHARED_ID_COLUMNS = [
        ["Trait name",  "Trait ID"],
        ["Method name", "Method ID"],
        ["Scale name",  "Scale ID"]
      ].freeze

      ID_COLUMNS = ["Variable ID", "Trait ID", "Method ID", "Scale ID"].freeze

      def auto_generate_ids!(rows)
        used_ids = collect_explicit_ids(rows)
        counter = 0
        mint = lambda do
          loop do
            counter += 1
            candidate = "#{@ontology_id}:#{counter.to_s.rjust(7, "0")}"
            next if used_ids.key?(candidate)
            used_ids[candidate] = true
            return candidate
          end
        end

        SHARED_ID_COLUMNS.each do |name_col, id_col|
          name_to_id = {}
          rows.each do |row|
            id = row[id_col].to_s.strip
            name_to_id[row[name_col]] ||= id unless id.empty?
          end
          rows.each do |row|
            next unless row[id_col].to_s.strip.empty?
            name_to_id[row[name_col]] ||= mint.call
            row[id_col] = name_to_id[row[name_col]]
          end
        end
      end

      def collect_explicit_ids(rows)
        ids = {}
        ID_COLUMNS.each do |col|
          rows.each do |row|
            v = row[col].to_s.strip
            ids[v] = true unless v.empty?
          end
        end
        ids
      end

      # === PHASE 2: Build OWL graph ===

      def build_owl(rows)
        graph = RDF::Graph.new
        ns = @base_uri

        define_properties(graph, ns)

        ontology_uri = RDF::URI(ns)
        graph << [ontology_uri, RDF.type, RDF::OWL.Ontology]
        graph << [ontology_uri, DCTERMS.license, RDF::URI("https://creativecommons.org/licenses/by/4.0/")]

        crop = rows.first && rows.first["Crop"]
        graph << [ontology_uri, RDF::RDFS.label, RDF::Literal("#{crop} ontology")] if crop && !crop.to_s.empty?

        rows.each do |row|
          var_id    = row["Variable ID"]
          var_name  = row["Variable name"]
          trait_id  = row["Trait ID"]
          method_id = row["Method ID"]
          scale_id  = row["Scale ID"]

          var_uri = RDF::URI(ns + var_id)

          add_variable(graph, ns, var_uri, var_name, row)

          trait_uri = RDF::URI(ns + trait_id)
          add_trait(graph, ns, trait_uri, row)
          add_restriction(graph, ns, var_uri, "variable_of", trait_uri)

          method_uri = RDF::URI(ns + method_id)
          add_method(graph, ns, method_uri, row)
          add_restriction(graph, ns, var_uri, "variable_of", method_uri)
          add_restriction(graph, ns, method_uri, "method_of", trait_uri)

          scale_uri = RDF::URI(ns + scale_id)
          add_scale(graph, ns, scale_uri, row)
          add_restriction(graph, ns, var_uri, "variable_of", scale_uri)
          add_restriction(graph, ns, scale_uri, "scale_of", method_uri)
        end

        graph.dump(:rdfxml, validate: false)
      end

      def define_properties(graph, ns)
        [[:variable_of, RDF::OWL.ObjectProperty],
         [:scale_of,    RDF::OWL.ObjectProperty],
         [:method_of,   RDF::OWL.ObjectProperty]].each do |name, type|
          uri = RDF::URI(ns + name.to_s)
          graph << [uri, RDF.type, type]
          graph << [uri, RDF::RDFS.label, RDF::Literal(name.to_s)]
        end

        [[:acronym, "acronym"],
         [:entity,  "entity"],
         [:attribute, "attribute"]].each do |name, label|
          uri = RDF::URI(ns + name.to_s)
          graph << [uri, RDF.type, RDF::OWL.AnnotationProperty]
          graph << [uri, RDF::RDFS.label, RDF::Literal(label)]
        end
      end

      def add_variable(graph, ns, var_uri, var_name, row)
        graph << [var_uri, RDF.type, RDF::OWL.Class]
        graph << [var_uri, RDF::RDFS.subClassOf, RDF::URI(ns + "Variable")]
        graph << [var_uri, RDF::RDFS.label, RDF::Literal(var_name, language: :en)]

        add_synonyms(graph, var_uri, row["Variable synonyms"])

        if (v = row["Variable Xref"]).to_s.strip.length > 0
          graph << [var_uri, DCTERMS.source, RDF::Literal(v.to_s)]
        end
        if (v = row["Institution"]).to_s.strip.length > 0
          graph << [var_uri, DCTERMS.contributor, RDF::Literal(v.to_s)]
        end
        if (v = row["Scientist"]).to_s.strip.length > 0
          graph << [var_uri, DCTERMS.contributor, RDF::Literal(v.to_s)]
        end
      end

      def add_trait(graph, ns, trait_uri, row)
        graph << [trait_uri, RDF.type, RDF::OWL.Class]
        graph << [trait_uri, RDF::RDFS.label, RDF::Literal(row["Trait name"].to_s, language: :en)]
        graph << [trait_uri, SKOS.definition, RDF::Literal(row["Trait description"].to_s, language: :en)]

        add_synonyms(graph, trait_uri, row["Trait synonyms"])

        if (v = row["Main trait abbreviation"]).to_s.strip.length > 0
          graph << [trait_uri, RDF::URI(ns + "acronym"), RDF::Literal(v.to_s, language: :en)]
        end
        if (v = row["Alternative trait abbreviations"]).to_s.strip.length > 0
          v.to_s.split(",").each do |abbr|
            graph << [trait_uri, SKOS.altLabel, RDF::Literal(abbr.strip, language: :en)]
          end
        end
        if (v = row["Entity"]).to_s.strip.length > 0
          graph << [trait_uri, RDF::URI(ns + "entity"), RDF::Literal(v.to_s)]
        end
        if (v = row["Attribute"]).to_s.strip.length > 0
          graph << [trait_uri, RDF::URI(ns + "attribute"), RDF::Literal(v.to_s)]
        end
        if (v = row["Trait Xref"]).to_s.strip.length > 0
          graph << [trait_uri, DCTERMS.source, RDF::Literal(v.to_s)]
        end

        trait_class = row["Trait class"].to_s.strip
        if trait_class.length > 0
          parent_class = trait_class.gsub(" ", "_")
          graph << [trait_uri, RDF::RDFS.subClassOf, RDF::URI(ns + parent_class)]
          graph << [RDF::URI(ns + parent_class), RDF::RDFS.subClassOf, RDF::URI(ns + "Trait")]
        else
          graph << [trait_uri, RDF::RDFS.subClassOf, RDF::URI(ns + "Trait")]
        end
      end

      def add_method(graph, ns, method_uri, row)
        graph << [method_uri, RDF.type, RDF::OWL.Class]
        graph << [method_uri, RDF::RDFS.label, RDF::Literal(row["Method name"].to_s, language: :en)]
        graph << [method_uri, SKOS.definition, RDF::Literal(row["Method description"].to_s, language: :en)]

        if (v = row["Method reference"]).to_s.strip.length > 0
          graph << [method_uri, DCTERMS.source, RDF::Literal(v.to_s)]
        end

        method_class = row["Method class"].to_s.strip
        if method_class.length > 0
          parent_class = method_class.gsub(" ", "_")
          graph << [method_uri, RDF::RDFS.subClassOf, RDF::URI(ns + parent_class)]
          graph << [RDF::URI(ns + parent_class), RDF::RDFS.subClassOf, RDF::URI(ns + "Method")]
        else
          graph << [method_uri, RDF::RDFS.subClassOf, RDF::URI(ns + "Method")]
        end
      end

      def add_scale(graph, ns, scale_uri, row)
        graph << [scale_uri, RDF.type, RDF::OWL.Class]
        graph << [scale_uri, RDF::RDFS.label, RDF::Literal(row["Scale name"].to_s, language: :en)]

        if (v = row["Scale Xref"]).to_s.strip.length > 0
          graph << [scale_uri, DCTERMS.source, RDF::Literal(v.to_s)]
        end

        scale_class = row["Scale class"].to_s.strip
        if scale_class.length > 0
          parent_class = scale_class.gsub(" ", "_")
          graph << [scale_uri, RDF::RDFS.subClassOf, RDF::URI(ns + parent_class)]
          graph << [RDF::URI(ns + parent_class), RDF::RDFS.subClassOf, RDF::URI(ns + "Scale")]
        else
          graph << [scale_uri, RDF::RDFS.subClassOf, RDF::URI(ns + "Scale")]
        end

        add_categories(graph, ns, scale_uri, row["Scale ID"], row)
      end

      def add_categories(graph, ns, scale_uri, scale_id, row)
        categories = []

        if row.key?("Category 1") && !row["Category 1"].to_s.strip.empty?
          i = 1
          while row.key?("Category #{i}")
            val = row["Category #{i}"].to_s.strip
            categories << val unless val.empty?
            i += 1
          end
        else
          i = 1
          while row.key?("Cat #{i} code")
            code = row["Cat #{i} code"].to_s.strip
            desc = row["Cat #{i} description"].to_s.strip
            categories << "#{code}=#{desc}" unless code.empty?
            i += 1
          end
        end

        categories.each do |s|
          begin
            if s.match?(/\A\[\d+\]/)
              cat_nums = s.scan(/\d+/)
              next if cat_nums.empty?
              cat_uri = RDF::URI(ns + scale_id + "/" + cat_nums[0].strip)
              cat_label = s.split("]", 2)[1].to_s.strip
              graph << [cat_uri, RDF::RDFS.subClassOf, scale_uri]
              graph << [cat_uri, RDF::RDFS.label, RDF::Literal(cat_label, language: :en)]
              graph << [cat_uri, SKOS.altLabel, RDF::Literal(cat_nums[0].strip, language: :en)]
            elsif s.include?("=")
              parts = s.split("=", 2)
              cat_uri = RDF::URI(ns + scale_id + "/" + parts[0].strip.gsub(" ", "_"))
              graph << [cat_uri, RDF::RDFS.subClassOf, scale_uri]
              graph << [cat_uri, RDF::RDFS.label, RDF::Literal(parts[1].strip, language: :en)]
              graph << [cat_uri, SKOS.altLabel, RDF::Literal(parts[0].strip, language: :en)]
            end
          rescue StandardError
            # Graceful skip — same as Python's except Exception: pass
          end
        end
      end

      def add_synonyms(graph, uri, synonyms_str)
        synonyms = synonyms_str.to_s.strip
        return if synonyms.empty?
        synonyms.split(",").each do |syn|
          s = syn.strip
          graph << [uri, SKOS.altLabel, RDF::Literal(s, language: :en)] unless s.empty?
        end
      end

      def add_restriction(graph, ns, source_uri, property_name, target_uri)
        bnode = RDF::Node.new
        graph << [bnode, RDF.type, RDF::OWL.Restriction]
        graph << [bnode, RDF::OWL.onProperty, RDF::URI(ns + property_name.to_s)]
        graph << [bnode, RDF::OWL.someValuesFrom, target_uri]
        graph << [source_uri, RDF::RDFS.subClassOf, bnode]
      end
    end
  end
end
