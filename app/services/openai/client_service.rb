# frozen_string_literal: true

require "openai"

module OpenAI
  class ClientService
    def initialize(client: OpenAIClient)
      @client = client
    end

    # Example: Chat completion for entity extraction
    def chat(prompt, model: "gpt-4o", temperature: 0.2, max_tokens: 2048)
      # Log truncated prompt to avoid sensitive data in logs
      Rails.logger.debug { "[OpenAI::ClientService] Sending chat prompt: #{prompt.truncate(120)}" }

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

      # Log response metadata without including potentially large content
      response_info = {
        id: response["id"],
        model: response["model"],
        usage: response["usage"],
        choices_count: response["choices"]&.size
      }
      Rails.logger.debug { "[OpenAI::ClientService] OpenAI response received: #{response_info.inspect}" }
      response
    rescue StandardError => e
      Rails.logger.error("[OpenAI::ClientService] OpenAI API error: #{e.class} - #{e.message}")
      raise
    end

    # Vision/multimodal: Accepts a note and one or more image files
    # files: array of { filename:, io: File/IO or StringIO, or :data => binary string }
    def chat_with_files(note:, files:, model: "gpt-4o", temperature: 0.2, max_tokens: 2048)
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
      # Log without including binary data
      file_info = files.map { |f| "#{f[:filename]} (#{File.extname(f[:filename]).delete('.').downcase})" }
      Rails.logger.debug { "[OpenAI::ClientService] Sending multimodal prompt with note and #{files.size} file(s): #{file_info.join(', ')}" }

      response = @client.chat(
        parameters: {
          model: model,
          messages: [
            { role: "system", content: "You are an AI assistant that extracts structured entities from user content." },
            { role: "user", content: user_content }
          ],
          temperature: temperature,
          max_tokens: max_tokens
        }
      )

      # Log response without including potentially large content
      response_info = {
        id: response["id"],
        model: response["model"],
        usage: response["usage"],
        choices_count: response["choices"]&.size
      }
      Rails.logger.debug { "[OpenAI::ClientService] OpenAI multimodal response received: #{response_info.inspect}" }
      response
    rescue StandardError => e
      Rails.logger.error("[OpenAI::ClientService] OpenAI API error (multimodal): #{e.class} - #{e.message}")
      raise
    end
  end
end
