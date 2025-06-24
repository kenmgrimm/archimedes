class Content < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  has_many_attached :files
  has_many :entities, dependent: :destroy

  validate :note_or_file_present
  before_save :generate_embedding
  after_save :log_file_attachments

  # Find similar content by vector similarity
  # Returns content with notes similar to the query text
  # @param query_text [String] The text to find similar content for
  # @param limit [Integer] Maximum number of results to return
  # @param threshold [Float] Similarity threshold (lower = more similar)
  # @return [ActiveRecord::Relation] Collection of similar content
  def self.find_similar(query_text, limit: 10, threshold: 0.8)
    return none if query_text.blank?

    Rails.logger.debug { "[Content] Finding content similar to: #{query_text}" }

    # Generate embedding for query text
    embedding_service = OpenAI::EmbeddingService.new
    query_embedding = embedding_service.embed(query_text)
    return none if query_embedding.nil?

    # Calculate distance and filter by threshold
    # Lower distance = more similar
    # Use a direct ordering by the calculation expression instead of by the alias
    # This avoids the PostgreSQL error when trying to order by an alias created in the same query
    distance_calc = "(note_embedding <=> '#{query_embedding}')"

    Rails.logger.debug { "[Content] Vector similarity query with distance calculation: #{distance_calc}" }

    # Debug logging for query construction
    Rails.logger.debug { "[Content] Building vector similarity query" }

    # Start with a base query and chain methods
    results = where.not(note_embedding: nil)
                   .select("*, #{distance_calc} AS similarity_distance")
                   .where("#{distance_calc} < ?", threshold)
                   .order(Arel.sql(distance_calc))
                   .limit(limit)

    # Safely log the SQL query if the results object supports to_sql
    if results.respond_to?(:to_sql)
      Rails.logger.debug { "[Content] Vector similarity query SQL: #{results.to_sql}" }
    else
      Rails.logger.debug { "[Content] Vector similarity query returned #{results.size} results" }
    end

    # Set the similarity attribute for each result from the similarity_distance
    results.each do |content|
      content.similarity = content.attributes["similarity_distance"]
    end

    Rails.logger.debug { "[Content] Found #{results.size} similar content items" }
    results
  end

  private

  def note_or_file_present
    return unless note.blank? && !files.attached?

    errors.add(:base, "You must provide a note or attach at least one file.")
  end

  def log_file_attachments
    Rails.logger.debug do
      "[Content] Saved content ##{id} with #{files.attachments.size} attached file(s). Note: '#{note&.truncate(40)}'"
    end
  end

  # Generate embedding for the content note
  # Only generates if note is present and has changed
  def generate_embedding
    return if note.blank? || !note_changed?

    Rails.logger.debug { "[Content] Generating embedding for note: #{note.truncate(50)}" }

    begin
      embedding_service = OpenAI::EmbeddingService.new
      embedding_array = embedding_service.embed(note)

      # Format the embedding array as a PostgreSQL vector string
      # The format should be '[n1,n2,n3,...]' for pgvector
      if embedding_array.present?
        self.note_embedding = ActiveRecord::Base.connection.quote_string(embedding_array.to_s)
        Rails.logger.debug { "[Content] Successfully generated embedding with #{embedding_array.size} dimensions" }
      else
        Rails.logger.warn { "[Content] Failed to generate embedding for note" }
      end
    rescue StandardError => e
      Rails.logger.error { "[Content] Error generating embedding: #{e.message}\n#{e.backtrace.join('\n')}" }
      # Don't fail the save if embedding generation fails
    end
  end
end
