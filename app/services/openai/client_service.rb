# frozen_string_literal: true

require "openai"

module OpenAI
  class ClientService
    class ExtractionError < StandardError; end

    # Initialize the OpenAI client service
    # @param client [Object] The OpenAI client instance (defaults to OpenAIClient)
    # @param logger [Logger] Optional logger (defaults to Rails.logger)
    def initialize(client: OpenAIClient, logger: nil)
      @client = client
      @logger = logger || Rails.logger
    end

    # Vision/multimodal: Accepts a note and one or more image files
    # files: array of { filename:, data: binary }
    def chat_with_files(prompt:, files:, model: "gpt-4o", temperature: 0.5, max_tokens: 2048)
      # Generate a unique request ID for tracking
      request_id = SecureRandom.uuid

      user_content = []
      user_content << { type: "text", text: prompt }

      files.each do |file|
        image_data = Base64.strict_encode64(file[:data])
        ext = File.extname(file[:filename]).delete(".").downcase
        mime = ext == "jpg" ? "jpeg" : ext
        user_content << {
          type: "image_url",
          image_url: { url: "data:image/#{mime};base64,#{image_data}" }
        }
      end

      # Log without including binary data for regular Rails logger
      file_info = files.map { |f| "#{f[:filename]} (#{File.extname(f[:filename]).delete('.')})" }
      Rails.logger.debug { "[OpenAI::ClientService] Sending multimodal prompt with note and #{files.size} file(s): #{file_info.join(', ')} (request_id: #{request_id})" }

      # Log detailed request to dedicated OpenAI logger (without binary data)
      OpenAI.logger.info("REQUEST #{request_id} (MULTIMODAL)")
      parameters = {
        model: model,
        messages: [
          # { role: "system", content: "You are an AI assistant that extracts structured entities from user content." },
          { role: "user", content: user_content }
        ],
        temperature: temperature,
        max_tokens: max_tokens,
        response_format: { type: "json_object" }
      }

      OpenAI.logger.debug(clean_parameters(parameters))

      # Make the API call
      response = @client.chat(parameters: parameters)

      # Log detailed response to dedicated OpenAI logger
      OpenAI.logger.info("RESPONSE #{request_id} (MULTIMODAL)")
      OpenAI.logger.debug(response)

      response
    rescue StandardError => e
      Rails.logger.error("[OpenAI::ClientService] OpenAI API error (multimodal): #{e.class} - #{e.message}")

      OpenAI.logger.error("ERROR #{request_id} (MULTIMODAL)")
      OpenAI.logger.error({
                            error_class: e.class.to_s,
                            error_message: e.message,
                            backtrace: e.backtrace.first(5)
                          })

      raise
    end

    # Make the method public since it's part of our public API
    # private

    def clean_parameters(parameters)
      # Remove binary data from logs
      parameters.merge(
        messages: parameters[:messages].map do |msg|
          if msg[:content].is_a?(Array)
            msg.merge(content: msg[:content].map { |c| c[:type] == "image_url" ? { type: "image_url", image_url: "..." } : c })
          else
            msg
          end
        end
      )
    end

    # Extracts structured data from text using a configurable prompt
    # @param text [String] The text to analyze
    # @param prompt_config [Hash] Configuration for the extraction prompt
    # @option prompt_config [String] :system_prompt The base system prompt
    # @option prompt_config [Hash] :taxonomy Taxonomy configuration (optional)
    # @option prompt_config [String] :response_format Expected response format instructions
    # @option prompt_config [Array<Hash>] :examples Example inputs and outputs
    # @param model [String] Model to use
    # @param temperature [Float] Controls randomness (0.0 to 1.0)
    # @param max_tokens [Integer] Maximum number of tokens to generate
    # @return [Hash] Structured extraction result
    def extract_structured_data(text:, prompt_config: {}, model: "gpt-4-turbo", temperature: 0.2, max_tokens: 2048)
      prompt_config = prompt_config.dup

      # Build the system prompt
      system_prompt = build_system_prompt(prompt_config)
      user_prompt = build_user_prompt(text, prompt_config)

      @logger.debug("System prompt: #{system_prompt}")
      @logger.debug("User prompt: #{user_prompt}")

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ]

      # Add examples if provided
      if prompt_config[:examples]
        prompt_config[:examples].each do |example|
          messages << { role: "user", content: example[:input] }
          messages << { role: "assistant", content: example[:output].to_json }
        end
      end

      @logger.debug("Sending request to OpenAI API with model: #{model}")
      begin
        response = @client.chat(
          parameters: {
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: max_tokens,
            response_format: { type: "json_object" }
          }
        )

        @logger.debug("Received response from OpenAI API")
        @logger.debug("Response: #{response.inspect}")

        # Check for error in response
        if response.is_a?(Hash) && response.key?("error")
          error_msg = response.dig("error", "message") || "Unknown error from OpenAI API"
          @logger.error("OpenAI API error: #{error_msg}")
          raise ExtractionError, "OpenAI API error: #{error_msg}"
        end

        response
      rescue StandardError => e
        @logger.error("OpenAI API request failed: #{e.message}")
        @logger.error(e.backtrace.join("\n")) if e.backtrace
        raise ExtractionError, "OpenAI API request failed: #{e.message}"
      end

      parse_response(response, prompt_config)
    rescue StandardError => e
      @logger.error("Error in extract_structured_data: #{e.message}")
      raise ExtractionError, "Failed to extract structured data: #{e.message}"
    end

    # Alias for backward compatibility
    def extract_entities_with_taxonomy(text:, taxonomy: {}, **options)
      prompt_config = {
        taxonomy: taxonomy,
        response_format: :neo4j_extraction
      }.merge(options)

      extract_structured_data(text: text, prompt_config: prompt_config)
    end

    private

    def build_system_prompt(config)
      return config[:system_prompt] if config[:system_prompt]

      if config[:response_format] == :neo4j_extraction
        # Add 'json' to the prompt to satisfy OpenAI's requirement when using response_format: { type: 'json_object' }
        build_neo4j_extraction_prompt(config[:taxonomy] || {}) + "\n\nPlease provide your response in valid JSON format."
      else
        "You are a helpful assistant that extracts structured information from text. Please provide your response in valid JSON format."
      end
    end

    def build_user_prompt(text, config)
      case config[:response_format]
      when :neo4j_extraction
        <<~PROMPT
          Extract entities and relationships from the following text, following the taxonomy and format instructions.

          IMPORTANT: Your response MUST be a valid JSON object with the exact structure shown in the system prompt.
          Do not include any markdown formatting, code blocks, or additional text outside the JSON object.

          Text to analyze:
          #{text}

          Respond with ONLY a JSON object containing 'entities' and 'relationships' arrays as shown in the format example.
        PROMPT
      else
        text
      end
    end

    def build_neo4j_extraction_prompt(taxonomy)
      entity_types = taxonomy[:entity_types] || {}
      relationship_types = taxonomy[:relationship_types] || {}

      <<~PROMPT
        You are an AI assistant that extracts structured information from text to build a knowledge graph in Neo4j.
        You MUST respond with a valid JSON object containing the extracted entities and relationships.

        # Available Entity Types:
        #{format_entity_types(entity_types)}

        # Available Relationship Types:
        #{format_relationship_types(relationship_types)}

        # Instructions:
        1. Extract entities and relationships using ONLY the types defined above
        2. If you encounter something that doesn't fit the taxonomy:
           - For entities: Use the most specific available type and add "suggested_type": "preferred_type"
           - For relationships: Use the closest match and add "suggested_relationship": "preferred_relationship"
        3. For properties, only use those defined for each entity type

        # Required Response Format:
        {
          "entities": [
            {
              "type": "EntityType",
              "name": "Entity Name",
              "properties": {
                // Entity properties as key-value pairs
              },
              "confidence": 0.0,  // Confidence score (0.0 to 1.0)
              "source_text": "Original text from which this entity was extracted"
            }
          ],
          "relationships": [
            {
              "type": "RelationshipType",
              "source": "Source Entity Name",
              "target": "Target Entity Name",
              "properties": {
                // Relationship properties as key-value pairs
              },
              "confidence": 0.0,  // Confidence score (0.0 to 1.0)
              "source_text": "Original text from which this relationship was extracted"
            }
          ]
        }
        4. If an important concept has no good match, include it in the "suggestions" section

        # Output Format:
        {
          "entities": [
            {
              "type": "EntityType",  // Must be from the list above
              "name": "Entity Name", // Human-readable name
              "description": "Brief description",
              "properties": {        // Only use properties defined for this entity type
                "property1": "value1"
              },
              "suggested_type": "PreferredType",  // Only if no good match exists
              "suggested_properties": {           // Properties not in the schema
                "new_property": "value"
              },
              "confidence": 0.0-1.0,
              "source_text": "exact text reference"
            }
          ],
          "relationships": [
            {
              "type": "RelationshipType",  // Must be from the list above
              "source": "source_entity_name",
              "target": "target_entity_name",
              "properties": {},
              "suggested_relationship": "PreferredRelationship", // If no good match
              "confidence": 0.0-1.0,
              "source_text": "exact text reference"
            }
          ],
          "suggestions": {
            "new_entity_types": [
              {
                "name": "NewType",
                "description": "Description of when to use this type",
                "example": "Example usage"
              }
            ],
            "new_relationship_types": [
              {
                "name": "NEW_RELATIONSHIP",
                "description": "When to use this relationship",
                "from": ["EntityType1", "EntityType2"],
                "to": ["EntityType3", "EntityType4"]
              }
            ],
            "new_properties": [
              {
                "entity_type": "EntityType",
                "property": "new_property",
                "type": "Text|Number|Date|etc",
                "description": "What this property represents"
              }
            ]
          }
        }
      PROMPT
    end

    def format_entity_types(types)
      return "Any (but please suggest specific types)" if types.empty?

      types.map { |t| "- #{t}" }.join("\n")
    end

    def format_relationship_types(types)
      return "Any" if types.empty?

      types.map do |name, details|
        "- #{name}: #{details[:description]} (from: #{details[:source]}, to: #{details[:target]})"
      end.join("\n")
    end

    def parse_response(response, config)
      content = response.dig("choices", 0, "message", "content")
      @logger.debug("Raw response content: #{content.inspect}")

      if content.nil? || content.empty?
        @logger.error("Empty or nil content in OpenAI response")
        raise ExtractionError, "Empty response from OpenAI API"
      end

      begin
        result = JSON.parse(content)
      rescue JSON::ParserError => e
        @logger.error("Failed to parse OpenAI response: #{e.message}")
        @logger.error("Content that failed to parse: #{content.inspect}")
        raise ExtractionError, "Failed to parse response from OpenAI: #{e.message}"
      end

      case config[:response_format]
      when :neo4j_extraction
        parse_neo4j_extraction(result)
      else
        result
      end
    rescue JSON::ParserError => e
      @logger.error("Failed to parse response: #{e.message}")
      raise ExtractionError, "Failed to parse response: #{e.message}"
    end

    def parse_neo4j_extraction(result)
      {
        valid: {
          entities: result["entities"]&.reject { |e| e.key?("suggested_type") } || [],
          relationships: result["relationships"]&.reject { |r| r.key?("suggested_relationship") } || []
        },
        suggested: {
          entities: result["entities"]&.select { |e| e.key?("suggested_type") } || [],
          relationships: result["relationships"]&.select { |r| r.key?("suggested_relationship") } || [],
          new_types: result.dig("suggestions", "new_entity_types") || [],
          new_relationships: result.dig("suggestions", "new_relationship_types") || [],
          new_properties: result.dig("suggestions", "new_properties") || []
        }
      }
    end
  end
end
