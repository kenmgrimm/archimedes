# frozen_string_literal: true

require "openai"

module OpenAI
  class ClientService
    def initialize(client: OpenAIClient)
      @client = client
    end

    # Example: Chat completion for entity extraction
    def chat(prompt, model: "gpt-4o", temperature: 0.2, max_tokens: 2048)
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
      Rails.logger.debug { "[OpenAI::ClientService] OpenAI raw response: #{response.inspect}" }
      response
    rescue StandardError => e
      Rails.logger.error("[OpenAI::ClientService] OpenAI API error: #{e.class} - #{e.message}")
      raise
    end
  end
end
