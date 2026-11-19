require_relative "../../test_case"
require_relative '../test_ontology_common'

class TestArtefactDistribution < LinkedData::TestOntologyCommon

    def test_create_artefact_distribution
        create_test_ontology
        sa = LinkedData::Models::SemanticArtefact.find('STY')
        sa.ontology.bring(*:submissions)
        sad = LinkedData::Models::SemanticArtefactDistribution.new(sa.ontology.submissions[0])
        assert_equal LinkedData::Models::SemanticArtefactDistribution , sad.class
        assert_equal "http://data.bioontology.org/mod-api/artefacts/STY/distributions/1", sad.id.to_s
    end

    def test_goo_attrs_to_load
        attrs = LinkedData::Models::SemanticArtefactDistribution.goo_attrs_to_load([])
        assert_equal [:distributionId, :title, :hasRepresentationLanguage, :hasSyntax, :description, :created, :modified, 
        :conformsToKnowledgeRepresentationParadigm, :usedEngineeringMethodology, :prefLabelProperty, 
        :synonymProperty, :definitionProperty, :accessURL, :downloadURL, :byteSize], attrs
    end

    def test_bring_attrs
        create_test_ontology
        sa = LinkedData::Models::SemanticArtefact.find('STY')
        sa.ontology.bring(*:submissions)
        latest_sub = sa.ontology.submissions[0]
        sad = LinkedData::Models::SemanticArtefactDistribution.new(latest_sub)
        sad.bring(*LinkedData::Models::SemanticArtefactDistribution.goo_attrs_to_load([:all]))
        latest_sub.bring(*LinkedData::Models::OntologySubmission.goo_attrs_to_load([:all]))

        LinkedData::Models::SemanticArtefactDistribution.attribute_mappings.each do |distribution_key, mapping|
            value_distribution_attr = sad.send(distribution_key)
            mapped_attr = mapping[:attribute]

            case mapping[:model]
            when :ontology_submission
                value_submission_attr = latest_sub.send(mapped_attr)

                if value_submission_attr.is_a?(Array)
                    value_distribution_attr.each_with_index do |v, i|
                        expected_value = value_submission_attr[i]
                        if expected_value.respond_to?(:id) && v.respond_to?(:id)
                            assert_equal expected_value.id, v.id
                        else
                            assert_equal_or_nil expected_value, v
                        end
                    end
                else
                    assert_equal_or_nil value_submission_attr, value_distribution_attr
                end
            when :metric
                metrics_obj = latest_sub.metrics
                value_submission_metric_attr = if metrics_obj && metrics_obj.respond_to?(mapped_attr)
                                                    metrics_obj.send(mapped_attr) || 0
                                                else
                                                    0
                                                end
                assert_equal_or_nil value_submission_metric_attr, value_distribution_attr
            end
        end
    end

    private
    def create_test_ontology
        acr = "STY"
        init_test_ontology_msotest acr
    end
    
end