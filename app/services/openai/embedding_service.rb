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
      generate_embedding(text)
    end

    # Alias for embed to maintain backward compatibility
    # @param text [String] The text to generate an embedding for
    # @return [Array<Float>, nil] The embedding vector or nil if generation failed
    def generate_embedding(text)
      return nil if text.blank?

      # Generate a unique request ID for tracking
      request_id = SecureRandom.uuid

      # Log to regular Rails logger
      Rails.logger.debug { "[OpenAI::EmbeddingService] Generating embedding for text: #{text.truncate(100)} (request_id: #{request_id})" }

      # Log detailed request to dedicated OpenAI logger
      OpenAI.logger.info("REQUEST #{request_id} (EMBEDDING)")
      OpenAI.logger.debug({
                            request_type: "embedding",
                            request_id: request_id,
                            model: @model,
                            text_length: text.length,
                            text_preview: text.truncate(200)
                          })

      # Make the API call
      response = @client.embeddings(
        parameters: {
          model: @model,
          input: text
        }
      )

      embedding = response.dig("data", 0, "embedding")

      # Log to regular Rails logger
      Rails.logger.debug { "[OpenAI::EmbeddingService] Generated embedding with #{embedding&.size || 0} dimensions (request_id: #{request_id})" }

      # Log detailed response to dedicated OpenAI logger
      OpenAI.logger.info("RESPONSE #{request_id} (EMBEDDING)")
      OpenAI.logger.debug({
                            request_id: request_id,
                            model: response["model"],
                            usage: response["usage"],
                            embedding_dimensions: embedding&.size || 0,
                            # Include first few dimensions as a sample
                            embedding_sample: embedding&.first(5)&.map { |v| v.round(4) }
                          })

      embedding
    rescue StandardError => e
      # Log error to both loggers
      error_message = "[OpenAI::EmbeddingService] Error generating embedding: #{e.message}"
      Rails.logger.error(error_message)

      OpenAI.logger.error("ERROR #{request_id} (EMBEDDING)")
      OpenAI.logger.error({
                            request_id: request_id,
                            error_class: e.class.to_s,
                            error_message: e.message,
                            backtrace: e.backtrace.first(5)
                          })

      nil
    end

    # Generate embeddings for multiple texts in batch
    # Returns an array of embeddings
    def embed_batch(texts)
      return [] if texts.blank?

      # Generate a unique request ID for tracking
      request_id = SecureRandom.uuid

      # Log to regular Rails logger
      Rails.logger.debug { "[OpenAI::EmbeddingService] Generating embeddings for #{texts.size} texts (request_id: #{request_id})" }

      # Log detailed request to dedicated OpenAI logger
      OpenAI.logger.info("REQUEST #{request_id} (BATCH_EMBEDDING)")
      OpenAI.logger.debug({
                            request_type: "batch_embedding",
                            request_id: request_id,
                            model: @model,
                            batch_size: texts.size,
                            text_samples: texts.first(2).map { |t| t.truncate(100) },
                            text_lengths: texts.map(&:length).first(5)
                          })

      # Make the API call
      response = @client.embeddings(
        parameters: {
          model: @model,
          input: texts
        }
      )

      embeddings = response["data"].pluck("embedding")

      # Log to regular Rails logger
      Rails.logger.debug { "[OpenAI::EmbeddingService] Generated #{embeddings.size} embeddings (request_id: #{request_id})" }

      # Log detailed response to dedicated OpenAI logger
      OpenAI.logger.info("RESPONSE #{request_id} (BATCH_EMBEDDING)")
      OpenAI.logger.debug({
                            request_id: request_id,
                            model: response["model"],
                            usage: response["usage"],
                            embeddings_count: embeddings.size,
                            embedding_dimensions: embeddings.first&.size || 0,
                            # Include first few dimensions of first embedding as a sample
                            first_embedding_sample: embeddings.first&.first(5)&.map { |v| v.round(4) }
                          })

      embeddings
    rescue StandardError => e
      # Log error to both loggers
      error_message = "[OpenAI::EmbeddingService] Error generating batch embeddings: #{e.message}"
      Rails.logger.error(error_message)

      OpenAI.logger.error("ERROR #{request_id} (BATCH_EMBEDDING)")
      OpenAI.logger.error({
                            request_id: request_id,
                            error_class: e.class.to_s,
                            error_message: e.message,
                            backtrace: e.backtrace.first(5)
                          })

      []
    end
  end
end
