# frozen_string_literal: true

# Statement model for V3 knowledge graph architecture
# Represents a triple (subject-predicate-object) in the knowledge graph
class Statement < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  # Associations
  belongs_to :entity # Subject entity (source node)
  belongs_to :object_entity, class_name: "Entity", optional: true # Target entity if object_type is "entity"
  belongs_to :content

  # Validations
  validates :text, presence: true # Keep for backward compatibility
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  # V3: These validations will be enabled after migration
  # validates :predicate, presence: true
  # validates :object, presence: true
  # validates :object_type, presence: true, inclusion: { in: %w[entity literal] }

  # Scopes
  scope :with_embedding, -> { where.not(text_embedding: nil) }
  scope :by_confidence, -> { order(confidence: :desc) }
  scope :with_predicate, ->(predicate) { where(predicate: predicate) }

  # V3: Updated scopes for knowledge graph
  scope :relationships, -> { where(object_type: "entity").or(where.not(object_entity_id: nil)) } # Support both V2 and V3
  scope :attributes, -> { where(object_type: "literal").or(where(object_entity_id: nil)) } # Support both V2 and V3

  # Debug logging
  after_create lambda {
    if ENV["DEBUG"]
      if predicate.present? && object.present?
        Rails.logger.debug { "Created statement: #{id} - #{subject_entity_name} #{predicate} #{object} (#{object_type})" }
      else
        Rails.logger.debug { "Created statement: #{id} - #{text[0..50]}..." }
      end
    end
  }

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

  # Helper methods for working with the knowledge graph

  # Get the subject entity name
  def subject_entity_name
    entity&.name
  end

  # Get the object entity name if object_type is "entity"
  def object_entity_name
    object_entity&.name if object_type == "entity" || object_entity.present?
  end

  # Format the statement as a human-readable triple
  def to_triple
    if predicate.present? && object.present?
      object_display = object_type == "entity" ? object_entity_name || object : object
      "#{subject_entity_name} #{predicate} #{object_display}"
    else
      text
    end
  end

  # Generate the text embedding for this statement
  def generate_embedding!
    # Skip if no OpenAI API key or if embedding already exists
    return if text_embedding.present?

    # Generate the embedding for the complete triple or text
    triple_text = to_triple
    Rails.logger.debug { "Generating embedding for statement: #{triple_text}" } if ENV["DEBUG"]

    embedding_service = OpenAI::EmbeddingService.new
    embedding = embedding_service.create(triple_text)

    if embedding.present?
      update(text_embedding: embedding)
      Rails.logger.debug { "Updated embedding for statement #{id}" } if ENV["DEBUG"]
    else
      Rails.logger.error { "Failed to generate embedding for statement #{id}" }
    end
  rescue StandardError => e
    Rails.logger.error "Error generating embedding for statement #{id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  # Find statements with similar meaning
  def find_similar(limit: 5)
    return [] if text_embedding.blank?

    Statement.vector_search(text_embedding, limit: limit + 1)
             .where.not(id: id) # Exclude self
             .limit(limit)
             .map do |statement|
      # Calculate similarity score (1 - distance)
      statement.similarity = 1 - statement.distance.to_f
      statement
    end
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
