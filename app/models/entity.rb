# frozen_string_literal: true

# Entity model for V3 knowledge graph architecture
# Represents a unique concept, person, organization, or thing in the knowledge graph
class Entity < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  # Associations
  belongs_to :content
  has_many :statements, dependent: :destroy
  has_many :object_statements, class_name: "Statement", foreign_key: "object_entity_id", dependent: :destroy
  has_many :verification_requests, foreign_key: "verified_entity_id", dependent: :nullify
  has_many :source_merges, class_name: "EntityMerge", foreign_key: "source_entity_id", dependent: :nullify
  has_many :target_merges, class_name: "EntityMerge", foreign_key: "target_entity_id", dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :verification_status, presence: true, inclusion: { in: ["pending", "verified", "rejected", "merged"] }

  # Callbacks
  before_save :generate_name_embedding
  after_create :log_creation

  # Scopes
  scope :by_name, ->(name) { where("name ILIKE ?", "%#{name}%") }
  scope :with_statements, -> { joins(:statements).distinct }
  scope :without_statements, -> { where.missing(:statements) }
  scope :verified, -> { where(verification_status: "verified") }
  scope :pending, -> { where(verification_status: "pending") }
  scope :rejected, -> { where(verification_status: "rejected") }

  # Find entities by name embedding similarity
  # Returns entities with names similar to the query text
  # @param query_text [String] The text to find similar entities for
  # @param limit [Integer] Maximum number of results to return
  # @param threshold [Float] Similarity threshold (lower = more similar)
  # @return [Array<Entity>] Collection of entities with similar names
  def self.find_similar(query_text, limit: 10)
    Rails.logger.debug { "[Entity] Finding similar entities for: #{query_text}" } if ENV["DEBUG"]
    find_by_name_similarity(query_text, limit: limit)
  end

  # Find entities related to statements that match the query text
  # @param query_text [String] The text to find related statements for
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Entity>] Collection of entities related to matching statements
  def self.find_by_statement(query_text, limit: 10)
    Rails.logger.debug { "[Entity] Finding entities by statement similarity to: #{query_text}" } if ENV["DEBUG"]

    # First find similar statements
    similar_statements = Statement.text_search(query_text, limit: limit * 2) # Get more statements to ensure we have enough entities

    # Extract unique entities from those statements
    entities = []

    similar_statements.each do |statement|
      # Add subject entity
      entities << statement.entity if statement.entity.present?

      # Add object entity if it's an entity-type object
      entities << statement.object_entity if statement.object_entity.present?
    end

    # Remove duplicates and limit results
    unique_entities = entities.compact.uniq

    # Add debug logging
    Rails.logger.debug { "[Entity] Found #{unique_entities.size} entities by statement" } if ENV["DEBUG"]

    # Return limited results
    unique_entities.first(limit)
  end

  def self.find_by_name_similarity(query_text, limit: 10, threshold: 0.8)
    return none if query_text.blank?

    Rails.logger.debug { "[Entity] Finding entities by name similarity to: #{query_text}" } if ENV["DEBUG"]

    # Generate embedding for query text
    embedding_service = OpenAI::EmbeddingService.new
    query_embedding = embedding_service.embed(query_text)
    return none if query_embedding.blank?

    # Format the embedding array for pgvector
    vector_string = "[#{query_embedding.join(',')}]"

    # Use cosine similarity to find similar entities
    # Lower cosine distance means more similar
    similar_entities = where.not(name_embedding: nil)
                            .select("*, (name_embedding <=> '#{vector_string}') as distance")
                            .order("distance ASC")
                            .limit(limit)

    # Add similarity score to each entity
    similar_entities.each do |entity|
      # Convert distance to similarity (1 - distance)
      entity.similarity = 1 - entity.distance.to_f
    end

    # Filter by threshold if specified
    similar_entities = similar_entities.select { |e| e.similarity >= threshold } if threshold.present?

    Rails.logger.debug { "[Entity] Found #{similar_entities.size} similar entities" } if ENV["DEBUG"]
    similar_entities
  end

  # Get statements where this entity is the subject, grouped by predicate
  # @return [Hash] Statements grouped by predicate
  def statements_by_predicate
    statements.group_by(&:predicate)
  end

  # Get statements where this entity is the object, grouped by predicate
  # @return [Hash] Statements grouped by predicate
  def referenced_by_predicate
    object_statements.group_by(&:predicate)
  end

  # Find all entities connected to this entity through statements
  # @param depth [Integer] How many hops to traverse (1 = direct connections only)
  # @return [Array<Entity>] Connected entities
  def connected_entities(depth: 1)
    return [] if depth < 1

    # Get directly connected entities
    direct_connections = []

    # Entities this entity points to
    direct_connections += statements.where(object_type: "entity")
                                    .where.not(object_entity_id: nil)
                                    .includes(:object_entity)
                                    .map(&:object_entity)

    # Entities that point to this entity
    direct_connections += object_statements.includes(:entity).map(&:entity)

    # Remove duplicates and self
    direct_connections = direct_connections.compact.uniq.reject { |e| e.id == id }

    return direct_connections if depth == 1

    # Recursively get connections of connections
    all_connections = direct_connections.dup
    direct_connections.each do |entity|
      all_connections += entity.connected_entities(depth: depth - 1)
    end

    all_connections.uniq
  end

  # Get a knowledge graph centered on this entity
  # @param depth [Integer] How many hops to include
  # @return [Hash] Knowledge graph data structure
  def knowledge_graph(depth: 1)
    nodes = [{ id: id, label: name, group: "focus" }]
    edges = []

    # Add this entity's statements
    statements.includes(:object_entity).find_each do |statement|
      next if statement.object_entity.blank?

      # Add the connected entity as a node if not already present
      unless nodes.any? { |n| n[:id] == statement.object_entity.id }
        nodes << { id: statement.object_entity.id, label: statement.object_entity.name, group: "entity" }
      end

      # Add the edge
      edges << {
        from: id,
        to: statement.object_entity.id,
        label: statement.predicate,
        arrows: "to"
      }
    end

    # Add statements where this entity is the object
    object_statements.includes(:entity).find_each do |statement|
      # Add the connected entity as a node if not already present
      unless nodes.any? { |n| n[:id] == statement.entity.id }
        nodes << { id: statement.entity.id, label: statement.entity.name, group: "entity" }
      end

      # Add the edge
      edges << {
        from: statement.entity.id,
        to: id,
        label: statement.predicate,
        arrows: "to"
      }
    end

    # If depth > 1, recursively add connections
    if depth > 1
      connected_entities(depth: 1).each do |entity|
        subgraph = entity.knowledge_graph(depth: depth - 1)

        # Add nodes and edges from subgraph, avoiding duplicates
        subgraph[:nodes].each do |node|
          nodes << node.merge(group: "extended") unless nodes.any? { |n| n[:id] == node[:id] }
        end

        subgraph[:edges].each do |edge|
          edges << edge unless edges.any? { |e| e[:from] == edge[:from] && e[:to] == edge[:to] && e[:label] == edge[:label] }
        end
      end
    end

    { nodes: nodes, edges: edges }
  end

  # Mark this entity as verified
  # @param verified_by [String] Who verified the entity
  # @return [Boolean] Success status
  def mark_verified(verified_by: "user")
    update(
      verification_status: "verified",
      verified_at: Time.current,
      verified_by: verified_by
    )
  end

  # Merge this entity into another entity
  # @param target_entity [Entity] The entity to merge into
  # @param initiated_by [String] Who initiated the merge
  # @return [Hash] Result with success status and counts
  def merge_into(target_entity, initiated_by: "user")
    return { success: false, error: "Cannot merge into self" } if id == target_entity.id

    ActiveRecord::Base.transaction do
      # Track statements to transfer
      transferred_count = 0

      # Transfer statements where this entity is the subject
      statements.each do |statement|
        # Check if an equivalent statement already exists for the target entity
        existing = Statement.where(
          entity_id: target_entity.id,
          predicate: statement.predicate,
          object: statement.object,
          object_type: statement.object_type,
          object_entity_id: statement.object_entity_id
        ).first

        if existing
          # If the existing statement has lower confidence, update it
          existing.update(confidence: statement.confidence) if existing.confidence < statement.confidence
          statement.destroy
        else
          # Transfer the statement to the target entity
          statement.update(entity_id: target_entity.id)
          transferred_count += 1
        end
      end

      # Update references to this entity in other statements
      Statement.where(object_entity_id: id).update_all(object_entity_id: target_entity.id)

      # Create merge record
      merge = EntityMerge.create!(
        source_entity_id: id,
        target_entity_id: target_entity.id,
        transferred_statements_count: transferred_count,
        initiated_by: initiated_by
      )

      # Mark this entity as merged (soft delete)
      update(verification_status: "merged")

      {
        success: true,
        target_entity: target_entity,
        transferred_statements: transferred_count,
        merge_record: merge
      }
    rescue StandardError => e
      Rails.logger.error { "[Entity] Error merging entity ##{id} into ##{target_entity.id}: #{e.message}" } if ENV["DEBUG"]
      { success: false, error: e.message }
    end
  end

  private

  # Generate embedding for entity name
  def generate_name_embedding
    return unless name_changed? || name_embedding.nil?

    Rails.logger.debug { "[Entity] Generating embedding for entity name: #{name}" } if ENV["DEBUG"]

    begin
      embedding_service = OpenAI::EmbeddingService.new
      embedding_array = embedding_service.embed(name)

      if embedding_array.present?
        # Format the embedding array for pgvector
        self.name_embedding = "[#{embedding_array.join(',')}]"
        Rails.logger.debug { "[Entity] Generated embedding with #{embedding_array.size} dimensions" } if ENV["DEBUG"]
      end
    rescue StandardError => e
      Rails.logger.error { "[Entity] Error generating name embedding: #{e.message}" }
    end
  end

  def log_creation
    Rails.logger.debug { "[Entity] Created entity ##{id}: #{name} (#{verification_status})" } if ENV["DEBUG"]
  end
end
