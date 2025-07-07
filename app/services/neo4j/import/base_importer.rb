# frozen_string_literal: true

module Neo4j
  module Import
    # Base class for importers that provides common functionality
    class BaseImporter
      attr_reader :logger, :dry_run

      # @param logger [Logger] Logger instance for progress and errors
      # @param dry_run [Boolean] If true, don't make any changes to the database
      def initialize(logger: nil, dry_run: false)
        @logger = logger || Rails.logger
        @dry_run = dry_run
      end

      protected

      # Log an informational message
      # @param message [String] Message to log
      def log_info(message)
        logger&.info("[#{self.class.name}] #{message}")
        Rails.logger.debug message if logger.nil? || !Rails.env.test?
      end

      # Log an error message
      # @param message [String] Error message
      # @param exception [Exception, nil] Optional exception that caused the error
      def log_error(message, exception = nil)
        error_message = "[#{self.class.name}] #{message}"
        error_message += ": #{exception.message}\n#{exception.backtrace.join("\n")}" if exception

        logger&.error(error_message)
        Rails.logger.debug error_message if logger.nil? || !Rails.env.test?
      end

      # Execute a block within a transaction
      # @yield [Neo4j::Driver::Transaction] The Neo4j transaction
      # @return [Object] The result of the block
      def with_transaction(&)
        return yield(nil) if dry_run

        Neo4j::DatabaseService.write_transaction(&)
      rescue StandardError => e
        log_error("Transaction failed", e)
        raise
      end

      # Format a property value for Neo4j
      # @param value [Object] The value to format
      # @return [String, Integer, Float, Boolean, nil] The formatted value
      def format_property(value)
        case value
        when String, Numeric, TrueClass, FalseClass, NilClass
          value
        when Time, DateTime, Date
          value.iso8601
        when Array
          value.map { |v| format_property(v) }
        when Hash
          value.transform_values { |v| format_property(v) }
        else
          value.to_s
        end
      end
    end
  end
end
