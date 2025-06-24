# frozen_string_literal: true

# Content model for V2 data architecture
# Represents a piece of content with notes, files, entities, and statements
class Content < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  # Associations
  has_many_attached :files
  has_many :entities, dependent: :destroy
  has_many :statements, dependent: :destroy

  validate :note_or_file_present
  before_save :generate_embedding
  after_save :log_file_attachments
  
  # V2 Data Model helper methods
  
  # Extract entities and statements from analysis results
  # @param analysis_result [Hash] The result from ContentAnalysisService
  # @return [Array<Entity>] The created or found entities
  def extract_entities_and_statements(analysis_result)
    return [] unless analysis_result.is_a?(Hash) && analysis_result['annotated_description'].present?
    
    # Debug logging
    Rails.logger.debug { "[Content] Extracting entities and statements from analysis result" } if ENV['DEBUG']
    
    # Parse the annotated description to find entity mentions
    # Format is typically: "...text... [EntityName] ...more text..."
    entity_names = analysis_result['annotated_description'].scan(/\[(.*?)\]/).flatten.uniq
    
    # Debug logging
    Rails.logger.debug { "[Content] Found #{entity_names.size} unique entity mentions: #{entity_names.join(', ')}" } if ENV['DEBUG']
    
    # Create or find entities and generate statements
    created_entities = []
    
    entity_names.each do |name|
      # Find or create the entity
      entity = entities.find_or_create_by(name: name)
      created_entities << entity
      
      # Create a basic statement about this entity
      entity.add_statement("Mentioned in content: #{title || 'Untitled'}", content: self)
      
      # Extract context around the entity mention to create more detailed statements
      context = extract_context_for_entity(analysis_result['annotated_description'], name)
      if context.present?
        entity.add_statement(context, content: self)
      end
    end
    
    # Debug logging
    Rails.logger.debug { "[Content] Created #{created_entities.size} entities with statements" } if ENV['DEBUG']
    
    created_entities
  end
  
  # Extract context around an entity mention
  # @param text [String] The full text to search in
  # @param entity_name [String] The entity name to find context for
  # @return [String] The extracted context
  def extract_context_for_entity(text, entity_name)
    # Find the position of the entity in the text
    entity_pattern = /\[#{Regexp.escape(entity_name)}\]/
    match = text.match(entity_pattern)
    return nil unless match
    
    # Get the start and end positions
    start_pos = [match.begin(0) - 100, 0].max
    end_pos = [match.end(0) + 100, text.length].min
    
    # Extract the context
    context = text[start_pos...end_pos].gsub(entity_pattern, entity_name)
    
    # Clean up the context
    context.strip
  end

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
