# frozen_string_literal: true

# Entity model for V2 data architecture
# Represents a unique concept, person, organization, or thing
class Entity < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  # Associations
  belongs_to :content
  has_many :statements, dependent: :destroy
  has_many :object_statements, class_name: 'Statement', foreign_key: 'object_entity_id', dependent: :destroy
  
  # Validations
  validates :name, presence: true
  
  # Callbacks
  after_create -> { Rails.logger.debug("Created entity: #{id} - #{name}") if ENV['DEBUG'] }
  
  # Scopes
  scope :by_name, ->(name) { where("name ILIKE ?", "%#{name}%") }
  scope :with_statements, -> { joins(:statements).distinct }
  scope :without_statements, -> { left_joins(:statements).where(statements: { id: nil }) }

  # No longer generate embeddings directly on entities
  # Embeddings are now on statements

  # Find entities by statement similarity
  # Returns entities that have statements similar to the query text
  # @param query_text [String] The text to find related entities for
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Entity>] Collection of entities with similar statements
  def self.find_by_statement(query_text, limit: 10)
    return none if query_text.blank?

    Rails.logger.debug { "[Entity] Finding entities with statements similar to: #{query_text}" } if ENV['DEBUG']

    # Find statements similar to the query text
    similar_statements = Statement.text_search(query_text, limit: limit * 2)
    
    # Get unique entities from those statements
    entity_ids = similar_statements.pluck(:entity_id).uniq
    
    # Debug logging
    Rails.logger.debug { "[Entity] Found #{similar_statements.count} similar statements with #{entity_ids.count} unique entities" } if ENV['DEBUG']
    
    # Return entities with similarity scores
    entities = where(id: entity_ids).limit(limit)
    
    # For each entity, find its most similar statement
    entities.each do |entity|
      best_statement = similar_statements.where(entity_id: entity.id).first
      entity.similarity = best_statement&.similarity || 1.0
    end
    
    # Sort by similarity
    entities.sort_by(&:similarity)
  end
  
  # Find entities by name (text search)
  # @param name [String] The name to search for
  # @param limit [Integer] Maximum number of results to return
  # @return [ActiveRecord::Relation] Collection of matching entities
  def self.search_by_name(name, limit: 10)
    return none if name.blank?
    
    Rails.logger.debug { "[Entity] Searching for entities with name like: #{name}" } if ENV['DEBUG']
    
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
    Rails.logger.debug { "[Entity] Adding statement to #{name}: #{text}" } if ENV['DEBUG']
    
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
end
