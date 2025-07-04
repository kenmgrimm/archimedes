module Neo4j
  class GraphRagService
    # Initialize the GraphRAG service with required dependencies
    # @param openai_service [Object] The OpenAI service for NLP tasks
    # @param neo4j_service [Object] The Neo4j service for graph operations
    # @param logger [Logger] Optional logger (defaults to Rails.logger)
    # @param fixture_service [Object] Optional fixture service for saving extractions
    def initialize(openai_service:, neo4j_service:, logger: nil, fixture_service: nil)
      @builder = KnowledgeGraphBuilder.new(
        openai_service: openai_service,
        neo4j_service: neo4j_service,
        logger: logger,
        fixture_service: fixture_service
      )
      @querier = GraphQueryService.new(
        openai_service: openai_service,
        neo4j_service: neo4j_service,
        logger: logger
      )
      @logger = logger || Rails.logger
    end

    # Delegate document processing to the KnowledgeGraphBuilder
    # @see KnowledgeGraphBuilder#process_documents
    def process_documents(*, **)
      @builder.process_documents(*, **)
    end

    # Delegate query execution to the GraphQueryService
    # @see GraphQueryService#execute_query
    def execute_query(*, **)
      @querier.execute_query(*, **)
    end

    # Delegate query suggestions to the GraphQueryService
    # @see GraphQueryService#suggest_queries
    def suggest_queries(*, **)
      @querier.suggest_queries(*, **)
    end

    # Get health status of all services
    # @return [Hash] Health status information
    def health_check
      {
        builder: @builder.health_check,
        querier: @querier.health_check,
        timestamp: Time.current,
        status: :ok
      }
    rescue StandardError => e
      @logger.error("Health check failed: #{e.message}")
      {
        status: :error,
        error: e.message,
        timestamp: Time.current
      }
    end
  end
end
