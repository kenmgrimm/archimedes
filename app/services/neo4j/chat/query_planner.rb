module Neo4j
  module Chat
    class QueryPlanner
      def initialize(intent, taxonomy, context: {})
        @intent = intent
        @taxonomy = taxonomy
        @context = context
        @logger = Rails.logger
      end

      def plan_queries
        return [] if @intent["clarification_needed"]

        @logger.debug { "QueryPlanner: Starting query planning" }
        @logger.debug { "QueryPlanner: Intent: #{@intent.inspect}" }
        @logger.debug { "QueryPlanner: Context: #{@context.inspect}" }
        @logger.debug { "QueryPlanner: Taxonomy: #{@taxonomy.keys}" }

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

        prompt = if is_modify
                   # For modifications, return update query directly
                   <<~PROMPT
                     Given this user intent: #{@intent.to_json}

                     Generate a write query based on operation type:

                     For update (when operation = "update"):
                     - Must use valid properties from schema
                     - Use property name as parameter (eg. SET n.name = $name)
                     - Include properties in required_info array
                     Example: MATCH (n:Person) WHERE elementId(n) = $target_id SET n.name = $name RETURN n

                     For delete (when operation = "delete"):
                     - MATCH (n:Person) WHERE elementId(n) = $target_id DETACH DELETE n
                     - Empty required_info array

                     Return ONLY ONE query matching the operation type.

                     IMPORTANT: Include these fields:
                     - write: true
                     - operation: must match intent operation exactly
                     - target_id: from intent
                     - required_info: property names for update, empty for delete
                     - entity_type: include in query (eg. n:Person)
                   PROMPT
                 else
                   # For read operations, use standard relationship query
                   <<~PROMPT
                     Given this user intent: #{@intent.to_json}

                     Plan READ queries to find existing relationships:
                     - Use bi-directional relationship matching:
                       MATCH (user:Person {name: $name})-[r]-(other)
                     - This captures all relationship directions:
                       start->TYPE->end and start<-TYPE<-end

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
        prompt = <<~PROMPT
          Given this user intent: #{@intent.to_json}
          And these read results: #{@context.to_json}

          Plan WRITE queries based on the user's intent and read results:
          For CREATE operations (no results):
          - Create new entities and relationships
          - Include required_info field
          - Let relationship direction convey meaning

          For UPDATE operations (existing data):
          - Use MATCH to find target by ID: MATCH (n) WHERE elementId(n) = id
          - Use SET for updates: SET n.property = value
          - Include required_info for new values
          - Set operation: "update"
          - Base query on the specific ID to modify

          Guidelines:
          - Include relationship_type field
          - Include operation: "create" or "update"
          - Required info should match operation
          - Base updates on specific node/relationship IDs
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
    end
  end
end
