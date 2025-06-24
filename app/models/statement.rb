# frozen_string_literal: true

# Statement model for V2 data architecture
# Represents a textual statement about an entity or relationship between entities
class Statement < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity
  # Associations
  belongs_to :entity
  belongs_to :object_entity, class_name: "Entity", optional: true
  belongs_to :content

  # Validations
  validates :text, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  # Scopes
  scope :with_embedding, -> { where.not(text_embedding: nil) }
  scope :by_confidence, -> { order(confidence: :desc) }
  scope :relationships, -> { where.not(object_entity_id: nil) }
  scope :attributes, -> { where(object_entity_id: nil) }

  # Debug logging
  after_create -> { Rails.logger.debug { "Created statement: #{id} - #{text[0..50]}..." } if ENV["DEBUG"] }

  # Vector search methods
  def self.vector_search(embedding, limit: 10)
    return none if embedding.nil?

    # Debug logging
    Rails.logger.debug { "Performing vector search with embedding of size: #{embedding.size}" } if ENV["DEBUG"]

    # Use cosine similarity for semantic search
    where.not(text_embedding: nil)
         .order(Arel.sql("text_embedding <=> ARRAY[#{embedding.join(',')}]::vector"))
         .limit(limit)
  end

  def self.text_search(query_text, limit: 10)
    return none if query_text.blank?

    # Get embedding for the query text
    embedding = OpenAI::EmbeddingService.new.embed(query_text)
    vector_search(embedding, limit: limit)
  end
  
  # Find similar statements with similarity score
  # @param query_text [String] The text to search for
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Statement>] Statements with similarity score
  def self.find_similar(query_text, limit: 10)
    return [] if query_text.blank?
    
    # Debug logging
    Rails.logger.debug { "Finding statements similar to: #{query_text}" } if ENV["DEBUG"]
    
    # Get embedding for the query text
    embedding = OpenAI::EmbeddingService.new.embed(query_text)
    return [] if embedding.nil?
    
    # Use raw SQL for cosine similarity calculation
    statements = connection.execute(
      "SELECT id, text, entity_id, object_entity_id, 
              1 - (text_embedding <=> ARRAY[#{embedding.join(',')}]::vector) AS similarity 
       FROM statements 
       WHERE text_embedding IS NOT NULL 
       ORDER BY similarity DESC 
       LIMIT #{limit}"
    )
    
    # Map results and add similarity score
    statements.map do |result|
      statement = find(result["id"])
      statement.similarity = result["similarity"]
      statement
    end
  end

  # Relationship helpers
  def relationship?
    object_entity_id.present?
  end

  def attribute?
    object_entity_id.nil?
  end

  # For display in UI
  def to_s
    if relationship?
      "#{entity.name} - #{text} - #{object_entity.name}"
    else
      "#{entity.name} - #{text}"
    end
  end
end
