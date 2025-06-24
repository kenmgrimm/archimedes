# frozen_string_literal: true

module OpenAI
  # Service to generate embeddings for text using OpenAI's embedding models
  class EmbeddingService
    def initialize(client: OpenAIClient, model: "text-embedding-3-small")
      @client = client
      @model = model
    end

    # Generate an embedding for a single text string
    # Returns the embedding as an array of floats
    def embed(text)
      return nil if text.blank?

      Rails.logger.debug { "[OpenAI::EmbeddingService] Generating embedding for text: #{text.truncate(100)}" }

      response = @client.embeddings(
        parameters: {
          model: @model,
          input: text
        }
      )

      embedding = response.dig("data", 0, "embedding")
      Rails.logger.debug { "[OpenAI::EmbeddingService] Generated embedding with #{embedding&.size || 0} dimensions" }

      embedding
    rescue StandardError => e
      Rails.logger.error("[OpenAI::EmbeddingService] Error generating embedding: #{e.message}")
      nil
    end

    # Generate embeddings for multiple texts in batch
    # Returns an array of embeddings
    def embed_batch(texts)
      return [] if texts.blank?

      Rails.logger.debug { "[OpenAI::EmbeddingService] Generating embeddings for #{texts.size} texts" }

      response = @client.embeddings(
        parameters: {
          model: @model,
          input: texts
        }
      )

      embeddings = response["data"].pluck("embedding")
      Rails.logger.debug { "[OpenAI::EmbeddingService] Generated #{embeddings.size} embeddings" }

      embeddings
    rescue StandardError => e
      Rails.logger.error("[OpenAI::EmbeddingService] Error generating batch embeddings: #{e.message}")
      []
    end
  end
end
