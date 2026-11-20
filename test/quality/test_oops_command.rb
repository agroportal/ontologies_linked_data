require_relative "../test_case"
require "logger"
require "tmpdir"

class TestOopsCommand < LinkedData::TestCase
  INPUT_FILE = "test/data/ontology_files/custom_properties.owl"

  def test_command_oops_single_file
    return if ENV["SKIP_PARSING"]

    Dir.mktmpdir do |dir|
      output_folder = File.join(dir, "oops")
      oops = LinkedData::Quality::OopsCommand.new(INPUT_FILE, output_folder, logger: Logger.new(TestLogFile.new))
      report_path = oops.generate

      assert(File.exist?(report_path))
      report = LinkedData::Quality::OopsReport.parse(report_path)
      assert(report["total_pitfalls"].positive?)
      assert(report["pitfalls"].all? { |p| p["code"] && p["importance"] })
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
end
