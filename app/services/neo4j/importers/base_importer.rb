# frozen_string_literal: true

module Neo4j
  module Importers
    # Base class for all importers providing common functionality
    class BaseImporter
      class ImportError < StandardError; end
      class ValidationError < ImportError; end
      class EntityNotFoundError < ImportError; end

      attr_reader :errors, :warnings, :imported_count, :updated_count, :skipped_count

      def initialize
        @errors = []
        @warnings = []
        @imported_count = 0
        @updated_count = 0
        @skipped_count = 0
      end

      # Main import method to be implemented by subclasses
      # @param data [Hash] The data to import
      # @param options [Hash] Additional options for the import
      # @return [Boolean] true if import was successful, false otherwise
      def import(data, options = {})
        raise NotImplementedError, "Subclasses must implement #import"
      end

      # Import with transaction support
      # @param _tx [Neo4j::Core::Transaction] The Neo4j transaction
      # @param data [Hash] The data to import
      # @param options [Hash] Additional options for the import
      # @return [Boolean] true if import was successful, false otherwise
      def import_with_tx(_tx, data, options = {})
        # Default implementation falls back to non-transactional import
        # Subclasses should override this if they need to use the transaction
        import(data, options)
      end

      # Reset the counters and error collections
      def reset_counters
        @errors = []
        @warnings = []
        @imported_count = 0
        @updated_count = 0
        @skipped_count = 0
      end

      # Check if the import was successful
      # @return [Boolean] true if there are no errors, false otherwise
      def success?
        @errors.empty?
      end

      # Get a summary of the import results
      # @return [Hash] Summary of the import results
      def summary
        {
          imported: @imported_count,
          updated: @updated_count,
          skipped: @skipped_count,
          errors: @errors.count,
          warnings: @warnings.count
        }
      end

      private

      def add_error(message, data = nil)
        @errors << { message: message, data: data }
        false
      end

      def add_warning(message, data = nil)
        @warnings << { message: message, data: data }
      end

      def log_import(entity_type, action, identifier)
        Rails.logger.info("[#{self.class.name}] #{action} #{entity_type}: #{identifier}")
      end
    end
  end
end
