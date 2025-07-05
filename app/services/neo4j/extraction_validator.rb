# frozen_string_literal: true

module Neo4j
  class ExtractionValidator
    class ValidationError < StandardError; end

    # Schema for the extraction data
    EXTRACTION_SCHEMA = {
      type: :hash,
      required: [:entities, :relationships],
      additional_properties: true, # Allow additional properties at the root level
      properties: {
        entities: {
          type: :array,
          items: {
            type: :hash,
            required: [:type, :id, :properties],
            additional_properties: true, # Allow additional properties in entities
            properties: {
              type: { type: :string, not_blank: true },
              id: { type: :string, not_blank: true },
              properties: {
                type: :hash,
                additional_properties: true # Allow any properties in the properties hash
              },
              confidence: { type: :numeric, optional: true, min: 0, max: 1 },
              source: { type: :string, optional: true },
              metadata: {
                type: :hash,
                optional: true,
                additional_properties: true # Allow any metadata
              }
            }
          }
        },
        relationships: {
          type: :array,
          items: {
            type: :hash,
            required: [:type, :source_id, :target_id],
            additional_properties: true, # Allow additional properties in relationships
            properties: {
              type: { type: :string, not_blank: true },
              source_id: { type: :string, not_blank: true },
              target_id: { type: :string, not_blank: true },
              properties: {
                type: :hash,
                optional: true,
                additional_properties: true # Allow any relationship properties
              },
              confidence: { type: :numeric, optional: true, min: 0, max: 1 },
              metadata: {
                type: :hash,
                optional: true,
                additional_properties: true # Allow any metadata
              }
            }
          }
        },
        metadata: {
          type: :hash,
          optional: true,
          additional_properties: true, # Allow any metadata at the root level
          properties: {
            source: { type: :string, optional: true },
            timestamp: { type: :string, format: :date_time, optional: true },
            version: { type: :string, optional: true }
          }
        }
      }
    }.freeze

    def self.validate!(extraction_data)
      new(extraction_data).validate!
    end

    def initialize(extraction_data)
      @data = extraction_data
      @errors = []
    end

    def validate!
      validate_structure
      validate_entity_references

      return true if @errors.empty?

      error_messages = @errors.map { |e| "- #{e}" }.join("\n")
      raise ValidationError, "Extraction validation failed:\n#{error_messages}"
    end

    private

    def validate_structure
      validate_schema(EXTRACTION_SCHEMA, @data, "")
    end

    def validate_entity_references
      return unless @data.is_a?(Hash) && @data[:relationships].is_a?(Array)

      entity_ids = Set.new

      # Collect all entity IDs
      Array(@data[:entities]).each do |entity|
        entity_ids << entity[:id] if entity.is_a?(Hash) && entity[:id].present?
      end

      # Check relationship references
      @data[:relationships].each_with_index do |rel, index|
        next unless rel.is_a?(Hash)

        @errors << "Relationship #{index}: Source entity not found: #{rel[:source_id]}" unless entity_ids.include?(rel[:source_id])

        @errors << "Relationship #{index}: Target entity not found: #{rel[:target_id]}" unless entity_ids.include?(rel[:target_id])
      end
    end

    def validate_schema(schema, data, path)
      case schema[:type]
      when :hash
        validate_hash(schema, data, path)
      when :array
        validate_array(schema, data, path)
      when :string
        validate_string(schema, data, path)
      when :numeric
        validate_numeric(schema, data, path)
      when :boolean
        validate_boolean(schema, data, path)
      end
    end

    def validate_hash(schema, data, path)
      return unless data.is_a?(Hash)

      # Check required fields
      Array(schema[:required]).each do |field|
        @errors << "#{path}Missing required field: #{field}" unless data.key?(field) || data.key?(field.to_s)
      end

      # Validate each property
      data.each do |key, value|
        key_sym = key.to_sym
        prop_schema = schema.dig(:properties, key) || schema.dig(:properties, key_sym)

        if prop_schema.nil? && !schema[:additional_properties]
          @errors << "#{path}Unexpected field: #{key}"
          next
        end

        next if prop_schema.nil? || (prop_schema[:optional] && value.nil?)

        validate_schema(prop_schema, value, "#{path}#{key}.")
      end
    end

    def validate_array(schema, data, path)
      return unless data.is_a?(Array)

      item_schema = schema[:items]
      return unless item_schema

      data.each_with_index do |item, index|
        validate_schema(item_schema, item, "#{path}[#{index}].")
      end
    end

    def validate_string(schema, data, path)
      return if !data.is_a?(String) && !data.is_a?(Symbol)

      @errors << "#{path}String cannot be blank" if schema[:not_blank] && data.to_s.strip.empty?

      return unless schema[:format] == :date_time

      begin
        Time.iso8601(data.to_s)
      rescue ArgumentError
        @errors << "#{path}Invalid ISO 8601 date format: #{data}"
      end
    end

    def validate_numeric(schema, data, path)
      return if data.is_a?(Numeric)

      # Try to convert to numeric if it's a string
      numeric_value = /^\d+(\.\d+)?$/.match?(data.to_s) ? data.to_f : nil

      if numeric_value.nil?
        @errors << "#{path}Expected numeric value, got #{data.class}"
        return
      end

      @errors << "#{path}Value must be at least #{schema[:min]}" if schema[:min] && numeric_value < schema[:min]

      return unless schema[:max] && numeric_value > schema[:max]

      @errors << "#{path}Value must be at most #{schema[:max]}"
    end

    def validate_boolean(_schema, data, path)
      return if [true, false].include?(data)

      @errors << "#{path}Expected boolean value, got #{data.class}"
    end
  end
end
