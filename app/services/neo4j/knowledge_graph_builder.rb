# frozen_string_literal: true

require_relative "importers/base_importer"
require_relative "importers/base_entity_importer"
require_relative "importers/base_relationship_importer"

module Neo4j
  # Service class for building and maintaining the knowledge graph
  class KnowledgeGraphBuilder
    attr_reader :import_results, :logger

    def initialize(neo4j_service:, openai_service: nil, taxonomy_service: nil, logger: nil, validate_schema: true)
      @neo4j = neo4j_service
      @openai = openai_service
      @logger = logger || Rails.logger
      @taxonomy_service = taxonomy_service || Neo4j::TaxonomyService.new(logger: logger)
      @validate_schema = validate_schema
      @importers = {}
      @import_results = {}
      @last_processed_at = nil

      register_default_importers
    end

    # Import data from extraction results
    # @param extraction_results [Hash] The extraction results to import
    # @param options [Hash] Additional options for the import
    # @return [Hash] Results of the import
    def import(extraction_results, options = {})
      @import_results = {
        entities: { imported: 0, updated: 0, skipped: 0, errors: [] },
        relationships: { created: 0, errors: [] },
        start_time: Time.current
      }

      # Skip validation for Bolt importer as it handles its own validation
      if @importers[:extraction].is_a?(Neo4j::Importers::BoltExtractionImporter)
        @logger.debug("Using Bolt importer, skipping validation")
        return @importers[:extraction].import(extraction_results, options.merge(neo4j_service: @neo4j))
      end

      # For other importers, use the standard validation flow
      unless validate_extraction_results(extraction_results)
        @import_results[:skipped] = true
        @import_results[:end_time] = Time.current
        @import_results[:duration] = 0
        return @import_results
      end

      begin
        # Use the neo4j-ruby-driver session for transactions
        @neo4j.session do |session|
          session.write_transaction do |tx|
            @tx = tx # Make transaction available to import methods
            import_entities(extraction_results[:entities] || [], options)
            import_relationships(extraction_results[:relationships] || [], options)
          end
        end

        @import_results[:success] = true
      rescue StandardError => e
        @logger.error("Import failed: #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        @import_results[:error] = e.message
        @import_results[:success] = false
      ensure
        @import_results[:end_time] = Time.current
        @import_results[:duration] = @import_results[:end_time] - @import_results[:start_time]
      end

      @import_results
    rescue StandardError => e
      @logger.error("Import failed: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
      raise
    end

    # Register a custom importer for an entity or relationship type
    # @param type [String] The entity or relationship type
    # @param importer_class [Class] The importer class
    def register_importer(type, importer_class)
      @importers[type] = importer_class
    end

    # Get an importer for the given type
    # @param type [String] The entity or relationship type
    # @return [BaseImporter] The importer instance
    def importer_for(type)
      @importers[type] ||= default_importer_for(type)
    end

    private

    def register_default_importers
      # Register the BoltExtractionImporter as the default importer
      @importers[:extraction] = Neo4j::Importers::BoltExtractionImporter.new

      # Auto-discover and register entity importers
      Rails.root.glob("app/services/neo4j/importers/entities/*.rb/services/neo4j/importers/entities/*.rb").each do |f|
        require_dependency f
      end
      Rails.root.glob("app/services/neo4j/importers/relationships/*.rb/services/neo4j/importers/relationships/*.rb").each do |f|
        require_dependency f
      end

      # Register entity importers
      Neo4j::Importers::Entities.constants.each do |const|
        klass = Neo4j::Importers::Entities.const_get(const)
        next unless klass.respond_to?(:handles)

        @importers[klass.handles] = klass.new
      end

      # Register relationship importers
      Neo4j::Importers::Relationships.constants.each do |const|
        klass = Neo4j::Importers::Relationships.const_get(const)
        next unless klass.respond_to?(:handles)

        @importers[klass.handles] = klass.new
      end
    end

    def default_importer_for(type)
      # Try to find a specific importer first
      importer_class = "Neo4j::Importers::#{type}Importer".safe_constantize
      return importer_class.new if importer_class

      # Fall back to generic importer
      if type.constantize < Neo4j::ActiveNode
        Neo4j::Importers::BaseEntityImporter.new
      elsif type.constantize < Neo4j::ActiveRel
        Neo4j::Importers::BaseRelationshipImporter.new
      else
        raise "No importer found for type: #{type}"
      end
    rescue NameError
      raise "Unknown type: #{type}"
    end

    def import_entities(entities, options)
      entities.each do |entity_data|
        importer = importer_for(entity_data[:type])

        # Pass the transaction to the importer
        result = if importer.respond_to?(:import_with_tx)
                   importer.import_with_tx(@tx, entity_data, options)
                 else
                   importer.import(entity_data, options)
                 end

        if result
          if result.is_a?(Hash) && result[:action] == :created
            @import_results[:entities][:imported] += 1
          else
            @import_results[:entities][:updated] += 1
          end
        else
          @import_results[:entities][:errors] << {
            type: entity_data[:type],
            data: entity_data,
            errors: importer.errors
          }
        end
      end
    end

    def import_relationships(relationships, options)
      relationships.each do |rel_data|
        importer = importer_for(rel_data[:type])

        # Pass the transaction to the importer
        result = if importer.respond_to?(:import_with_tx)
                   importer.import_with_tx(@tx, rel_data, options)
                 else
                   importer.import(rel_data, options)
                 end

        if result
          @import_results[:relationships][:created] += 1
        else
          @import_results[:relationships][:errors] << {
            type: rel_data[:type],
            data: rel_data,
            errors: importer.errors
          }
        end
      end
    end

    def validate_extraction_results(extraction_results)
      raise ArgumentError, "Extraction results must be a Hash" unless extraction_results.is_a?(Hash)

      # Check if we have any data to import
      if extraction_results.values_at(:entities, :relationships).all?(&:blank?)
        @logger.warn("No entities or relationships to import")
        return false
      end

      Neo4j::ExtractionValidator.validate!(extraction_results) if @validate_schema

      true
    rescue Neo4j::ExtractionValidator::ValidationError => e
      @logger.error("Extraction validation failed: #{e.message}")
      raise
    end
  end
end
