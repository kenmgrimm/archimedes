# frozen_string_literal: true

# Neo4jSeeder class for handling Neo4j data seeding
class Neo4jSeeder
  class << self
    # Creates or updates a node in Neo4j
    # @param session [Neo4j::Driver::Session] the Neo4j session
    # @param node_data [Hash] the node data from YAML
    # @param index [Integer] the index of the node in the seed file
    def create_node(session, node_data, index = nil)
      labels = Array(node_data["labels"])
      properties = convert_properties(node_data["properties"] || {})

      # Ensure we use the exact ID from the YAML file
      node_id = node_data["id"].to_s

      # Add labels to the query
      label_str = labels.any? ? ":#{labels.join(':')}" : ""

      # Build the properties part of the query
      set_statements = properties.keys.map { |k| "n.#{k} = $#{k}" }.join(", ")

      # Create a single-line query to avoid newline issues
      query = <<~CYPHER.squish
        MERGE (n#{label_str} {id: $node_id})#{' '}
        ON CREATE SET n.id = $node_id, #{set_statements}#{' '}
        ON MATCH SET n.id = $node_id, #{set_statements}#{' '}
        RETURN n
      CYPHER

      # Prepare parameters with the ID included
      params = properties.merge(node_id: node_id)

      begin
        session.write_transaction do |tx|
          result = tx.run(query, **params)
          record = result.first
          if record
            node = record["n"]
            node_type = labels.last || "Node"
            display_name = node.properties["name"] || node.properties["title"] || node.properties["id"]
            Rails.logger.debug { "    ✓ #{node_type} #{index}: #{display_name} (ID: #{node_id}, Labels: #{labels.join(', ')})" }
            # Debug: Show all properties for this node
            Rails.logger.debug { "      Properties: #{node.properties.inspect}" } if ENV["DEBUG"]
            true
          else
            Rails.logger.debug { "    ⚠️ Failed to create/update node: #{node_id} (Labels: #{labels.join(', ')})" }
            false
          end
        end
      rescue StandardError => e
        Rails.logger.debug { "    ❌ Error creating/updating node: #{e.message}" }
        Rails.logger.debug { "      Query: #{query}" }
        Rails.logger.debug { "      Params: #{params.inspect}" }
        Rails.logger.debug e.backtrace.join("\n") if ENV["DEBUG"]
        false
      end
    end

    # Creates relationships between nodes
    # @param session [Neo4j::Driver::Session] the Neo4j session
    # @param rel_data [Hash] the relationship data from YAML
    def create_relationships(session, rel_data)
      rel_type = rel_data["type"]
      from_id = rel_data["from"].to_s
      to_ids = Array(rel_data["to"]).map(&:to_s)
      properties = convert_properties(rel_data["properties"] || {})

      # Convert properties to a string for display
      props_str = properties.any? ? " #{properties.inspect}" : ""

      Rails.logger.debug { "  - Relationship: #{rel_type} from #{from_id} to #{to_ids.join(', ')}" }
      Rails.logger.debug { "      Properties: #{properties.inspect}" } if properties.any?

      to_ids.each do |to_id|
        # Debug: Check if nodes exist with a simple query
        debug_query = <<~CYPHER.squish
          MATCH (a {id: $from_id})#{' '}
          RETURN a.id as id, labels(a) as labels, 'from' as node_type
          UNION
          MATCH (b {id: $to_id})#{' '}
          RETURN b.id as id, labels(b) as labels, 'to' as node_type
        CYPHER

        debug_result = session.read_transaction do |tx|
          tx.run(debug_query, from_id: from_id, to_id: to_id).map(&:to_h)
        end

        if ENV["DEBUG"]
          Rails.logger.debug "      Debug - Found nodes:"
          debug_result.each do |row|
            node_type = row["node_type"] || "unknown"
            node_id = row["id"]
            labels = row["labels"].is_a?(Array) ? row["labels"].join(",") : "none"
            Rails.logger.debug { "        - #{node_type.to_s.upcase} Node: id=#{node_id}, labels=[#{labels}]" }
          end
        end

        # Check if both nodes exist in a single transaction
        session.write_transaction do |tx|
          # First check if both nodes exist with a more specific query
          check_query = <<~CYPHER.squish
            MATCH (a {id: $from_id}), (b {id: $to_id})
            RETURN#{' '}
              a.id as from_id,#{' '}
              labels(a) as from_labels,#{' '}
              b.id as to_id,#{' '}
              labels(b) as to_labels,
              a IS NOT NULL as from_exists,#{' '}
              b IS NOT NULL as to_exists
          CYPHER

          check_result = tx.run(check_query, from_id: from_id, to_id: to_id).first

          unless check_result
            Rails.logger.debug do
              "    Could not find nodes for relationship: (#{from_id})-[#{rel_type}]->(#{to_id}) - Query returned no results"
            end
            next
          end

          from_exists = check_result["from_exists"]
          to_exists = check_result["to_exists"]

          unless from_exists && to_exists
            missing = []
            missing << "source node (#{from_id})" unless from_exists
            missing << "target node (#{to_id})" unless to_exists

            # Get more details about what was found
            details = []
            if check_result["from_id"]
              details << "Source ID: #{check_result['from_id']} (Labels: #{check_result['from_labels']&.join(', ')})"
            end
            details << "Target ID: #{check_result['to_id']} (Labels: #{check_result['to_labels']&.join(', ')})" if check_result["to_id"]

            Rails.logger.debug { "    Skipping relationship: (#{from_id})-[#{rel_type}]->(#{to_id})" }
            Rails.logger.debug { "      Missing: #{missing.join(' and ')}" }
            Rails.logger.debug { "      Details: #{details.join(' | ')}" } if details.any?
            next
          end

          # If we get here, both nodes exist - create the relationship
          set_clause = properties.any? ? "SET r += $properties" : ""

          query = <<~CYPHER.squish
            MATCH (a {id: $from_id}), (b {id: $to_id})
            MERGE (a)-[r:#{rel_type}]->(b)
            #{set_clause}
            RETURN r, a.id as from_id, b.id as to_id
          CYPHER

          # Run the relationship creation in the same transaction
          result = tx.run(query, from_id: from_id, to_id: to_id, properties: properties)
          result_record = result.first

          if result_record
            Rails.logger.debug do
              "    Created relationship: (#{result_record['from_id']})-[#{rel_type}#{props_str}]->(#{result_record['to_id']})"
            end
          else
            Rails.logger.debug { "    Failed to create relationship: (#{from_id})-[#{rel_type}]->(#{to_id}) - No result returned" }
          end
        end
      rescue StandardError => e
        Rails.logger.debug { "    Error creating relationship (#{from_id})-[#{rel_type}]->(#{to_id}): #{e.message}" }
        Rails.logger.debug { "      Query: #{query}" } if defined?(query)
        Rails.logger.debug e.backtrace.join("\n") if ENV["DEBUG"]
      end
    end

    # Converts Ruby objects to Neo4j-compatible types
    # @param properties [Hash] the properties to convert
    # @return [Hash] the converted properties
    def convert_properties(properties)
      return {} if properties.nil?

      properties.transform_values do |value|
        case value
        when Time, DateTime
          value.iso8601
        when Date
          value.to_s
        when Hash, Array
          value.to_json
        else
          value
        end
      end
    end
  end
end
