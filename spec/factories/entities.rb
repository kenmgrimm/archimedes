# frozen_string_literal: true

FactoryBot.define do
  factory :entity do
    # Default attributes
    entity_type { "Organization" }
    value { "Acme Corporation" }
    
    # Association with Content
    association :content
    
    # Debug logging
    after(:build) do |entity, _evaluator|
      Rails.logger.debug { "[Factory] Built Entity type: #{entity.entity_type}, value: #{entity.value}" }
    end
    
    after(:create) do |entity, _evaluator|
      Rails.logger.debug { "[Factory] Created Entity ##{entity.id} type: #{entity.entity_type}, value: #{entity.value}" }
    end
    
    # Traits for different entity types
    trait :organization do
      entity_type { "Organization" }
      value { "Acme Corporation" }
    end
    
    trait :person do
      entity_type { "Person" }
      value { "John Doe" }
    end
    
    trait :location do
      entity_type { "Location" }
      value { "San Francisco, CA" }
    end
    
    trait :date do
      entity_type { "Date" }
      value { "2023-06-15" }
    end
    
    trait :topic do
      entity_type { "Topic" }
      value { "Artificial Intelligence" }
    end
  end
end
