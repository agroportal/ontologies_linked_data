require_relative "../test_case"

class TestGroup < LinkedData::TestCase

  def test_ontology_format_equal
    this = LinkedData::Models::OntologyFormat.find('OWL').first
    that = LinkedData::Models::OntologyFormat.find('OWL').first
    assert(!this.nil?, msg="OntologyFormat failed to find OWL.")
    assert(!that.nil?, msg="OntologyFormat failed to find OWL.")
    assert_equal(this, that, msg="OntologyFormat 'OWL' failing equality test.")
    assert_equal(this, "OWL", msg="OntologyFormat 'OWL' failing equality test.")
    assert(this.owl?, msg="OntologyFormat failing .owl? test.")
  end

  def test_ontology_format_tdv5
    format = LinkedData::Models::OntologyFormat.find('TDV5').first
    assert(!format.nil?, msg="OntologyFormat failed to find TDV5.")
    assert(format.tdv5?, msg="OntologyFormat failing .tdv5? test.")
    assert_equal(format, "TDV5", msg="OntologyFormat 'TDV5' failing equality test.")
    assert_equal(".xlsx", format.file_extension,
                 msg="TDV5 submissions are uploaded as spreadsheets.")
    assert_equal([".xlsx", ".xls", ".csv"], format.master_file_extensions,
                 msg="TDV5 accepts the spreadsheet extensions.")
  end

end
