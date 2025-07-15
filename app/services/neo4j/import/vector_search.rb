# frozen_string_literal: true

require_relative "node_matcher_registry"

module Neo4j
  module Import
    # Handles vector search functionality for node importing
    class VectorSearch
      def initialize(embedding_service, logger: nil, similarity_threshold: 0.8, debug: false)
        @embedding_service = embedding_service
        @logger = logger
        @similarity_threshold = similarity_threshold
        @debug = debug
      end

      # Add vector embedding to node properties if enabled
      # @param props [Hash] The node properties
      # @param node_type [String, Symbol] The type of node (e.g., 'Address', 'Person')
      # @return [Hash] Updated properties with embedding if applicable
      def add_embedding(props, node_type = nil)
        return props unless @embedding_service

        # Use NodeMatcherRegistry to generate embedding text based on node type
        text = NodeMatcherRegistry.generate_embedding_text(node_type, props)

        if text.present? && !text.strip.empty?
          log_debug("  + Generating embedding for #{node_type} text")
          begin
            embedding = @embedding_service.generate_embedding(text)
            if embedding&.any?
              props["embedding"] = embedding
              log_debug("  + Added embedding (length: #{embedding.length})")
            else
              log_warn("  + Empty embedding returned")
            end
          rescue StandardError => e
            log_error("  + Error generating embedding: #{e.message}")
            log_error(e.backtrace.join("\n")) if @debug
          end
        else
          log_debug("  + No text available for embedding")
        end

        props
      end

      # Find similar nodes using vector search
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type to search for
      # @param embedding [Array<Float>] The embedding vector to search with
      # @param threshold [Float] The similarity threshold (0-1)
      # @return [Array<Hash>] Matching nodes with similarity scores
      def find_similar_nodes(tx, type, embedding, threshold: nil)
        return [] unless @embedding_service && embedding.is_a?(Array)

        threshold ||= @similarity_threshold

        escaped_type = type.include?(" ") ? "`#{type}`" : type
        query = <<~CYPHER
          MATCH (n:#{escaped_type})
          WHERE n.embedding IS NOT NULL
          WITH n, vector.similarity.cosine($embedding, n.embedding) AS similarity
          WHERE similarity >= $threshold
          RETURN n, similarity
          ORDER BY similarity DESC
          LIMIT 5
        CYPHER

        log_debug("  + Searching for similar #{type} nodes with threshold: #{threshold}")

        results = tx.run(query, embedding: embedding, threshold: threshold).map do |record|
          {
            node: record[:n],
            similarity: record[:similarity]
          }
        end

        log_debug("  + Found #{results.size} similar nodes")
        results.each_with_index do |result, i|
          log_debug("    #{i + 1}. Node #{result[:node].id} (similarity: #{result[:similarity].round(4)})")
        end

        results
      rescue StandardError => e
        log_error("Error in vector search: #{e.message}")
        log_error(e.backtrace.join("\n")) if @debug
        []
      end

      private

      def log_debug(message)
        @logger&.debug(message)
      end

      def log_warn(message)
        @logger&.warn(message)
      end

      def log_error(message)
        @logger&.error(message)
      end
    end
  end
end
