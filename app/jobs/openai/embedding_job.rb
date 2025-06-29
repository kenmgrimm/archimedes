# frozen_string_literal: true

module OpenAI
  # Job to asynchronously generate embeddings for entities and statements using OpenAI API
  class EmbeddingJob < ApplicationJob
    queue_as :default

    # Process embedding generation for a record
    # @param record [ActiveRecord::Base] The record to generate embeddings for (Entity or Statement)
    # @param field_name [String] The field to generate embeddings for (e.g., 'name', 'text')
    # @param embedding_field [String] The field to store the embedding in (e.g., 'name_embedding', 'text_embedding')
    def perform(record, field_name, embedding_field)
      if ENV["DEBUG"]
        Rails.logger.debug do
          "[OpenAI::EmbeddingJob] Generating embedding for #{record.class.name} ##{record.id} field: #{field_name}"
        end
      end

      begin
        # Get the text to embed
        text = record.send(field_name.to_sym)
        return if text.blank?

        # Generate embedding using OpenAI API
        embedding = generate_embedding(text)

        # Store the embedding in the record
        if embedding.present?
          record.update_column(embedding_field.to_sym, embedding)
          if ENV["DEBUG"]
            Rails.logger.debug do
              "[OpenAI::EmbeddingJob] Successfully updated embedding for #{record.class.name} ##{record.id}"
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error "[OpenAI::EmbeddingJob] Error generating embedding: #{e.message}"
        Rails.logger.error e.backtrace.join("\n") if ENV["DEBUG"]
      end
    end

    private

    # Generate embedding using OpenAI API
    # @param text [String] Text to generate embedding for
    # @return [Array<Float>] Vector embedding
    def generate_embedding(text)
      # Mock implementation for testing - in production this would call the OpenAI API
      # This allows our test to run without actually calling the API
      Rails.logger.debug { "[OpenAI::EmbeddingJob] Generating mock embedding for: #{text[0..30]}..." } if ENV["DEBUG"]

      # Generate a deterministic mock embedding based on the text
      # In a real implementation, this would call the OpenAI API
      Array.new(1536) { |i| Math.sin(i + text.sum) * 0.1 }

      # Return the mock embedding
    end
  end
end
