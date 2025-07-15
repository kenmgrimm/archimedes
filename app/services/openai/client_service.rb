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
    def extract_structured_data(text:, prompt_config: {}, model: "gpt-4-turbo", temperature: 0.2, max_tokens: 4096)
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
      prompt_config[:examples]&.each do |example|
        messages << { role: "user", content: example[:input] }
        messages << { role: "assistant", content: example[:output].to_json }
      end

      @logger.debug("Sending request to OpenAI API with model: #{model}")

      messages[-1][:content] = "#{messages[-1][:content]}\n\nReturn your response as a JSON object."
      retries = 0
      max_retries = 3

      response = nil
      loop do
        response = @client.chat(
          parameters: {
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: max_tokens,
            response_format: { type: "json_object" }
          }
        )
        break
      rescue OpenAI::RateLimitError => e
        retries += 1
        raise if retries > max_retries

        wait_time = (e.retry_after || 1).to_f
        @logger.info("Rate limited, waiting #{wait_time}s (retry #{retries}/#{max_retries})")
        sleep(wait_time)
      end

      @logger.debug("Received response from OpenAI API")
      @logger.debug("Response: #{response.inspect}")

      # Check for error in response
      if response.is_a?(Hash) && response.key?("error")
        error_msg = response.dig("error", "message") || "Unknown error from OpenAI API"
        @logger.error("OpenAI API error: #{error_msg}")
        raise ExtractionError, "OpenAI API error: #{error_msg}"
      end

      begin
        JSON.parse(response.dig("choices", 0, "message", "content"))
      rescue StandardError => e
        @logger.error("Error in extract_structured_data: #{e.message}")
        raise ExtractionError, "Failed to extract structured data: #{e.message}"
      end
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

      "You are a helpful assistant that extracts structured information from text. Please provide your response in valid JSON format."
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

    # Formatting helpers moved to EntityExtractionService

    def parse_response(response, config)
      content = response.dig("choices", 0, "message", "content")
      @logger.debug("Raw response content: #{content.inspect}")

      if content.blank?
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
