# frozen_string_literal: true

# Service for creating and validating statements in the knowledge graph
class StatementCreationService
  # Initialize the service
  def initialize
    Rails.logger.debug { "[StatementCreationService] Initialized" } if ENV["DEBUG"]
  end

  # Create a statement from structured data
  # @param statement_data [Hash] The statement data
  # @param entity [Entity] The subject entity
  # @param content [Content] The content associated with the statement
  # @return [Hash] Result with created statement or error
  def create_statement(statement_data, entity, content)
    if ENV["DEBUG"]
      Rails.logger.debug do
        "[StatementCreationService] Creating statement for entity ##{entity.id}: #{statement_data.inspect}"
      end
    end

    # Validate statement data
    validation_result = validate_statement_data(statement_data)
    unless validation_result[:valid]
      Rails.logger.error { "[StatementCreationService] Invalid statement data: #{validation_result[:errors].join(', ')}" }
      return { success: false, errors: validation_result[:errors] }
    end

    # Prepare statement parameters
    statement_params = prepare_statement_params(statement_data, entity, content)

    # Handle object entity if it's an entity type
    if statement_params[:object_type] == "entity"
      object_entity_result = find_or_create_object_entity(statement_params[:object], content)

      if object_entity_result[:success]
        if object_entity_result[:status] == :needs_verification
          # Object entity needs verification, store as pending
          Rails.logger.debug { "[StatementCreationService] Object entity needs verification, storing as pending" } if ENV["DEBUG"]
          return {
            success: true,
            status: :pending_verification,
            verification_request: object_entity_result[:verification_request],
            pending_statement: statement_data.merge(
              "subject" => entity.name,
              "subject_id" => entity.id
            )
          }
        else
          # Object entity exists or was created
          statement_params[:object_entity] = object_entity_result[:entity]
        end
      else
        # Error finding/creating object entity
        Rails.logger.error { "[StatementCreationService] Error with object entity: #{object_entity_result[:error]}" }
        return { success: false, error: object_entity_result[:error] }
      end
    end

    # Create the statement
    begin
      statement = Statement.create!(statement_params)

      # Generate embedding for the statement
      generate_embedding_for_statement(statement)

      Rails.logger.debug { "[StatementCreationService] Created statement ##{statement.id}" } if ENV["DEBUG"]

      { success: true, statement: statement }
    rescue StandardError => e
      Rails.logger.error { "[StatementCreationService] Error creating statement: #{e.message}" }
      { success: false, error: e.message }
    end
  end

  # Validate statement data
  # @param statement_data [Hash] The statement data to validate
  # @return [Hash] Validation result with valid flag and errors
  def validate_statement_data(statement_data)
    errors = []

    # Check if statement_data is a hash
    unless statement_data.is_a?(Hash)
      errors << "Statement data must be a hash, got #{statement_data.class}"
      return { valid: false, errors: errors }
    end

    # Check required fields
    errors << "Missing required field 'text'" if statement_data["text"].blank?

    # V3 Knowledge Graph fields
    errors << "Missing required field 'predicate'" if statement_data["predicate"].blank?

    errors << "Missing required field 'object'" if statement_data["object"].blank?

    # Validate confidence if present
    if statement_data["confidence"].present?
      if !statement_data["confidence"].is_a?(Numeric)
        errors << "Confidence must be a number, got #{statement_data['confidence'].class}"
      elsif !statement_data["confidence"].between?(0, 1)
        errors << "Confidence must be between 0 and 1, got #{statement_data['confidence']}"
      end
    end

    # Validate object_type if present
    if statement_data["object_type"].present? && ["entity", "literal"].exclude?(statement_data["object_type"])
      errors << "Object type must be 'entity' or 'literal', got #{statement_data['object_type']}"
    end

    { valid: errors.empty?, errors: errors }
  end

  private

  # Prepare statement parameters from statement data
  # @param statement_data [Hash] The statement data
  # @param entity [Entity] The subject entity
  # @param content [Content] The content associated with the statement
  # @return [Hash] Statement parameters
  def prepare_statement_params(statement_data, entity, content)
    # Start with basic parameters
    params = {
      entity: entity,
      content: content,
      text: statement_data["text"],
      confidence: statement_data["confidence"] || 0.7,
      source: statement_data["source"] || "ai",
      extraction_method: statement_data["extraction_method"] || "ai"
    }

    # Add V3 Knowledge Graph fields
    params[:predicate] = statement_data["predicate"] if statement_data["predicate"].present?
    params[:object] = statement_data["object"] if statement_data["object"].present?
    params[:object_type] = statement_data["object_type"] || "literal"

    # Set default text if not provided
    if params[:text].blank? && params[:predicate].present? && params[:object].present?
      params[:text] = "#{entity.name} #{params[:predicate]} #{params[:object]}"
    end

    params
  end

  # Find or create object entity for a statement
  # @param object_name [String] The name of the object entity
  # @param content [Content] The content associated with the statement
  # @return [Hash] Result with entity or verification request
  def find_or_create_object_entity(object_name, content)
    Rails.logger.debug { "[StatementCreationService] Finding or creating object entity: '#{object_name}'" } if ENV["DEBUG"]

    # Use EntityExtractionService to find or create the entity
    entity_extraction_service = EntityExtractionService.new
    entity_extraction_service.find_or_create_entity(object_name, content)
  end

  # Generate embedding for a statement
  # @param statement [Statement] The statement to generate embedding for
  def generate_embedding_for_statement(statement)
    return unless statement.persisted?

    Rails.logger.debug { "[StatementCreationService] Generating embedding for statement ##{statement.id}" } if ENV["DEBUG"]

    # Queue embedding generation job
    OpenAI::EmbeddingJob.perform_later(statement, :text)
  end
end
