require_relative "./test_ontology_common"
require "logger"

class TestClassModel < LinkedData::TestOntologyCommon

  def test_class_parents

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"

    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).to_a[0]
    pp = cls.parents[0]
    assert_equal(os.id, pp.submission.id)
    pp.bring(:parents)
    assert pp.parents.length == 1
    assert_equal(os.id, pp.parents.first.submission.id)

    # read_only
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).read_only.all[0]
    pp = cls.parents[0]
    assert_equal(os.id, pp.submission.id)

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:parents).first
    parents = cls.parents
    assert_equal(parents, cls.parents)
    assert_equal(3, cls.parents.length)
    parent_ids = ["http://bioportal.bioontology.org/ontologies/msotes#class2",
                  "http://bioportal.bioontology.org/ontologies/msotes#class4",
                  "http://bioportal.bioontology.org/ontologies/msotes#class3"]
    parent_id_db = cls.parents.map { |x| x.id.to_s }
    assert_equal(parent_id_db.sort, parent_ids.sort)

    assert !cls.parents[0].submission.nil?
    # they should have the same submission
    assert_equal(cls.parents[0].submission, os)

    # transitive
    cls.bring(:ancestors)
    assert_includes cls.loaded_attributes.to_a, :ancestors
    ancestors = cls.ancestors.dup
    ancestors.each do |a|
      assert !a.submission.nil?
    end
    assert ancestors.length == cls.ancestors.length
    ancestors.map! { |a| a.id.to_s }
    data_ancestors = ["http://bioportal.bioontology.org/ontologies/msotes#class1",
                      "http://bioportal.bioontology.org/ontologies/msotes#class2",
                      "http://bioportal.bioontology.org/ontologies/msotes#class4",
                      "http://bioportal.bioontology.org/ontologies/msotes#class3"]
    assert ancestors.sort == data_ancestors.sort

  end

  def test_class_children

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class1"

    cls = LinkedData::Models::Class.find(class_id).in(os)
                                   .include(:parents)
                                   .include(:children)
                                   .to_a[0]
    children = cls.children
    assert_equal(1, cls.children.length)
    children_id = "http://bioportal.bioontology.org/ontologies/msotes#class2"
    assert_equal(children_id, cls.children[0].id.to_s)

    # they should have the same submission
    assert_equal(cls.children[0].submission, os)

    # transitive
    cls.bring(:descendants)
    assert_includes cls.loaded_attributes.to_a, :descendants
    descendants = cls.descendants.dup
    descendants.map! { |a| a.id.to_s }
    data_descendants = ["http://bioportal.bioontology.org/ontologies/msotes#class_5",
                        "http://bioportal.bioontology.org/ontologies/msotes#class2",
                        "http://bioportal.bioontology.org/ontologies/msotes#class_7"]
    assert descendants.sort == data_descendants.sort
    page = cls.retrieve_descendants(page = 2, size = 2)
    assert page.total_pages == 2
    assert page.prev_page == 1
    assert page.next_page == nil
    assert page.aggregate == 3
    assert page[0].id.to_s == data_descendants[2]

    cls = LinkedData::Models::Class.find(class_id).in(os)
                                   .to_a[0]
    cls.load_has_children
    has_c = cls.hasChildren
    assert_equal(has_c, true)
    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"
    cls = LinkedData::Models::Class.find(class_id).in(os)
                                   .to_a[0]
    cls.load_has_children
    has_c = cls.hasChildren
    assert_equal(has_c, false)
  end

  def test_path_to_root

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_7"

    cls = LinkedData::Models::Class.find(class_id).in(os).first

    paths = cls.paths_to_root
    assert paths.length == 1
    path = paths[0]
    assert path.length == 3
    assert path[2].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class_7"
    assert path[1].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class2"
    assert path[0].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class1"

  end

  def test_path_to_root_with_multiple_parents

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    cls = LinkedData::Models::Class.find(class_id).in(os).first

    paths = cls.paths_to_root
    # class3 and class4 form a cycle; each path through it must be listed once.
    path_ids = paths.map { |p| p.map { |c| c.id.to_s.split('#').last } }
    assert_equal [%w[class1 class2 class_5], %w[class3 class4 class_5], %w[class3 class_5],
                  %w[class4 class3 class_5], %w[class4 class_5]], path_ids.sort
    # sort the array by the 0s element id
    paths = paths.sort { |a, b| a[0].nil? ? -1 : b[0].nil? ? 1 : a[0].id.to_s <=> b[0].id.to_s }.select { |x| x.length == 3 }
    path = paths[0]
    assert path.length == 3
    assert path[2].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    assert path[1].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class2"
    assert path[0].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class1"
    path = paths[1]
    assert path.length == 3
    assert path[2].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class_5"
    assert path[1].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class4"
    assert path[0].id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class3"

  end

  def test_class_all_attributes

    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::URI.new "http://bioportal.bioontology.org/ontologies/msotes#class2"
    cls = LinkedData::Models::Class.find(class_id).in(os).include(:unmapped).first
    versionInfo = Goo.vocabulary(:owl)[:versionInfo]
    uris = cls.properties.keys.map { |k| k.to_s }
    assert uris.include?(versionInfo.to_s)

    bad_property = "http://data.bioontology.org/metadata/def/mappingLoom"
    assert !uris.include?(bad_property)

    cls.properties.each do |k, v|
      if k == versionInfo
        assert v[0].value == "some version info"
      end
    end
  end

  def test_children_count

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]
    clss = LinkedData::Models::Class.in(os)
                                    .include(:prefLabel)
                                    .aggregate(:count, :children)
                                    .all
    clss.each do |c|
      if c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class1"
        assert c.childrenCount == 1
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class2"
        assert c.childrenCount == 2
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class3"
        assert c.childrenCount == 2
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class4"
        assert c.childrenCount == 2
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class97"
        assert c.childrenCount == 1
      elsif c.id.to_s == "http://bioportal.bioontology.org/ontologies/msotes#class98"
        assert c.childrenCount == 1
      else
        assert c.childrenCount == 0
      end
    end
  end

  def test_bro_tree
    # just one path with children
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    assert os
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).first

    root_backend = cls.tree
    assert root_backend.id.to_s == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"
    tree_backend = root_backend
    root_backend.children.each do |c|
      assert c.childrenCount > 0
    end
    levels = 0
    while tree_backend and tree_backend.children.length > 0 do
      cc = 0
      next_tree = nil
      tree_backend.children.each do |c|
        assert c.childrenCount != nil
        assert c.prefLabel != nil
        next_tree = c if c.children.length > 0
      end
      assert cc < 2
      if next_tree.nil?
        assert tree_backend.children.select { |x| x.id.to_s == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis" }.length == 1
        assert tree_backend.children.length == 2
        assert tree_backend.children.first.childrenCount == 0
        assert tree_backend.children[1].childrenCount == 0
      end
      tree_backend = next_tree
      levels += 1
    end
  end

  def test_tree_exceeded_threshold_bug
    submission_parse('INRAETHES', 'Testing skos',
                     'test/data/ontology_files/thesaurusINRAE_nouv_structure.skos',
                     1, process_rdf: true, extract_metadata: false, generate_missing_labels: false)
    ontology = LinkedData::Models::Ontology.find('INRAETHES').first
    latest_submission = ontology.latest_submission(status: [:rdf])
    cls = LinkedData::Models::Class.find('http://opendata.inrae.fr/thesaurusINRAE/c_9983').in(latest_submission).first
    tree = cls.tree(concept_schemes: ['http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE'])

    index_of_parent = tree.children.index { |x| x.prefLabel.to_s['CON processed biobased products'] }
    refute_nil index_of_parent

    cls_parent = tree.children[index_of_parent].children
    index_of_parent = cls_parent.index { |x| x.prefLabel.to_s['by-product'] }
    refute_nil index_of_parent

    cls_parent = cls_parent[index_of_parent]
    index_of_parent = cls_parent.children.index{ |x| x.id.to_s['c_10443'] }
    refute_nil index_of_parent

    cls_parent = cls_parent.children[index_of_parent]
    index_of_parent = cls_parent.children.index{ |x| x.id.to_s['c_10392'] }
    refute_nil index_of_parent

    cls_parent = cls_parent.children[index_of_parent]
    refute cls_parent.bring?(:children), 'child not found'
    assert_includes cls_parent.children.map(&:prefLabel),'press cake'
  end

  def test_include_ancestors
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    assert_raises ArgumentError do
      cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os)
                                     .include(:prefLabel, ancestors: [:prefLabel]).first
    end
  end

  def test_bro_paths_to_root
    if !LinkedData::Models::Ontology.find("BROTEST123").first
      submission_parse("BROTEST123", "SOME BROTEST Bla", "./test/data/ontology_files/BRO_v3.2.owl", 123,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: true)
    end
    os = LinkedData::Models::Ontology.find("BROTEST123").first.latest_submission(status: [:rdf])
    statistical_Text_Analysis = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis"
    cls = LinkedData::Models::Class.find(RDF::URI.new(statistical_Text_Analysis)).in(os).first

    paths_backend = cls.paths_to_root
    paths = []
    paths_backend.each do |pb|
      paths << pb.map { |x| x.id.to_s }
    end

    path_0 = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Text_Mining",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Mining_and_Inference",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Analysis_Software",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Software",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"].reverse

    path_1 = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Text_Mining",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Natural_Language_Processing",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Analysis_Software",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Software",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"].reverse

    path_2 = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Text_Analysis",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Text_Mining",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Mining_and_Inference",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Statistical_Analysis",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Analysis_Software",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Software",
              "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"].reverse

    paths.each do |path|
      assert (path == path_0 || path == path_1 || path == path_2)
    end
    assert paths.length == 3
    assert paths[0] != paths[1]
    assert paths[1] != paths[2]
    assert paths[0] != paths[2]

    # xref test in bro
    classId = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource"
    classIR = LinkedData::Models::Class.find(RDF::URI.new(classId))
                                       .in(os).include(:xref, :prefLabel).first
    assert_equal(classIR.xref, "hasDbXref0000001")
    assert_equal(classIR.prefLabel, "Information Resource")

  end

  def test_xml_literal_serialization
    comment = "A form of cancer that begins in melanocytes (cells that make the pigment melanin). It may begin in a mole (skin melanoma), but can also begin in other pigmented tissues, such as in the eye or in the intestines.NCI-GLOSS"
    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr],
                                                      submissionId: 1).all
    assert(os.length == 1)
    os = os[0]

    class_id = RDF::IRI.new "http://bioportal.bioontology.org/ontologies/msotes#class6"

    cls = LinkedData::Models::Class.find(class_id).in(os).include(:unmapped).to_a[0]

    cls_hash = cls.to_flex_hash(only: [:properties])
    xml_comment = cls_hash[:properties]["http://www.w3.org/2000/01/rdf-schema#comment"].first
    assert_equal String, xml_comment.class
    assert_equal comment, xml_comment
  end

  # Companion to test_bro_paths_to_root, for the OBO tree property. BRO cannot
  # cover this: owlapi asserts `rdfs:subClassOf owl:Thing` on top-level OWL
  # classes, and the traversal treats owl:Thing as a stop sentinel. OBO
  # submissions walk metadata:treeView, where no such sentinel exists, so the
  # traversal has to terminate on a genuinely parentless ancestor instead.
  # Regressing that recurses into an empty parents array and raises
  # "undefined method `id' for nil:NilClass" in append_if_not_there_already.
  def test_obo_paths_to_root_terminates_at_parentless_class
    if !LinkedData::Models::Ontology.find("HPPATHSTEST").first
      submission_parse("HPPATHSTEST", "HP paths_to_root test", "./test/data/ontology_files/hp.obo", 124,
                       process_rdf: true, index_search: false,
                       run_metrics: false)
    end
    os = LinkedData::Models::Ontology.find("HPPATHSTEST").first.latest_submission(status: [:rdf])

    assert_equal 'http://data.bioontology.org/metadata/treeView',
                 LinkedData::Models::Class.tree_view_property(os).to_s,
                 'expected the OBO tree property, otherwise this duplicates the OWL test'

    # Find a class with a parent that itself has no parents -- one hop is enough
    # to make the traversal walk into the parentless ancestor. Candidates are
    # sorted so the same class is picked on every backend (row order is not
    # guaranteed and differs between 4store/AG/GraphDB/Virtuoso).
    # owl:Thing has no parents either, but the traversal stops on it via the
    # sentinel, so it does not exercise the empty-parents branch.
    classes = LinkedData::Models::Class.in(os)
                                       .include(parents: [:prefLabel, parents: [:prefLabel]])
                                       .page(1, 500).to_a
    target_id = classes.select do |cls|
      (cls.parents || []).any? { |p| !p.id.to_s['#Thing'] && (p.parents || []).empty? }
    end.map { |cls| cls.id.to_s }.min
    refute_nil target_id, 'expected an OBO class whose parent is parentless'
    target = LinkedData::Models::Class.find(RDF::URI.new(target_id)).in(os).first

    # A path may also stop on the owl:Thing sentinel, which owlapi asserts on
    # top-level classes.
    assert_paths_terminate_at_parentless(target, allow_thing: true)
  end

  # The remaining paths_to_root tests drive the traversal directly with stub
  # nodes, so they need no triplestore and pin exact path shapes.
  class StubNode
    attr_reader :id, :loaded_attributes, :submission, :brings
    attr_accessor :parents

    # loaded: false with no load_parents models a class whose parents cannot load.
    def initialize(id, parents: [], loaded: true, load_parents: nil)
      @id = RDF::URI.new("http://example.org/#{id}")
      @parents = parents
      @loaded_attributes = Set.new(loaded ? [:parents] : [])
      @load_parents = load_parents
      @submission = Struct.new(:id).new('http://example.org/sub')
      @brings = 0
    end

    def bring?(attr)
      attr == :parents && !@loaded_attributes.include?(:parents) && !@load_parents.nil?
    end

    def bring(*)
      @brings += 1
      @parents = @load_parents.call
      @loaded_attributes << :parents
    end
  end

  def stub_paths(target)
    paths = [[target]]
    LinkedData::Models::Class.new.send(:traverse_path_to_root, target.parents.dup, paths, 0)
    paths.map { |p| p.map { |n| n.id.to_s.split('/').last } }
  end

  def test_paths_to_root_keeps_siblings_when_a_parent_cannot_load
    top = StubNode.new('top')
    good = StubNode.new('good', parents: [top])
    broken = StubNode.new('broken', loaded: false)
    target = StubNode.new('target', parents: [broken, good])

    # broken is first, so a `return` in the fail-safe would cut off good's path.
    assert_equal [%w[target broken], %w[target good top]].sort, stub_paths(target).sort
  end

  def test_paths_to_root_drops_cycle_parents_without_duplicate_paths
    top = StubNode.new('top')
    target = StubNode.new('target')
    a = StubNode.new('a', parents: [target, top])
    target.parents = [a]

    # a's parent `target` closes a cycle. It must not leave a second, unextended
    # copy of [target, a] next to the real path.
    assert_equal [%w[target a top]], stub_paths(target)
  end

  def test_paths_to_root_loads_a_shared_ancestor_once
    top = StubNode.new('top')
    # Two separately loaded instances of the same ancestor, as goo returns them
    # when it reaches `shared` through two different parents.
    shared_via_a = StubNode.new('shared', loaded: false, load_parents: -> { [top] })
    shared_via_b = StubNode.new('shared', loaded: false, load_parents: -> { [top] })
    a = StubNode.new('a', parents: [shared_via_a])
    b = StubNode.new('b', parents: [shared_via_b])
    target = StubNode.new('target', parents: [a, b])

    assert_equal [%w[target a shared top], %w[target b shared top]].sort, stub_paths(target).sort
    assert_equal 1, shared_via_a.brings + shared_via_b.brings, 'shared ancestor loaded more than once'
  end
end
