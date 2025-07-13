# frozen_string_literal: true

require_relative "node_matchers/base_node_matcher"
require_relative "node_matchers/default_node_matcher"
require_relative "node_matchers/address_node_matcher"
require_relative "node_matchers/person_node_matcher"
require_relative "node_matchers/asset_node_matcher"

module Neo4j
  module Import
    # Registry for node matchers
    class NodeMatcherRegistry
      class << self
        attr_accessor :debug
      end

      # Initialize debug mode to false by default
      @debug = false

      # Maps node types to their corresponding matcher classes
      MATCHERS = {
        "Address" => NodeMatchers::AddressNodeMatcher,
        "Person" => NodeMatchers::PersonNodeMatcher,
        "User" => NodeMatchers::PersonNodeMatcher, # Alias for backward compatibility
        "Contact" => NodeMatchers::PersonNodeMatcher, # Common alternative
        "Asset" => NodeMatchers::AssetNodeMatcher,
        "Vehicle" => NodeMatchers::AssetNodeMatcher # Vehicles are assets
        # Add other node matchers here as they are implemented
      }.freeze

      # Get a matcher for a specific node type
      # @param node_type [String, Symbol] the type of node
      # @return [Class] the matcher class
      def self.matcher_for(node_type)
        return NodeMatchers::DefaultNodeMatcher if node_type.blank?

        type_str = node_type.to_s.camelize
        MATCHERS[type_str] || NodeMatchers::DefaultNodeMatcher
      end

      # Gets the embedding properties for a node type
      # @param node_type [String, Symbol] the type of node
      # @return [Array<String>] property names to use for embeddings
      def self.embedding_properties_for(node_type)
        matcher_for(node_type).embedding_properties
      end

      # Generates embedding text for a node
      # @param node_type [String, Symbol] the type of node
      # @param properties [Hash] the node's properties
      # @return [String] text to use for generating embeddings
      def self.generate_embedding_text(node_type, properties)
        matcher_class = matcher_for(node_type)
        matcher_class.generate_embedding_text(properties)
      end

      # Gets the similarity threshold for a node type
      # @param node_type [String, Symbol] the type of node
      # @return [Float] the similarity threshold (0.0-1.0)
      def self.similarity_threshold_for(node_type)
        matcher_class = matcher_for(node_type)
        matcher_class.similarity_threshold
      end

      # Checks if two nodes match using fuzzy matching
      # @param node_type [String, Symbol] the type of nodes being compared
      # @param props1 [Hash] first node's properties
      # @param props2 [Hash] second node's properties
      # @param debug [Boolean] whether to enable debug logging
      # @return [Boolean] true if the nodes match
      def self.fuzzy_match?(node_type, props1, props2, debug: false)
        return false if props1.blank? || props2.blank?

        # Set debug mode for logging if needed
        original_debug = $debug_mode
        $debug_mode = debug

        log_debug = ->(msg) { Rails.logger.debug { "[NodeMatcherRegistry] #{msg}" } if $debug_mode }

        begin
          log_debug.call("\n=== FUZZY MATCHING STARTED ===")
          log_debug.call("Node type: #{node_type}")
          log_debug.call("Props1: #{props1.inspect}")
          log_debug.call("Props2: #{props2.inspect}")

          matcher_class = MATCHERS[node_type] || DefaultNodeMatcher
          log_debug.call("Using matcher: #{matcher_class.name}")

          # Check for exact ID match first
          if props1["id"].present? && props2["id"].present? && props1["id"] == props2["id"]
            log_debug.call("✅ Exact ID match found: #{props1['id']}")
            return true
          end

          # Check for exact matching on unique identifiers if present
          if props1["email"].present? && props2["email"].present? &&
             props1["email"].downcase == props2["email"].downcase
            log_debug.call("✅ Exact email match found: #{props1['email']}")
            return true
          end

          # Check for exact matching on phone numbers if present
          if props1["phone"].present? && props2["phone"].present? &&
             normalize_phone(props1["phone"]) == normalize_phone(props2["phone"])
            log_debug.call("✅ Exact phone match found: #{props1['phone']}")
            return true
          end

          # Check for exact matching on SSN if present
          if props1["ssn"].present? && props2["ssn"].present? &&
             props1["ssn"].gsub(/\D/, "") == props2["ssn"].gsub(/\D/, "")
            log_debug.call("✅ Exact SSN match found")
            return true
          end

          # For Address nodes, log specific properties for comparison
          if node_type == "Address"
            log_debug.call("\n--- Address Property Comparison ---")
            log_debug.call("Street: '#{props1['street']}' <=> '#{props2['street']}'")
            log_debug.call("City:   '#{props1['city']}' <=> '#{props2['city']}'")
            log_debug.call("State:  '#{props1['state']}' <=> '#{props2['state']}'")
            log_debug.call("ZIP:    '#{props1['zip'] || props1['postalCode']}' <=> '#{props2['zip'] || props2['postalCode']}'")
            log_debug.call("Country:'#{props1['country']}' <=> '#{props2['country']}'")
          end

          # Delegate to the appropriate matcher class for fuzzy matching
          log_debug.call("\n--- Delegating to #{matcher_class.name} for fuzzy matching ---")
          result = matcher_class.match_nodes(props1, props2)

          log_debug.call("\n=== FUZZY MATCHING COMPLETE ===")
          log_debug.call("Final result: #{result ? '✅ MATCH' : '❌ NO MATCH'}")

          result
        rescue StandardError => e
          log_debug.call("\n❌ ERROR during fuzzy matching: #{e.message}")
          log_debug.call(e.backtrace.join("\n")) if $debug_mode
          false
        ensure
          # Restore original debug mode
          $debug_mode = original_debug
        end
      end
    end
  end
end
