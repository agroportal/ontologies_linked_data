require_relative "../test_case"
require "logger"
require "tmpdir"

class TestWidocoCommand < LinkedData::TestCase
  INPUT_FILE = "test/data/ontology_files/custom_properties.owl"

  def test_command_widoco_single_file
    return if ENV["SKIP_PARSING"]

    Dir.mktmpdir do |dir|
      output_folder = File.join(dir, "widoco")
      widoco = LinkedData::Documentation::WidocoCommand.new(INPUT_FILE, output_folder, logger: Logger.new(TestLogFile.new))
      widoco.generate

      assert(File.exist?(File.join(output_folder, "index-en.html")))
    end
  end

  def test_command_KO_input
    Dir.mktmpdir do |dir|
      widoco = LinkedData::Documentation::WidocoCommand.new("test/data/ontology_files/does_not_exist.owl", File.join(dir, "widoco"))
      assert_raises(LinkedData::Documentation::InputFileNotFoundError) { widoco.generate }
    end
  end
end
