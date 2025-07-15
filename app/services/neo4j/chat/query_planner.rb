module Neo4j
  module Chat
    class QueryPlanner
      def initialize(intent, taxonomy_service, context: {})
        @intent = intent
        @taxonomy_service = taxonomy_service
        @context = context
        @logger = Rails.logger
      end

      def plan_queries
        return [] if @intent["clarification_needed"]

        @logger.debug { "QueryPlanner: Starting query planning" }
        @logger.debug { "QueryPlanner: Intent: #{@intent.inspect}" }
        @logger.debug { "QueryPlanner: Context: #{@context.inspect}" }
        @logger.debug { "QueryPlanner: Entity types: #{@taxonomy_service.entity_types}" }

        if @intent["type"] == "error"
          @logger.debug { "QueryPlanner: Error intent, returning empty plan" }
          return []
        end

        # First plan read queries
        read_queries = plan_read_phase

        # Then plan write queries if needed
        write_queries = plan_write_phase if @intent["action_type"] == "modify"

        # Combine both phases
        [read_queries, write_queries].flatten.compact
      end

      private

      def plan_read_phase
        intent_type = @intent["intent"]["type"]
        is_modify = intent_type&.start_with?("modify_")

        # Build taxonomy context for the LLM
        entity_types = build_entity_types_context
        relationship_types = build_relationship_types_context
        property_types = @taxonomy_service.property_types

        prompt = if is_modify
                   # For modifications, return update query directly
                   <<~PROMPT
                     You are planning Cypher queries for a personal knowledge graph.

                     Given this user intent: #{@intent.to_json}

                     # VALID ENTITY TYPES:
                     #{format_entity_types(entity_types)}

                     # VALID RELATIONSHIPS:
                     #{format_relationship_types(relationship_types)}

                     # PROPERTY TYPES:
                     #{format_property_types(property_types)}

                     Generate a write query based on operation type:

                     For update (when operation = "update"):
                     - MUST use ONLY valid properties from the entity schema above
                     - Use property name as parameter (eg. SET n.name = $name)
                     - Include properties in required_info array
                     - Validate that the property exists for the target entity type
                     Example: MATCH (n:Person) WHERE elementId(n) = $target_id SET n.name = $name RETURN n

                     For delete (when operation = "delete"):
                     - MATCH (n:EntityType) WHERE elementId(n) = $target_id DETACH DELETE n
                     - Empty required_info array
                     - Use correct entity type from schema

                     Return ONLY ONE query matching the operation type.

                     IMPORTANT: Include these fields:
                     - write: true
                     - operation: must match intent operation exactly
                     - target_id: from intent
                     - required_info: property names for update (MUST be valid properties), empty for delete
                     - entity_type: MUST be valid entity type from schema above
                   PROMPT
                 else
                   # For read operations, use standard relationship query
                   <<~PROMPT
                     You are planning Cypher queries for a personal knowledge graph.

                     Given this user intent: #{@intent.to_json}

                     # VALID ENTITY TYPES:
                     #{format_entity_types(entity_types)}

                     # VALID RELATIONSHIPS:
                     #{format_relationship_types(relationship_types)}

                     # PROPERTY TYPES:
                     #{format_property_types(property_types)}

                     Plan READ queries to find existing relationships:
                     - Use bi-directional relationship matching for comprehensive results
                     - ONLY use entity types and relationships that exist in the schema above
                     - Example pattern: MATCH (user:Person {name: $name})-[r:VALID_RELATIONSHIP]-(other:ValidEntityType)

                     Query Guidelines:
                     1. Use ONLY entity types from the schema above
                     2. Use ONLY relationship types from the schema above#{'  '}
                     3. Include appropriate WHERE clauses for filtering
                     4. Use parameters for user input ($name, etc.)

                     IMPORTANT: Return format must be:
                     MATCH ... RETURN DISTINCT
                       type(r) AS `type(r)`,
                       startNode(r) AS `startNode(r)`,
                       endNode(r) AS `endNode(r)`,
                       elementId(r) AS `id(r)`
                   PROMPT
                 end

        plan_phase(prompt)
      end

      def plan_write_phase
        # Build taxonomy context for the LLM
        entity_types = build_entity_types_context
        relationship_types = build_relationship_types_context
        property_types = @taxonomy_service.property_types

        prompt = <<~PROMPT
          You are planning write Cypher queries for a personal knowledge graph.

          Given this user intent: #{@intent.to_json}
          And these read results: #{@context.to_json}

          # VALID ENTITY TYPES:
          #{format_entity_types(entity_types)}

          # VALID RELATIONSHIPS:
          #{format_relationship_types(relationship_types)}

          # PROPERTY TYPES:
          #{format_property_types(property_types)}

          Plan WRITE queries based on the user's intent and read results:

          For CREATE operations (no existing results):
          - Create new entities using ONLY valid entity types from schema above
          - Create relationships using ONLY valid relationship types from schema above
          - Use ONLY valid properties from the entity schema
          - Include required_info field with property names that need user input
          - Example: CREATE (n:Person {name: $name}) RETURN n

          For UPDATE operations (existing data found):
          - Use MATCH to find target by ID: MATCH (n:EntityType) WHERE elementId(n) = $target_id
          - Use SET for updates with ONLY valid properties: SET n.validProperty = $validProperty
          - Include required_info for properties that need new values
          - Set operation: "update"
          - Validate entity type and properties against schema

          Guidelines:
          1. ONLY use entity types, relationships, and properties from the schema above
          2. Include relationship_type field for relationship operations
          3. Include operation: "create", "update", or "delete"
          4. Required info should match operation and use valid property names
          5. Base updates on specific node/relationship IDs
          6. Validate all schema elements before including in queries
        PROMPT

        plan_phase(prompt)
      end

      def plan_phase(prompt)
        prompt += <<~STRUCTURE
          Return your response as a JSON object with this structure:
          {
            "queries": [
              {
                "query": "The Cypher query to execute",
                "description": "What this query will find/create",
                "write": boolean,  # true for write operations
                "operation": "create|update",  # only for write queries
                "required_info": ["field1", "field2"],  # for write queries
                "relationship_type": "TYPE",  # the relationship being queried/created
                "next_steps": {
                  "if_empty": "What information is missing",
                  "if_results": "What we learned/changed"
                }
              }
            ]
          }
        STRUCTURE

        begin
          content = OpenAI::ClientService.new.extract_structured_data(
            text: prompt,
            prompt_config: {
              system_prompt: "You plan Cypher queries to fulfill user intents in a knowledge graph."
            }
          )

          @logger.debug { "QueryPlanner: Content: #{content.inspect}" }
          raise "Invalid response format" unless content.is_a?(Hash)

          content["queries"] || []
        rescue StandardError => e
          @logger.error { "QueryPlanner: Error: #{e.class} - #{e.message}" }
          @logger.error { "QueryPlanner: Content was: #{content}" }
          @logger.error { "QueryPlanner: Backtrace:\n#{e.backtrace[0..5].join("\n")}" }
          raise
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
