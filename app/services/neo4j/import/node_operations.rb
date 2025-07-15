# frozen_string_literal: true

module Neo4j
  module Import
    # Handles core node operations
    class NodeOperations
      def initialize(logger: nil, dry_run: false, debug: false, property_formatter: nil, vector_search: nil)
        @logger = logger
        @dry_run = dry_run
        @debug = debug
        @property_formatter = property_formatter
        @vector_search = vector_search
      end

      # Create a new node in the graph
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type/label
      # @param properties [Hash] The node properties
      # @param stats [Hash] Statistics hash to update
      # @return [Neo4j::Node, nil] The created node or nil if creation failed
      def create_node(tx, type, properties, stats)
        log_info("\n=== create_node ===")
        log_info("  + Type: #{type}")

        if @dry_run
          log_info("  + DRY RUN: Would create node: #{type} with properties: #{properties.inspect}")
          stats[:skipped] += 1
          return nil
        end

        begin
          props = @property_formatter.format_properties(properties.dup, is_top_level: false, logger: @logger)

          # Add vector embedding if enabled
          if @vector_search
            @vector_search.add_embedding(props, type)
            # Reformat after adding embedding
            props = @property_formatter.format_properties(props, is_top_level: false, logger: @logger)
          end

          # Create the node
          execute_create_node(tx, type, props, stats)
        rescue StandardError => e
          log_error("  + ERROR in create_node: #{e.class}: #{e.message}")
          log_error("  + Backtrace:\n#{e.backtrace.join("\n")}")
          stats[:errors] += 1
          nil
        end
      end

      # Update an existing node
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param node [Neo4j::Node] The node to update
      # @param properties [Hash] The properties to update
      # @param stats [Hash] Statistics hash to update
      # @return [Neo4j::Node, nil] The updated node or nil if update failed
      def update_node(tx, node, properties, stats)
        return if @dry_run

        begin
          log_debug("  + update_node called with: tx=#{tx.class}, node=#{node.class}, properties=#{properties.inspect}, stats=#{stats.inspect}")
          props = @property_formatter.format_properties(properties.dup, is_top_level: false, logger: @logger)

          query = <<~CYPHER
            MATCH (n) WHERE id(n) = $id
            SET n += $props
            RETURN n
          CYPHER

          result = tx.run(query, id: node.id, props: props)
          updated_node = result&.first&.[](:n)

          if updated_node
            stats[:updated] += 1
            log_info("  + Updated node: #{node.id}")
          else
            stats[:errors] += 1
            log_error("  + Failed to update node: #{node.id}")
          end

          updated_node
        rescue StandardError => e
          log_error("  + ERROR updating node: #{e.message}")
          log_error("  + ERROR class: #{e.class}")
          log_error(e.backtrace.join("\n")) if @debug
          stats[:errors] += 1
          nil
        end
      end

      private

      def execute_create_node(tx, type, properties, stats)
        # Escape type names that contain spaces or special characters
        escaped_type = type.include?(" ") ? "`#{type}`" : type
        query = "CREATE (n:#{escaped_type} $props) RETURN n"
        log_info("  + Executing: #{query}")
        Rails.logger.debug { "  + Properties being stored: #{properties.inspect}" } if @debug

        result = tx.run(query, props: properties)

        # Get the first result record
        unless (record = result.first)
          log_error("  + ERROR: No record returned from query")
          stats[:errors] += 1
          return nil
        end

        # Get the node from the record
        unless (node = record[:n] || record["n"] || record["n()"])
          log_error("  + ERROR: Could not extract node from record")
          log_error("  + Record keys: #{record.keys.inspect}")
          stats[:errors] += 1
          return nil
        end

        log_info("  + Created node: #{node.respond_to?(:id) ? node.id : 'N/A'}")
        stats[:created] += 1
        node
      rescue StandardError => e
        log_error("  + ERROR executing query: #{e.class}: #{e.message}")
        log_error("  + Query: #{query}")
        log_error(e.backtrace.join("\n")) if @debug

        # Test connection with a simple query
        begin
          log_info("  + Testing connection with a simple query...")
          test_result = tx.run("RETURN 1 as test")
          log_info("  + Test query result: #{test_result.first.inspect}")
        rescue StandardError => test_error
          log_error("  + Connection test failed: #{test_error.message}")
        end

        stats[:errors] += 1
        nil
      end

      def log_info(message)
        @logger&.info(message)
      end

      def log_debug(message)
        @logger&.debug(message)
      end

      def log_error(message)
        @logger&.error(message)
      end
    end
  end
end
