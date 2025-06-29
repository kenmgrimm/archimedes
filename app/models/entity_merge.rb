# frozen_string_literal: true

# Model for tracking entity merges in the knowledge graph
class EntityMerge < ApplicationRecord
  # Associations
  belongs_to :source_entity, class_name: "Entity", optional: true
  belongs_to :target_entity, class_name: "Entity"

  # Validations
  validate :source_and_target_must_differ

  # Debug logging
  after_create :log_merge

  private

  def source_and_target_must_differ
    return unless source_entity_id.present? && source_entity_id == target_entity_id

    errors.add(:source_entity_id, "cannot be the same as target entity")
  end

  def log_merge
    return unless ENV["DEBUG"]

    Rails.logger.debug do
      "[EntityMerge] Merged entity ##{source_entity_id} into ##{target_entity_id} (#{transferred_statements_count} statements transferred)"
    end
  end
end
