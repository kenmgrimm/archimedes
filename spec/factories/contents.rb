# frozen_string_literal: true

FactoryBot.define do
  factory :content do
    # Default attributes
    note { "This is a sample note for testing" }
    
    # Debug logging
    after(:build) do |content, _evaluator|
      Rails.logger.debug { "[Factory] Built Content with note: #{content.note&.truncate(30)}" }
    end
    
    after(:create) do |content, _evaluator|
      Rails.logger.debug { "[Factory] Created Content ##{content.id} with note: #{content.note&.truncate(30)}" }
    end
  end
end
