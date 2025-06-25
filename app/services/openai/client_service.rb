# frozen_string_literal: true

require "openai"

module OpenAI
  class ClientService
    def initialize(client: OpenAIClient)
      @client = client
    end

    # Example: Chat completion for entity extraction
    def chat(prompt, model: "gpt-4o", temperature: 0.2, max_tokens: 2048)
      # Generate a unique request ID for tracking
      request_id = SecureRandom.uuid

      # Log truncated prompt to regular Rails logger
      Rails.logger.debug { "[OpenAI::ClientService] Sending chat prompt: #{prompt.truncate(120)} (request_id: #{request_id})" }

      # Log detailed request to dedicated OpenAI logger
      OpenAI.logger.info("REQUEST #{request_id}")
      OpenAI.logger.debug({
                            request_type: "chat",
                            request_id: request_id,
                            model: model,
                            temperature: temperature,
                            max_tokens: max_tokens,
                            system_message: "You are an AI assistant that extracts structured entities from user content.",
                            user_message: prompt
                          })

      # Make the API call
      response = @client.chat(
        parameters: {
          model: model,
          messages: [
            { role: "system", content: "You are an AI assistant that extracts structured entities from user content." },
            { role: "user", content: prompt }
          ],
          temperature: temperature,
          max_tokens: max_tokens
        }
      )

      # Log response metadata to regular Rails logger
      response_info = {
        id: response["id"],
        model: response["model"],
        usage: response["usage"],
        choices_count: response["choices"]&.size
      }
      Rails.logger.debug { "[OpenAI::ClientService] OpenAI response received: #{response_info.inspect} (request_id: #{request_id})" }

      # Log detailed response to dedicated OpenAI logger
      OpenAI.logger.info("RESPONSE #{request_id}")
      OpenAI.logger.debug({
                            request_id: request_id,
                            response_id: response["id"],
                            model: response["model"],
                            usage: response["usage"],
                            content: response["choices"].first["message"]["content"],
                            finish_reason: response["choices"].first["finish_reason"]
                          })

      response
    rescue StandardError => e
      # Log error to both loggers
      error_message = "[OpenAI::ClientService] OpenAI API error: #{e.class} - #{e.message}"
      Rails.logger.error(error_message)

      OpenAI.logger.error("ERROR #{request_id}")
      OpenAI.logger.error({
                            request_id: request_id,
                            error_class: e.class.to_s,
                            error_message: e.message,
                            backtrace: e.backtrace.first(5)
                          })

      raise
    end

    # Vision/multimodal: Accepts a note and one or more image files
    # files: array of { filename:, io: File/IO or StringIO, or :data => binary string }
    def chat_with_files(note:, files:, model: "gpt-4o", temperature: 0.2, max_tokens: 2048)
      # Generate a unique request ID for tracking
      request_id = SecureRandom.uuid

      user_content = []
      user_content << { type: "text", text: note } if note.present?

      files.each do |file|
        image_data = if file[:io]
                       Base64.strict_encode64(file[:io].read)
                     elsif file[:data]
                       Base64.strict_encode64(file[:data])
                     else
                       raise ArgumentError, "File must have :io or :data"
                     end
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
          { role: "system", content: "You are an AI assistant that extracts structured entities from user content." },
          { role: "user", content: user_content }
        ],
        temperature: temperature,
        max_tokens: max_tokens
      }

      OpenAI.logger.debug(clean_parameters(parameters))

      # Make the API call
      response = @client.chat(parameters: parameters)

      # Log response metadata to regular Rails logger
      response_info = {
        id: response["id"],
        model: response["model"],
        usage: response["usage"],
        choices_count: response["choices"]&.size
      }
      Rails.logger.debug { "[OpenAI::ClientService] OpenAI multimodal response received: #{response_info.inspect} (request_id: #{request_id})" }

      # Log detailed response to dedicated OpenAI logger
      OpenAI.logger.info("RESPONSE #{request_id} (MULTIMODAL)")
      OpenAI.logger.debug(
        {
          request_id: request_id,
          response_id: response["id"],
          model: response["model"],
          usage: response["usage"],
          content: response["choices"].first["message"]["content"],
          finish_reason: response["choices"].first["finish_reason"]
        }
      )

      response
    rescue StandardError => e
      # Log error to both loggers
      error_message = "[OpenAI::ClientService] OpenAI API error (multimodal): #{e.class} - #{e.message}"
      Rails.logger.error(error_message)

      OpenAI.logger.error("ERROR #{request_id} (MULTIMODAL)")
      OpenAI.logger.error({
                            request_id: request_id,
                            error_class: e.class.to_s,
                            error_message: e.message,
                            backtrace: e.backtrace.first(5)
                          })

      raise
    end

    private

    # Clean parameters for logging by removing large base64 image data
    # @param parameters [Hash] The parameters to clean
    # @return [Hash] A copy of the parameters with base64 image data stripped
    def clean_parameters(parameters)
      # Create a deep copy to avoid modifying the original
      cleaned = Marshal.load(Marshal.dump(parameters))
      
      # Process the messages array if it exists
      if cleaned[:messages].is_a?(Array)
        cleaned[:messages].each do |message|
          # Process user content which might contain image data
          if message[:role] == "user" && message[:content].is_a?(Array)
            message[:content].each do |content_item|
              # Replace base64 image data with a placeholder
              if content_item.is_a?(Hash) && content_item[:image_url].is_a?(Hash) && content_item[:image_url][:url].is_a?(String)
                url = content_item[:image_url][:url]
                if url.match?(/data:image\/[^;]+;base64,/)
                  mime_type = url.match(/data:image\/([^;]+);base64,/)[1]
                  content_item[:image_url][:url] = "data:image/#{mime_type};base64,STRIPPED"
                end
              end
            end
          end
        end
      end
      
      cleaned
    end
  end
end
