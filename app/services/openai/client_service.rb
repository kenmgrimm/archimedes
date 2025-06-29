# frozen_string_literal: true

require "openai"

module OpenAI
  class ClientService
    def initialize(client: OpenAIClient)
      @client = client
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
        max_tokens: max_tokens
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

    private

    def clean_parameters(parameters)
      JSON.parse(
        parameters.to_json.gsub(
          %r{"data:image/jpeg;base64,[^"]+"},
          '"data:image/jpeg;base64,STRIPPED"'
        )
      )
    end
  end
end
