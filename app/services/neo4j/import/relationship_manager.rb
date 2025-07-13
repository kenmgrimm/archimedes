# frozen_string_literal: true

module Neo4j
  module Import
    # Handles creating and managing relationships between nodes
    class RelationshipManager
      def initialize(logger: nil, dry_run: false, debug: false)
        @logger = logger
        @dry_run = dry_run
        @debug = debug
      end

      # Create a relationship between two nodes
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param from_node [Neo4j::Node] The source node
      # @param to_node [Neo4j::Node] The target node
      # @param rel_type [Symbol] The relationship type
      # @param properties [Hash] Relationship properties
      # @param stats [Hash] Statistics hash to update
      # @return [Neo4j::Relationship, nil] The created relationship or nil if failed
      def create_relationship(tx, from_node, to_node, rel_type, properties = {}, stats = {})
        return if @dry_run

        begin
          query = <<~CYPHER
            MATCH (from), (to)
            WHERE id(from) = $from_id AND id(to) = $to_id
            MERGE (from)-[r:#{rel_type}]->(to)
            SET r += $props
            RETURN r
          CYPHER

          result = tx.run(query, {
                            from_id: from_node.id,
                            to_id: to_node.id,
                            props: properties
                          })

          relationship = result&.first&.[](:r)
          stats[:relationships_created] += 1 if relationship
          relationship
        rescue StandardError => e
          log_error("Error creating relationship: #{e.message}")
          log_error(e.backtrace.join("\n")) if @debug
          stats[:errors] += 1
          nil
        end
      end

      # Find existing relationships between nodes
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param from_node [Neo4j::Node] The source node
      # @param to_node [Neo4j::Node] The target node
      # @param rel_type [Symbol] The relationship type to look for
      # @return [Array<Neo4j::Relationship>] Array of matching relationships
      def find_relationships(tx, from_node, to_node, rel_type = nil)
        rel_type_clause = ":#{rel_type}" if rel_type

        query = <<~CYPHER
          MATCH (from)-[r#{rel_type_clause}]->(to)
          WHERE id(from) = $from_id AND id(to) = $to_id
          RETURN r
        CYPHER

        tx.run(query, {
                 from_id: from_node.id,
                 to_id: to_node.id
               }).map { |record| record[:r] }
      rescue StandardError => e
        log_error("Error finding relationships: #{e.message}")
        log_error(e.backtrace.join("\n")) if @debug
        []
      end

      private

      def log_error(message)
        @logger&.error(message)
      end
    end
  end
end
