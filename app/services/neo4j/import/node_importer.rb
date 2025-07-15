# frozen_string_literal: true

require_relative "base_importer"
require_relative "property_formatter"
require_relative "vector_search"
require_relative "node_matcher_registry"
require_relative "node_operations"
require_relative "relationship_manager"
require_relative "../../openai/embedding_service"
require_relative "../../openai/entity_matching_service"

module Neo4j
  module Import
    # Handles importing nodes into Neo4j with deduplication
    class NodeImporter < BaseImporter
      # @param logger [Logger] Logger instance for progress and errors
      # @param dry_run [Boolean] If true, don't make any changes to the database
      # @param enable_vector_search [Boolean, nil] Override for enabling vector similarity search
      # @param similarity_threshold [Float, nil] Override for minimum similarity score (0-1)
      # @param enable_human_review [Boolean] If true, queue uncertain matches for human review
      def initialize(logger: nil, dry_run: false, enable_vector_search: nil, similarity_threshold: nil, debug: false,
                     enable_human_review: false)
        super(logger: logger, dry_run: dry_run)
        @debug = debug
        @enable_human_review = enable_human_review

        # Initialize services
        @enable_vector_search = enable_vector_search.nil? ? ENV["VECTOR_SEARCH_ENABLED"] == "true" : enable_vector_search
        @similarity_threshold = similarity_threshold || ENV.fetch("VECTOR_SIMILARITY_THRESHOLD", 0.8).to_f

        @property_formatter = PropertyFormatter.new(debug: @debug)

        if @enable_vector_search
          @embedding_service = OpenAI::EmbeddingService.new
          @entity_matching_service = OpenAI::EntityMatchingService.new
          @vector_search = VectorSearch.new(
            @embedding_service,
            logger: logger,
            similarity_threshold: @similarity_threshold,
            debug: @debug
          )
          log_info("Vector search enabled with similarity threshold: #{@similarity_threshold}")
        else
          log_info("Vector search is disabled")
        end

        # Initialize operation handlers
        @node_operations = NodeOperations.new(
          logger: logger,
          dry_run: dry_run,
          debug: debug,
          property_formatter: @property_formatter,
          vector_search: @vector_search
        )

        @relationship_manager = RelationshipManager.new(
          logger: logger,
          dry_run: dry_run,
          debug: debug
        )

        # Initialize human review manager if enabled
        return unless @enable_human_review

        require_relative "human_review_manager"
        @human_review_manager = HumanReviewManager.new(logger: logger)
        log_info("Human review enabled for uncertain matches")
      end

      # Imports a collection of entities (main interface method)
      # @param entities [Array<Hash>] Array of entity hashes to import
      # @return [Hash] Import statistics
      def import(entities)
        return { total: 0, created: 0, updated: 0, skipped: 0, errors: 0, duplicates: 0 } if entities.empty?

        # Group entities by type for efficient processing
        entities_by_type = entities.group_by { |entity| entity[:type] || entity["type"] }

        # Aggregate stats across all types
        total_stats = { total: 0, created: 0, updated: 0, skipped: 0, errors: 0, duplicates: 0 }

        entities_by_type.each do |type, type_entities|
          log_info("Importing #{type_entities.size} #{type} nodes...")

          # Convert entities to the format expected by import_nodes
          formatted_entities = type_entities.map do |entity|
            # Ensure properties include the name field
            properties = entity[:properties] || entity["properties"] || {}
            properties["name"] = entity[:name] || entity["name"] if entity[:name] || entity["name"]
            properties
          end

          type_stats = import_nodes(formatted_entities, type: type)

          # Aggregate stats
          total_stats.each_key do |key|
            total_stats[key] += type_stats[key] if type_stats[key]
          end

          log_info("Completed #{type} import: #{type_stats[:created]} created, #{type_stats[:updated]} updated, #{type_stats[:skipped]} skipped, #{type_stats[:errors]} errors")
        end

        total_stats
      end

      # Imports a collection of nodes
      # @param nodes [Array<Hash>] Array of node hashes to import
      # @param type [String] The type/label of the nodes
      # @param batch_size [Integer] Number of nodes to process in each batch
      # @return [Hash] Import statistics
      def import_nodes(nodes, type:, batch_size: 100)
        stats = {
          total: nodes.size,
          created: 0,
          updated: 0,
          skipped: 0,
          errors: 0,
          duplicates: 0
        }

        total_batches = (nodes.size / batch_size.to_f).ceil

        nodes.each_slice(batch_size).with_index do |batch, batch_index|
          log_info("\n=== Processing batch #{batch_index + 1} of #{total_batches} ===")

          Neo4j::DatabaseService.write_transaction do |tx|
            batch.each_with_index do |node_data, index|
              log_info("\n[#{(batch_index * batch_size) + index + 1}/#{nodes.size}] Processing node")

              begin
                # Format properties
                properties = @property_formatter.format_properties(node_data, logger: @logger)

                # Find or create node
                existing_node = find_existing_node(tx, type, properties)

                if existing_node
                  if node_needs_update?(existing_node, properties)
                    @node_operations.update_node(tx, existing_node, properties, stats)
                  else
                    log_info("  + Node already exists and is up to date")
                    stats[:skipped] += 1
                  end
                else
                  @node_operations.create_node(tx, type, properties, stats)
                end
              rescue StandardError => e
                log_error("  + ERROR processing node: #{e.message}")
                log_error(e.backtrace.join("\n")) if @debug
                stats[:errors] += 1
                next
              end
            end
          end
        end

        stats
      end

      # Find an existing node that matches the given properties
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type to search for
      # @param properties [Hash] The properties to match against
      # @return [Neo4j::Core::Node, nil] The matching node, or nil if not found
      def find_existing_node(tx, type, properties)
        Rails.logger.debug { "\n🔍 FIND_EXISTING_NODE - Starting search for #{type}" } if @debug
        Rails.logger.debug { "  Properties: #{properties.keys.join(', ')}" } if @debug

        # First try exact matching on unique constraints
        Rails.logger.debug "  Step 1: Trying constraint matching..." if @debug
        existing_node = find_node_by_constraints(tx, type, properties)
        if existing_node
          Rails.logger.debug "  ✅ Found via constraints!" if @debug
          return existing_node
        end
        Rails.logger.debug "  ❌ No constraint matches" if @debug

        # If vector search is enabled, try similarity search
        if @enable_vector_search && properties["embedding"].is_a?(Array)
          Rails.logger.debug "  Step 2: Trying vector search (has embedding)..." if @debug

          # Get type-specific similarity threshold
          threshold = NodeMatcherRegistry.similarity_threshold_for(type)

          similar_nodes = @vector_search.find_similar_nodes(
            tx,
            type,
            properties["embedding"],
            threshold: threshold
          )

          # Return the most similar node if above threshold
          best_match = similar_nodes.first
          if best_match&.dig(:similarity).to_f >= threshold
            Rails.logger.debug { "  ✅ Found via vector search! (similarity: #{best_match[:similarity].round(4)})" } if @debug
            return best_match[:node]
          elsif @debug
            Rails.logger.debug "  ❌ Vector search found no matches above threshold"
          end
        elsif @enable_vector_search
          Rails.logger.debug "  Step 2: Skipping vector search (no embedding)" if @debug
        elsif @debug
          Rails.logger.debug "  Step 2: Vector search disabled"
        end

        # Fall back to fuzzy matching using NodeMatcherRegistry (with human review if enabled)
        Rails.logger.debug "  Step 3: Trying fuzzy matching..." if @debug

        # Debug: Check what nodes exist before fuzzy matching
        if @debug
          debug_result = tx.run("MATCH (n:#{type}) RETURN count(n) as count")
          node_count = debug_result.first[:count]
          Rails.logger.debug { "    Debug: Found #{node_count} existing #{type} nodes in database" }
        end

        fuzzy_result = find_node_by_fuzzy_matching_with_review(tx, type, properties)
        if fuzzy_result
          Rails.logger.debug "  ✅ Found via fuzzy matching!" if @debug
          return fuzzy_result
        end
        Rails.logger.debug "  ❌ No fuzzy matches" if @debug

        Rails.logger.debug "  Step 4: Trying property matching..." if @debug
        property_result = find_node_by_properties(tx, type, properties)
        if property_result
          Rails.logger.debug "  ✅ Found via property matching!" if @debug
          return property_result
        end
        Rails.logger.debug "  ❌ No property matches" if @debug

        Rails.logger.debug "  🚫 No existing node found - will create new one" if @debug
        nil
      end

      # Find a node by its unique constraints
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type to search for
      # @param properties [Hash] The properties to match against
      # @return [Neo4j::Core::Node, nil] The matching node, or nil if not found
      def find_node_by_constraints(tx, type, properties)
        # First try to find by ID if present
        if properties["id"]
          escaped_type = type.include?(" ") ? "`#{type}`" : type
          query = "MATCH (n:#{escaped_type} {id: $id}) RETURN n LIMIT 1"
          result = tx.run(query, id: properties["id"])
          record = result.first
          return record[:n] if record
        end

        # Then try to find by other unique properties
        unique_props = properties.select { |k, _| k.to_s.start_with?("unique_") }
        if unique_props.any?
          escaped_type = type.include?(" ") ? "`#{type}`" : type
          where_clause = unique_props.map do |k, _|
            escaped_prop = k.to_s.include?(" ") ? "`#{k}`" : k
            param_name = k.to_s.tr(" ", "_")
            "n.#{escaped_prop} = $#{param_name}"
          end.join(" AND ")
          query = "MATCH (n:#{escaped_type}) WHERE #{where_clause} RETURN n LIMIT 1"
          # Convert unique properties to symbol keys with underscores
          unique_params = unique_props.transform_keys { |k| k.to_s.tr(" ", "_").to_sym }
          result = tx.run(query, **unique_params)
          record = result.first
          return record[:n] if record
        end

        nil
      end

      # Find a node by property matching
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type to search for
      # @param properties [Hash] The properties to match against
      # @return [Neo4j::Core::Node, nil] The matching node, or nil if not found
      def find_node_by_properties(tx, type, properties)
        # Skip if no properties to match on
        return nil if properties.empty?

        # Create a simple property-based query
        escaped_type = type.include?(" ") ? "`#{type}`" : type
        where_clause = properties.map do |k, _|
          escaped_prop = k.to_s.include?(" ") ? "`#{k}`" : k
          param_name = k.to_s.tr(" ", "_")
          "n.#{escaped_prop} = $#{param_name}"
        end.join(" AND ")
        query = "MATCH (n:#{escaped_type}) WHERE #{where_clause} RETURN n LIMIT 1"

        begin
          # Convert properties to symbol keys for the neo4j-driver, replacing spaces with underscores
          params = properties.transform_keys { |k| k.to_s.tr(" ", "_").to_sym }
          result = tx.run(query, **params)
          record = result.first
          record ? record[:n] : nil
        rescue StandardError => e
          log_error("Error finding node by properties: #{e.message}")
          log_error(e.backtrace.join("\n")) if @debug
          nil
        end
      end

      # Find a node using fuzzy matching with optional human review
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type to search for
      # @param properties [Hash] The properties to match against
      # @return [Neo4j::Core::Node, nil] The matching node, or nil if not found
      def find_node_by_fuzzy_matching_with_review(tx, type, properties)
        return find_node_by_fuzzy_matching(tx, type, properties) unless @enable_human_review

        # With human review enabled, evaluate each potential match
        Rails.logger.debug "\\n=== Fuzzy Matching with Human Review ===" if @debug
        Rails.logger.debug { "Type: #{type}" } if @debug
        Rails.logger.debug { "Properties: #{properties.keys.join(', ')}" } if @debug

        # Query for all nodes of the specified type
        escaped_type = type.include?(" ") ? "`#{type}`" : type

        # Build property list based on node type
        if type == "Person"
          query = "MATCH (n:#{escaped_type}) RETURN n, n.name as name, n.email as email, n.phone_number as phone_number, n.ID as ID, n.aliases as aliases"
        elsif ["Asset", "Vehicle"].include?(type)
          query = "MATCH (n:#{escaped_type}) RETURN n, n.name as name, n.model as model, n.brand as brand, n.make as make, n.serial_number as serial_number, n.license_plate as license_plate, n.category as category, n.description as description"
        else
          query = "MATCH (n:#{escaped_type}) RETURN n, n.name as name, n.description as description, n.title as title"
        end

        result = tx.run(query)
        records = result.to_a
        Rails.logger.debug { "Found #{records.size} records to evaluate" } if @debug

        matcher_class = NodeMatcherRegistry.matcher_for(type)

        records.each_with_index do |record, index|
          node = record[:n]

          # Reconstruct properties from individual fields
          existing_props = extract_node_properties(record, type)

          Rails.logger.debug { "\\n--- Evaluating match #{index + 1} ---" } if @debug
          Rails.logger.debug { "Node ID: #{node.id}" } if @debug
          Rails.logger.debug { "Existing: #{existing_props['name']}" } if @debug
          Rails.logger.debug { "New: #{properties['name']}" } if @debug

          # Use human review manager to evaluate the match
          decision = @human_review_manager.evaluate_merge_decision(
            existing_props,
            properties,
            matcher_class
          )

          case decision[:action]
          when :auto_merge
            Rails.logger.debug { "  ✅ Auto-merge approved (#{decision[:confidence].round(3)} confidence)" } if @debug
            return node
          when :auto_reject
            Rails.logger.debug { "  ❌ Auto-reject (#{decision[:confidence].round(3)} confidence)" } if @debug
            next
          when :human_review
            Rails.logger.debug { "  🤔 Queued for human review (#{decision[:confidence].round(3)} confidence)" } if @debug
            Rails.logger.debug { "  Review ID: #{decision[:review_id]}" } if @debug
            # Continue to next potential match
            next
          end
        end

        Rails.logger.debug "No automatic matches found" if @debug
        nil
      end

      # Find a node using fuzzy matching logic from NodeMatcherRegistry (original method)
      # @param tx [Neo4j::Core::CypherSession::Transaction] The Neo4j transaction
      # @param type [String] The node type to search for
      # @param properties [Hash] The properties to match against
      # @return [Neo4j::Core::Node, nil] The matching node, or nil if not found
      def find_node_by_fuzzy_matching(tx, type, properties)
        Rails.logger.debug "\n=== Fuzzy Matching ===" if @debug
        Rails.logger.debug { "Type: #{type}" } if @debug
        Rails.logger.debug { "Properties: #{properties.keys.join(', ')}" } if @debug

        # Enable debug mode for this operation if @debug is true
        original_debug = $debug_mode
        $debug_mode = @debug

        begin
          # Query for all nodes of the specified type
          # Escape type names that contain spaces or special characters
          escaped_type = type.include?(" ") ? "`#{type}`" : type
          # Build property list based on node type
          if type == "Person"
            query = "MATCH (n:#{escaped_type}) RETURN n, n.name as name, n.email as email, n.phone_number as phone_number, n.ID as ID, n.aliases as aliases"
          elsif ["Asset", "Vehicle"].include?(type)
            query = "MATCH (n:#{escaped_type}) RETURN n, n.name as name, n.model as model, n.brand as brand, n.make as make, n.serial_number as serial_number, n.license_plate as license_plate, n.category as category, n.description as description"
          else
            # Default for other types
            query = "MATCH (n:#{escaped_type}) RETURN n, n.name as name, n.description as description, n.title as title"
          end
          Rails.logger.debug { "Executing query: #{query}" } if @debug

          result = tx.run(query)
          Rails.logger.debug "Executing fuzzy matching query..." if @debug

          # Collect all results to avoid result stream consumption issues
          records = result.to_a
          Rails.logger.debug { "Found #{records.size} records to check" } if @debug
          records.each_with_index do |record, index|
            node = record[:n]
            # Reconstruct properties from individual fields based on node type
            existing_props = if type == "Person"
                               {
                                 "name" => record[:name],
                                 "email" => record[:email],
                                 "phone_number" => record[:phone_number],
                                 "ID" => record[:ID],
                                 "aliases" => record[:aliases]
                               }.compact
                             elsif ["Asset", "Vehicle"].include?(type)
                               {
                                 "name" => record[:name],
                                 "model" => record[:model],
                                 "brand" => record[:brand],
                                 "make" => record[:make],
                                 "serial_number" => record[:serial_number],
                                 "license_plate" => record[:license_plate],
                                 "category" => record[:category],
                                 "description" => record[:description]
                               }.compact
                             else
                               # Default for other types
                               {
                                 "name" => record[:name],
                                 "description" => record[:description],
                                 "title" => record[:title]
                               }.compact
                             end

            Rails.logger.debug { "\n--- Checking match #{index + 1} ---" } if @debug
            Rails.logger.debug { "Node ID: #{node.id}" } if @debug
            Rails.logger.debug { "Existing props keys: #{existing_props.keys.join(', ')}" } if @debug
            Rails.logger.debug { "New props keys: #{properties.keys.join(', ')}" } if @debug
            Rails.logger.debug { "Existing name: '#{existing_props['name']}'" } if @debug
            Rails.logger.debug { "New name: '#{properties['name']}'" } if @debug

            # Log specific properties for comparison
            if type == "Address"
              log_debug("  Street: #{existing_props['street']} <=> #{properties['street']}")
              log_debug("  City:   #{existing_props['city']} <=> #{properties['city']}")
              log_debug("  State:  #{existing_props['state']} <=> #{properties['state']}")
              log_debug("  ZIP:    #{existing_props['zip'] || existing_props['postalCode']} <=> #{properties['zip'] || properties['postalCode']}")
              log_debug("  Country:#{existing_props['country']} <=> #{properties['country']}")
            end

            # Enable detailed debug logging for the fuzzy match
            NodeMatcherRegistry.debug = true if @debug

            Rails.logger.debug "Calling NodeMatcherRegistry.fuzzy_match?..." if @debug
            Rails.logger.debug { "  Using matcher: #{NodeMatcherRegistry.matcher_for(type).name}" } if @debug
            match_result = NodeMatcherRegistry.fuzzy_match?(type, existing_props, properties, debug: @debug)
            if match_result
              Rails.logger.debug "✅ Found fuzzy match!" if @debug
              return node
            elsif @debug
              Rails.logger.debug "❌ No match"
            end

            # Reset debug mode
            NodeMatcherRegistry.debug = false if @debug
          end

          log_debug("No fuzzy matches found")
          nil
        rescue StandardError => e
          log_error("Error during fuzzy matching: #{e.message}")
          log_error(e.backtrace.join("\n")) if @debug
          nil
        ensure
          # Restore original debug mode
          $debug_mode = original_debug
        end
      end

      # Extract node properties from Neo4j record based on node type
      # @param record [Hash] Neo4j record with node properties
      # @param type [String] The node type
      # @return [Hash] Extracted properties
      def extract_node_properties(record, type)
        case type
        when "Person"
          {
            "name" => record[:name],
            "email" => record[:email],
            "phone_number" => record[:phone_number],
            "ID" => record[:ID],
            "aliases" => record[:aliases]
          }.compact
        when "Asset", "Vehicle"
          {
            "name" => record[:name],
            "model" => record[:model],
            "brand" => record[:brand],
            "make" => record[:make],
            "serial_number" => record[:serial_number],
            "license_plate" => record[:license_plate],
            "category" => record[:category],
            "description" => record[:description]
          }.compact
        else
          {
            "name" => record[:name],
            "description" => record[:description],
            "title" => record[:title]
          }.compact
        end
      end

      # Check if a node needs to be updated
      # @param node [Neo4j::Node] The existing node
      # @param new_properties [Hash] The new properties
      # @return [Boolean] True if the node needs to be updated
      def node_needs_update?(node, new_properties)
        existing_properties = node.properties

        new_properties.any? do |key, value|
          existing_value = existing_properties[key.to_s]
          existing_value != value
        end
      end

      # Create a relationship between two nodes
      # @param from_node [Neo4j::Node] The source node
      # @param to_node [Neo4j::Node] The target node
      # @param rel_type [Symbol] The relationship type
      # @param properties [Hash] Relationship properties
      # @param stats [Hash] Statistics hash to update
      # @return [Neo4j::Relationship, nil] The created relationship or nil if failed
      def create_relationship(from_node, to_node, rel_type, properties = {}, stats = {})
        Neo4j::DatabaseService.write_transaction do |tx|
          @relationship_manager.create_relationship(tx, from_node, to_node, rel_type, properties, stats)
        end
      end

      # Find existing relationships between nodes
      # @param from_node [Neo4j::Node] The source node
      # @param to_node [Neo4j::Node] The target node
      # @param rel_type [Symbol] The relationship type to look for
      # @return [Array<Neo4j::Relationship>] Array of matching relationships
      def find_relationships(from_node, to_node, rel_type = nil)
        Neo4j::DatabaseService.read_transaction do |tx|
          @relationship_manager.find_relationships(tx, from_node, to_node, rel_type)
        end
      end

      # Delegate node creation to NodeOperations
      delegate :create_node, to: :@node_operations

      # Delegate node update to NodeOperations
      delegate :update_node, to: :@node_operations

      # Delegate vector search to VectorSearch
      def find_similar_nodes(tx, type, embedding, threshold = nil)
        @vector_search.find_similar_nodes(tx, type, embedding, threshold)
      end

      # Delegate property formatting to PropertyFormatter
      def format_property(value, depth: 0)
        @property_formatter.format_property(value, depth: depth, logger: @logger)
      end

      # Delegate properties formatting to PropertyFormatter
      def format_properties(properties, is_top_level: true)
        @property_formatter.format_properties(properties, is_top_level: is_top_level, logger: @logger)
      end
    end
  end
end
