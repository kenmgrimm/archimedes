# frozen_string_literal: true

# Service for extracting entities from annotated text and managing entity creation/verification
class EntityExtractionService
  # Initialize the service
  def initialize
    Rails.logger.debug { "[EntityExtractionService] Initialized" } if ENV["DEBUG"]
  end

  # Extract entity names from annotated description
  # @param annotated_description [String] The annotated description with [Entity: Name] tags
  # @return [Array<String>] Array of entity names
  def extract_entity_names_from_annotation(annotated_description)
    return [] if annotated_description.blank?

    if ENV["DEBUG"]
      Rails.logger.debug do
        "[EntityExtractionService] Extracting entities from annotation: #{annotated_description.to_s[0..100]}..."
      end
    end

    # Extract entity names from [Entity: Name] tags
    entity_names = annotated_description.to_s.scan(/\[Entity:\s*([^\]]+)\]/).flatten.map(&:strip).uniq

    Rails.logger.debug { "[EntityExtractionService] Extracted #{entity_names.size} entities: #{entity_names.join(', ')}" } if ENV["DEBUG"]

    entity_names
  end

  # Find or create entity, or create verification request if needed
  # @param entity_name [String] The name of the entity
  # @param content [Content] The content associated with the entity
  # @param pending_statements [Array<Hash>] Optional statements that reference this entity
  # @return [Hash] Result with entity or verification request
  def find_or_create_entity(entity_name, content, pending_statements = [])
    Rails.logger.debug { "[EntityExtractionService] Finding or creating entity: '#{entity_name}'" } if ENV["DEBUG"]

    # Check if entity already exists
    existing_entity = Entity.find_by(name: entity_name)

    if existing_entity
      if ENV["DEBUG"]
        Rails.logger.debug do
          "[EntityExtractionService] Found existing entity: ##{existing_entity.id} - #{existing_entity.name}"
        end
      end
      return { success: true, entity: existing_entity, status: :existing }
    end

    # Find similar entities for verification
    similar_entities = find_similar_entities(entity_name)

    if similar_entities.any?
      if ENV["DEBUG"]
        Rails.logger.debug do
          "[EntityExtractionService] Found #{similar_entities.size} similar entities, creating verification request"
        end
      end

      # Create verification request
      verification_request = create_verification_request(entity_name, content, similar_entities, pending_statements)

      {
        success: true,
        verification_request: verification_request,
        status: :needs_verification,
        similar_entities: similar_entities
      }
    else
      # No similar entities found, create new entity
      Rails.logger.debug { "[EntityExtractionService] No similar entities found, creating new entity" } if ENV["DEBUG"]

      entity = Entity.create!(
        name: entity_name,
        content: content,
        verification_status: "verified",
        verified_at: Time.current,
        verified_by: "system"
      )

      # Generate embedding for the entity
      OpenAI::EmbeddingJob.perform_later(entity, :name)

      # Process any pending statements
      process_pending_statements(entity, pending_statements) if pending_statements.any?

      Rails.logger.debug { "[EntityExtractionService] Created new entity: ##{entity.id} - #{entity.name}" } if ENV["DEBUG"]

      { success: true, entity: entity, status: :created }
    end
  rescue StandardError => e
    Rails.logger.error { "[EntityExtractionService] Error finding/creating entity '#{entity_name}': #{e.message}" }
    { success: false, error: e.message }
  end

  # Create a verification request for an entity
  # @param entity_name [String] The name of the entity
  # @param content [Content] The content associated with the entity
  # @param similar_entities [Array<Entity>] Similar entities found
  # @param pending_statements [Array<Hash>] Statements that reference this entity
  # @return [VerificationRequest] The created verification request
  def create_verification_request(entity_name, content, similar_entities, pending_statements = [])
    Rails.logger.debug { "[EntityExtractionService] Creating verification request for '#{entity_name}'" } if ENV["DEBUG"]

    # Check if a verification request already exists for this candidate name and content
    existing_request = VerificationRequest.find_by(
      candidate_name: entity_name,
      content: content
    )

    if existing_request
      if ENV["DEBUG"]
        Rails.logger.debug do
          "[EntityExtractionService] Verification request already exists for '#{entity_name}' in content ##{content.id}"
        end
      end
      return existing_request
    end

    # Format similar entities for JSON storage
    similar_entities_json = similar_entities.map do |entity|
      {
        id: entity.id,
        name: entity.name,
        similarity: entity.similarity || 0.0,
        statement_count: entity.statements.count
      }
    end

    # Create the verification request
    verification_request = VerificationRequest.create!(
      content: content,
      candidate_name: entity_name,
      status: "pending",
      similar_entities: similar_entities_json,
      pending_statements: pending_statements
    )

    if ENV["DEBUG"]
      Rails.logger.debug do
        "[EntityExtractionService] Created verification request ##{verification_request.id} for '#{entity_name}'"
      end
    end

    verification_request
  end

  # Process pending statements for an entity
  # @param entity [Entity] The entity to associate statements with
  # @param pending_statements [Array<Hash>] Statements to process
  # @return [Array<Statement>] Created statements
  def process_pending_statements(entity, pending_statements)
    return [] if pending_statements.blank?

    if ENV["DEBUG"]
      Rails.logger.debug do
        "[EntityExtractionService] Processing #{pending_statements.size} pending statements for entity ##{entity.id}"
      end
    end

    created_statements = []

    pending_statements.each do |statement_data|
      # Create the statement with the verified entity
      statement_params = {
        entity: entity,
        text: "#{entity.name} #{statement_data['predicate']} #{statement_data['object']}",
        predicate: statement_data["predicate"],
        object: statement_data["object"],
        object_type: statement_data["object_type"] || "literal",
        confidence: statement_data["confidence"] || 0.7,
        content: entity.content,
        source: "verification",
        extraction_method: "ai"
      }

      # Handle object entity if it's an entity type
      if statement_params[:object_type] == "entity"
        object_entity = Entity.find_by(name: statement_data["object"])
        statement_params[:object_entity] = object_entity if object_entity
      end

      # Create the statement
      begin
        statement = Statement.create!(statement_params)
        created_statements << statement

        # Generate embedding
        OpenAI::EmbeddingJob.perform_later(statement, :text) if statement.persisted?

        Rails.logger.debug { "[EntityExtractionService] Created statement ##{statement.id} for entity ##{entity.id}" } if ENV["DEBUG"]
      rescue StandardError => e
        Rails.logger.error { "[EntityExtractionService] Error creating statement: #{e.message}" }
      end
    end

    created_statements
  end

  private

  # Find similar entities based on name
  # @param entity_name [String] The name to find similar entities for
  # @param limit [Integer] Maximum number of results to return
  # @return [Array<Entity>] List of similar entities with similarity scores
  def find_similar_entities(entity_name, limit: 5)
    Rails.logger.debug { "[EntityExtractionService] Finding similar entities for '#{entity_name}'" } if ENV["DEBUG"]

    # Use Entity model's similarity search
    similar_entities = Entity.find_similar(entity_name, limit: limit)

    Rails.logger.debug { "[EntityExtractionService] Found #{similar_entities.size} similar entities" } if ENV["DEBUG"]

    similar_entities
  end
end
