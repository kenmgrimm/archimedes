# frozen_string_literal: true

# Service for managing entities in the knowledge graph
# Handles entity deduplication, merging, and verification
class EntityManagementService
  # Debug logging
  def initialize
    Rails.logger.debug { "Initializing EntityManagementService" } if ENV["DEBUG"]
  end

  # Find potential duplicate entities based on name similarity
  # @param entity_name [String] The name to check for duplicates
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Entity>] List of potential duplicate entities with similarity scores
  def find_similar_entities(entity_name, limit: 5)
    Rails.logger.debug { "Finding similar entities for '#{entity_name}'" } if ENV["DEBUG"]

    # Get embedding for the entity name
    embedding_service = OpenAI::EmbeddingService.new
    embedding = embedding_service.create(entity_name)

    return [] if embedding.blank?

    # Find entities with similar names using vector search
    similar_entities = Entity.vector_search(embedding, limit: limit)

    Rails.logger.debug { "Found #{similar_entities.count} potential matches for '#{entity_name}'" } if ENV["DEBUG"]

    similar_entities
  end

  # Merge two entities, transferring all statements from source to target
  # @param source_entity_id [Integer] ID of the source entity to merge from
  # @param target_entity_id [Integer] ID of the target entity to merge into
  # @return [Hash] Result of the merge operation
  def merge_entities(source_entity_id, target_entity_id)
    Rails.logger.debug { "Merging entity ##{source_entity_id} into ##{target_entity_id}" } if ENV["DEBUG"]

    source_entity = Entity.find(source_entity_id)
    target_entity = Entity.find(target_entity_id)

    return { success: false, error: "Cannot merge an entity into itself" } if source_entity_id == target_entity_id

    ActiveRecord::Base.transaction do
      # Transfer statements where the source entity is the subject
      statements_to_transfer = source_entity.statements

      transferred_count = 0
      statements_to_transfer.find_each do |statement|
        # Create a new statement with the target entity as subject
        new_statement = Statement.new(
          entity_id: target_entity.id,
          object_entity_id: statement.object_entity_id,
          text: statement.text,
          predicate: statement.predicate,
          object: statement.object,
          object_type: statement.object_type,
          confidence: statement.confidence,
          content_id: statement.content_id
        )

        if new_statement.save
          transferred_count += 1
        else
          Rails.logger.error { "Failed to transfer statement ##{statement.id}: #{new_statement.errors.full_messages.join(', ')}" }
        end
      end

      # Update statements where the source entity is the object
      referencing_statements = Statement.where(object_entity_id: source_entity.id)
      referencing_count = 0

      referencing_statements.find_each do |statement|
        if statement.update(object_entity_id: target_entity.id)
          referencing_count += 1
        else
          Rails.logger.error { "Failed to update referencing statement ##{statement.id}: #{statement.errors.full_messages.join(', ')}" }
        end
      end

      # Mark the source entity as merged
      source_entity.update(
        name: "#{source_entity.name} (merged into #{target_entity.name})"
      )

      if ENV["DEBUG"]
        Rails.logger.debug do
          "Transferred #{transferred_count} statements and updated #{referencing_count} references during merge"
        end
      end

      {
        success: true,
        source_entity: source_entity,
        target_entity: target_entity,
        transferred_statements: transferred_count,
        updated_references: referencing_count
      }
    end
  rescue StandardError => e
    Rails.logger.error "Error merging entities: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: e.message }
  end

  # Create a new entity with verification against existing entities
  # @param name [String] The name of the entity to create
  # @param content_id [Integer] ID of the source content
  # @param check_duplicates [Boolean] Whether to check for duplicates
  # @return [Hash] The created entity or potential matches
  def create_entity_with_verification(name, content_id, check_duplicates: true)
    Rails.logger.debug { "Creating entity with verification: '#{name}'" } if ENV["DEBUG"]

    # Check for potential duplicates if requested
    if check_duplicates
      similar_entities = find_similar_entities(name)

      if similar_entities.any?
        Rails.logger.debug { "Found #{similar_entities.count} potential matches, returning for user verification" } if ENV["DEBUG"]
        return {
          status: :needs_verification,
          candidate_name: name,
          similar_entities: similar_entities
        }
      end
    end

    # No duplicates found or checking disabled, create the entity
    entity = Entity.create(name: name, content_id: content_id)

    if entity.persisted?
      Rails.logger.debug { "Created new entity ##{entity.id}: #{entity.name}" } if ENV["DEBUG"]
      { status: :created, entity: entity }
    else
      Rails.logger.error { "Failed to create entity: #{entity.errors.full_messages.join(', ')}" }
      { status: :error, errors: entity.errors.full_messages }
    end
  end
end
