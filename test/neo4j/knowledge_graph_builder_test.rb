require "test_helper"
require "tempfile"

module Neo4j
  class KnowledgeGraphBuilderTest < ActiveSupport::TestCase
    setup do
      # Mock OpenAI client
      @openai_service = Minitest::Mock.new
      @neo4j_service = nil # We'll implement Neo4j storage later

      # Create a test logger that captures output
      @output = StringIO.new
      @logger = Logger.new(@output)

      # Initialize with test logger
      @builder = Neo4j::KnowledgeGraphBuilder.new(
        openai_service: @openai_service,
        neo4j_service: @neo4j_service,
        logger: @logger
      )
    end

    test "processes documents and extracts entities" do
      # Sample text to process
      sample_text = <<~TEXT
        John Smith is a software engineer at Acme Corp in New York.#{' '}
        He previously worked at TechStart Inc. in Boston.#{' '}
        He attended MIT and graduated in 2015.
      TEXT

      # Create a temporary file
      temp_file = Tempfile.new("test_doc.txt")
      temp_file.write(sample_text)
      temp_file.rewind

      # Mock the expected OpenAI response
      expected_response = {
        entities: [
          { type: "Person", name: "John Smith", description: "Software engineer", confidence: 0.95, source_text: "John Smith" },
          { type: "Organization", name: "Acme Corp", description: "Company", confidence: 0.9, source_text: "Acme Corp" },
          { type: "Location", name: "New York", description: "City", confidence: 0.98, source_text: "New York" }
        ],
        relationships: [
          { type: "worksAt", source: "John Smith", target: "Acme Corp", description: "Employment", confidence: 0.92,
            source_text: "John Smith is a software engineer at Acme Corp" }
        ]
      }

      # Set up the mock
      @openai_service.expect(:extract_entities_with_taxonomy, expected_response) do |text:, taxonomy:|
        # Verify the text and taxonomy are passed correctly
        assert_includes text, "John Smith"
        assert_includes taxonomy[:entity_types], "Person"
        true
      end

      # Process the document
      results = @builder.process_documents([temp_file])

      # Verify the results
      assert_equal 1, results[:processed]
      assert_empty results[:errors]

      # Check the fixture was created
      fixtures = @builder.send(:fixture_service).list_fixtures
      assert_includes @output.string, "Extracted 3 entities and 1 relationships"

      # Print the fixture for inspection
      latest_fixture = @builder.send(:fixture_service).load_fixture(fixtures.last[:id])
      puts "\n=== Extracted Data ==="
      puts JSON.pretty_generate(latest_fixture)
    ensure
      temp_file.close
      temp_file.unlink
    end
  end
end
