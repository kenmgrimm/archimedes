# frozen_string_literal: true

module Neo4j
  module Import
    module NodeMatchers
      # Global debug flag
      $debug_mode = false

      # Base class for all node matchers
      class BaseNodeMatcher
        class << self
          # Log a debug message if debug mode is enabled
          # @param message [String] the message to log
          def log_debug(message)
            Rails.logger.debug { "[#{name}] #{message}" } if $debug_mode
          end

          # Returns an array of property names to use for generating embeddings
          # @return [Array<String>] property names
          def embedding_properties
            ["name", "title", "description"]
          end

          # Generates text for embedding from node properties
          # @param properties [Hash] node properties
          # @return [String] text to embed
          def generate_embedding_text(properties)
            return "" unless properties.is_a?(Hash)

            text_parts = embedding_properties
                         .map { |p| properties[p] }
                         .compact
                         .reject(&:empty?)

            text_parts.any? ? text_parts.join(". ") : ""
          end

          # Returns an array of fuzzy equality method symbols to try
          # @return [Array<Symbol>] method names
          def fuzzy_equality_methods
            []
          end

          # Default similarity threshold for this node type
          # @return [Float] similarity threshold (0.0-1.0)
          def similarity_threshold
            0.8
          end

          # Main method to check if two nodes match
          # @param props1 [Hash] first node's properties
          # @param props2 [Hash] second node's properties
          # @return [Boolean] true if nodes match
          def match_nodes(props1, props2)
            log_debug("\n=== Matching nodes ===") if $debug_mode
            log_debug("Node 1: #{props1.inspect}") if $debug_mode
            log_debug("Node 2: #{props2.inspect}") if $debug_mode

            # Check for exact match on ID if present
            if props1["id"] && props2["id"] && props1["id"] == props2["id"]
              log_debug("✅ Exact match on ID: #{props1['id']}") if $debug_mode
              return true
            end

            # Try all fuzzy equality methods
            methods = fuzzy_equality_methods
            log_debug("\nAvailable matchers: #{methods.join(', ')}") if $debug_mode

            methods.each_with_index do |method, index|
              log_debug("\n[#{index + 1}/#{methods.size}] Trying matcher: #{method}") if $debug_mode
              begin
                result = send(method, props1, props2)
                if result
                  log_debug("✅ MATCH FOUND with #{method}") if $debug_mode
                  return true
                elsif $debug_mode
                  log_debug("❌ No match with #{method}")
                end
              rescue StandardError => e
                log_debug("❌ ERROR in #{method}: #{e.message}") if $debug_mode
                log_debug(e.backtrace.join("\n")) if $debug_mode
              end
            end

            # Try vector similarity as a last resort if embedding is available
            if props1["embedding"] && props2["embedding"]
              log_debug("\nTrying vector similarity...") if $debug_mode
              similarity = vector_similarity(props1["embedding"], props2["embedding"])
              threshold = similarity_threshold
              log_debug("Vector similarity: #{similarity} (threshold: #{threshold})") if $debug_mode
              if similarity >= threshold
                log_debug("✅ MATCH FOUND with vector similarity") if $debug_mode
                return true
              elsif $debug_mode
                log_debug("❌ Vector similarity below threshold")
              end
            end

            log_debug("\n❌ No matches found with any matcher") if $debug_mode
            false
          end

          # Helper method to check string similarity
          # @param str1 [String, nil] first string
          # @param str2 [String, nil] second string
          # @param threshold [Float] similarity threshold (0.0-1.0)
          # @return [Boolean] true if strings are similar
          def string_similar?(str1, str2, threshold = 0.8)
            return false if str1.nil? || str2.nil?
            return true if str1 == str2

            # Simple string similarity using Jaro-Winkler distance
            distance = DidYouMean::Levenshtein.distance(str1.downcase, str2.downcase)
            max_length = [str1.length, str2.length].max
            similarity = 1.0 - (distance.to_f / max_length)

            similarity >= threshold
          end

          # Calculate cosine similarity between two vectors
          # @param vec1 [Array<Numeric>] first vector
          # @param vec2 [Array<Numeric>] second vector
          # @return [Float] cosine similarity between -1.0 and 1.0
          def vector_similarity(vec1, vec2)
            return 0.0 if vec1.nil? || vec2.nil? || vec1.empty? || vec2.empty? || vec1.size != vec2.size

            # Calculate dot product
            dot_product = vec1.each_with_index.sum { |v1, i| v1 * vec2[i] }

            # Calculate magnitudes
            magnitude1 = Math.sqrt(vec1.sum { |v| v**2 })
            magnitude2 = Math.sqrt(vec2.sum { |v| v**2 })

            # Avoid division by zero
            return 0.0 if magnitude1.zero? || magnitude2.zero?

            # Calculate and return cosine similarity
            dot_product / (magnitude1 * magnitude2)
          end
        end
      end
    end
  end
end
