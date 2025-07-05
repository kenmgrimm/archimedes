# frozen_string_literal: true

module Neo4j
  module Importers
    # Base class for all entity importers
    class BaseEntityImporter < BaseImporter
      # Define the entity type this importer handles
      # @return [String] The entity type
      def self.handles
        raise NotImplementedError, "Subclasses must implement .handles"
      end

      # Define the properties that are required for this entity type
      # @return [Array<Symbol>] List of required property names
      def required_properties
        []
      end

      # Define property mappings from extraction format to graph format
      # @return [Hash] Property mappings (extraction_key => graph_key)
      def property_mappings
        {}
      end

      # Main import method for entities
      # @param entity_data [Hash] The entity data to import
      # @param options [Hash] Additional options
      # @return [Neo4j::ActiveNode, nil] The imported or updated node, or nil if failed
      def import(entity_data, options = {})
        @entity_data = entity_data
        @options = options
        @tx = nil

        validate_entity || create_or_update_entity
      rescue StandardError => e
        handle_error("Error importing #{self.class.handles} entity", e, entity_data)
        nil
      end

      # Import with transaction support
      # @param tx [Neo4j::Core::Transaction] The Neo4j transaction
      # @param entity_data [Hash] The entity data to import
      # @param options [Hash] Additional options
      # @return [Neo4j::ActiveNode, nil] The imported or updated node, or nil if failed
      def import_with_tx(tx, entity_data, options = {})
        @entity_data = entity_data
        @options = options
        @tx = tx

        validate_entity || create_or_update_entity
      rescue StandardError => e
        handle_error("Error importing #{self.class.handles} entity", e, entity_data)
        nil
      end

      private

      def validate_entity
        validate_required_properties || validate_entity_specific_rules
      end

      def validate_required_properties
        missing = required_properties.reject { |prop| @entity_data[prop.to_s].present? }
        return if missing.empty?

        add_error("Missing required properties: #{missing.join(', ')}", @entity_data)
      end

      def validate_entity_specific_rules
        # To be implemented by subclasses
        true
      end

      def create_or_update_entity
        properties = map_properties(@entity_data)
        existing = find_existing_entity(properties)

        if existing
          update_existing_entity(existing, properties)
        else
          create_new_entity(properties)
        end
      end

      def map_properties(data)
        return {} unless data

        properties = {}
        property_mappings.each do |source_key, target_key|
          properties[target_key] = data[source_key.to_s] if data.key?(source_key.to_s)
        end

        # Add any additional properties not in the mappings
        data.each do |key, value|
          next if property_mappings.key?(key.to_sym)

          properties[key] = value
        end

        properties
      end

      def find_existing_entity(_properties)
        # To be implemented by subclasses
        nil
      end

      def create_new_entity(properties)
        if @tx
          # Use transaction to create the node
          query = "CREATE (n:#{self.class.handles} $props) RETURN n"
          result = @tx.query(query, props: properties)

          if result.any?
            node = result.first["n"]
            @imported_count += 1
            log_import(self.class.handles, "Created", node.id)
            node
          else
            add_error("Failed to create #{self.class.handles}", properties)
            nil
          end
        else
          # Fall back to non-transactional create
          node = entity_class.create(properties)
          if node.persisted?
            @imported_count += 1
            log_import(self.class.handles, "Created", node.id)
            node
          else
            add_error("Failed to create #{self.class.handles}: #{node.errors.full_messages.join(', ')}", properties)
            nil
          end
        end
      end

      def update_existing_entity(existing, new_properties)
        if @tx
          # Use transaction to update the node
          query = "MATCH (n) WHERE id(n) = $id SET n += $props RETURN n"
          result = @tx.query(query, id: existing.id, props: new_properties)

          if result.any?
            node = result.first["n"]
            @updated_count += 1
            log_import(self.class.handles, "Updated", node.id)
            node
          else
            add_error("Failed to update #{self.class.handles} #{existing.id}", new_properties)
            nil
          end
        elsif existing.update(new_properties)
          # Fall back to non-transactional update
          @updated_count += 1
          log_import(self.class.handles, "Updated", existing.id)
          existing
        else
          add_error("Failed to update #{self.class.handles} #{existing.id}: #{existing.errors.full_messages.join(', ')}", new_properties)
          nil
        end
      end

      def entity_class
        @entity_class ||= self.class.handles.constantize
      rescue NameError
        raise "Could not find model class for #{self.class.handles}"
      end

      def handle_error(message, error, data = nil)
        error_message = "#{message}: #{error.message}"
        Rails.logger.error(error_message)
        Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
        add_error(error_message, data)
      end
    end
  end
end
