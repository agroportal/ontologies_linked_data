require_relative "../../test_case"
require_relative '../test_ontology_common'

class TestArtefact < LinkedData::TestOntologyCommon

    def self.before_suite
        backend_4s_delete
        helper = LinkedData::TestOntologyCommon.new(self)
        helper.init_test_ontology_msotest "STY"
    end

    def test_create_artefact
        sa = LinkedData::Models::SemanticArtefact.new
        assert_equal LinkedData::Models::SemanticArtefact , sa.class
    end

    def test_find_artefact
        sa = LinkedData::Models::SemanticArtefact.find('STY')
        assert_equal LinkedData::Models::SemanticArtefact , sa.class
        assert_equal "STY", sa.acronym
        assert_equal "STY", sa.ontology.acronym
    end

    def test_goo_attrs_to_load
        attrs = LinkedData::Models::SemanticArtefact.goo_attrs_to_load([])
        assert_equal [:acronym, :title, :accessRights, :subject, :URI, :versionIRI, :creator, :identifier, :status, :language, 
        :license, :rightsHolder, :description, :landingPage, :keyword, :bibliographicCitation, :contactPoint,
        :contributor, :publisher, :coverage, :createdWith, :accrualMethod, :accrualPeriodicity, 
        :competencyQuestion, :wasGeneratedBy, :hasFormat, :includedInDataCatalog, :semanticArtefactRelation], attrs
    end

    def test_bring_attrs
        r = LinkedData::Models::SemanticArtefact.find('STY')
        r.bring(*LinkedData::Models::SemanticArtefact.goo_attrs_to_load([:all]))
        ont = r.ontology
        latest_sub = r.ontology.latest_submission
        latest_sub.bring(*LinkedData::Models::OntologySubmission.goo_attrs_to_load([:all]))

        LinkedData::Models::SemanticArtefact.attribute_mappings.each do |artefact_key, mapping|
            value_artefact_attr = r.send(artefact_key)
            mapped_attr = mapping[:attribute]

            case mapping[:model]
            when :ontology
                value_ontology_attr = ont.send(mapped_attr)
                if value_ontology_attr.is_a?(Array)
                    value_artefact_attr.each_with_index do |v, i|
                        expected_value = value_ontology_attr[i]
                        if expected_value.respond_to?(:id) && v.respond_to?(:id)
                            assert_equal expected_value.id, v.id
                        else
                            assert_equal_or_nil expected_value, v
                        end
                    end
                else
                    assert_equal_or_nil value_ontology_attr, value_artefact_attr 
                end
            when :ontology_submission
                value_submission_attr = latest_sub.send(mapped_attr)

                if value_submission_attr.is_a?(Array)
                    value_artefact_attr.each_with_index do |v, i|
                        if v.respond_to?(:id) && value_submission_attr[i].respond_to?(:id)
                            assert_equal v.id, value_submission_attr[i].id
                        else
                            assert_equal_or_nil value_submission_attr[i], v
                        end
                    end
                else
                    assert_equal_or_nil value_submission_attr, value_artefact_attr
                end
            when :metric
                metrics_obj = latest_sub.metrics
                value_submission_metric_attr = if metrics_obj && metrics_obj.respond_to?(mapped_attr)
                                                    metrics_obj.send(mapped_attr) || 0
                                                else
                                                    0
                                                end
                assert_equal_or_nil value_submission_metric_attr, value_artefact_attr
            end
        end

        assert_equal r.analytics, ont.analytics
    end


    def test_latest_distribution
        sa = LinkedData::Models::SemanticArtefact.find('STY')
        assert_equal "STY", sa.acronym
        latest_distribution = sa.latest_distribution(status: :any)

        assert_equal LinkedData::Models::SemanticArtefactDistribution , latest_distribution.class
        assert_equal 1, latest_distribution.distributionId
        assert_equal 1, latest_distribution.submission.submissionId
    end
    
    def test_all_artefacts
        attributes = LinkedData::Models::SemanticArtefact.goo_attrs_to_load([])
        page = 1
        pagesize = 1
        all_artefacts = LinkedData::Models::SemanticArtefact.all_artefacts(attributes, page, pagesize)
        assert_equal LinkedData::Models::HydraPage, all_artefacts.class
        assert_equal 1, all_artefacts.length
        assert_equal LinkedData::Models::SemanticArtefact, all_artefacts[0].class
    end

    def test_distributions
        r = LinkedData::Models::SemanticArtefact.find('STY')
        attributes =  LinkedData::Models::SemanticArtefactDistribution.goo_attrs_to_load([])
        page = 1
        pagesize = 1
        all_distros = r.all_distributions(attributes, page, pagesize)
        assert_equal LinkedData::Models::HydraPage, all_distros.class
        assert_equal 1, all_distros.length
        assert_equal LinkedData::Models::SemanticArtefactDistribution, all_distros[0].class
    end

end