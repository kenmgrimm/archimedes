require "test_helper"

module Neo4j
  class TaxonomyServiceTest < ActiveSupport::TestCase
    setup do
      @service = Neo4j::TaxonomyService.new
    end

    test "loads entity types from YAML" do
      assert_includes @service.entity_types, "Person"
      assert_includes @service.entity_types, "Organization"
      assert_includes @service.entity_types, "Location"
    end

    test "gets properties for entity type" do
      person_props = @service.properties_for("Person")
      assert_not_empty person_props
      assert_includes person_props.keys, :name
      assert_includes person_props.keys, :email
    end

    test "gets relationship types for entity type" do
      rels = @service.relationship_types_for("Person")
      assert_not_empty rels
      assert_includes rels.keys, :worksFor
      assert_includes rels.keys, :memberOf
    end

    test "validates property values" do
      assert @service.valid_property_value?("Person", "name", "John Doe")
      assert @service.valid_property_value?("Person", "birthDate", "1990-01-01")
      assert @service.valid_property_value?("Person", "email", "test@example.com")

      assert_not @service.valid_property_value?("Person", "birthDate", "not-a-date")
      assert_not @service.valid_property_value?("Person", "email", "not-an-email")
    end

    test "gets property type descriptions" do
      types = @service.property_types
      assert_includes types.keys, "Text"
      assert_includes types.keys, "Date"
      assert_includes types.keys, "DateTime"
    end
  end
end
