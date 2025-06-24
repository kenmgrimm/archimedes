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
  def analyze(notes:, files:)
    results = []
    if files.blank? || files.empty?
      response = @openai_service.chat(build_prompt(notes), model: "gpt-4o", max_tokens: 4096)
      content = response.dig("choices", 0, "message", "content")
      result = parse_response(content)
      raise "OpenAI response is not valid JSON" if result.nil?
      raise "OpenAI response does not match required output format" unless valid_output_format?(result)

      results << { note: notes.join("\n"), file: nil, result: result }
    else
      files.each do |file|
        # File size and mime type validation
        size = file_size(file)
        mime_type = file_mime_type(file)

        allowed_types = ["application/pdf", "text/plain", "image/jpeg", "image/png", "image/gif"]
        max_size = 4 * 1024 * 1024 # 4 MB

        unless size.nil? || size <= max_size
          Rails.logger.warn("[ContentAnalysisService] Skipping file #{file[:filename] || (file.respond_to?(:filename) && file.filename.to_s)} due to size > 4MB (#{size} bytes)")
          next
        end
        image_types = ["image/jpeg", "image/png", "image/gif"]
        # Get filename for better error messages
        filename = file[:filename] || (file.respond_to?(:filename) && file.filename.to_s) || "unknown"

        # Check if mime type is allowed, with special handling for images
        is_allowed = allowed_types.include?(mime_type) ||
                     image_types.any? { |type| mime_type.start_with?(type.split("/").first) } ||
                     (filename.end_with?(".jpg", ".jpeg", ".png", ".gif") && mime_type == "application/octet-stream")

        unless is_allowed
          # Don't log unsupported mime type messages for JPEGs with octet-stream type
          unless filename.end_with?(".jpg", ".jpeg", ".png", ".gif") && mime_type == "application/octet-stream"
            log_safe("Skipping file #{filename} due to unsupported mime type: #{mime_type}", :warn)
          end
          results << { note: notes.join("\n"), file: filename, result: nil, skipped: true }
          next
        end

        prompt = build_prompt(notes)
        # Get file data without logging binary content
        begin
          file_data = file.respond_to?(:download) ? file.download : file[:data]
          filename = file.respond_to?(:filename) ? file.filename.to_s : file[:filename].to_s

          # Log file processing without including binary data
          log_safe("Processing file: #{filename} (#{file_mime_type(file)})")

          file_arg = { io: StringIO.new(file_data), filename: filename }
          response = @openai_service.chat_with_files(note: prompt, files: [file_arg], model: "gpt-4o", max_tokens: 4096)
        rescue StandardError => e
          Rails.logger.error { "[ContentAnalysisService] Error processing file #{filename}: #{e.message}" }
          next
        end
        content = response.dig("choices", 0, "message", "content")
        result = parse_response(content)
        if result.nil?
          # Re-prompt for JSON as a second pass
          response = @openai_service.chat_with_files(note: prompt, files: [file_arg], model: "gpt-4o", max_tokens: 4096)
          content = response.dig("choices", 0, "message", "content")
          result = parse_response(content)
        end
        raise "OpenAI response is not valid JSON" if result.nil?
        raise "OpenAI response does not match required output format" unless valid_output_format?(result)

        file_name = file.respond_to?(:filename) ? file.filename.to_s : file[:filename].to_s
        results << { note: notes.join("\n"), file: file_name, result: result }
      end
    end
    results
  rescue StandardError => e
    Rails.logger.error("[ContentAnalysisService] Error analyzing content: #{e.message}")
    raise
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
        description_embedding = embedding_service.embed_text(description)

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
      created_entities << subject_entity if subject_entity.persisted? && !created_entities.include?(subject_entity)

      # Find or create object entity if present
      object_entity = find_or_create_entity(content, object_name) if object_name.present?
      created_entities << object_entity if object_entity&.persisted? && !created_entities.include?(object_entity)

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
  
  # Find or create an entity by name
  # @param content [Content] The content to associate the entity with
  # @param name [String] The entity name
  # @return [Entity] The found or created entity
  def find_or_create_entity(content, name)
    return nil if name.blank?
    
    # Debug logging
    Rails.logger.debug { "[ContentAnalysisService] Finding or creating entity: #{name}" } if ENV["DEBUG"]
    
    # Try to find existing entity by name
    entity = Entity.find_by(name: name)
    
    if entity
      Rails.logger.debug { "[ContentAnalysisService] Found existing entity: #{name} (ID: #{entity.id})" } if ENV["DEBUG"]
      return entity
    end
    
    # Create new entity
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
  def create_statement(content:, entity:, object_entity: nil, text:, confidence: 1.0)
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
        embedding = embedding_service.embed_text(text)
        statement.update(text_embedding: embedding) if embedding.present?
        Rails.logger.debug { "[ContentAnalysisService] Added embedding to statement (ID: #{statement.id})" } if ENV["DEBUG"]
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
        "description": "This is a Florida license plate CJ8 9NF on a GMC Sierra 1500 truck, expiring in February 2026.",
        "annotated_description": "This is a [Entity: Florida license plate] [Entity: CJ8 9NF] on a [Entity: GMC Sierra 1500 truck], expiring in [Entity: February 2026].",
        "statements": [
          {
            "subject": "CJ8 9NF",
            "text": "is a license plate number",
            "confidence": 1.0
          },
          {
            "subject": "Florida license plate",
            "text": "has number",
            "object": "CJ8 9NF",
            "confidence": 1.0
          },
          {
            "subject": "GMC Sierra 1500 truck",
            "text": "has license plate",
            "object": "CJ8 9NF",
            "confidence": 0.95
          },
          {
            "subject": "CJ8 9NF",
            "text": "expires in",
            "object": "February 2026",
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
  def valid_output_format?(result)
    return false unless result.is_a?(Hash)
    return false unless result["description"].is_a?(String)
    return false unless result["annotated_description"].is_a?(String)
    return false unless result["rating"].is_a?(Numeric) && result["rating"].between?(0, 1)
    
    # Check statements array
    return true if result["statements"].nil? # Allow missing statements for backward compatibility
    
    return false unless result["statements"].is_a?(Array)
    
    # Validate each statement
    result["statements"].all? do |statement|
      statement.is_a?(Hash) &&
      statement["subject"].is_a?(String) &&
      statement["text"].is_a?(String) &&
      (statement["object"].nil? || statement["object"].is_a?(String)) &&
      (statement["confidence"].nil? || 
       (statement["confidence"].is_a?(Numeric) && statement["confidence"].between?(0, 1)))
    end
  end

  # Returns the size (in bytes) of the file, or nil if not available
  def file_size(file)
    filename = nil

    # Get filename for better logging
    if file.respond_to?(:filename)
      filename = file.filename.to_s
    elsif file.is_a?(Hash) && file[:filename]
      filename = file[:filename].to_s
    end

    size = if file.respond_to?(:byte_size)
             file.byte_size
           elsif file.is_a?(Hash) && file[:byte_size]
             file[:byte_size]
           elsif file.is_a?(Hash) && file[:data]
             file[:data].respond_to?(:bytesize) ? file[:data].bytesize : file[:data].to_s.bytesize
           end

    # Log without including the full file object
    log_safe("File size: #{filename || 'unnamed'} -> #{size} bytes")

    size
  end

  # Returns the mime type for the file, or application/octet-stream if unknown
  def file_mime_type(file)
    mime_type = nil
    filename = nil

    # Get filename for better logging
    if file.respond_to?(:filename)
      filename = file.filename.to_s
    elsif file.is_a?(Hash) && file[:filename]
      filename = file[:filename].to_s
    end

    # First try to get content_type from the file object
    if file.respond_to?(:content_type) && file.content_type.present?
      mime_type = file.content_type
    elsif file.is_a?(Hash) && file[:content_type].present?
      mime_type = file[:content_type]
    end

    # If no content_type available, try to detect from filename extension
    if mime_type.nil? && filename.present?
      ext = File.extname(filename).delete(".").downcase
      mime_type = case ext
                  when "pdf" then "application/pdf"
                  when "txt" then "text/plain"
                  when "jpg", "jpeg" then "image/jpeg"
                  when "png" then "image/png"
                  when "gif" then "image/gif"
                  else "application/octet-stream"
                  end
    end

    # Default to octet-stream if we still don't have a mime type
    mime_type ||= "application/octet-stream"

    # Log without including the full file object
    log_safe("File type: #{filename || 'unnamed'} -> #{mime_type}")

    mime_type
  end
end
