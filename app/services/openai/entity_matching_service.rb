# frozen_string_literal: true

module OpenAI
  class EntityMatchingService
    class EntityRelationship < Struct.new(:type, :confidence, :reason, :existing_entity, :new_entity)
      # type: :duplicate, :component, or :none
      # confidence: Float between 0.0 and 1.0
      # reason: Explanation of the relationship
      # existing_entity: The existing entity (for components, this is the parent)
      # new_entity: The new entity being analyzed
    end

    def initialize(api_key: nil, model: "gpt-4")
      @client = OpenAI::Client.new(access_token: api_key || ENV.fetch("OPENAI_API_KEY", nil))
      @model = model
    end

    # Determines the relationship between a new entity and an existing one
    # @param existing_entity [Hash] The existing entity in the system
    # @param new_entity [Hash] The new entity being analyzed
    # @param entity_type [String] Type of entity (e.g., 'Person', 'Vehicle')
    # @return [EntityRelationship] The relationship between the entities
    def analyze_relationship(existing_entity, new_entity, entity_type)
      return EntityRelationship.new(:none, 0.0, "Invalid input") if existing_entity.nil? || new_entity.nil? || entity_type.nil?
      return EntityRelationship.new(:duplicate, 1.0, "Exact match", existing_entity, new_entity) if existing_entity == new_entity

      prompt = build_analysis_prompt(existing_entity, new_entity, entity_type)

      begin
        response = @client.chat(
          parameters: {
            model: @model,
            messages: [
              { role: "system", content: system_prompt },
              { role: "user", content: prompt }
            ],
            temperature: 0.1,
            max_tokens: 200
          }
        )

        parse_relationship_response(response, existing_entity, new_entity)
      rescue StandardError => e
        Rails.logger.error("Error in EntityMatchingService: #{e.message}")
        EntityRelationship.new(:none, 0.0, "Error: #{e.message}", existing_entity, new_entity)
      end
    end

    # For backward compatibility
    def match?(entity1, entity2, entity_type)
      relationship = analyze_relationship(entity1, entity2, entity_type)
      relationship.type == :duplicate
    end

    private

    def system_prompt
      <<~PROMPT
        You are an AI assistant that analyzes relationships between entities for a personal organization system.
        Your goal is to help users manage their possessions, tasks, events, and life goals.

        When analyzing entities, consider:
        1. If they are the same entity (duplicates)
        2. If one is a component or part of the other (e.g., a license plate is part of a car)
        3. If they should be related in some other way

        Focus on relationships that would be meaningful for personal organization, not industrial inventory systems.
        Be practical and consider how a typical person would want these items organized.
      PROMPT
    end

    def build_analysis_prompt(existing_entity, new_entity, entity_type)
      <<~PROMPT
        Analyze the relationship between these two #{entity_type} entities:

        EXISTING ENTITY:
        #{JSON.pretty_generate(existing_entity)}

        NEW ENTITY:
        #{JSON.pretty_generate(new_entity)}

        Determine if:
        1. They represent the SAME entity (duplicates)
        2. The new entity is a COMPONENT of the existing entity
        3. The existing entity is a COMPONENT of the new entity
        4. They are UNRELATED

        Respond in this exact JSON format:
        {
          "relationship_type": "duplicate|component|reverse_component|none",
          "confidence": 0.0-1.0,
          "reason": "Brief explanation of the relationship"
        }
      PROMPT
    end

    def parse_relationship_response(response, existing_entity, new_entity)
      content = response.dig("choices", 0, "message", "content").to_s.strip

      begin
        result = JSON.parse(content)
        type = case result["relationship_type"]
               when "duplicate" then :duplicate
               when "component" then :component
               when "reverse_component" then :reverse_component
               else :none
               end

        EntityRelationship.new(
          type,
          result["confidence"].to_f.clamp(0.0, 1.0),
          result["reason"],
          existing_entity,
          new_entity
        )
      rescue JSON::ParserError
        Rails.logger.error("Failed to parse AI response: #{content}")
        EntityRelationship.new(:none, 0.0, "Invalid response format", existing_entity, new_entity)
      end
    end
  end
end
