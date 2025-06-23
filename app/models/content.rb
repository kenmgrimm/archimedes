class Content < ApplicationRecord
  has_many_attached :files

  validate :note_or_file_present
  after_save :log_file_attachments

  private

  def note_or_file_present
    if note.blank? && !files.attached?
      errors.add(:base, "You must provide a note or attach at least one file.")
    end
  end

  def log_file_attachments
    Rails.logger.debug do
      "[Content] Saved content ##{id} with #{files.attachments.size} attached file(s). Note: '#{note&.truncate(40)}'"
    end
  end
end
