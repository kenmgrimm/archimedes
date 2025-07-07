# frozen_string_literal: true

require_relative "base_importer"

module Neo4j
  module Import
    # Handles importing nodes into Neo4j with deduplication
    class NodeImporter < BaseImporter
      # Imports a collection of nodes
      # @param nodes [Array<Hash>] Array of node data hashes
      # @return [Hash] Import statistics
      def import(nodes)
        stats = { total: nodes.size, created: 0, updated: 0, skipped: 0, errors: 0 }

        log_info("Starting import of #{nodes.size} nodes...")

        nodes.each_with_index do |node_data, index|
          log_info("\n[#{index + 1}/#{nodes.size}] Processing node:")
          log_info("  Type: #{node_data[:type] || node_data['type']}")
          log_info("  Name: #{node_data[:name] || node_data['name']}")
          log_info("  Properties: #{node_data[:properties] || node_data['properties']}")

          begin
            import_node(node_data, stats)
            log_info("  Status: #{stats[:created] > 0 ? 'Created' : 'Updated'}")
          rescue StandardError => e
            log_error("  Failed to import node: #{e.message}")
            log_error(e.backtrace.join("\n")) if @debug
            stats[:errors] += 1
          end
        end

        log_info("\nImport completed: #{stats[:created]} created, #{stats[:updated]} updated, #{stats[:errors]} errors")
        stats
      end

      private

      def import_node(node_data, stats)
        type = node_data[:type] || node_data["type"]

        # Extract properties, ensuring all keys are strings
        properties = (node_data[:properties] || node_data["properties"] || {}).transform_keys(&:to_s)

        # Ensure name is set from the node data if not already in properties
        node_name = properties["name"] || node_data[:name] || node_data["name"]
        properties["name"] ||= node_name if node_name

        log_info("Importing #{type} node: #{properties['name'] || properties['id']}")
        log_debug("Node properties: #{properties.inspect}")

        with_transaction do |tx|
          if (existing = find_existing_node(tx, type, properties))
            update_node(tx, existing, properties, stats)
          else
            create_node(tx, type, properties, stats)
          end
        end
      end

      def find_existing_node(tx, type, properties)
        # First try to find by ID if present
        if (node_id = properties["id"] || properties[:id])
          log_info("  + Trying to find by ID: #{node_id}")
          query = "MATCH (n:#{type} {id: $id}) RETURN n LIMIT 1"
          log_info("  + Executing query: #{query} with id: #{node_id.inspect}")

          # Use keyword arguments for parameters
          result = tx.run(query, id: node_id)

          if result.any?
            node = result.single&.first
            log_info("  + Found existing node by ID: #{node&.id}")
            return node
          end
        end

        # Try to find by name if present
        if (node_name = properties["name"] || properties[:name])
          # Ensure we have a string name
          node_name = node_name.to_s.strip
          unless node_name.empty?
            log_info("  + Trying to find by name: #{node_name}")
            query = ""
            query += "MATCH (n:#{type}) "
            query += "WHERE n.name = $name "
            query += "RETURN n, id(n) as id LIMIT 1"

            log_info("  + Executing query: #{query} with name: #{node_name.inspect}")

            # Use keyword arguments for parameters
            result = tx.run(query, name: node_name)

            if result.any?
              record = result.first
              if record && record["id"]
                node = record["n"]
                log_info("  + Found existing node by name: #{record['id']} (Labels: #{node.labels.inspect})")
                return node
              end
            end
          end
        end

        # Try to find by matching all properties if no ID or name match
        log_info("  + Trying to find by all properties: #{properties.inspect}")

        # Format properties for query
        props = {}
        where_parts = []

        properties.each_with_index do |(k, v), index|
          next if v.nil? || v.to_s.empty? || k.to_s == "id" # Skip empty values and id

          param = "p#{index}"
          where_parts << "n.#{k} = $#{param}"
          props[param.to_sym] = v # Use symbol keys for parameters
        end

        if where_parts.any?
          where_clause = where_parts.join(" AND ")
          query = "MATCH (n:#{type}) WHERE #{where_clause} RETURN n LIMIT 1"
          log_info("  + Executing query: #{query} with params: #{props.inspect}")

          # Convert props to keyword arguments
          result = tx.run(query, **props)

          if result.any?
            node = result.single&.first
            log_info("  + Found existing node by properties: #{node&.id}")
            return node
          end
        end

        log_info("  + No existing node found matching criteria")
        nil
      end

      def create_node(tx, type, properties, stats)
        # Ensure name is always a string
        name_property = properties["name"] || properties[:name]

        # Convert to string and clean up
        node_name = if name_property.is_a?(Array)
                      # Use the first non-blank name if available
                      name = name_property.find { |n| n.to_s.present? }
                      name.to_s.strip
                    else
                      name_property.to_s.strip
                    end

        # Fall back to a default name if empty
        node_name = "Unnamed #{type.downcase}" if node_name.blank?

        # Ensure name is set in properties
        properties = properties.merge("name" => node_name)

        log_info("  + Creating new #{type} node: #{node_name}")

        if dry_run
          log_info("  - DRY RUN: Would create node with properties: #{properties.inspect}")
          stats[:created] += 1
          return { id: "dry-run-id", labels: [type], properties: properties.merge("name" => node_name) }
        end

        begin
          # Set the processed name in properties
          properties = properties.merge("name" => node_name)

          # Format properties for Neo4j
          formatted_props = format_properties(properties)

          # Build the CREATE query
          query = "CREATE (n:#{type} $props) RETURN n"

          log_info("  + Executing query: #{query}")
          log_info("  + With properties: #{formatted_props.inspect}")

          # Execute the query with keyword arguments
          result = tx.run(query, props: formatted_props)

          # Extract the created node
          record = result.single
          if record.nil? || record["n"].nil?
            log_error("  ! Failed to create node - no record returned")
            log_error("  ! Query: #{query}")
            log_error("  ! Props: #{formatted_props.inspect}")
            return nil
          end

          node = record["n"]

          # Log success
          log_info("  + Successfully created node:")
          log_info("    - ID: #{node.id}")
          log_info("    - Labels: #{node.labels}")
          log_info("    - Properties: #{node.properties}")

          stats[:created] += 1
          node
        rescue StandardError => e
          log_error("  ! Error creating node: #{e.message}")
          log_error("  ! Query: #{query}")
          log_error("  ! Props: #{formatted_props.inspect}")
          log_error("  ! Backtrace: #{e.backtrace.join("\n")}") if @debug
          raise
        end
      end

      def update_node(tx, existing, properties, stats)
        log_info("  ~ Updating existing #{existing.labels.first} node")

        return if dry_run

        # Don't update the ID if it exists
        properties = properties.except("id")

        # Ensure name is a string if present
        if properties.key?("name")
          name = properties["name"]
          if name.is_a?(Array)
            # Use the first non-blank name if available
            name = name.find { |n| n.to_s.present? }&.to_s
            name = "Unnamed #{existing.labels.first.downcase}" if name.blank?
            properties["name"] = name
          end
        end

        return if properties.empty? # Nothing to update after processing

        formatted_props = format_properties(properties)

        # Build SET clause for properties
        set_clause = properties.keys.map { |k| "n.#{k} = $props.#{k}" }.join(", ")
        query = "MATCH (n) WHERE id(n) = $id SET #{set_clause} RETURN n"

        log_info("  + Executing update query: #{query}")
        log_debug("  + With properties: #{formatted_props.inspect}")

        result = tx.run(query, id: existing.id, props: formatted_props)

        if result.any?
          stats[:updated] += 1
          result.single&.first
        else
          log_error("  ! Failed to update node #{existing.id}")
          nil
        end
      end

      def format_properties(properties)
        properties.transform_values { |v| format_property(v) }
      end
    end
  end
end
