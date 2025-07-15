module Neo4j
  module Chat
    class IntentAnalyzer
      def initialize(query, taxonomy)
        @query = query
        @taxonomy = taxonomy
        @logger = Rails.logger
      end

      def analyze
        @logger.debug { "IntentAnalyzer: Starting analysis" }
        @logger.debug { "IntentAnalyzer: Query: #{@query.inspect}" }
        @logger.debug { "IntentAnalyzer: Taxonomy keys: #{@taxonomy.keys.inspect}" }
        @logger.debug { "IntentAnalyzer: Person data: #{@taxonomy['Person'].inspect}" }

        person_relations = @taxonomy["Person"]["relations"].transform_values { |v| v["description"] }
        @logger.debug { "IntentAnalyzer: Person relations: #{person_relations.inspect}" }

        prompt = <<~PROMPT
          Given this query: "#{@query}"

          Available Person relationships:
          #{person_relations.map { |name, desc| "- #{name}: #{desc}" }.join("\n")}

          Other major entities: #{(@taxonomy.keys - ['Person', 'property_types']).join(', ')}

          # IMPORTANT: Parse command format for entity modifications:
          # Format: "<operation> <type> id <id>"
          # Examples:
          # - "rename Person id 19"
          # - "update Person id 12 phone"
          # - "delete Task id 45"

          After parsing command:
          1. Set type to "modify_entity" or "modify_relationship"
          2. Set action_type to "modify"
          3. Include target_id from parsed ID
          4. Set operation to the action (rename, update, delete)
          5. Set properties based on what's being modified

          Available Person properties:
          #{@taxonomy["Person"]["properties"].transform_values { |v| v["description"] }.to_json}

          Return JSON with intent analysis:
          {
            "intent": {
              "type": "modify_entity",  # For modifications
              "description": "Brief description",
              "entities": ["Person"],
              "target_id": 19,  # Parsed ID from command
              "operation": "update",  # Command type
              "action_type": "modify",  # Always modify for these commands
              "properties": ["name"],  # Properties to change, MUST be valid properties
              "schema": "Person"  # Entity type for property validation
            },
            "clarification_needed": false,
            "clarification_question": "",
            "suggested_followups": []
          }

          Instructions:
          1. Use all appropriate relationship types to build a complete picture
          2. Only set clarification_needed: true if you cannot determine which relationships to include
          3. Keep clarification_question empty unless clarification is needed
          4. Include all relevant properties that should be returned
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
    end
  end
end
