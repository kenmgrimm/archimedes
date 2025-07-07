# frozen_string_literal: true

require_relative "base_importer"

module Neo4j
  module Import
    # Handles importing relationships into Neo4j
    class RelationshipImporter < BaseImporter
      # Imports a collection of relationships
      # @param relationships [Array<Hash>] Array of relationship data hashes
      # @param node_mapping [Hash] Mapping of node IDs to Neo4j internal IDs
      # @return [Hash] Import statistics
      def import(relationships, node_mapping = {})
        stats = { total: relationships.size, created: 0, skipped: 0, errors: 0 }

        relationships.each do |rel_data|
          import_relationship(rel_data, node_mapping, stats)
        rescue StandardError => e
          log_error("Failed to import relationship: #{rel_data.inspect}", e)
          stats[:errors] += 1
        end

        stats
      end

      # Safely extract and format a node name
      # @param name [String, Array, Object] The name to format
      # @return [String] The formatted name as a string
      def format_node_name(name)
        return nil if name.nil?

        # Handle arrays by taking the first non-blank element
        if name.is_a?(Array)
          name = name.find { |n| n.to_s.strip.present? }
          return nil if name.nil?
        end

        # Convert to string and clean up
        name = name.to_s.strip
        name.empty? ? nil : name
      end

      private

      def import_relationship(rel_data, _node_mapping, stats)
        log_info("  + [DEBUG] Starting import_relationship with rel_data: #{rel_data.inspect}")

        # Handle both symbol and string keys for flexibility
        rel_data = rel_data.transform_keys(&:to_sym) if rel_data.is_a?(Hash)

        # Extract and format node names
        from_name = format_node_name(rel_data[:source] || rel_data[:from] || rel_data[:from_id])
        to_name = format_node_name(rel_data[:target] || rel_data[:to] || rel_data[:to_id])
        rel_type = (rel_data[:type] || "RELATED").to_s.upcase

        # Handle properties with proper key handling
        properties = rel_data[:properties] || {}

        # Ensure we have valid names
        unless from_name && to_name
          log_error("  ! Invalid relationship data - missing or invalid source/target names: #{rel_data.inspect}")
          log_error("  ! from_name: #{from_name.inspect}, to_name: #{to_name.inspect}")
          stats[:skipped] += 1
          return
        end

        log_info("  + Processing relationship: #{from_name.inspect} -[#{rel_type}]-> #{to_name.inspect}")
        log_info("  + [DEBUG] from_name class: #{from_name.class.name}, to_name class: #{to_name.class.name}")

        # Find or create nodes with proper error handling
        log_info("  + [DEBUG] Looking up from_node: #{from_name.inspect}")
        from_node_id = find_node_by_name(from_name, type: rel_data[:source_type])
        log_info("  + [DEBUG] from_node_id: #{from_node_id.inspect}")

        unless from_node_id
          log_error("  ! Could not find source node: #{from_name.inspect}")
          stats[:skipped] += 1
          return
        end

        log_info("  + [DEBUG] Looking up to_node: #{to_name.inspect}")
        to_node_id = find_node_by_name(to_name, type: rel_data[:target_type])
        log_info("  + [DEBUG] to_node_id: #{to_node_id.inspect}")

        unless to_node_id
          log_error("  ! Could not find target node: #{to_name.inspect}")
          stats[:skipped] += 1
          return
        end

        # At this point we have both node IDs, proceed with relationship creation
        Neo4j::DatabaseService.write_transaction do |tx|
          if relationship_exists?(tx, from_node_id, to_node_id, rel_type)
            log_info("  ~ Relationship already exists: #{from_name} -[#{rel_type}]-> #{to_name}")
            stats[:skipped] += 1
          else
            create_relationship(tx, from_node_id, to_node_id, rel_type, properties, stats)
          end
        end
      rescue StandardError => e
        log_error("  ! Error processing relationship: #{e.message}")
        log_error("  ! Backtrace: #{e.backtrace.join("\n    ")}")
        stats[:errors] += 1
      end

      def relationship_exists?(tx, from_id, to_id, type)
        query = <<~CYPHER
          MATCH (a)-[r:#{type}]->(b)
          WHERE id(a) = $from_id AND id(b) = $to_id
          RETURN r
          LIMIT 1
        CYPHER

        result = tx.run(query, from_id: from_id, to_id: to_id)
        result.any?
      end

      def create_relationship(tx, from_id, to_id, type, properties, stats)
        log_info("  + Creating new #{type} relationship")

        return if dry_run

        begin
          # Format properties for Neo4j
          formatted_props = format_properties(properties || {})

          query = <<~CYPHER
            MATCH (a), (b)
            WHERE id(a) = $from_id AND id(b) = $to_id
            CREATE (a)-[r:#{type} $props]->(b)
            RETURN r
          CYPHER

          log_info("  + Executing query: #{query.gsub(/\s+/, ' ').strip}")
          log_info("  + With params: {from_id: #{from_id}, to_id: #{to_id}, props: #{formatted_props.inspect}}")

          # Convert parameters to a flat hash with string keys
          params = {
            "from_id" => from_id,
            "to_id" => to_id,
            "props" => formatted_props
          }

          log_info("  + Executing query: #{query.gsub(/\s+/, ' ').strip}")
          log_info("  + With params: #{params.inspect}")

          # Pass parameters as keyword arguments
          result = tx.run(query, **params)

          if result.any?
            log_info("  + Successfully created relationship")
            stats[:created] += 1
          else
            log_error("  ! Failed to create relationship - no result returned")
            stats[:errors] += 1
          end
        rescue StandardError => e
          log_error("  ! Failed to create relationship: #{e.message}")
          stats[:errors] += 1
        end
      end

      def format_properties(properties)
        properties.transform_values { |v| format_property(v) }
      end

      # Find a node by its name and optional type
      # @param name [String, Array] The name of the node to find (can be an array of names)
      # @param type [String, nil] Optional node type to filter by
      # @return [Integer, nil] The internal Neo4j node ID or nil if not found
      def find_node_by_name(name, type: nil)
        # Format the node name using our helper method
        formatted_name = format_node_name(name)

        log_info("  + [DEBUG] find_node_by_name called with: #{name.inspect} (formatted: #{formatted_name.inspect})")

        # Return nil if we don't have a valid name after formatting
        return nil if formatted_name.nil?

        # Use the transaction's return value as our result
        Neo4j::DatabaseService.read_transaction do |tx|
          # First try: Exact match on name
          query = ""
          query += "MATCH (n#{':' + type if type}) "
          query += "WHERE n.name = $name "
          query += "RETURN id(n) as id, labels(n) as labels, properties(n) as props "
          query += "LIMIT 1"

          log_info("  + Looking up #{type || 'any'} node by name: #{formatted_name.inspect}")
          log_debug("  + Executing query: #{query} with name=#{formatted_name.inspect}")

          result = tx.run(query, name: formatted_name, type: type)
          entity = result.first
          if entity && entity["id"]
            log_info("  + Found node by name match: #{entity['id']} (Labels: #{entity['labels'].inspect})")
            next entity["id"]
          end

          # Second try: Look for nodes where any property contains the name (case-insensitive)
          type_filter = type ? ":#{type}" : ""
          query = "MATCH (n#{type_filter}) "
          query += "WHERE any(prop in keys(n) WHERE toLower(toString(n[prop])) CONTAINS toLower(toString($name))) "
          query += "RETURN id(n) as id, labels(n) as labels, properties(n) as props "
          query += "ORDER BY size(keys(n)) LIMIT 1"

          log_info("  + Trying to find node with name in any string property: #{name.inspect}")
          log_debug("  + Executing query: #{query} with name=#{name.inspect}")

          result = tx.run(query, name: name, type: type)
          entity = result.first

          if entity && entity["id"]
            log_info("  + Found node with matching property: #{entity['id']} (Labels: #{entity['labels'].inspect})")
            next entity["id"]
          end

          # Third try: Directly query all nodes and filter in Ruby (slower but more flexible)
          log_info("  + Falling back to Ruby-side filtering for node: #{name.inspect}")
          query = "MATCH (n#{type_filter}) RETURN id(n) as id, labels(n) as labels, properties(n) as props"
          log_debug("  + Executing query: #{query}")

          result = tx.run(query, type: type)
          name_lower = name.to_s.downcase
          found_id = nil

          result.each do |entity|
            next unless entity && entity["id"]

            # Check if any string property contains the name (case-insensitive)
            entity["props"].each do |_, value|
              next unless value.to_s.downcase.include?(name_lower)

              log_info("  + Found matching node by property: #{entity['id']} (Labels: #{entity['labels'].inspect})")
              found_id = entity["id"]
              break
            end

            # If we found a match, break out of the loop
            break if found_id
          end

          # Return the found ID or nil
          found_id
        end
      rescue StandardError => e
        log_error("Error finding node by name: #{name.inspect}", e)
        nil
      end
    end
  end
end
