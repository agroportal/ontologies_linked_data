require_relative "../test_case"
require "logger"
require "tmpdir"

class TestOopsCommand < LinkedData::TestCase
  INPUT_FILE = "test/data/ontology_files/custom_properties.owl"
  REPORT = <<~RDF
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:oops="http://oops.linkeddata.es/def#">
      <oops:pitfall rdf:about="http://oops.linkeddata.es/data/p41">
        <oops:hasCode>P41 - No license declared</oops:hasCode>
        <oops:hasName>No license declared</oops:hasName>
        <oops:hasImportanceLevel> important </oops:hasImportanceLevel>
      </oops:pitfall>
      <oops:pitfall rdf:about="http://oops.linkeddata.es/data/p13">
        <oops:hasCode>P13-N - Inverse relationships not explicitly declared</oops:hasCode>
        <oops:hasImportanceLevel>Minor</oops:hasImportanceLevel>
        <oops:hasAffectedElement>http://example.org/a</oops:hasAffectedElement>
        <oops:hasAffectedElement>http://example.org/b</oops:hasAffectedElement>
        <oops:hasAffectedElement>http://example.org/c</oops:hasAffectedElement>
      </oops:pitfall>
      <oops:pitfall rdf:about="http://oops.linkeddata.es/data/p04">
        <oops:hasCode>P04 - Creating unconnected ontology elements</oops:hasCode>
        <oops:hasImportanceLevel>MINOR</oops:hasImportanceLevel>
        <oops:hasNumberAffectedElements rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">25</oops:hasNumberAffectedElements>
      </oops:pitfall>
      <oops:pitfall rdf:about="http://oops.linkeddata.es/data/p10">
        <oops:hasCode>P10 - Missing disjointness</oops:hasCode>
        <oops:hasImportanceLevel>Critical</oops:hasImportanceLevel>
        <oops:hasNumberAffectedElements rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">5</oops:hasNumberAffectedElements>
      </oops:pitfall>
      <oops:pitfall rdf:about="http://oops.linkeddata.es/data/custom">
        <oops:hasCode>Custom check</oops:hasCode>
        <oops:hasImportanceLevel>IMPORTANT</oops:hasImportanceLevel>
        <oops:hasAffectedElement>http://example.org/d</oops:hasAffectedElement>
      </oops:pitfall>
      <oops:pitfall rdf:about="http://oops.linkeddata.es/data/no-code">
        <oops:hasImportanceLevel>CRITICAL</oops:hasImportanceLevel>
      </oops:pitfall>
    </rdf:RDF>
  RDF

  def test_command_oops_single_file
    return if ENV["SKIP_PARSING"]

    Dir.mktmpdir do |dir|
      output_folder = File.join(dir, "oops")
      oops = LinkedData::Quality::OopsCommand.new(INPUT_FILE, output_folder, logger: Logger.new(TestLogFile.new))
      report_path = oops.generate

      assert(File.exist?(report_path))
      report = LinkedData::Quality::OopsReport.parse(report_path)
      assert(report["total_pitfalls"].positive?)
      report["pitfalls"].each do |p|
        assert_match(LinkedData::Quality::OopsReport::CODE_PATTERN, p["code"])
        assert_includes(LinkedData::Quality::OopsReport::IMPORTANCE_ORDER.keys, p["importance"])
      end
    end
  end

  def test_command_KO_input
    Dir.mktmpdir do |dir|
      oops = LinkedData::Quality::OopsCommand.new("test/data/ontology_files/does_not_exist.owl", File.join(dir, "oops"))
      assert_raises(LinkedData::Quality::OopsCommandInputFileNotFoundError) { oops.generate }
    end
  end

  def test_report_KO_no_pitfall
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.rdf")
      File.write(path, '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"/>')
      assert_raises(LinkedData::Quality::UnusableOopsReportError) { LinkedData::Quality::OopsReport.parse(path) }
    end
  end

  def test_report_KO_missing_file
    Dir.mktmpdir do |dir|
      assert_raises(LinkedData::Quality::UnusableOopsReportError) { LinkedData::Quality::OopsReport.parse(File.join(dir, "missing.rdf")) }
    end
  end

  def test_report_parse
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.rdf")
      File.write(path, REPORT)
      report = LinkedData::Quality::OopsReport.parse(path, max_affected_elements: 2)

      assert_equal(%w[P10 Custom\ check P41 P04 P13-N], report["pitfalls"].map { |p| p["code"] })
      assert_equal([5, 1, 2, 2], report.values_at("total_pitfalls", "total_critical", "total_important", "total_minor"))

      p41 = report["pitfalls"].find { |p| p["code"].eql?("P41") }
      assert_equal("P41 - No license declared", p41["title"])
      assert_equal("IMPORTANT", p41["importance"])
      assert_equal(0, p41["affected_elements_total"])

      assert_equal(25, report["pitfalls"].find { |p| p["code"].eql?("P04") }["affected_elements_total"])

      p13 = report["pitfalls"].find { |p| p["code"].eql?("P13-N") }
      assert_equal(3, p13["affected_elements_total"])
      assert_equal(2, p13["affected_elements"].length)
      assert_empty(p13["affected_elements"] - %w[http://example.org/a http://example.org/b http://example.org/c])
      assert(p13["affected_elements_truncated"])
    end
  end
end
