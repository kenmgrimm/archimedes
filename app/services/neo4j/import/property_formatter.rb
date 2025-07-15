# frozen_string_literal: true

require "date"
require "json"

module Neo4j
  module Import
    # Handles formatting property values for Neo4j
    class PropertyFormatter
      def initialize(debug: false)
        @debug = debug
      end

      # Format a single property value for Neo4j
      # @param value [Object] The value to format
      # @param depth [Integer] Recursion depth for nested structures
      # @return [Object] The formatted value
      def format_property(value, depth: 0, logger: nil)
        log_debug(logger, "  + Formatting property (#{value.class.name})") if depth.zero?

        case value
        when Hash
          log_debug(logger, "    - Formatting hash") if depth.zero?
          # Neo4j doesn't support nested objects, so we need to flatten or serialize them
          if depth.positive?
            # Convert nested hashes to JSON strings
            log_debug(logger, "    - Converting nested hash to JSON string") if logger && depth == 1
            value.to_json
          else
            # For top-level hashes, process each value but don't nest hashes
            # If any value is a hash, convert it to JSON string
            result = {}
            value.each do |k, v|
              if v.is_a?(Hash)
                log_debug(logger, "    - Converting nested hash property '#{k}' to JSON string")
                result[k] = v.to_json
              else
                result[k] = format_property(v, depth: depth + 1, logger: logger)
              end
            end
            result
          end
        when Array
          log_debug(logger, "    - Formatting array (#{value.size} items)") if depth.zero?

          # For large arrays (like embeddings), don't log individual items
          if value.size > 5 && depth.zero? && value.all?(Numeric)
            log_debug(logger, "    - Large numeric array detected, skipping detailed logging")
            return value.map { |v| format_property(v, depth: depth + 1, logger: logger) }
          end

          value.map { |v| format_property(v, depth: depth + 1, logger: logger) }
        when Time, Date
          value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
        when NilClass
          nil
        when String
          value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        when TrueClass, FalseClass, Numeric
          value
        else
          # Handle time-like objects and other classes by name
          case value.class.name
          when "DateTime", "ActiveSupport::TimeWithZone"
            value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
          else
            log_warn(logger, "Unhandled type #{value.class.name}, converting to string") if depth.zero?
            value.to_s
          end
        end
      rescue StandardError => e
        log_error(logger, "Error formatting property: #{e.message}")
        log_error(logger, e.backtrace.join("\n")) if @debug
        nil
      end

      # Format all properties in a hash for Neo4j
      # @param properties [Hash] The properties to format
      # @param is_top_level [Boolean] Whether this is a top-level call (for logging)
      # @return [Hash] The formatted properties
      def format_properties(properties, is_top_level: true, logger: nil)
        return {} if properties.nil? || !properties.is_a?(Hash)

        log_debug(logger, "Formatting #{properties.size} properties") if is_top_level

        formatted = {}
        properties.each do |key, value|
          log_debug(logger, "  - Processing property: #{key}") if is_top_level

          formatted_value = format_property(value, depth: 1, logger: logger)
          formatted[key.to_s] = formatted_value

          next unless is_top_level

          log_value = if formatted_value.is_a?(Array)
                        if formatted_value.size > 5 && formatted_value.all?(Numeric)
                          "[Array(#{formatted_value.size} numbers)]"
                        elsif formatted_value.size > 5
                          "[Array(#{formatted_value.size} items) #{formatted_value.first(3).inspect}... #{formatted_value.last(2).inspect}]"
                        else
                          formatted_value.inspect
                        end
                      else
                        formatted_value.inspect
                      end
          log_debug(logger, "    #{key}: #{log_value}")
        end

        formatted
      rescue StandardError => e
        log_error(logger, "Error formatting properties: #{e.message}")
        log_error(logger, e.backtrace.join("\n")) if @debug
        {}
      end

      private

      def log_debug(logger, message)
        return unless logger

        logger.debug(message)
      end

      def log_warn(logger, message)
        return unless logger

        logger.warn(message)
      end

      def log_error(logger, message)
        return unless logger

        logger.error(message)
      end
    end
  end
end
