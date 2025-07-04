module Neo4j
  class KnowledgeGraphBuilder
    def initialize(openai_service:, neo4j_service:, taxonomy_service: nil, logger: nil, fixture_service: nil)
      @openai = openai_service
      @neo4j = neo4j_service
      @logger = logger || Rails.logger
      @taxonomy_service = taxonomy_service || Neo4j::TaxonomyService.new(logger: logger)
      @extractor = Neo4j::EntityExtractionService.new(
        openai_service,
        taxonomy_service: @taxonomy_service,
        logger: logger
      )
      @fixture_service = fixture_service || Neo4j::FixtureService.new(logger: logger)
      @last_processed_at = nil
    end

    def process_documents(documents, metadata = {})
      validate_documents(documents)
      results = { processed: 0, errors: [] }

      documents.each do |doc|
        extract_and_store_entities(doc, metadata)
        results[:processed] += 1
        @last_processed_at = Time.current
      rescue StandardError => e
        error_msg = "Failed to process #{doc}: #{e.message}"
        @logger.error(error_msg)
        results[:errors] << error_msg
      end

      results
    end

    def health_check
      {
        status: :ok,
        last_processed: @last_processed_at,
        dependencies: {
          neo4j: @neo4j.respond_to?(:health_check) ? @neo4j.health_check : :unknown
        }
      }
    end

    private

    # No default taxonomy - using TaxonomyService instead

    def validate_documents(documents)
      raise ArgumentError, "No documents provided" if documents.blank?

      documents.each do |doc|
        next if doc.respond_to?(:read) || File.exist?(doc.to_s)

        raise ArgumentError, "Document not found or unreadable: #{doc}"
      end
    end

    def extract_and_store_entities(document, metadata)
      # Extract entities and relationships
      result = @extractor.process_document(document)

      # Save to fixtures for debugging/observability
      source = document.respond_to?(:path) ? document.path : document.to_s
      fixture_path = @fixture_service.save_extraction(
        result,
        source: source,
        metadata: metadata
      )

      @logger.info("Extracted #{result[:entities]&.size || 0} entities and " +
                 "#{result[:relationships]&.size || 0} relationships. " +
                 "Saved to #{fixture_path}")

      # TODO: Store in Neo4j (next step)
      # load_fixture_and_import(fixture_path, metadata) if @neo4j

      result
    end

    # def load_fixture_and_import(fixture_path, metadata)
    #   # Will be implemented to load from fixture and import to Neo4j
    #   # This allows us to replay extractions if needed
    # end

    # def store_in_neo4j(entities, relationships, metadata)
    #   # Implementation will go here
    # end
  end
end
