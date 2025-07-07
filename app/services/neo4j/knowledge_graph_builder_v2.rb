# frozen_string_literal: true

require_relative "import/import_orchestrator"

module Neo4j
  # Enhanced KnowledgeGraphBuilder that uses the new import services
  class KnowledgeGraphBuilderV2
    attr_reader :logger, :import_orchestrator, :deduplication_service

    def initialize(logger: nil, deduplication_service: nil, dry_run: false)
      @logger = logger || Rails.logger
      @deduplication_service = deduplication_service
      @dry_run = dry_run
      @import_orchestrator = Import::ImportOrchestrator.new(logger: @logger, dry_run: @dry_run)
    end

    # Import data from extraction results
    # @param extraction_results [Hash] The extraction results to import
    # @option options [Boolean] :clear_database Whether to clear the database before import
    # @option options [Boolean] :validate_schema Whether to validate the extraction schema
    # @return [Hash] Results of the import
    def import(extraction_results, options = {})
      start_time = Time.current
      logger.info("Starting import process...")
      logger.debug("Options: #{options.inspect}")

      # Validate the extraction results if requested
      if options.fetch(:validate_schema, true)
        logger.debug("Validating extraction results schema...")
        unless validate_extraction_results(extraction_results)
          logger.error("Validation failed: Invalid extraction results format")
          return error_result("Invalid extraction results", start_time)
        end
      else
        logger.debug("Skipping schema validation as requested")
      end

      begin
        # Clear database if requested
        if options[:clear_database]
          logger.info("Clearing database before import...")
          Neo4j::DatabaseService.clear_database(logger: logger) unless @dry_run
          logger.info("Database cleared successfully") unless @dry_run
        end

        # Transform extraction results to match our import format
        logger.debug("Transforming extraction results...")
        logger.debug("Raw extraction results: #{extraction_results.inspect}")
        import_data = transform_extraction_results(extraction_results)

        # Log the transformed data in detail
        logger.debug("Transformed data:")
        logger.debug("  - Entities: #{import_data[:entities]&.size || 0}")
        import_data[:entities]&.each_with_index do |entity, idx|
          logger.debug("    #{idx + 1}. Type: #{entity[:type]}, Name: #{entity[:name]}")
          logger.debug("       Properties: #{entity[:properties].inspect}")
        end

        logger.debug("  - Relationships: #{import_data[:relationships]&.size || 0}")
        import_data[:relationships]&.each_with_index do |rel, idx|
          logger.debug("    #{idx + 1}. Type: #{rel[:type]}, From: #{rel[:source]}, To: #{rel[:target]}")
          logger.debug("       Properties: #{rel[:properties].inspect}")
        end

        # Run the import
        logger.info("Starting import process...")
        results = @import_orchestrator.import(import_data)
        logger.info("Import process completed")

        # Return formatted results
        success_result(results, start_time)
      rescue StandardError => e
        logger.error("Import failed: #{e.message}")
        logger.error(e.backtrace.join("\n")) if @debug
        error_result(e.message, start_time)
      end
    end

    private

    def transform_extraction_results(extraction_results)
      # Handle nested extraction_result structure if present
      if extraction_results.key?(:extraction_result) || extraction_results.key?("extraction_result")
        logger.debug("Found nested 'extraction_result' key, extracting entities and relationships from it")
        extraction_results = extraction_results[:extraction_result] || extraction_results["extraction_result"]
      end

      # Get entities and relationships
      entities = extraction_results[:entities] || extraction_results["entities"] || []
      relationships = extraction_results[:relationships] || extraction_results["relationships"] || []
      node_mapping = extraction_results[:node_mapping] || extraction_results["node_mapping"] || {}

      # Transform entities to ensure they have proper names and properties
      transformed_entities = entities.map do |entity|
        # Convert to symbol keys for easier access
        entity = entity.transform_keys(&:to_sym) if entity.respond_to?(:transform_keys)

        # Extract properties
        properties = entity[:properties] || entity["properties"] || {}
        properties = properties.transform_keys(&:to_s)

        # Ensure name is set at the top level and in properties
        name = entity[:name] || entity["name"]
        properties["name"] ||= name if name

        # Build the transformed entity
        {
          type: (entity[:type] || entity["type"]).to_s,
          name: name,
          properties: properties
        }
      end

      # Transform relationships to ensure they reference nodes correctly
      transformed_relationships = relationships.map do |rel|
        rel = rel.transform_keys(&:to_sym) if rel.respond_to?(:transform_keys)

        {
          type: (rel[:type] || rel["type"]).to_s,
          source: rel[:source] || rel["source"],
          target: rel[:target] || rel["target"],
          source_type: rel[:source_type] || rel["source_type"],
          target_type: rel[:target_type] || rel["target_type"],
          properties: (rel[:properties] || rel["properties"] || {}).transform_keys(&:to_s)
        }
      end

      # Build the result hash
      result = {
        entities: transformed_entities,
        relationships: transformed_relationships,
        node_mapping: node_mapping
      }

      logger.debug("Transformed extraction results - " \
                   "Entities: #{result[:entities].size}, " \
                   "Relationships: #{result[:relationships].size}, " \
                   "Node mappings: #{result[:node_mapping].size}")

      # Ensure all keys are symbols and handle nested structures
      transform_nested_hashes = lambda do |hash|
        hash.each_with_object({}) do |(k, v), h|
          key = k.respond_to?(:to_sym) ? k.to_sym : k
          h[key] = if v.is_a?(Hash)
                     transform_nested_hashes.call(v)
                   elsif v.is_a?(Array)
                     v.map { |item| item.is_a?(Hash) ? transform_nested_hashes.call(item) : item }
                   else
                     v
                   end
        end
      end

      # Apply transformation to the result
      result.transform_values do |value|
        if value.is_a?(Array)
          value.map { |item| item.is_a?(Hash) ? transform_nested_hashes.call(item) : item }
        elsif value.is_a?(Hash)
          transform_nested_hashes.call(value)
        else
          value
        end
      end
    end

    def validate_extraction_results(extraction_results)
      # Basic validation of the extraction results structure
      unless extraction_results.is_a?(Hash)
        logger.error("Validation failed: extraction_results must be a Hash, got #{extraction_results.class}")
        return false
      end

      # Check for nested extraction_result
      if extraction_results.key?(:extraction_result) || extraction_results.key?("extraction_result")
        logger.debug("Found nested 'extraction_result' key, validating its content")
        extraction_results = extraction_results[:extraction_result] || extraction_results["extraction_result"]

        unless extraction_results.is_a?(Hash)
          logger.error("Validation failed: extraction_result must be a Hash, got #{extraction_results.class}")
          return false
        end
      end

      has_entities = extraction_results.key?(:entities) || extraction_results.key?("entities")
      has_relationships = extraction_results.key?(:relationships) || extraction_results.key?("relationships")

      if !has_entities && !has_relationships
        logger.error("Validation failed: extraction_results must contain at least one of :entities or :relationships")
        logger.debug("Available keys: #{extraction_results.keys.inspect}")
        return false
      end

      # Validate entities and relationships if they exist
      if has_entities
        entities = extraction_results[:entities] || extraction_results["entities"]
        unless entities.is_a?(Array)
          logger.error("Validation failed: entities must be an Array, got #{entities.class}")
          return false
        end

        entities.each_with_index do |entity, index|
          unless entity.is_a?(Hash)
            logger.error("Validation failed: entity at index #{index} must be a Hash, got #{entity.class}")
            return false
          end

          # Check for required fields
          entity = entity.transform_keys(&:to_sym)
          unless entity[:type] || entity["type"]
            logger.error("Validation failed: entity at index #{index} is missing required field 'type'")
            return false
          end
        end
      end

      if has_relationships
        relationships = extraction_results[:relationships] || extraction_results["relationships"]
        unless relationships.is_a?(Array)
          logger.error("Validation failed: relationships must be an Array, got #{relationships.class}")
          return false
        end

        relationships.each_with_index do |rel, index|
          unless rel.is_a?(Hash)
            logger.error("Validation failed: relationship at index #{index} must be a Hash, got #{rel.class}")
            return false
          end

          # Check for required fields
          rel = rel.transform_keys(&:to_sym)
          required_fields = [:type, :source, :target]
          missing_fields = required_fields.reject { |f| rel.key?(f) || rel.key?(f.to_s) }

          unless missing_fields.empty?
            logger.error("Validation failed: relationship at index #{index} is missing required fields: #{missing_fields.join(', ')}")
            return false
          end
        end
      end

      logger.debug("Validation passed - " \
                   "Has entities: #{has_entities}, " \
                   "Has relationships: #{has_relationships}")

      true
    end

    def success_result(import_results, start_time)
      duration = Time.current - start_time

      {
        success: true,
        stats: {
          nodes: import_results[:nodes] || {},
          relationships: import_results[:relationships] || {},
          duration: duration
        },
        timestamp: Time.current
      }
    end

    def error_result(message, start_time)
      duration = Time.current - start_time

      {
        success: false,
        error: message,
        stats: {
          duration: duration
        },
        timestamp: Time.current
      }
    end
  end
end
