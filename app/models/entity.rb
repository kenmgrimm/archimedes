# frozen_string_literal: true

# Entity model for V2 data architecture
# Represents a unique concept, person, organization, or thing
class Entity < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  # Associations
  belongs_to :content
  has_many :statements, dependent: :destroy
  has_many :object_statements, class_name: "Statement", foreign_key: "object_entity_id", dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: true

  before_save :generate_name_embedding
  # Callbacks
  after_create -> { Rails.logger.debug { "Created entity: #{id} - #{name}" } if ENV["DEBUG"] }

  # Scopes
  scope :by_name, ->(name) { where("name ILIKE ?", "%#{name}%") }
  scope :with_statements, -> { joins(:statements).distinct }
  scope :without_statements, -> { where.missing(:statements) }

  # Generate embeddings for entity names for direct entity similarity search
  # Statements also have their own embeddings for more detailed semantic search

  # Find entities by name embedding similarity
  # Returns entities with names similar to the query text
  # @param query_text [String] The text to find similar entities for
  # @param limit [Integer] Maximum number of results to return
  # @param threshold [Float] Similarity threshold (lower = more similar)
  # @return [Array<Entity>] Collection of entities with similar names
  def self.find_by_name_similarity(query_text, limit: 10, threshold: 0.8)
    return none if query_text.blank?

    Rails.logger.debug { "[Entity] Finding entities by name similarity to: #{query_text}" } if ENV["DEBUG"]

    # Generate embedding for query text
    embedding_service = OpenAI::EmbeddingService.new
    query_embedding = embedding_service.embed(query_text)
    return none if query_embedding.nil?

    # Calculate distance and filter by threshold
    # Lower distance = more similar
    distance_calc = "(name_embedding <=> '#{query_embedding}')"

    # Debug logging for query construction
    Rails.logger.debug { "[Entity] Building name vector similarity query with distance calculation: #{distance_calc}" } if ENV["DEBUG"]

    # Start with a base query and chain methods
    results = where.not(name_embedding: nil)
                   .select("*, #{distance_calc} AS similarity_distance")
                   .where("#{distance_calc} < ?", threshold)
                   .order(Arel.sql(distance_calc))
                   .limit(limit)

    # Safely log the SQL query if the results object supports to_sql
    Rails.logger.debug { "[Entity] Name vector similarity query SQL: #{results.to_sql}" } if results.respond_to?(:to_sql) && ENV["DEBUG"]

    # Set similarity score for each result
    results.each do |entity|
      entity.similarity = entity.attributes["similarity_distance"]
    end

    results
  end

  # Find entities by statement similarity
  # Returns entities that have statements similar to the query text
  # @param query_text [String] The text to find related entities for
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Entity>] Collection of entities with similar statements
  def self.find_by_statement(query_text, limit: 10)
    return none if query_text.blank?

    Rails.logger.debug { "[Entity] Finding entities by statement similarity to: #{query_text}" } if ENV["DEBUG"]

    # Generate embedding for query text
    embedding_service = OpenAI::EmbeddingService.new
    query_embedding = embedding_service.embed(query_text)
    return none if query_embedding.nil?

    # Find statements similar to the query
    statements = Statement.find_similar(query_text, limit: limit * 3) # Get more statements than needed

    # Get unique entities from those statements
    entity_ids = statements.pluck(:entity_id).uniq

    # Debug logging
    Rails.logger.debug { "[Entity] Found #{entity_ids.size} entities with similar statements" } if ENV["DEBUG"]

    # Fetch entities
    entities = where(id: entity_ids).limit(limit)

    # For each entity, find its most similar statement and set similarity score
    entities.each do |entity|
      best_statement = statements.find { |s| s.entity_id == entity.id }
      entity.similarity = best_statement&.similarity || 1.0
    end

    # Sort by similarity (lowest distance first)
    entities.sort_by(&:similarity)
  end

  # Find entities by name (text search)
  # @param name [String] The name to search for
  # @param limit [Integer] Maximum number of results to return
  # @return [ActiveRecord::Relation] Collection of matching entities
  def self.search_by_name(name, limit: 10)
    return none if name.blank?

    Rails.logger.debug { "[Entity] Searching for entities with name like: #{name}" } if ENV["DEBUG"]

    where("name ILIKE ?", "%#{name}%").limit(limit)
  end

  # Helper methods for working with statements

  # Get all statements about this entity (as subject)
  # @return [ActiveRecord::Relation] Collection of statements
  def subject_statements
    statements
  end

  # Get all statements where this entity is the object
  # @return [ActiveRecord::Relation] Collection of statements
  def object_statements
    Statement.where(object_entity_id: id)
  end

  # Get all statements related to this entity (as subject or object)
  # @return [ActiveRecord::Relation] Collection of statements
  def all_statements
    Statement.where("entity_id = ? OR object_entity_id = ?", id, id)
  end

  # Get the most relevant statements about this entity
  # @param limit [Integer] Maximum number of statements to return
  # @return [ActiveRecord::Relation] Collection of statements
  def relevant_statements(limit: 5)
    statements.by_confidence.limit(limit)
  end

  # Create a new statement about this entity
  # @param text [String] The statement text
  # @param object_entity [Entity] Optional object entity for relationships
  # @param content [Content] The source content
  # @param confidence [Float] Confidence score (0-1)
  # @return [Statement] The created statement
  def add_statement(text, object_entity: nil, content: self.content, confidence: 1.0)
    # Debug logging
    Rails.logger.debug { "[Entity] Adding statement to #{name}: #{text}" } if ENV["DEBUG"]

    # Create the statement
    statement = statements.create!(
      text: text,
      object_entity: object_entity,
      content: content,
      confidence: confidence
    )

    # Generate embedding asynchronously
    # In a real app, this would be a background job
    begin
      embedding_service = OpenAI::EmbeddingService.new
      embedding = embedding_service.embed_text(text)
      statement.update(text_embedding: embedding) if embedding.present?
    rescue StandardError => e
      Rails.logger.error { "[Entity] Error generating embedding for statement: #{e.message}" }
    end

    statement
  end

  # For display in UI
  def to_s
    name
  end

  private

  # Generate embedding for the entity name
  # Only generates if name is present and has changed
  def generate_name_embedding
    return if name.blank? || !name_changed?

    Rails.logger.debug { "[Entity] Generating embedding for entity name: #{name}" } if ENV["DEBUG"]

    begin
      embedding_service = OpenAI::EmbeddingService.new
      embedding_array = embedding_service.embed(name)

      # Store the embedding array directly - pgvector will handle the conversion
      if embedding_array.present?
        self.name_embedding = embedding_array
        if ENV["DEBUG"]
          Rails.logger.debug do
            "[Entity] Successfully generated embedding for '#{name}' with #{embedding_array.size} dimensions"
          end
        end
      else
        Rails.logger.warn { "[Entity] Failed to generate embedding for entity name" }
      end
    rescue StandardError => e
      Rails.logger.error { "[Entity] Error generating name embedding: #{e.message}\n#{e.backtrace.join('\n')}" }
      # Don't fail the save if embedding generation fails
    end
  end
end
