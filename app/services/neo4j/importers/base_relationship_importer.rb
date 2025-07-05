# frozen_string_literal: true

module Neo4j
  module Importers
    # Base class for all relationship importers
    class BaseRelationshipImporter < BaseImporter
      # Define the relationship type this importer handles
      # @return [String] The relationship type
      def self.handles
        raise NotImplementedError, "Subclasses must implement .handles"
      end

      # Main import method for relationships
      # @param relationship_data [Hash] The relationship data to import
      # @param options [Hash] Additional options
      # @return [Neo4j::ActiveRel, nil] The created or updated relationship, or nil if failed
      def import(relationship_data, options = {})
        @relationship_data = relationship_data
        @options = options
        @tx = nil

        validate_relationship || create_or_update_relationship
      rescue StandardError => e
        handle_error("Error importing #{self.class.handles} relationship", e, relationship_data)
        nil
      end

      # Import with transaction support
      # @param tx [Neo4j::Core::Transaction] The Neo4j transaction
      # @param relationship_data [Hash] The relationship data to import
      # @param options [Hash] Additional options
      # @return [Neo4j::ActiveRel, nil] The created or updated relationship, or nil if failed
      def import_with_tx(tx, relationship_data, options = {})
        @relationship_data = relationship_data
        @options = options
        @tx = tx

        validate_relationship || create_or_update_relationship
      rescue StandardError => e
        handle_error("Error importing #{self.class.handles} relationship", e, relationship_data)
        nil
      end

      private

      def validate_relationship
        validate_required_properties && validate_nodes_exist
      end

      def validate_required_properties
        required = [:source_id, :target_id]
        missing = required.reject { |prop| @relationship_data[prop.to_s].present? }

        if missing.any?
          add_error("Missing required properties: #{missing.join(', ')}", @relationship_data)
        else
          true
        end
      end

      def validate_nodes_exist
        source_exists = source_node.present?
        target_exists = target_node.present?

        unless source_exists && target_exists
          missing = []
          missing << "source node with id #{@relationship_data['source_id']}" unless source_exists
          missing << "target node with id #{@relationship_data['target_id']}" unless target_exists
          add_error("Could not find #{missing.join(' and ')}", @relationship_data)
          return false
        end

        true
      end

      def create_or_update_relationship
        properties = relationship_properties
        existing = find_existing_relationship

        if existing
          update_existing_relationship(existing, properties)
        else
          create_new_relationship(properties)
        end
      end

      def relationship_properties
        @relationship_data.reject { |k, _| ["source_id", "target_id", "type"].include?(k) }
      end

      def find_existing_relationship
        source_id = @relationship_data["source_id"]
        target_id = @relationship_data["target_id"]
        relationship_type = self.class.handles

        if @tx
          # Use transaction to find the relationship
          query = <<~CYPHER
            MATCH (source)-[r:#{relationship_type}]->(target)
            WHERE id(source) = $source_id AND id(target) = $target_id
            RETURN r
            LIMIT 1
          CYPHER

          result = @tx.query(query, {
                               source_id: source_id.to_i,
                               target_id: target_id.to_i
                             })

          result.any? ? result.first["r"] : nil
        else
          # Fall back to non-transactional find
          source_node = begin
            Neo4j::ActiveNode.find(source_id)
          rescue StandardError
            nil
          end
          target_node = begin
            Neo4j::ActiveNode.find(target_id)
          rescue StandardError
            nil
          end

          relationship_class.between(source_node, target_node).first if source_node && target_node
        end
      rescue StandardError => e
        handle_error("Error finding existing #{self.class.handles} relationship", e, { source_id: source_id, target_id: target_id })
        nil
      end

      def create_new_relationship(properties)
        if @tx
          # Use transaction to create the relationship
          query = <<~CYPHER
            MATCH (source), (target)
            WHERE id(source) = $source_id AND id(target) = $target_id
            CREATE (source)-[r:#{self.class.handles} $props]->(target)
            RETURN r
          CYPHER

          result = @tx.query(query, {
                               source_id: source_node.id,
                               target_id: target_node.id,
                               props: properties
                             })

          if result.any?
            rel = result.first["r"]
            @imported_count += 1
            log_import("#{self.class.handles} relationship", "Created", rel.id)
            rel
          else
            add_error("Failed to create #{self.class.handles} relationship", properties)
            nil
          end
        else
          # Fall back to non-transactional create
          rel = relationship_class.create(
            from_node: source_node,
            to_node: target_node,
            **properties
          )

          if rel.persisted?
            @imported_count += 1
            log_import("#{self.class.handles} relationship", "Created", rel.id)
            rel
          else
            add_error("Failed to create #{self.class.handles} relationship: #{rel.errors.full_messages.join(', ')}", properties)
            nil
          end
        end
      end

      def update_existing_relationship(existing, new_properties)
        if @tx
          # Use transaction to update the relationship
          query = <<~CYPHER
            MATCH ()-[r]->()#{' '}
            WHERE id(r) = $id#{' '}
            SET r += $props#{' '}
            RETURN r
          CYPHER

          result = @tx.query(query, {
                               id: existing.id,
                               props: new_properties
                             })

          if result.any?
            rel = result.first["r"]
            @updated_count += 1
            log_import("#{self.class.handles} relationship", "Updated", rel.id)
            rel
          else
            add_error("Failed to update #{self.class.handles} relationship #{existing.id}", new_properties)
            nil
          end
        elsif existing.update(new_properties)
          # Fall back to non-transactional update
          @updated_count += 1
          log_import("#{self.class.handles} relationship", "Updated", existing.id)
          existing
        else
          add_error("Failed to update #{self.class.handles} relationship #{existing.id}: #{existing.errors.full_messages.join(', ')}",
                    new_properties)
          nil
        end
      end

      def source_node
        return @source_node if defined?(@source_node)

        if @tx
          # Use transaction to find the source node
          result = @tx.query("MATCH (n) WHERE id(n) = $id RETURN n", id: @relationship_data["source_id"].to_i)
          @source_node = result.any? ? result.first["n"] : nil
        else
          @source_node = Neo4j::ActiveNode.find(@relationship_data["source_id"])
        end
      rescue Neo4j::ActiveNode::Labels::RecordNotFound
        nil
      end

      def target_node
        return @target_node if defined?(@target_node)

        if @tx
          # Use transaction to find the target node
          result = @tx.query("MATCH (n) WHERE id(n) = $id RETURN n", id: @relationship_data["target_id"].to_i)
          @target_node = result.any? ? result.first["n"] : nil
        else
          @target_node = Neo4j::ActiveNode.find(@relationship_data["target_id"])
        end
      rescue Neo4j::ActiveNode::Labels::RecordNotFound
        nil
      end

      def relationship_class
        @relationship_class ||= begin
          # Try to find the relationship class in the Neo4j namespace
          class_name = self.class.handles
          class_name = "Neo4j::ActiveRel::RelTypeConverters::RelType" if class_name.blank?

          # Try to constantize the class name
          klass = class_name.safe_constantize

          # If the class doesn't exist yet, define a simple relationship class dynamically
          unless klass
            klass = Class.new(Neo4j::ActiveRel::Property) do
              from_class :any
              to_class :any
              type class_name

              # Define a simple property setter/getter for each property in the relationship data
              define_method(:initialize) do |params = {}|
                params.each do |key, value|
                  self.class.property key.to_sym
                  send("#{key}=", value)
                end
                super()
              end
            end

            # Store the dynamically created class in the Neo4j module's constants
            Neo4j.const_set(class_name.demodulize, klass)
          end

          klass
        rescue StandardError => e
          handle_error("Error initializing relationship class #{class_name}", e)
          raise
        end
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
