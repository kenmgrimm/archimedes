module Neo4j
  class TaxonomyService
    class TaxonomyError < StandardError; end

    def initialize(logger: Rails.logger)
      @logger = logger
      @taxonomies = {}
      @property_types = nil
      load_taxonomies
    end

    # Load all taxonomy files from config/taxonomies and app/services/neo4j
    def load_taxonomies
      # Load from config/taxonomies first (if any)
      taxonomies_dir = Rails.root.join("app", "services", "neo4j", "taxonomy")
      if File.directory?(taxonomies_dir)
        Dir.glob(File.join(taxonomies_dir, "*.yml")).each do |file|
          load_taxonomy(file)
        end
      end
    rescue StandardError => e
      @logger.error("Failed to load taxonomies: #{e.message}")
      raise TaxonomyError, "Failed to load taxonomies: #{e.message}"
    end

    # Load a single taxonomy file
    def load_taxonomy(file_path)
      yaml_content = YAML.load_file(file_path, aliases: true) || {}

      # Handle the case where the YAML file is empty or invalid
      raise TaxonomyError, "Empty or invalid YAML file: #{file_path}" if yaml_content.nil?

      # Process entity types
      yaml_content.each do |key, value|
        next if key == "property_types" # Handle property types separately

        # Ensure properties exist and is a hash
        value = { "properties" => {} } unless value.is_a?(Hash)
        value["properties"] ||= {}

        # Handle inheritance
        if value["extends"]
          parent_type = value["extends"]
          parent_props = @taxonomies[parent_type]&.dig("properties") || {}
          value["properties"] = parent_props.merge(value["properties"])
        end

        @taxonomies[key] = value
      end

      # Handle property types if defined in the YAML
      @taxonomies["property_types"] = yaml_content["property_types"] if yaml_content["property_types"]
    rescue Psych::SyntaxError => e
      @logger.error("YAML syntax error in #{file_path}: #{e.message}")
      raise TaxonomyError, "YAML syntax error in #{file_path}: #{e.message}"
    rescue StandardError => e
      @logger.error("Failed to load taxonomy from #{file_path}: #{e.message}")
      raise TaxonomyError, "Failed to load taxonomy from #{file_path}: #{e.message}"
    end

    # Get all entity types
    def entity_types
      @taxonomies.keys.reject { |k| k == "property_types" }
    end

    # Get properties for a specific entity type (excludes relationships)
    def properties_for(entity_type)
      entity = @taxonomies[entity_type.to_s]
      return {} unless entity && entity["properties"]

      entity["properties"].each_with_object({}) do |(key, value), hash|
        # Convert property definition to a consistent hash format
        prop = value.is_a?(Hash) ? value.dup : { "type" => value }

        # Set default type to 'Text' if not specified
        prop["type"] ||= "Text"

        # Convert to symbolized keys for consistent access
        hash[key] = prop.transform_keys(&:to_sym)
      end
    end

    # Get all relationship types for an entity type
    def relationship_types_for(entity_type)
      entity = @taxonomies[entity_type.to_s]
      return {} unless entity

      # Get relationships from the relations section
      relations = entity["relations"] || {}

      # Convert to the expected format
      relations.transform_values do |rel_def|
        {
          target: rel_def["to"],
          cardinality: rel_def["cardinality"] || "one",
          description: rel_def["description"]
        }
      end
    end

    # Get all property types
    def property_types
      @property_types ||= load_property_types
    end

    # Get the full taxonomy definition for a specific entity type
    # @param entity_type [String] The type of entity to look up
    # @return [Hash] The full entity definition including description, properties, and relations
    def taxonomy_for(entity_type)
      @taxonomies[entity_type.to_s] || {}
    end

    # Load property types from built-in and custom definitions
    def load_property_types
      # First add the built-in types
      built_in_types = {
        "Text" => { "description" => "Plain text" },
        "Email" => { "description" => "Email address" },
        "URL" => { "description" => "Web URL" },
        "DateTime" => { "description" => "Date and time (ISO 8601)" },
        "Duration" => { "description" => "Time duration (ISO 8601 duration format)" },
        "Boolean" => { "description" => "True or false" },
        "Number" => { "description" => "Numeric value" },
        "Object" => { "description" => "Arbitrary key-value data" },
        "Relationship" => { "description" => "Reference to another entity" }
      }

      # Add any additional types defined in the taxonomy
      built_in_types.merge!(@taxonomies["property_types"] || {})

      built_in_types.transform_keys(&:to_s)
    end

    # Validate if a property is valid for an entity type
    def valid_property?(entity_type, property_name)
      properties_for(entity_type).key?(property_name.to_sym)
    end

    # Validate if a value is valid for a property
    def valid_property_value?(entity_type, property_name, value)
      prop = properties_for(entity_type)[property_name.to_sym]
      return false unless prop

      case prop[:type]
      when "Text"
        value.is_a?(String)
      when "Integer"
        value.is_a?(Integer) || value.to_s =~ /^\d+$/
      when "Float"
        value.is_a?(Numeric) || value.to_s =~ /^\d+(\.\d+)?$/
      when "Boolean"
        [true, false].include?(value) || ["true", "false"].include?(value.to_s.downcase)
      when "Date", "DateTime"
        # Simple date format validation - could be enhanced with actual date parsing
        value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime) || value.to_s =~ /^\d{4}-\d{2}-\d{2}/
      else
        # For custom types, check if they're defined in property_types
        property_types.key?(prop[:type])
      end
    end

    # Get all required properties for an entity type
    def required_properties_for(entity_type)
      properties = properties_for(entity_type)
      properties.select { |_, prop| prop[:required] }.keys
    end

    # Get the type of a specific property for an entity type
    def property_type_for(entity_type, property_name)
      properties = properties_for(entity_type)
      properties[property_name.to_sym]&.dig(:type)
    end

    # Check if a property is required for an entity type
    def required_property?(entity_type, property_name)
      properties = properties_for(entity_type)
      properties[property_name.to_sym]&.dig(:required) || false
    end

    # Get all possible values for an enum property
    def enum_values_for(entity_type, property_name)
      properties = properties_for(entity_type)
      properties[property_name.to_sym]&.dig(:enum)
    end

    # Get the default value for a property
    def default_value_for(entity_type, property_name)
      properties = properties_for(entity_type)
      properties[property_name.to_sym]&.dig(:default)
    end

    # Get the description for a property
    def property_description(entity_type, property_name)
      properties = properties_for(entity_type)
      properties[property_name.to_sym]&.dig(:description)
    end

    # Get all entities that extend a specific type
    def entities_extending(type_name)
      @taxonomies.select do |_, entity|
        entity.is_a?(Hash) && entity["extends"] == type_name
      end.keys
    end

    # Get all relationships where this entity type is the target
    def relationships_targeting(entity_type)
      @taxonomies.each_with_object({}) do |(source_type, entity), result|
        next unless entity.is_a?(Hash) && entity["relations"]

        entity["relations"].each do |rel_name, rel_def|
          target = rel_def["to"]
          target = [target] unless target.is_a?(Array)

          next unless target.include?(entity_type)

          result[source_type] ||= {}
          result[source_type][rel_name] = {
            cardinality: rel_def["cardinality"] || "one",
            description: rel_def["description"]
          }
        end
      end
    end

    # Get all relationships for an entity type, including both incoming and outgoing
    def all_relationships_for(entity_type)
      outgoing = relationship_types_for(entity_type).transform_values { |v| v.merge(direction: :outgoing) }
      incoming = relationships_targeting(entity_type).each_with_object({}) do |(source, rels), hash|
        rels.each do |rel_name, rel_def|
          hash["#{source}_#{rel_name}"] = rel_def.merge(
            direction: :incoming,
            source: source
          )
        end
      end

      outgoing.merge(incoming)
    end

    # Get the parent type of an entity
    def parent_type(entity_type)
      @taxonomies[entity_type.to_s]&.dig("extends")
    end

    # Check if a type is a subtype of another type
    def subtype_of?(subtype, supertype)
      current = subtype
      while current
        return true if current == supertype

        current = parent_type(current)
      end
      false
    end

    # Get all properties including inherited ones
    def all_properties_for(entity_type)
      properties = {}
      current = entity_type

      while current
        entity = @taxonomies[current.to_s]
        if entity && entity["properties"]
          # Convert to symbolized keys for consistency
          entity_props = entity["properties"].transform_keys(&:to_sym)
          properties = entity_props.merge(properties)
        end
        current = entity&.dig("extends")
      end

      properties
    end

    # Validate an entity against its type definition
    def validate_entity(entity_type, entity_data)
      errors = []
      properties = all_properties_for(entity_type)

      # Check for missing required properties
      properties.each do |prop_name, prop_def|
        if prop_def[:required] && !entity_data.key?(prop_name.to_s) && !entity_data.key?(prop_name.to_sym)
          errors << "Missing required property: #{prop_name}"
        end
      end

      # Check property types
      entity_data.each do |key, value|
        prop_def = properties[key.to_sym] || properties[key.to_s]
        next unless prop_def

        # Check enum values if specified
        if prop_def[:enum]&.exclude?(value)
          errors << "Invalid value '#{value}' for property '#{key}'. Must be one of: #{prop_def[:enum].join(', ')}"
        end

        # TODO: Add type validation based on property type
      end

      errors
    end
  end
end
