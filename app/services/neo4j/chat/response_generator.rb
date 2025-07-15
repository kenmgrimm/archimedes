module Neo4j
  module Chat
    class ResponseGenerator
      def initialize(intent, query_results, taxonomy)
        @intent = intent
        @query_results = query_results
        @taxonomy = taxonomy
        @logger = Rails.logger
      end

      def generate
        @logger.debug { "ResponseGenerator: Starting response generation" }
        @logger.debug { "ResponseGenerator: Intent: #{Chat::Utils.clean_embeddings(@intent.inspect)}" }
        @logger.debug { "ResponseGenerator: Query results: #{Chat::Utils.clean_embeddings(@query_results.inspect)}" }

        sanitized = sanitize_results(@query_results)
        @logger.debug { "ResponseGenerator: Query results before OpenAI: #{Chat::Utils.clean_embeddings(sanitized.inspect)}" }

        prompt = <<~PROMPT
          Given:
          - User intent: #{@intent.to_json}
          - Query results: #{sanitized.to_json}

          Generate a response based on the user's intent and results:

          For read queries:
          1. Filter and organize relevant relationships
          2. Present them in a clear, structured way
          3. Keep relationship IDs for reference: [ID] EntityName
          4. Suggest relevant follow-up questions

          For write queries:
          1. Clearly state what changed (old value -> new value)
          2. Show the updated data with IDs
          3. Confirm the operation was successful
          4. Suggest relevant follow-up actions

          Return a JSON object:
          {
            "response": "The natural language response",
            "follow_ups": ["Suggested follow-up questions"],
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
    end
  end
end
