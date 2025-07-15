module Neo4j
  class EntityExtractionService
    class ExtractionError < StandardError; end

    # Get the current user
    def current_user
      @current_user ||= User.current
    end

    # Initialize the service with required dependencies
    # @param openai_service [Object] The OpenAI service for processing
    # @param taxonomy_service [TaxonomyService] Service providing taxonomy information
    # @param logger [Logger] Optional logger
    def initialize(openai_service, taxonomy_service: nil, logger: nil)
      @openai = openai_service
      @taxonomy_service = taxonomy_service || Neo4j::TaxonomyService.new(logger: logger)
      @logger = logger || Rails.logger
    end

    # Extract entities and relationships from text and optional documents
    # @param text [String] User-provided text to analyze
    # @param documents [Array<String, File>] Optional array of document paths or file objects
    # @return [Hash] Extracted and validated entities and relationships
    def extract(text, documents: [])
      raise ArgumentError, "Text cannot be blank" if text.blank?

      begin
        # Build taxonomy context for the prompt
        taxonomy_context = build_taxonomy_context

        # Check if we have any image documents
        image_docs = documents.select { |doc| File.extname(doc.to_s).downcase.match?(/\.(jpe?g|png|gif|webp)\z/) }
        text_docs = documents - image_docs

        # Process text content
        all_content = [text]
        text_docs.each do |doc|
          all_content << read_document_content(doc)
        end
        text_content = all_content.join("\n\n")

        # Process images if any
        if image_docs.any?
          # Create a single message with both text and images
          content = []

          # Add text content if present
          unless text_content.strip.empty?
            # Add a clear instruction to analyze both text and images together
            content << {
              type: "text",
              text: "Please analyze the following information. The text describes the image(s) that follow.\n\n#{text_content}"
            }
          end

          # Add images
          image_docs.each do |doc_path|
            content << {
              type: "image_url",
              image_url: {
                url: "data:#{MimeMagic.by_magic(File.open(doc_path, 'rb'))&.type};base64,#{Base64.strict_encode64(File.binread(doc_path))}",
                detail: "high"
              }
            }
          end

          # Ensure we have at least one content item
          content << { type: "text", text: "Analyze the following image(s):" } if content.empty?

          # Add a system message to provide context about the current user
          messages = [
            {
              role: "system",
              content: "You are an AI assistant that extracts structured information from text and images. " \
                       "When the text refers to 'my' or 'I' or other first-person pronouns, it refers to the current user (#{current_user.prompt_description}). " \
                       "When extracting information about vehicles or other items, include all relevant details from both the text and images."
            },
            {
              role: "user",
              content: content
            }
          ]

          response = @openai.extract_entities_with_taxonomy(
            model: "gpt-4-vision-preview",
            messages: messages,
            taxonomy: taxonomy_context
          )
        else
          # For text-only content, we can use the simpler API
          response = @openai.extract_entities_with_taxonomy(
            model: "gpt-4o-turbo",
            text: text_content,
            taxonomy: taxonomy_context
          )
        end

        # Parse and validate the response
        parse_and_validate_response(response)
      rescue StandardError => e
        @logger.error("Extraction failed: #{e.message}")
        raise ExtractionError, "Failed to extract entities: #{e.message}"
      end
    end

    # Extract entities and relationships from a list of messages (can include images)
    # @param messages [Array<Hash>] Array of message hashes with role and content
    # @return [Hash] Extracted and validated entities and relationships
    def extract_with_messages(messages)
      raise ArgumentError, "Messages cannot be empty" if messages.blank?

      begin
        # Build taxonomy context for the prompt
        taxonomy_context = build_taxonomy_context

        # Create a system message with taxonomy context
        system_message = {
          role: "system",
          content: build_neo4j_extraction_prompt(taxonomy_context)
        }

        # Ensure we have a valid messages array with system message first
        messages = [system_message] + messages.reject { |m| m[:role] == "system" }

        # Extract image files from messages
        image_files = extract_images_from_messages(messages)
        user_text = messages.reject do |m|
          m[:role] == "system" || (m[:content].is_a?(Array) && m[:content].any? { |c| c[:type] == "image_url" })
        end.pluck(:content).join("\n\n")
        raw_response = nil

        # Process with OpenAI
        prompt = build_neo4j_extraction_prompt(taxonomy_context) + "\n\nUser provided context:#{user_text}"

        if image_files.any?
          @logger.info("Processing #{image_files.size} image(s) in first pass")
          # First pass: Process images only
          raw_response = @openai.chat_with_files(
            prompt: prompt,
            files: image_files,
            model: "gpt-4o"
          )

          # Extract the content from the image response
          image_content = raw_response.dig("choices", 0, "message", "content")

          if image_content.blank?
            @logger.error("Empty content in image processing response")
            @logger.error("Full response: #{raw_response.inspect}")
            raise ExtractionError, "Empty content in image processing response"
          end

          # Parse the JSON content from image processing
          begin
            response = JSON.parse(image_content, symbolize_names: true)
            @logger.info("Successfully processed #{response[:entities]&.size || 0} entities from images")
          rescue JSON::ParserError => e
            @logger.error("Failed to parse image processing response: #{e.message}")
            @logger.error("Content: #{image_content}")
            raise ExtractionError, "Failed to parse image processing response: #{e.message}"
          end
        else
          @logger.info("Processing text-only content")
          raw_response = @openai.extract_entities_with_taxonomy(
            text: messages.pluck(:content).join("\n\n"),
            taxonomy: taxonomy_context
          )
          response = raw_response
        end

        @logger.debug("OpenAI response: #{raw_response.inspect}")
        @logger.debug("Parsed extraction response: #{response.inspect}")

        # Parse and validate the response
        parse_and_validate_response(response, raw_response)
      rescue StandardError => e
        @logger.error("Extraction with messages failed: #{e.message}")
        @logger.error(e.backtrace.join("\n")) if e.backtrace
        raise ExtractionError, "Failed to extract entities from messages: #{e.message}"
      end
    end

    private

    # Build the extraction prompt with taxonomy context
    def build_neo4j_extraction_prompt(taxonomy_context)
      taxonomy_context[:entity_types] || {}
      taxonomy_context[:relationship_types] || {}

      # Get user references for the prompt
      user_refs = current_user.all_references
      user_description = current_user.prompt_description

      <<~PROMPT
        Extract detailed knowledge from the provided content to build a comprehensive personal knowledge graph.
        Focus on identifying all relevant entities, their properties, and relationships.

        # User Context:
        - You are analyzing content for: #{user_description} (ID: #{current_user.id})
        - First-person pronouns (I, me, my, mine) refer to this user
        - Known aliases: #{user_refs.join(', ')}

        # Extraction Guidelines:
        1. Extract ALL possible entities and relationships from the content
        2. Include every relevant detail as entity properties
        3. Set confidence scores (0.0-1.0) reflecting your certainty
        4. Always include the exact source text for each extraction

        # For Images/Documents:
        - Create Photo/Document entities with all available metadata
        - Extract and link any identifiable content (people, assets, text)
        - Include detailed descriptions of visual content

        # For Assets:
        - Attempt to describe any asset that can be seen as a full asset.  Any part of an Asset, for example a keyboard on a laptop, a door on a house, a wheel on a car, etc. should be categorized as the parent asset.  A door on a house should be categorized as the house.
        - Create Asset entities with all available metadata
        - Include detailed descriptions of visual content

        # For Lists:
        - Create List and ListItem entities
        - Extract quantities, descriptions, and other structured data
        - Preserve the original text in source_text

        # Response Format (JSON):
        {
          "entities": [{
            "type": "EntityType",
            "name": "Name",
            "properties": {"key": "value"},
            "confidence": 0.95,
            "source_text": "Original text"
          }],
          "relationships": [{
            "type": "RELATIONSHIP_NAME",
            "source": "SourceEntity",
            "source_type": "SourceEntityType",
            "target": "TargetEntity",
            "target_type": "TargetEntityType",
            "properties": {"key": "value"},
            "confidence": 0.95,
            "source_text": "Original text"
          }]
        }

        Response Examples:

        # Asset Example:
        {
          "entities": [
            {
              "type": "Person",
              "name": "John Doe",
              "properties": {"email": "john@example.com"},
              "confidence": 0.98,
              "source_text": "John Doe's laptop"
            },
            {
              "type": "Asset",
              "name": "MacBook Pro 2023",
              "properties": {
                "model": "MacBook Pro 16"",
                "serial_number": "C02X12345678"
              },
              "confidence": 0.97,
              "source_text": "MacBook Pro 2023"
            }
          ],
          "relationships": [
            {
              "type": "OWNS",
              "source": "John Doe",
              "source_type": "Person",
              "target": "MacBook Pro 2023",
              "target_type": "Asset",
              "properties": {
                "since": "2023-01-15",
                "purchase_price": 2499.99
              },
              "confidence": 0.99,
              "source_text": "John Doe's MacBook Pro 2023"
            }
          ]
        }

        # List Example:
        {
          "entities": [
            {
              "type": "List",
              "name": "Hardware Store Shopping List",
              "properties": {
                "category": "shopping",
                "status": "active"
              },
              "confidence": 0.95,
              "source_text": "hardware store list"
            },
            {
              "type": "ListItem",
              "name": "desk cord clips",
              "properties": {},
              "confidence": 0.99,
              "source_text": "desk cord clips"
            },
            {
              "type": "ListItem",
              "name": "Clothesline",
              "properties": {},
              "confidence": 0.99,
              "source_text": "Clothesline"
            }
          ],
          "relationships": [
            {
              "type": "HAS_ITEM",
              "source": "Hardware Store Shopping List",
              "source_type": "List",
              "target": "desk cord clips",
              "target_type": "ListItem",
              "properties": {},
              "confidence": 0.95,
              "source_text": "hardware store list: desk cord clips"
            },
            {
              "type": "HAS_ITEM",
              "source": "Hardware Store Shopping List",
              "source_type": "List",
              "target": "Clothesline",
              "target_type": "ListItem",
              "properties": {},
              "confidence": 0.95,
              "source_text": "hardware store list: Clothesline"
            }
          ]
        }
      PROMPT
    end

    # Format entity types for the prompt
    def format_entity_types(types)
      return "None defined" if types.blank?

      types.map do |type, details|
        # Normalize details to use string keys
        details = details.with_indifferent_access if details.respond_to?(:with_indifferent_access)

        desc = if details.is_a?(Hash)
                 details["description"] || details[:description] || "No description available"
               else
                 "No description available"
               end

        props = if details.is_a?(Hash) && (details["properties"] || details[:properties])
                  props_hash = details["properties"] || details[:properties]
                  props_hash.map do |k, v|
                    prop_desc = v.is_a?(Hash) ? v.inspect : v.to_s
                    "  - #{k}: #{prop_desc}"
                  end.join("\n")
                else
                  "  No properties defined"
                end

        "#{type}: #{desc}\n#{props}"
      end.join("\n\n")
    end

    # Format relationship types for the prompt
    def format_relationship_types(types)
      return "None defined" if types.blank?

      types.map do |name, details|
        desc = if details.is_a?(Hash)
                 details[:description] || details["description"] || "No description available"
               else
                 "No description available"
               end

        source = if details.is_a?(Hash)
                   details[:source] || details["source"] || "Unknown source"
                 else
                   "Unknown source"
                 end

        target = if details.is_a?(Hash)
                   details[:target] || details["target"] || "Unknown target"
                 else
                   "Unknown target"
                 end

        "#{name}: #{desc}\n  Source: #{source}\n  Target: #{target}"
      end.join("\n\n")
    end

    # Extract image files from messages for processing
    # @param messages [Array<Hash>] Array of message hashes with role and content
    # @return [Array<Hash>] Array of file hashes with filename and data
    def extract_images_from_messages(messages)
      files = []

      messages.each do |msg|
        next unless msg[:role] == "user"

        content = msg[:content]

        # Handle both string content (text) and array content (mixed media)
        next unless content.is_a?(Array)

        content.each do |item|
          next unless item.is_a?(Hash) && item[:type] == "image_url"

          # Extract base64 data from data URL
          data_url = item.dig(:image_url, :url)
          next unless data_url

          next unless data_url =~ %r{^data:image/(\w+);base64,(.*)$}

          mime_type = ::Regexp.last_match(1)
          base64_data = ::Regexp.last_match(2)

          files << {
            filename: "image.#{mime_type}",
            data: Base64.decode64(base64_data)
          }
        end
      end

      files
    end

    # Build a structured context of the taxonomy for the LLM
    def build_taxonomy_context
      {
        entity_types: entity_types_with_properties,
        relationship_types: relationship_types_with_descriptions,
        property_types: property_type_descriptions
      }
    end

    # Get all entity types with their properties
    def entity_types_with_properties
      @taxonomy_service.entity_types.index_with do |type|
        entity_definition = @taxonomy_service.taxonomy_for(type)
        {
          description: entity_definition["description"] || "No description available",
          properties: @taxonomy_service.properties_for(type)
        }
      end
    end

    # Get all relationship types with their descriptions
    def relationship_types_with_descriptions
      relationships = {}
      @taxonomy_service.entity_types.each do |type|
        @taxonomy_service.relationship_types_for(type).each do |rel_name, rel_def|
          relationships[rel_name] = {
            description: rel_def[:description],
            source: type,
            target: Array(rel_def[:target]).join(" or ")
          }
        end
      end
      relationships
    end

    # Get descriptions for all property types
    def property_type_descriptions
      @taxonomy_service.property_types.transform_values { |v| v["description"] }
    end

    # Generate a unique signature for an entity to detect duplicates
    def entity_signature(entity)
      "#{entity[:type]}:#{entity[:name]}:#{entity.dig(:properties, :id) || entity.dig('properties', 'id')}"
    end

    # Generate a unique signature for a relationship to detect duplicates
    def relationship_signature(rel)
      "#{rel[:type]}:#{rel[:source]}->#{rel[:target]}:#{rel.dig(:properties, :id) || rel.dig('properties', 'id')}"
    end

    def parse_and_validate_response(response, raw_response)
      # Log the raw response for debugging
      @logger.debug("Raw response: #{response.class.name}")
      @logger.debug("Response content: #{response.inspect}")

      # If response is already in the expected format, return it
      if response.is_a?(Hash) && response.key?(:entities) && response.key?(:relationships)

        # Store the full response for debugging
        response[:openai_response] = raw_response

        @logger.debug("Response is already in the expected format")
        return response
      end

      ### Maybe nothing past here is necessary

      # Handle error responses from the API
      if response.is_a?(Hash) && response[:error].present?
        error_msg = "OpenAI API error: #{response[:error][:message]}"
        # Store the full response for debugging
        response[:openai_response] = raw_response
        @logger.error(error_msg)
        raise ExtractionError, error_msg
      end

      # Extract content from the response
      content = extract_content_from_response(response)
      @logger.debug("Parsed content: #{content.inspect}")

      # If we have a direct hash response, use it as the result
      result = content.is_a?(Hash) ? content : { content: content }

      # Normalize keys to symbols
      result = result.transform_keys(&:to_sym) if result.respond_to?(:transform_keys)

      # Extract the actual response from under the :valid key if it exists
      if result.key?(:valid) && result[:valid].is_a?(Hash)
        result = result[:valid]
        result = result.transform_keys(&:to_sym) if result.respond_to?(:transform_keys)
      end

      # Check for error messages in the response
      if result[:error].present?
        error_msg = "OpenAI API error: #{result[:error][:message]}"
        @logger.error(error_msg)
        raise ExtractionError, error_msg
      end

      # Handle case where the response is in the OpenAI chat format
      if result.dig(:choices, 0, :message, :content).present?
        content = result.dig(:choices, 0, :message, :content)
        if content.is_a?(String)
          begin
            result = JSON.parse(content, symbolize_names: true)
          rescue JSON::ParserError => e
            @logger.error("Failed to parse message content as JSON: #{e.message}")
            result = { content: content }
          end
        end
      end

      # Ensure we have the required top-level keys or provide defaults
      result[:entities] ||= []
      result[:relationships] ||= []

      # Store the full response for debugging
      result[:openai_response] = raw_response

      # Ensure entities and relationships are arrays
      unless result[:entities].is_a?(Array) && result[:relationships].is_a?(Array)
        @logger.error("Invalid data types in response")
        @logger.error("Entities type: #{result[:entities].class.name}")
        @logger.error("Relationships type: #{result[:relationships].class.name}")
        raise ExtractionError, "Invalid response format: 'entities' and 'relationships' must be arrays"
      end

      result
    end

    # Extract content from various response formats
    def extract_content_from_response(response)
      if response.is_a?(String)
        begin
          JSON.parse(response, symbolize_names: true)
        rescue JSON::ParserError => e
          @logger.error("Failed to parse JSON response: #{e.message}")
          raise ExtractionError, "Invalid JSON response from OpenAI API"
        end
      elsif response.is_a?(Hash)
        # Try to get content from choices[0].message.content
        content = response.dig(:choices, 0, :message, :content) || response

        if content.is_a?(String) && content.start_with?("{")
          begin
            JSON.parse(content, symbolize_names: true)
          rescue JSON::ParserError => e
            @logger.error("Failed to parse content as JSON: #{e.message}")
            { content: content }
          end
        else
          content.respond_to?(:to_h) ? content.to_h : content
        end
      end
    end

    # Validate a relationship against the taxonomy
    def validate_relationship(relationship)
      rel_type = relationship[:type]

      # Check if relationship type is present and valid
      if rel_type.nil? || rel_type.to_s.strip.empty?
        relationship[:validation_status] = "missing_type"
        @logger.error("Relationship is missing a type: #{relationship.inspect}")
        return
      end

      # Convert to string and normalize case
      rel_type_str = rel_type.to_s.strip.upcase

      # Get all available relationship types from the taxonomy
      available_relationships = {}
      @taxonomy_service.entity_types.each do |entity_type|
        @taxonomy_service.relationship_types_for(entity_type).each do |rel_name, rel_def|
          available_relationships[rel_name.to_s.upcase] = rel_def
        end
      end

      # Check if the relationship type exists (case-insensitive)
      if available_relationships.key?(rel_type_str)
        # Update the relationship type to match the case in the taxonomy
        relationship[:type] = available_relationships[rel_type_str].keys.first.to_s
        return
      end

      # If we get here, the relationship type is not valid
      relationship[:validation_status] = "type_not_allowed"
      @logger.warn("Relationship type '#{rel_type}' is not in allowed types")
      @logger.debug("Available relationship types: #{available_relationships.keys.inspect}")

      # Try to find a similar relationship type
      similar = available_relationships.keys.find { |t| t.downcase == rel_type_str.downcase }
      return unless similar

      relationship[:suggested_type] = similar
      @logger.info("Did you mean '#{similar}'?")
    end

    def read_document_content(document)
      if document.respond_to?(:read)
        document.read
      elsif File.exist?(document.to_s)
        File.read(document)
      else
        raise ArgumentError, "Invalid document: #{document}"
      end
    end

    # Format taxonomy terms for display
    # @param terms [Array<String>] Array of term strings
    # @return [String] Formatted terms as a string
    def format_taxonomy_terms(terms)
      return "None defined" if terms.blank?

      terms.map { |t| "- #{t}" }.join("\n")
    end
  end
end
