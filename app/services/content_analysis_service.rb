# frozen_string_literal: true

require_relative "openai/client_service"
require "yaml"
require "json"

# Service to analyze uploaded content and notes, and extract/annotate entities using OpenAI
class ContentAnalysisService
  # V2 Data Model: Using statements instead of typed entities
  OUTPUT_FORMAT_PATH = Rails.root.join("app", "services", "openai", "statement_output_format.json")

  def initialize(openai_service: OpenAI::ClientService.new)
    @openai_service = openai_service
    @output_format = JSON.parse(File.read(OUTPUT_FORMAT_PATH))
  end

  # Analyze content: notes (array of strings) and files (array of hashes: {filename, text_content})
  # Returns the OpenAI response parsed as JSON
  # @raise [TypeError] if the response is not a valid hash
  # @raise [ArgumentError] if the response doesn't match the required format
  def analyze(notes:, files:)
    results = []
    if files.blank? || files.empty?
      response = @openai_service.chat(build_prompt(notes), model: "gpt-4o", max_tokens: 4096)
      content = response.dig("choices", 0, "message", "content")
      result = parse_response(content)

      # Validate response format
      validate_response_format(result)

      results << { note: notes.join("\n"), file: nil, result: result }
    else
      files.each do |file|
        # Get filename for logging
        filename = file[:filename] || (file.respond_to?(:filename) && file.filename.to_s) || "unknown"

        # Log that we're processing this file
        log_safe("Processing file: #{filename} for analysis")

        prompt = build_prompt(notes)
        # Get file data without logging binary content
        begin
          # Extract file data based on the file object type
          file_data = if file.respond_to?(:download)
                        log_safe("Downloading file content for #{filename}")
                        file.download
                      elsif file.is_a?(Hash) && file[:data]
                        file[:data]
                      else
                        raise "Unable to extract file data from #{filename}"
                      end

          # Get file size for logging (without storing large data in logs)
          file_size = file_data.respond_to?(:bytesize) ? file_data.bytesize : file_data.to_s.bytesize
          log_safe("File #{filename} size: #{file_size} bytes")

          # Create file argument for OpenAI API
          file_arg = { io: StringIO.new(file_data), filename: filename }

          # Send to OpenAI API
          log_safe("Sending file #{filename} to OpenAI API for analysis")
          response = @openai_service.chat_with_files(note: prompt, files: [file_arg], model: "gpt-4o", max_tokens: 4096)
        rescue StandardError => e
          error_message = "Error processing file #{filename}: #{e.message}"
          log_safe(error_message, :error)
          log_safe("Stack trace: #{e.backtrace[0..5].join('\n')}", :error)
          results << { note: notes.join("\n"), file: filename, result: nil, error: error_message }
          next
        end
        # Extract content from response
        content = response.dig("choices", 0, "message", "content")
        if content.nil?
          log_safe("No content returned from OpenAI API for file #{filename}", :warn)
          results << { note: notes.join("\n"), file: filename, result: nil, error: "No content returned from API" }
          next
        end

        # Parse the response
        log_safe("Parsing response for file #{filename}")
        result = parse_response(content)

        # If parsing failed, try a second pass with a more explicit prompt
        if result.nil?
          log_safe("First parsing attempt failed for #{filename}, trying second pass", :warn)
          begin
            # Re-prompt for JSON as a second pass with more explicit instructions
            second_prompt = "#{prompt}\n\nIMPORTANT: Your response MUST be valid JSON matching the example format exactly."
            log_safe("Sending second request to OpenAI API for file #{filename}")
            response = @openai_service.chat_with_files(note: second_prompt, files: [file_arg], model: "gpt-4o", max_tokens: 4096)
            content = response.dig("choices", 0, "message", "content")
            result = parse_response(content)
          rescue StandardError => e
            error_message = "Error in second parsing attempt for file #{filename}: #{e.message}"
            log_safe(error_message, :error)
            results << { note: notes.join("\n"), file: filename, result: nil, error: error_message }
            next
          end
        end

        # Validate response format
        begin
          validate_response_format(result)
          log_safe("Successfully validated response format for file #{filename}")
        rescue StandardError => e
          error_message = "Invalid response format for file #{filename}: #{e.message}"
          log_safe(error_message, :warn)
          # Still include the result, but note the validation error
          results << { note: notes.join("\n"), file: filename, result: result, validation_error: error_message }
          next
        end

        # Add successful result to results array
        log_safe("Analysis completed successfully for file #{filename}")
        results << { note: notes.join("\n"), file: filename, result: result }
      end
    end
    results
  rescue StandardError => e
    Rails.logger.error("[ContentAnalysisService] Error analyzing content: #{e.message}")
    raise
  end

  # Process analysis results for a content item
  # @param content [Content] The content to process results for
  # @param results [Array<Hash>] The analysis results from analyze method
  # @return [Hash] Summary of processing including created entities and updated content
  def process_analysis_results(content, results)
    return { success: false, message: "No results to process" } if results.blank?

    # Log detailed results
    log_analysis_results(results)

    # Process each result and extract entities
    created_entities = []
    results.each do |result|
      next unless result[:result].present? && result[:result].is_a?(Hash)

      # Extract entities from this result
      entities = extract_and_create_entities(content, result[:result])
      created_entities << entities if entities.present?
    end

    # Flatten the array of created entities
    created_entities = created_entities.flatten.compact

    # Save the OpenAI response to the content record if we have valid results
    if results.any? && results.last[:result].present?
      Rails.logger.debug { "[ContentAnalysisService] Preparing to save OpenAI response for content ##{content.id}" } if ENV["DEBUG"]

      begin
        # Get a fresh instance of the content to avoid any state issues
        fresh_content = Content.find(content.id)
        Rails.logger.debug { "[ContentAnalysisService] Using fresh content instance ##{fresh_content.id}" } if ENV["DEBUG"]

        # Get the raw response - no formatting needed as JSONB handles arrays fine
        last_response = results.last[:result]

        # Log detailed information about the response structure
        log_response_structure(last_response) if ENV["DEBUG"]

        # Directly assign and save
        Rails.logger.debug { "[ContentAnalysisService] Assigning OpenAI response to content" } if ENV["DEBUG"]
        fresh_content.openai_response = last_response

        Rails.logger.debug { "[ContentAnalysisService] Attempting to save content with OpenAI response" } if ENV["DEBUG"]
        if fresh_content.save
          if ENV["DEBUG"]
            Rails.logger.debug do
              "[ContentAnalysisService] Successfully saved OpenAI response to content ##{fresh_content.id}"
            end
          end
          # Update our reference to use the fresh content
          content = fresh_content
        else
          error_msg = "Failed to save OpenAI response: #{fresh_content.errors.full_messages.join(', ')}"
          Rails.logger.error { "[ContentAnalysisService] #{error_msg}" }
          return { success: false, message: error_msg }
        end
      rescue StandardError => e
        Rails.logger.error { "[ContentAnalysisService] Error saving OpenAI response: #{e.message}" }
        Rails.logger.error { "[ContentAnalysisService] Error backtrace: #{e.backtrace.join('\n')}" } if ENV["DEBUG"]
        return { success: false, message: "Error saving OpenAI response: #{e.message}" }
      end
    end

    # Generate summary information
    entity_count = content.entities.reload.count
    skipped_files = results.select { |r| r[:skipped] }.pluck(:file)

    # Return processing summary
    {
      success: true,
      entity_count: entity_count,
      created_entities: created_entities,
      skipped_files: skipped_files,
      results: results
    }
  end

  # Log detailed information about the OpenAI response structure
  # @param response [Hash] The OpenAI response hash
  # @return [void]
  def log_response_structure(response)
    return unless ENV["DEBUG"] && response.is_a?(Hash)

    Rails.logger.debug { "[ContentAnalysisService] Response type: #{response.class.name}" }
    Rails.logger.debug { "[ContentAnalysisService] Response keys: #{response.keys.inspect}" }

    # Log information about arrays in the response
    response.each do |key, value|
      next unless value.is_a?(Array)

      Rails.logger.debug { "[ContentAnalysisService] Key '#{key}' contains an Array with #{value.size} elements" }

      if key.to_s.end_with?("_embedding")
        Rails.logger.debug { "[ContentAnalysisService] Found embedding array for '#{key}' with #{value.size} dimensions" }
      elsif value.size.positive? && value.first.is_a?(Hash)
        Rails.logger.debug { "[ContentAnalysisService] Array contains Hash objects with keys: #{value.first.keys.inspect}" }
      end
    end
  end

  # Log detailed information about analysis results
  # @param results [Array<Hash>] The analysis results
  def log_analysis_results(results)
    return if results.blank?

    results.each_with_index do |result, index|
      Rails.logger.debug { "[ContentAnalysisService] Analysis result ##{index + 1}:" } if ENV["DEBUG"]
      Rails.logger.debug { "  - File: #{result[:file] || 'No file (note only)'}" } if ENV["DEBUG"]

      if result[:result].present? && result[:result].is_a?(Hash)
        Rails.logger.debug { "  - Description: #{result[:result]['description']}" } if ENV["DEBUG"]
        Rails.logger.debug { "  - Annotated Description: #{result[:result]['annotated_description']}" } if ENV["DEBUG"]
        Rails.logger.debug { "  - Confidence Rating: #{result[:result]['rating']}" } if ENV["DEBUG"]

        # Extract and log entities from annotated_description
        entities = extract_entity_names_from_annotation(result[:result]["annotated_description"])

        Rails.logger.debug { "  - Extracted #{entities.size} entities from annotated_description:" } if ENV["DEBUG"]
        entities.each do |entity_name|
          Rails.logger.debug { "    * Entity: #{entity_name}" } if ENV["DEBUG"]
        end
      elsif ENV["DEBUG"]
        Rails.logger.debug { "  - No valid result data" }
      end
    end
  end

  # Extract entity names from annotated description
  # @param annotated_description [String] The annotated description with [Entity: Name] tags
  # @return [Array<String>] Array of entity names
  def extract_entity_names_from_annotation(annotated_description)
    return [] if annotated_description.blank?

    annotated_description.to_s.scan(/\[Entity:\s*([^\]]+)\]/).flatten.map(&:strip).uniq
  end

  # Extract entities and statements from OpenAI result and create records for the given Content.
  # V2 Data Model: Creates entities and statements instead of typed entities.
  # Includes debug logging for all steps.
  def extract_and_create_entities(content, openai_result)
    # Validate content is a Content model instance
    unless content.is_a?(Content)
      Rails.logger.error { "[ContentAnalysisService] Error: content must be a Content model instance, got #{content.class}" }
      return false
    end

    description = openai_result["description"]
    annotated = openai_result["annotated_description"]
    statements = openai_result["statements"]
    return if annotated.blank? && statements.blank?

    # Store description embedding if available
    if description.present?
      Rails.logger.debug { "[ContentAnalysisService] Generating embedding for description: #{description.truncate(50)}" }
      begin
        embedding_service = OpenAI::EmbeddingService.new
        description_embedding = embedding_service.embed(description)

        if description_embedding.present?
          # Store the embedding with the content for future similarity searches
          content.update(note_embedding: description_embedding)
          Rails.logger.debug do
            "[ContentAnalysisService] Successfully stored description embedding with #{description_embedding.size} dimensions to content ##{content.id}"
          end
        end
      rescue StandardError => e
        Rails.logger.error { "[ContentAnalysisService] Error generating description embedding: #{e.message}" }
      end
    end

    Rails.logger.debug { "[ContentAnalysisService] Processing statements and entities" }

    # Extract entities from annotated description if statements aren't provided directly
    if statements.blank? && annotated.present?
      Rails.logger.debug { "[ContentAnalysisService] Extracting entities from annotated description: #{annotated}" }
      # Extract entities from format [Entity: name]
      entity_names = annotated.scan(/\[Entity:\s*([^\]]+)\]/).flatten.map(&:strip).uniq

      # Create simple statements for each entity
      statements = entity_names.map do |name|
        {
          "subject" => name,
          "text" => "is mentioned in the content",
          "confidence" => 0.9
        }
      end

      Rails.logger.debug { "[ContentAnalysisService] Created #{statements.size} basic statements from annotated text" }
    end

    created_entities = []
    created_statements = []

    # Process statements
    statements.each do |statement_data|
      subject_name = statement_data["subject"].strip
      object_name = statement_data["object"]&.strip
      statement_text = statement_data["text"].strip
      confidence = statement_data["confidence"] || 1.0

      # Find or create subject entity
      subject_entity = find_or_create_entity(content, subject_name)
      created_entities << subject_entity if subject_entity.persisted? && created_entities.exclude?(subject_entity)

      # Find or create object entity if present
      object_entity = find_or_create_entity(content, object_name) if object_name.present?
      created_entities << object_entity if object_entity&.persisted? && created_entities.exclude?(object_entity)

      # Create statement
      statement = create_statement(
        content: content,
        entity: subject_entity,
        object_entity: object_entity,
        text: statement_text,
        confidence: confidence
      )

      created_statements << statement if statement&.persisted?
    end

    Rails.logger.debug { "[ContentAnalysisService] Created #{created_entities.size} entities and #{created_statements.size} statements" }

    { entities: created_entities, statements: created_statements }
  end

  private

  # Validates the OpenAI response format
  # @param result [Object] The parsed response from OpenAI
  # @raise [TypeError] If the response is nil or not a hash
  # @raise [ArgumentError] If the response doesn't match the required format
  # Validate the format of the OpenAI response
  # @param result [Hash, nil] The parsed response from OpenAI
  # @raise [TypeError] If the response is nil or not a hash
  # @raise [ArgumentError] If the response doesn't match the required format
  def validate_response_format(result)
    # Check if response is nil
    if result.nil?
      error_msg = "OpenAI response is not valid JSON or could not be parsed"
      log_safe(error_msg, :error)
      raise TypeError, error_msg
    end

    # Check if response is a hash
    unless result.is_a?(Hash)
      error_msg = "OpenAI response has unexpected format: #{result.class}. Expected a Hash."
      log_safe(error_msg, :error)
      raise TypeError, error_msg
    end

    # Check if response matches required output format
    format_errors = validate_output_format_with_details(result)
    unless format_errors.empty?
      error_msg = "OpenAI response format validation failed: #{format_errors.join('; ')}"
      log_safe(error_msg, :error)
      raise ArgumentError, error_msg
    end

    # Log successful validation
    log_safe("Response format validated successfully")
  end

  # Find or create an entity by name
  # @param content [Content] The content to associate the entity with
  # @param name [String] The entity name
  # @return [Entity] The found or created entity
  def find_or_create_entity(content, name)
    return nil if name.blank?

    # Debug logging
    Rails.logger.debug { "[ContentAnalysisService] Finding or creating entity: #{name} for content ##{content.id}" } if ENV["DEBUG"]

    # First, try to find an entity with this name that's already associated with this content
    entity = content.entities.find_by(name: name)

    if entity
      Rails.logger.debug { "[ContentAnalysisService] Found existing entity for this content: #{name} (ID: #{entity.id})" } if ENV["DEBUG"]
      return entity
    end

    # Due to the uniqueness constraint on entity names, we need to handle this carefully
    # Each entity represents a unique concept in the system
    # If an entity with this name already exists, we'll update its content association
    existing_entity = Entity.find_by(name: name)

    if existing_entity
      if ENV["DEBUG"]
        Rails.logger.debug do
          "[ContentAnalysisService] Found existing entity: #{name} (ID: #{existing_entity.id}) for content ##{existing_entity.content_id}"
        end
      end

      # Update the content association to the current content
      # This effectively moves the entity to the new content
      Rails.logger.debug { "[ContentAnalysisService] Updating entity to associate with content ##{content.id}" } if ENV["DEBUG"]
      existing_entity.update(content: content)
      return existing_entity
    end

    # Create new entity if no existing entity was found
    entity = Entity.new(name: name, content: content)

    if entity.save
      Rails.logger.debug { "[ContentAnalysisService] Created new entity: #{name} (ID: #{entity.id})" } if ENV["DEBUG"]
    else
      Rails.logger.error { "[ContentAnalysisService] Failed to create entity: #{name} - #{entity.errors.full_messages.join(', ')}" }
    end

    entity
  end

  # Create a statement
  # @param content [Content] The content to associate the statement with
  # @param entity [Entity] The subject entity
  # @param object_entity [Entity] The optional object entity
  # @param text [String] The statement text
  # @param confidence [Float] The confidence score (0-1)
  # @return [Statement] The created statement
  def create_statement(content:, entity:, text:, object_entity: nil, confidence: 1.0)
    return nil if entity.nil? || text.blank?

    # Debug logging
    statement_desc = object_entity ? "#{entity.name} -> #{text} -> #{object_entity.name}" : "#{entity.name} -> #{text}"
    Rails.logger.debug { "[ContentAnalysisService] Creating statement: #{statement_desc}" } if ENV["DEBUG"]

    # Create statement
    statement = Statement.new(
      entity: entity,
      object_entity: object_entity,
      content: content,
      text: text,
      confidence: confidence
    )

    if statement.save
      Rails.logger.debug { "[ContentAnalysisService] Created statement (ID: #{statement.id})" } if ENV["DEBUG"]

      # Generate embedding asynchronously
      # In a real app, this would be a background job
      begin
        embedding_service = OpenAI::EmbeddingService.new
        embedding_array = embedding_service.embed(text)

        if embedding_array.present?
          # Format the embedding array for pgvector
          # This is the format PostgreSQL expects: [val1,val2,val3,...]
          vector_string = "[#{embedding_array.join(',')}]"

          # Update with properly formatted vector
          statement.update(text_embedding: vector_string)
          if ENV["DEBUG"]
            Rails.logger.debug do
              "[ContentAnalysisService] Added embedding to statement (ID: #{statement.id}) with #{embedding_array.size} dimensions"
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error { "[ContentAnalysisService] Error generating embedding for statement: #{e.message}" }
      end
    else
      Rails.logger.error { "[ContentAnalysisService] Failed to create statement: #{statement.errors.full_messages.join(', ')}" }
    end

    statement
  end

  # Safe logging method that prevents binary data from being logged
  def log_safe(message, level = :debug)
    prefix = "[ContentAnalysisService] "

    # Skip logging if message contains binary data indicators
    return if message.include?("application/octet-stream") && ENV["LOG_BINARY_DATA"] != "true"

    case level
    when :debug
      Rails.logger.debug { prefix + message }
    when :info
      Rails.logger.info { prefix + message }
    when :warn
      Rails.logger.warn { prefix + message }
    when :error
      Rails.logger.error { prefix + message }
    end
  end

  def build_prompt(notes)
    <<~PROMPT
      IMPORTANT: You are NOT being asked to identify, describe, or provide information about people or faces in any image. Do NOT attempt to identify individuals. Your task is strictly to extract and summarize the contents of documents, receipts, images, or user notes.

      You are an expert assistant for information extraction and knowledge graph building. Your job is to:
      1. Read the provided user notes and, if present, the uploaded document or image.
      2. Write a detailed, human-readable description that synthesizes information from BOTH the user note(s) and the document/image, making clear connections between them.
      3. Identify all entities (people, places, things, concepts) in the content and mark them with [Entity: Name] tags.
      4. Generate a list of statements about these entities. Each statement should have:
         - subject: The entity the statement is about
         - text: The statement text (what is being said about the subject)
         - object: Optional second entity that is related to the subject
         - confidence: A confidence score between 0 and 1 (1 = very sure, 0 = not sure)
      5. Provide a confidence rating between 0 and 1 for your overall analysis.
      6. Output your result as a single JSON object matching the following strict schema. IMPORTANT: The output MUST be valid JSON and MUST match the schema exactly, with no extra text, comments, or Markdown.

      CRITICAL: Your description MUST include ALL specific identifying information visible in the content:
      - For license plates: Include the full plate number, state/province, expiration dates, and any visible registration tags or stickers
      - For vehicles: Include make, model, year (if visible), color, and any distinguishing features
      - For documents: Include all ID numbers, dates, names of organizations, and other key identifiers
      - For locations: Include full addresses, coordinates, or other location identifiers
      - For all items: Include serial numbers, model numbers, and other unique identifiers

      DO NOT omit any identifying information that is visible in the content. The description should be comprehensive enough that someone could identify the exact item without seeing the original content.

      OUTPUT FORMAT:
      - description: string (describe what the note and/or file is about, combining both)
      - annotated_description: string (with [Entity: Name] tags)
      - statements: array of statement objects with structure:
        - subject: string (entity name)
        - text: string (statement about the entity)
        - object: string (optional related entity)
        - confidence: float (0-1)
      - rating: float (0-1)

      EXAMPLE OUTPUT:
      {
        "description": "This is a vehicle door panel label from a 2022 Toyota RAV4 XLE with VIN 4T3R6RFV2NU123456, manufactured in Japan in October 2021. The label indicates a tire pressure of 35 PSI for front tires and 33 PSI for rear tires.",
        "annotated_description": "This is a [Entity: vehicle door panel label] from a [Entity: 2022 Toyota RAV4 XLE] with [Entity: VIN 4T3R6RFV2NU123456], manufactured in [Entity: Japan] in [Entity: October 2021]. The label indicates a [Entity: tire pressure] of [Entity: 35 PSI] for front tires and [Entity: 33 PSI] for rear tires.",
        "statements": [
          {
            "subject": "2022 Toyota RAV4 XLE",
            "text": "has VIN",
            "object": "VIN 4T3R6RFV2NU123456",
            "confidence": 1.0
          },
          {
            "subject": "2022 Toyota RAV4 XLE",
            "text": "was manufactured in",
            "object": "Japan",
            "confidence": 1.0
          },
          {
            "subject": "2022 Toyota RAV4 XLE",
            "text": "was manufactured in",
            "object": "October 2021",
            "confidence": 0.95
          },
          {
            "subject": "vehicle door panel label",
            "text": "specifies front tire pressure of",
            "object": "35 PSI",
            "confidence": 0.9
          },
          {
            "subject": "vehicle door panel label",
            "text": "specifies rear tire pressure of",
            "object": "33 PSI",
            "confidence": 0.9
          }
        ],
        "rating": 0.95
      }

      USER NOTES:
      #{notes.join("\n\n")}

      IMPORTANT: Only output valid JSON. If you are unsure, return your best guess but always follow the schema.
    PROMPT
  end

  # Parse the OpenAI response content as JSON, stripping code fences if present
  def parse_response(content)
    json_str = content.strip
    # Remove all code fences regardless of position
    json_str = json_str.gsub(/```json|```/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError
    nil
  end

  # Validate that the OpenAI response matches the required V2 output format with statements
  # Check if the result has a valid output format
  # @param result [Hash] The result to check
  # @return [Boolean] Whether the result has a valid output format
  def valid_output_format?(result)
    validate_output_format_with_details(result).empty?
  end

  # Validate the output format and return detailed error messages
  # @param result [Hash] The result to validate
  # @return [Array<String>] Array of error messages, empty if valid
  def validate_output_format_with_details(result)
    errors = []

    # Basic structure checks
    unless result.is_a?(Hash)
      errors << "Result is not a Hash (got #{result.class})"
      return errors # Early return as other checks depend on this
    end

    # Check required fields
    errors << "Missing 'description' field" if result["description"].blank?
    errors << "'description' is not a String" if result["description"].present? && !result["description"].is_a?(String)

    errors << "Missing 'annotated_description' field" if result["annotated_description"].blank?
    if result["annotated_description"].present? && !result["annotated_description"].is_a?(String)
      errors << "'annotated_description' is not a String"
    end

    errors << "Missing 'rating' field" if result["rating"].blank?
    if result["rating"].present?
      if !result["rating"].is_a?(Numeric)
        errors << "'rating' is not a number (got #{result['rating'].class})"
      elsif !result["rating"].between?(0, 1)
        errors << "'rating' must be between 0 and 1 (got #{result['rating']})"
      end
    end

    # Check statements array (optional for backward compatibility)
    return errors if result["statements"].nil?

    unless result["statements"].is_a?(Array)
      errors << "'statements' is not an Array (got #{result['statements'].class})"
      return errors # Early return as statement validation depends on this
    end

    # Validate each statement
    result["statements"].each_with_index do |statement, index|
      statement_errors = validate_statement(statement, index)
      errors.concat(statement_errors) if statement_errors.any?
    end

    errors
  end

  # Validate a single statement
  # @param statement [Hash] The statement to validate
  # @param index [Integer] The index of the statement in the array
  # @return [Array<String>] Array of error messages, empty if valid
  def validate_statement(statement, index)
    errors = []

    unless statement.is_a?(Hash)
      errors << "Statement ##{index} is not a Hash (got #{statement.class})"
      return errors # Early return as other checks depend on this
    end

    # Check required fields
    errors << "Statement ##{index} missing 'subject' field" if statement["subject"].blank?
    errors << "Statement ##{index} 'subject' is not a String" if statement["subject"].present? && !statement["subject"].is_a?(String)

    errors << "Statement ##{index} missing 'text' field" if statement["text"].blank?
    errors << "Statement ##{index} 'text' is not a String" if statement["text"].present? && !statement["text"].is_a?(String)

    # Optional fields
    if statement["object"].present? && !statement["object"].is_a?(String)
      errors << "Statement ##{index} 'object' is not a String (got #{statement['object'].class})"
    end

    if statement["confidence"].present?
      if !statement["confidence"].is_a?(Numeric)
        errors << "Statement ##{index} 'confidence' is not a number (got #{statement['confidence'].class})"
      elsif !statement["confidence"].between?(0, 1)
        errors << "Statement ##{index} 'confidence' must be between 0 and 1 (got #{statement['confidence']})"
      end
    end

    errors
  end

  # This duplicate log_safe method was removed as it already exists at line 439
end
