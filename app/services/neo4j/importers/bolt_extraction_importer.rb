# frozen_string_literal: true

module Neo4j
  module Importers
    # Importer for extraction data using the Neo4j Bolt protocol
    class BoltExtractionImporter < BaseImporter
      # Import extraction data using the Bolt protocol
      # @param data [Hash] The extraction data to import
      # @param options [Hash] Additional options for the import
      # @option options [Boolean] :clear_database Whether to clear the database before import (default: false)
      # @option options [Logger] :logger Logger instance (default: Rails.logger)
      # @option options [Object] :neo4j_service The Neo4j service instance to use
      # @return [Hash] Import statistics
      def import(data, options = {})
        @logger = options[:logger] || Rails.logger
        @neo4j = options[:neo4j_service]
        @clear_database = options[:clear_database] || false
        @import_results = {
          nodes: 0,
          relationships: 0,
          errors: [],
          start_time: Time.current
        }

        begin
          # Clear database if requested
          clear_database if @clear_database

          # Process the extraction data
          process_extraction(data)

          @import_results[:success] = true
        rescue StandardError => e
          @logger.error("Import failed: #{e.message}")
          @logger.error(e.backtrace.join("\n"))
          @import_results[:success] = false
          @import_results[:error] = e.message
        ensure
          @import_results[:end_time] = Time.current
          @import_results[:duration] = @import_results[:end_time] - @import_results[:start_time]
        end

        @import_results
      end

      # Import with transaction support
      # @param tx [Neo4j::Core::Transaction] The Neo4j transaction
      # @param data [Hash] The extraction data to import
      # @param options [Hash] Additional options for the import
      # @return [Hash] Import statistics
      def import_with_tx(tx, data, options = {})
        # Store the transaction for use in the import methods
        @tx = tx
        import(data, options)
      end

      private

      # Clear the Neo4j database
      def clear_database
        @logger.info("Clearing Neo4j database...")
        query = "MATCH (n) DETACH DELETE n"

        if @tx
          @tx.run(query)
        else
          Neo4j::ActiveBase.current_session.query(query)
        end

        @logger.info("Database cleared successfully")
      end

      # Process the extraction data
      # @param data [Hash] The extraction data
      def process_extraction(data)
        # Handle nested extraction_result if present
        extraction_data = data[:extraction_result] || data

        # Process entities (nodes)
        entities = extraction_data[:entities] || extraction_data["entities"] || []
        if entities.any?
          @logger.info("Importing #{entities.size} entities...")
          entities.each do |entity|
            process_entity(entity)
          end
        else
          @logger.warn("No entities found in extraction data")
        end

        # Process relationships
        relationships = extraction_data[:relationships] || extraction_data["relationships"] || []
        if relationships.any?
          @logger.info("Importing #{relationships.size} relationships...")
          relationships.each do |relationship|
            process_relationship(relationship)
          end
        else
          @logger.warn("No relationships found in extraction data")
        end
      end

      # Process an entity (node)
      # @param entity [Hash] The entity data
      def process_entity(entity)
        # Convert string keys to symbols for consistency
        entity = entity.transform_keys(&:to_sym) if entity.is_a?(Hash) && entity.keys.any? { |k| k.is_a?(String) }

        type = (entity[:type] || "Entity").to_s

        # Generate a unique ID if not provided
        id = entity[:id] || entity[:name] || SecureRandom.uuid

        # Get properties
        properties = entity[:properties] || {}
        properties[:name] ||= entity[:name] if entity[:name]

        # Handle metadata
        metadata = entity[:metadata] || {}
        metadata[:confidence] = entity[:confidence] if entity.key?(:confidence)

        # Create or update the node
        node_id = create_or_update_node(type, id, properties, metadata)

        if node_id
          @import_results[:nodes] += 1
          @logger.debug("Created/updated #{type} node with ID: #{node_id}")
        else
          @import_results[:errors] << { type: "node", entity: entity, error: "Failed to create/update node" }
        end
      rescue StandardError => e
        @logger.error("Error processing entity: #{e.message}")
        @import_results[:errors] << { type: "node", entity: entity, error: e.message }
      end

      # Process a relationship
      # @param relationship [Hash] The relationship data
      def process_relationship(relationship)
        # Convert string keys to symbols for consistency
        relationship = relationship.transform_keys(&:to_sym) if relationship.is_a?(Hash) && relationship.keys.any? { |k| k.is_a?(String) }

        type = (relationship[:type] || "RELATED_TO").to_s

        # Get source and target IDs
        source_id = relationship[:source_id] || relationship[:source]
        target_id = relationship[:target_id] || relationship[:target]

        unless source_id && target_id
          @logger.warn("Skipping relationship missing source or target: #{relationship.inspect}")
          @import_results[:errors] << {
            type: "relationship",
            relationship: relationship,
            error: "Missing source_id/source or target_id/target"
          }
          return
        end

        # Get properties
        properties = relationship[:properties] || {}

        # Handle metadata
        metadata = relationship[:metadata] || {}
        metadata[:confidence] = relationship[:confidence] if relationship.key?(:confidence)

        # Create the relationship
        rel_id = create_relationship(source_id, type, target_id, properties, metadata)

        if rel_id
          @import_results[:relationships] += 1
          @logger.debug("Created #{type} relationship from #{source_id} to #{target_id}")
        else
          @import_results[:errors] << {
            type: "relationship",
            relationship: relationship,
            error: "Failed to create relationship"
          }
        end
      rescue StandardError => e
        @logger.error("Error processing relationship: #{e.message}")
        @import_results[:errors] << { type: "relationship", relationship: relationship, error: e.message }
      end

      # Create or update a node
      # @param label [String] The node label
      # @param id [String] The node ID
      # @param properties [Hash] The node properties
      # @param metadata [Hash] Additional metadata
      # @return [Integer, nil] The node ID if successful, nil otherwise
      def create_or_update_node(label, id, properties, metadata = {})
        # Prepare properties
        node_properties = properties.dup
        node_properties[:id] = id
        node_properties[:metadata] = metadata if metadata.present?

        # Convert properties to string values for Neo4j
        prepared_props = prepare_properties(node_properties)

        query = <<~CYPHER
          MERGE (n:#{label} {id: $id})
          ON CREATE SET n = $props
          ON MATCH SET n += $props
          RETURN id(n) as id
        CYPHER

        result = run_query(query, id: id, props: prepared_props)

        result&.first&.[]("id")
      end

      # Create a relationship between two nodes
      # @param from_id [String] The source node ID
      # @param type [String] The relationship type
      # @param to_id [String] The target node ID
      # @param properties [Hash] The relationship properties
      # @param metadata [Hash] Additional metadata
      # @return [Integer, nil] The relationship ID if successful, nil otherwise
      def create_relationship(from_id, type, to_id, properties = {}, metadata = {})
        # Prepare properties
        rel_properties = properties.dup
        rel_properties[:metadata] = metadata if metadata.present?

        # Convert properties to string values for Neo4j
        prepared_props = prepare_properties(rel_properties)

        query = <<~CYPHER
          MATCH (source), (target)
          WHERE (source.id = $from_id OR source.name = $from_id)
            AND (target.id = $to_id OR target.name = $to_id)
          MERGE (source)-[r:#{type}]->(target)
          ON CREATE SET r = $props
          ON MATCH SET r += $props
          RETURN id(r) as id
        CYPHER

        result = run_query(query, {
                             from_id: from_id,
                             to_id: to_id,
                             props: prepared_props
                           })

        result&.first&.[]("id")
      end

      # Prepare properties for Neo4j by converting complex objects to JSON
      # @param properties [Hash] The properties to prepare
      # @return [Hash] The prepared properties
      def prepare_properties(properties)
        properties.transform_values do |value|
          case value
          when Hash, Array
            value.to_json
          when Date, Time, DateTime
            value.iso8601
          else
            value
          end
        end
      end

      # Run a query with the current session or transaction
      # @param query [String] The Cypher query
      # @param params [Hash] The query parameters
      # @return [Neo4j::Core::Result, nil] The query result or nil if there was an error
      def run_query(query, params = {})
        @logger.debug("Executing query: #{query.tr('\n', ' ').squish}")
        @logger.debug("With params: #{params.inspect}") if params.any?

        result =
          if @tx
            @tx.run(query, params)
          elsif @neo4j.respond_to?(:query)
            @neo4j.query(query, params)
          else
            @neo4j.session do |session|
              session.run(query, params)
            end
          end

        @logger.debug("Query executed successfully")
        result
      rescue StandardError => e
        @logger.error("Query failed: #{e.class} - #{e.message}")
        @logger.error("Query: #{query}")
        @logger.error("Params: #{params.inspect}") if params.any?
        @logger.error("Backtrace: #{e.backtrace.take(5).join("\n")}")
        raise e
      end
    end
  end
end
