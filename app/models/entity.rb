# frozen_string_literal: true

class Entity < ApplicationRecord
  # Add accessor for similarity score to be used in views
  attr_accessor :similarity

  belongs_to :canonical_entity, class_name: "Entity", optional: true

  # Returns the canonical entity for this entity
  def canonical
    Rails.logger.debug { "Entity##{id}: canonical_entity_id=#{canonical_entity_id}" }
    canonical_entity || self
  end

  # Is this entity canonical?
  def canonical?
    canonical_entity_id.nil?
  end

  belongs_to :content
  # Optionally, associate with a file (if needed in the future)
  # belongs_to :file_attachment, optional: true

  validates :entity_type, presence: true
  validates :value, presence: true
  validate :entity_type_in_taxonomy

  # Generate embedding before save if value changed
  before_save :generate_embedding

  # Find similar entities by vector similarity
  # Returns entities with similar values to the query text
  # @param query_text [String] The text to find similar entities for
  # @param limit [Integer] Maximum number of results to return
  # @param threshold [Float] Similarity threshold (lower = more similar)
  # @return [ActiveRecord::Relation] Collection of similar entities
  def self.find_similar(query_text, entity_type: nil, limit: 10, threshold: 0.8)
    return none if query_text.blank?

    Rails.logger.debug { "[Entity] Finding entities similar to: #{query_text}" }

    # Generate embedding for query text
    embedding_service = OpenAI::EmbeddingService.new
    query_embedding = embedding_service.embed(query_text)
    return none if query_embedding.nil?

    # Debug the embedding
    Rails.logger.debug { "[Entity] Generated query embedding with #{query_embedding.size} dimensions" }

    # Use a raw SQL approach to avoid PostgreSQL issues with ordering by calculated columns
    # This is more reliable for vector similarity searches
    base_conditions = ["value_embedding IS NOT NULL"]
    base_params = []

    if entity_type.present?
      base_conditions << "entity_type = ?"
      base_params << entity_type
    end

    # Check if we have any entities with value_embedding
    # Use a simpler query approach to avoid ActiveRecord chaining issues
    embedding_count = Entity.where.not(value_embedding: nil).count
    Rails.logger.debug { "[Entity] Found #{embedding_count} entities with embeddings" }

    # First, try without the threshold to see if we get any results at all
    # This will help us understand if the issue is with the threshold or something else
    all_entities = Entity.all
    Rails.logger.debug { "[Entity] Total entities in database: #{all_entities.count}" }
    Rails.logger.debug { "[Entity] Entity types: #{all_entities.pluck(:entity_type).uniq}" }
    Rails.logger.debug { "[Entity] Sample values: #{all_entities.limit(5).pluck(:value)}" }

    # Now add the threshold condition
    base_conditions << "(value_embedding <=> ?) < ?"
    base_params << query_embedding
    base_params << threshold

    # Log the threshold being used
    Rails.logger.debug { "[Entity] Using similarity threshold: #{threshold}" }

    # First, try without the threshold to see if we get any results at all
    # Cast the embedding to the vector type explicitly to avoid PG errors
    diagnostic_sql = <<~SQL.squish
      SELECT id, entity_type, value, (value_embedding <=> ?::vector) as similarity_score
      FROM entities
      WHERE value_embedding IS NOT NULL
      ORDER BY similarity_score ASC
      LIMIT 5
    SQL

    # Debug the query and embedding
    Rails.logger.debug { "[Entity] Query embedding dimensions: #{query_embedding&.size || 0}" }

    begin
      diagnostic_results = find_by_sql([diagnostic_sql, query_embedding])

      Rails.logger.debug { "[Entity] Diagnostic similarity scores:" }
      diagnostic_results.each do |entity|
        # Use attributes hash to access the similarity_score from the SQL query
        score = entity.attributes["similarity_score"] || "N/A"
        Rails.logger.debug { "  - #{entity.entity_type}: #{entity.value} (Score: #{score})" }
      end
    rescue StandardError => e
      Rails.logger.error("[Entity] Error in diagnostic query: #{e.message}")
      Rails.logger.debug { "[Entity] Query embedding sample: #{query_embedding&.first(5)}" }
      return none
    end

    # Execute the main query - properly format the SQL with params
    # Cast the embedding to the vector type explicitly
    sql = <<~SQL.squish
      SELECT id, entity_type, value, (value_embedding <=> ?::vector) as similarity_score
      FROM entities
      WHERE value_embedding IS NOT NULL
    SQL

    # Add entity_type filter if provided
    if entity_type.present?
      sql += " AND entity_type = ? "
      params = [query_embedding, entity_type]
    else
      params = [query_embedding]
    end

    # Add similarity threshold and ordering
    sql += <<~SQL.squish
      AND (value_embedding <=> ?::vector) <= ?
      ORDER BY similarity_score ASC
      LIMIT ?
    SQL

    # Add threshold and limit to params
    params += [query_embedding, threshold, limit]

    begin
      # Execute the query
      results = find_by_sql([sql, *params])
      Rails.logger.debug { "[Entity] Found #{results.size} similar entities" }
      results
    rescue StandardError => e
      Rails.logger.error("[Entity] Error in similarity query: #{e.message}")
      none
    end
  end

  # Returns the taxonomy as an array of valid entity type names
  def self.taxonomy_types
    taxonomy_path = Rails.root.join("app", "services", "openai", "entity_taxonomy.yml")
    yaml = YAML.load_file(taxonomy_path)
    yaml["entity_types"].pluck("name")
  end

  private

  def entity_type_in_taxonomy
    return if self.class.taxonomy_types.include?(entity_type)

    errors.add(:entity_type, "must match a type in the taxonomy (see entity_taxonomy.yml)")
  end

  # Generate embedding for the entity value
  # Only generates if value is present and has changed
  def generate_embedding
    return if value.blank? || !value_changed?

    Rails.logger.debug { "[Entity] Generating embedding for entity value: #{value.truncate(50)}" }

    begin
      embedding_service = OpenAI::EmbeddingService.new
      embedding_array = embedding_service.embed(value)

      # Store the embedding array directly - pgvector will handle the conversion
      if embedding_array.present?
        self.value_embedding = embedding_array
        Rails.logger.debug { "[Entity] Successfully generated embedding with #{embedding_array.size} dimensions" }
      else
        Rails.logger.warn { "[Entity] Failed to generate embedding for entity value" }
      end
    rescue StandardError => e
      Rails.logger.error { "[Entity] Error generating embedding: #{e.message}\n#{e.backtrace.join('\n')}" }
      # Don't fail the save if embedding generation fails
    end
  end
end
