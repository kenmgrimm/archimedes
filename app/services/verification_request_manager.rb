# frozen_string_literal: true

# Service for managing verification requests in the knowledge graph workflow
class VerificationRequestManager
  # Initialize the service
  def initialize
    Rails.logger.debug { "[VerificationRequestManager] Initialized" } if ENV["DEBUG"]
  end

  # Create a verification request for an entity
  # @param entity_name [String] The name of the candidate entity
  # @param content [Content] The content associated with the entity
  # @param similar_entities [Array<Entity>] Similar entities found
  # @param pending_statements [Array<Hash>] Statements that reference this entity
  # @return [VerificationRequest] The created verification request
  def create_verification_request(entity_name, content, similar_entities, pending_statements = [])
    Rails.logger.debug { "[VerificationRequestManager] Creating verification request for '#{entity_name}'" } if ENV["DEBUG"]

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
        "[VerificationRequestManager] Created verification request ##{verification_request.id} for '#{entity_name}'"
      end
    end

    verification_request
  rescue StandardError => e
    Rails.logger.error { "[VerificationRequestManager] Error creating verification request: #{e.message}" }
    raise
  end

  # Process a verification request with the given action
  # @param verification_request [VerificationRequest] The verification request to process
  # @param action [String] "approve", "reject", or "merge"
  # @param params [Hash] Additional parameters for the action
  # @return [Hash] Result of the action
  def process_verification_request(verification_request, action, params = {})
    if ENV["DEBUG"]
      Rails.logger.debug do
        "[VerificationRequestManager] Processing verification request ##{verification_request.id} with action: #{action}"
      end
    end

    case action
    when "approve"
      approve_request(verification_request, params[:entity_id])
    when "reject"
      reject_request(verification_request)
    when "merge"
      merge_request(verification_request, params[:target_entity_id])
    else
      { success: false, error: "Invalid action: #{action}" }
    end
  end

  # Get pending verification requests for a content
  # @param content [Content] The content to get verification requests for
  # @return [Array<VerificationRequest>] Pending verification requests
  def pending_verification_requests(content)
    VerificationRequest.where(content: content, status: "pending")
  end

  # Check if a content has any pending verification requests
  # @param content [Content] The content to check
  # @return [Boolean] True if there are pending verification requests
  def has_pending_verification_requests?(content)
    VerificationRequest.exists?(content: content, status: "pending")
  end

  private

  # Approve a verification request
  # @param verification_request [VerificationRequest] The verification request to approve
  # @param entity_id [Integer] Optional existing entity ID to use instead of creating new
  # @return [Hash] Result with success status and entity
  def approve_request(verification_request, entity_id = nil)
    Rails.logger.debug { "[VerificationRequestManager] Approving verification request ##{verification_request.id}" } if ENV["DEBUG"]

    ActiveRecord::Base.transaction do
      # Use existing entity or create new one
      entity = if entity_id.present?
                 Entity.find(entity_id)
               else
                 Entity.create!(
                   name: verification_request.candidate_name,
                   content: verification_request.content,
                   verification_status: "verified",
                   verified_at: Time.current,
                   verified_by: "user"
                 )
               end

      # Process pending statements
      process_pending_statements(verification_request, entity)

      # Update verification request
      verification_request.update!(
        status: "approved",
        verified_entity: entity
      )

      # Generate embedding for the entity
      OpenAI::EmbeddingJob.perform_later(entity, :name)

      { success: true, entity: entity }
    rescue StandardError => e
      Rails.logger.error { "[VerificationRequestManager] Error approving request: #{e.message}" }
      { success: false, error: e.message }
    end
  end

  # Reject a verification request
  # @param verification_request [VerificationRequest] The verification request to reject
  # @return [Hash] Result with success status
  def reject_request(verification_request)
    Rails.logger.debug { "[VerificationRequestManager] Rejecting verification request ##{verification_request.id}" } if ENV["DEBUG"]

    verification_request.update(status: "rejected")
    { success: true }
  rescue StandardError => e
    Rails.logger.error { "[VerificationRequestManager] Error rejecting request: #{e.message}" }
    { success: false, error: e.message }
  end

  # Merge a verification request with an existing entity
  # @param verification_request [VerificationRequest] The verification request to merge
  # @param target_entity_id [Integer] ID of the entity to merge into
  # @return [Hash] Result with success status and target entity
  def merge_request(verification_request, target_entity_id)
    if ENV["DEBUG"]
      Rails.logger.debug do
        "[VerificationRequestManager] Merging verification request ##{verification_request.id} into entity ##{target_entity_id}"
      end
    end

    ActiveRecord::Base.transaction do
      target_entity = Entity.find(target_entity_id)

      # Process pending statements with the target entity
      process_pending_statements(verification_request, target_entity)

      # Update verification request
      verification_request.update!(
        status: "merged",
        verified_entity: target_entity
      )

      { success: true, entity: target_entity }
    rescue StandardError => e
      Rails.logger.error { "[VerificationRequestManager] Error merging request: #{e.message}" }
      { success: false, error: e.message }
    end
  end

  # Process pending statements for a verification request
  # @param verification_request [VerificationRequest] The verification request
  # @param entity [Entity] The entity to associate statements with
  # @return [Array<Statement>] Created statements
  def process_pending_statements(verification_request, entity)
    pending_statements = verification_request.pending_statements
    return [] if pending_statements.blank?

    if ENV["DEBUG"]
      Rails.logger.debug do
        "[VerificationRequestManager] Processing #{pending_statements.size} pending statements for entity ##{entity.id}"
      end
    end

    created_statements = []
    statement_creation_service = StatementCreationService.new

    pending_statements.each do |statement_data|
      # Create statement parameters
      statement_params = {
        "text" => "#{entity.name} #{statement_data['predicate']} #{statement_data['object']}",
        "predicate" => statement_data["predicate"],
        "object" => statement_data["object"],
        "object_type" => statement_data["object_type"] || "literal",
        "confidence" => statement_data["confidence"] || 0.7,
        "source" => "verification",
        "extraction_method" => "ai"
      }

      # Create the statement
      result = statement_creation_service.create_statement(statement_params, entity, verification_request.content)

      if result[:success] && result[:statement].present?
        created_statements << result[:statement]
        Rails.logger.debug { "[VerificationRequestManager] Created statement ##{result[:statement].id}" } if ENV["DEBUG"]
      elsif result[:error].present?
        Rails.logger.error { "[VerificationRequestManager] Error creating statement: #{result[:error]}" }
      end
    end

    created_statements
  end
end
