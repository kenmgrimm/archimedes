module Neo4j
  module Chat
    class IntentAnalyzer
      def initialize(query, taxonomy_service)
        @query = query
        @taxonomy_service = taxonomy_service
        @logger = Rails.logger
      end

      def analyze
        @logger.debug { "IntentAnalyzer: Starting analysis" }
        @logger.debug { "IntentAnalyzer: Query: #{@query.inspect}" }
        @logger.debug { "IntentAnalyzer: Entity types: #{@taxonomy_service.entity_types.inspect}" }

        # Build comprehensive taxonomy context using TaxonomyService
        entity_types = build_entity_types_context
        relationship_types = build_relationship_types_context
        property_types = @taxonomy_service.property_types

        prompt = <<~PROMPT
          You are analyzing user queries to determine intent for a personal knowledge graph.

          Given this query: "#{@query}"

          # VALID ENTITY TYPES:
          #{format_entity_types(entity_types)}

          # VALID RELATIONSHIPS:
          #{format_relationship_types(relationship_types)}

          # PROPERTY TYPES:
          #{format_property_types(property_types)}

          # QUERY TYPES TO RECOGNIZE:

          ## 1. SEARCH/READ QUERIES:
          Examples: "show me my tasks", "find documents about X", "who owns the house"
          - type: "search" or "relationship_query"
          - action_type: "read"
          - entities: relevant entity types from taxonomy
          - relationships: relevant relationship types

          ## 2. MODIFICATION COMMANDS:
          Format: "<operation> <EntityType> id <id> [property]"
          Examples: "rename Person id 19", "update Task id 12 status", "delete Asset id 45"
          - type: "modify_entity"#{' '}
          - action_type: "modify"
          - target_id: parsed ID
          - operation: "update", "delete", "rename"
          - properties: MUST be valid properties from entity schema

          ## 3. CREATION COMMANDS:
          Examples: "create new task", "add person John Smith"
          - type: "create_entity"
          - action_type: "create"
          - entity_type: valid entity type from taxonomy

          ## 4. RELATIONSHIP QUERIES:
          Examples: "what does John own", "who lives at this address"
          - type: "relationship_query"
          - action_type: "read"
          - relationships: specific relationship types to traverse

          Return JSON with intent analysis:
          {
            "intent": {
              "type": "search|modify_entity|create_entity|relationship_query",
              "description": "Brief description of what user wants",
              "entities": ["EntityType1", "EntityType2"],  # MUST be valid entity types
              "relationships": ["RELATIONSHIP_NAME"],  # MUST be valid relationships#{'  '}
              "target_id": 19,  # Only for modify operations
              "operation": "read|update|delete|create|rename",
              "action_type": "read|modify|create",
              "properties": ["property1"],  # MUST be valid properties for the entity type
              "entity_type": "EntityType",  # Primary entity type for the query
              "filters": {}  # Any search filters or conditions
            },
            "clarification_needed": false,
            "clarification_question": "",
            "suggested_followups": []
          }

          Instructions:
          1. ONLY use entity types, relationships, and properties that exist in the taxonomy above
          2. For search queries, identify which entities and relationships are relevant
          3. For modifications, validate that properties exist for the target entity type
          4. Set clarification_needed: true only if the query is ambiguous
          5. Suggest relevant follow-up questions based on available relationships
        PROMPT

        begin
          response = OpenAI::ClientService.new.extract_structured_data(
            text: prompt,
            prompt_config: {
              system_prompt: "You analyze user queries to determine their intent for a personal knowledge graph."
            }
          )

          @logger.debug { "IntentAnalyzer: Content: #{response.inspect}" }
          raise "Invalid response format" unless response.is_a?(Hash)

          response
        rescue StandardError => e
          @logger.error { "IntentAnalyzer: Error in analysis: #{e.class} - #{e.message}" }
          @logger.error { "IntentAnalyzer: Response was: #{response.inspect}" }
          @logger.error { "IntentAnalyzer: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          raise
        end
      end

      private

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
