module Neo4j
  module Chat
    class ResponseGenerator
      def initialize(intent, query_results, taxonomy_service)
        @intent = intent
        @query_results = query_results
        @taxonomy_service = taxonomy_service
        @logger = Rails.logger
      end

      def generate
        @logger.debug { "ResponseGenerator: Starting response generation" }
        @logger.debug { "ResponseGenerator: Intent: #{Chat::Utils.clean_embeddings(@intent.inspect)}" }
        @logger.debug { "ResponseGenerator: Query results: #{Chat::Utils.clean_embeddings(@query_results.inspect)}" }

        sanitized = sanitize_results(@query_results)
        @logger.debug { "ResponseGenerator: Query results before OpenAI: #{Chat::Utils.clean_embeddings(sanitized.inspect)}" }

        # Build taxonomy context for smart response generation
        entity_types = build_entity_types_context
        relationship_types = build_relationship_types_context
        property_types = @taxonomy_service.property_types

        prompt = <<~PROMPT
          You are generating natural language responses from knowledge graph query results.

          Given:
          - User intent: #{@intent.to_json}
          - Query results: #{sanitized.to_json}

          # VALID ENTITY TYPES:
          #{format_entity_types(entity_types)}

          # VALID RELATIONSHIPS:
          #{format_relationship_types(relationship_types)}

          # PROPERTY TYPES:
          #{format_property_types(property_types)}

          Generate a response based on the user's intent and results:

          For read queries:
          1. Filter and organize relevant relationships using entity/relationship descriptions from schema
          2. Present them in a clear, structured way with meaningful context
          3. Keep relationship IDs for reference: [ID] EntityName
          4. Suggest relevant follow-up questions based on available relationships in schema
          5. Use entity and relationship descriptions to provide rich context

          For write queries:
          1. Clearly state what changed using proper entity/property terminology from schema
          2. Show the updated data with IDs and validate against schema
          3. Confirm the operation was successful using schema-aware language
          4. Suggest relevant follow-up actions based on available relationships

          For empty results:
          1. Explain why no results were found using schema context
          2. Suggest alternative queries using valid entity types and relationships
          3. Help user understand what data is available in the knowledge graph

          Response Guidelines:
          - Use entity type descriptions to provide context about what each entity represents
          - Use relationship descriptions to explain how entities are connected
          - Suggest follow-ups that leverage valid relationships from the schema
          - If data seems incomplete, suggest using valid properties for more information
          - Reference the schema to help users understand available query options

          Return a JSON object:
          {
            "response": "The natural language response with schema-aware context",
            "follow_ups": ["Schema-based suggested follow-up questions"],
            "needs_clarification": boolean,
            "clarification_question": "Question to ask user if needed"
          }
        PROMPT

        begin
          content = OpenAI::ClientService.new.extract_structured_data(
            text: prompt,
            prompt_config: {
              system_prompt: "You generate natural language responses from knowledge graph query results."
            }
          )

          @logger.debug { "ResponseGenerator: Content: #{content.inspect}" }
          raise "Invalid response format" unless content.is_a?(Hash)

          content
        rescue StandardError => e
          @logger.error { "ResponseGenerator: Error in generation: #{e.class} - #{e.message}" }
          @logger.error { "ResponseGenerator: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          raise
        end
      end

      private

      def sanitize_results(results)
        # Add comprehensive debug logging
        @logger.debug { "ResponseGenerator: Sanitizing #{results.size} result items" }

        # Handle nil or empty results
        return [] if results.blank?

        sanitized = results.filter_map do |result|
          # Skip nil results
          next nil if result.nil?

          # Handle different result formats
          case result
          when Hash
            # Transform hash values and remove embeddings
            result.transform_values { |v| strip_embedding(v) }
          else
            # Convert to hash if possible
            begin
              result.to_h.transform_values { |v| strip_embedding(v) }
            rescue NoMethodError
              # If to_h fails, return as is
              @logger.warn { "ResponseGenerator: Could not convert result to hash: #{result.class}" }
              result
            end
          end
        end

        @logger.debug { "ResponseGenerator: Sanitized #{sanitized.size} result items" }
        sanitized
      end

      def strip_embedding(result_item)
        case result_item
        when Neo4j::Driver::Internal::InternalNode
          # Convert to hash and remove both symbol and string embedding keys
          node_hash = result_item.to_h
          node_hash.delete(:embedding)
          node_hash.delete("embedding")
          node_hash
        when Array
          result_item.map { |item| strip_embedding(item) }
        when Hash
          # Remove both symbol and string embedding keys from hashes
          clean_hash = result_item.dup
          clean_hash.delete(:embedding)
          clean_hash.delete("embedding")
          # Process nested values
          clean_hash.transform_values { |v| strip_embedding(v) }
        else
          result_item
        end
      end

      # Build entity types context using TaxonomyService
      def build_entity_types_context
        entity_types = {}
        @taxonomy_service.entity_types.each do |type|
          entity_definition = @taxonomy_service.taxonomy_for(type)
          entity_types[type] = {
            description: entity_definition["description"] || "No description available",
            properties: @taxonomy_service.properties_for(type)
          }
        end
        entity_types
      end

      # Build relationship types context using TaxonomyService
      def build_relationship_types_context
        relationships = {}
        @taxonomy_service.entity_types.each do |type|
          @taxonomy_service.relationship_types_for(type).each do |rel_name, rel_def|
            relationships[rel_name] = {
              description: rel_def[:description] || "No description available",
              source: type,
              target: Array(rel_def[:to]).join(" or "),
              cardinality: rel_def[:cardinality]
            }
          end
        end
        relationships
      end

      # Format entity types for the prompt
      def format_entity_types(types)
        return "None defined" if types.blank?

        types.map do |type, details|
          desc = details[:description] || details["description"] || "No description available"

          props = if details[:properties] || details["properties"]
                    props_hash = details[:properties] || details["properties"]
                    if props_hash.any?
                      props_hash.map do |k, v|
                        prop_desc = v.is_a?(Hash) ? (v["description"] || v[:description] || "No description") : v.to_s
                        "  - #{k}: #{prop_desc}"
                      end.join("\n")
                    else
                      "  No properties defined"
                    end
                  else
                    "  No properties defined"
                  end

          "#{type}: #{desc}\n#{props}"
        end.join("\n\n")
      end

      # Format relationship types for the prompt
      def format_relationship_types(types)
        return "None defined" if types.blank?

        types.map do |name, details|
          desc = details[:description] || details["description"] || "No description available"
          source = details[:source] || details["source"] || "Unknown source"
          target = details[:target] || details["target"] || "Unknown target"
          cardinality = details[:cardinality] || details["cardinality"] || "many"

          "#{name}: #{desc}\n  Source: #{source} -> Target: #{target} (#{cardinality})"
        end.join("\n\n")
      end

      # Format property types for the prompt
      def format_property_types(types)
        return "None defined" if types.blank?

        types.map do |type, description|
          "#{type}: #{description}"
        end.join("\n")
      end
    end
  end
end
