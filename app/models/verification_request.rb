# frozen_string_literal: true

# Model for entity verification requests in the knowledge graph workflow
class VerificationRequest < ApplicationRecord
  # Associations
  belongs_to :content
  belongs_to :verified_entity, class_name: "Entity", optional: true

  # Validations
  validates :candidate_name, presence: true
  validates :status, presence: true, inclusion: { in: ["pending", "approved", "rejected", "merged"] }
  validates :candidate_name, uniqueness: { scope: :content_id, message: "already has a verification request for this content" }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :merged, -> { where(status: "merged") }

  # Store pending statements as JSON
  # Format: [
  #   { subject: "...", predicate: "...", object: "...", object_type: "...", confidence: 0.9 },
  #   ...
  # ]

  # Store similar entities as JSON
  # Format: [
  #   { id: 1, name: "...", similarity: 0.95 },
  #   ...
  # ]

  # Debug logging
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?

  # Methods

  # Process this verification request with the given action
  # @param action [String] "approve", "reject", or "merge"
  # @param params [Hash] Additional parameters for the action
  # @return [Hash] Result of the action
  def process(action, params = {})
    case action
    when "approve"
      approve_request(params[:entity_id])
    when "reject"
      reject_request
    when "merge"
      merge_request(params[:target_entity_id])
    else
      { success: false, error: "Invalid action: #{action}" }
    end
  end

  # Create a new entity and process pending statements
  # @param entity_id [Integer] Optional existing entity ID to use instead of creating new
  # @return [Hash] Result with success status and entity
  def approve_request(entity_id = nil)
    ActiveRecord::Base.transaction do
      # Use existing entity or create new one
      entity = if entity_id.present?
                 Entity.find(entity_id)
               else
                 Entity.create!(
                   name: candidate_name,
                   content: content,
                   verification_status: "verified",
                   verified_at: Time.current,
                   verified_by: "user"
                 )
               end

      # Process pending statements
      process_pending_statements(entity)

      # Update verification request
      update!(
        status: "approved",
        verified_entity: entity
      )

      # Generate embedding for the entity
      OpenAI::EmbeddingJob.perform_later(entity, :name)

      { success: true, entity: entity }
    rescue StandardError => e
      Rails.logger.error { "[VerificationRequest] Error approving request: #{e.message}" } if ENV["DEBUG"]
      { success: false, error: e.message }
    end
  end

  # Reject this verification request
  # @return [Hash] Result with success status
  def reject_request
    update(status: "rejected")
    { success: true }
  end

  # Merge this entity with another entity
  # @param target_entity_id [Integer] ID of the entity to merge into
  # @return [Hash] Result with success status and target entity
  def merge_request(target_entity_id)
    ActiveRecord::Base.transaction do
      target_entity = Entity.find(target_entity_id)

      # Process pending statements with the target entity
      process_pending_statements(target_entity)

      # Update verification request
      update!(
        status: "merged",
        verified_entity: target_entity
      )

      { success: true, entity: target_entity }
    rescue StandardError => e
      Rails.logger.error { "[VerificationRequest] Error merging request: #{e.message}" } if ENV["DEBUG"]
      { success: false, error: e.message }
    end
  end

  private

  # Process pending statements for the given entity
  # @param entity [Entity] The entity to associate statements with
  def process_pending_statements(entity)
    return if pending_statements.blank?

    pending_statements.each do |statement_data|
      # Create the statement with the verified entity
      statement_params = {
        entity: entity,
        text: "#{entity.name} #{statement_data['predicate']} #{statement_data['object']}",
        predicate: statement_data["predicate"],
        object: statement_data["object"],
        object_type: statement_data["object_type"] || "literal",
        confidence: statement_data["confidence"] || 0.7,
        content: content,
        source: "verification",
        extraction_method: "ai"
      }

      # Handle object entity if it's an entity type
      if statement_params[:object_type] == "entity"
        object_entity = Entity.find_by(name: statement_data["object"])
        statement_params[:object_entity] = object_entity if object_entity
      end

      # Create the statement
      statement = Statement.create!(statement_params)

      # Generate embedding
      OpenAI::EmbeddingJob.perform_later(statement, :text) if statement.persisted?
    end
  end

  def log_creation
    Rails.logger.debug { "[VerificationRequest] Created request for '#{candidate_name}' in content ##{content_id}" } if ENV["DEBUG"]
  end

  def log_status_change
    return unless ENV["DEBUG"]

    Rails.logger.debug do
      "[VerificationRequest] Status changed from '#{status_before_last_save}' to '#{status}' for '#{candidate_name}'"
    end
  end
end
