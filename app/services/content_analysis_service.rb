# frozen_string_literal: true

require_relative "openai/client_service"
require "yaml"
require "json"

# Service to analyze uploaded content and notes, and extract/annotate entities using OpenAI
class ContentAnalysisService
  TAXONOMY_PATH = Rails.root.join("app", "services", "openai", "entity_taxonomy.yml")
  OUTPUT_FORMAT_PATH = Rails.root.join("app", "services", "openai", "entity_output_format.json")

  def initialize(openai_service: OpenAI::ClientService.new)
    @openai_service = openai_service
    @taxonomy = YAML.load_file(TAXONOMY_PATH)["entity_types"]
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

  # Extract entities from annotated_description and create Entity records for the given Content.
  # Entities must match taxonomy. Includes debug logging for all steps.
  def extract_and_create_entities(content, openai_result)
    # Validate content is a Content model instance
    unless content.is_a?(Content)
      Rails.logger.error { "[ContentAnalysisService] Error: content must be a Content model instance, got #{content.class}" }
      return false
    end

    annotated = openai_result["annotated_description"]
    description = openai_result["description"]
    return if annotated.blank?

    # Store description embedding if available
    if description.present?
      Rails.logger.debug { "[ContentAnalysisService] Generating embedding for description: #{description.truncate(50)}" }
      begin
        embedding_service = OpenAI::EmbeddingService.new
        description_embedding = embedding_service.embed(description)

        if description_embedding.present?
          # Format the embedding array as a PostgreSQL vector string
          # The format should be '[n1,n2,n3,...]' for pgvector
          formatted_embedding = ActiveRecord::Base.connection.quote_string(description_embedding.to_s)

          # Store the embedding with the content for future similarity searches
          content.update(note_embedding: formatted_embedding)
          Rails.logger.debug do
            "[ContentAnalysisService] Successfully stored description embedding with #{description_embedding.size} dimensions to content ##{content.id}"
          end
        end
      rescue StandardError => e
        Rails.logger.error { "[ContentAnalysisService] Error generating description embedding: #{e.message}" }
      end
    end

    Rails.logger.debug { "[ContentAnalysisService] Processing annotated description: #{annotated}" }

    valid_types = @taxonomy.pluck("name")
    entities = annotated.scan(/\[([^\]:]+):\s*([^\]]+)\]/)
    Rails.logger.debug { "[ContentAnalysisService] Extracted entities: #{entities.inspect}" }

    created_entities = []

    entities.each do |type, value|
      type_down = type.strip.downcase
      canonical_type = valid_types.find { |t| t.downcase == type_down }
      unless canonical_type
        Rails.logger.warn("[ContentAnalysisService] Skipping entity with invalid type: #{type}")
        next
      end

      # Check if entity already exists to prevent duplicates
      clean_value = value.strip
      existing_entity = content.entities.find_by(entity_type: canonical_type, value: clean_value)

      if existing_entity
        # Entity already exists, don't create a duplicate
        log_safe("Entity already exists: #{canonical_type} - #{clean_value}", :debug)
        created_entities << existing_entity
        next
      end

      # Create entity with value embedding
      begin
        # Generate embedding for entity value
        embedding_service = OpenAI::EmbeddingService.new
        embedding_array = embedding_service.embed(clean_value)

        # Format the embedding array as a PostgreSQL vector string
        # The format should be '[n1,n2,n3,...]' for pgvector
        formatted_embedding = (ActiveRecord::Base.connection.quote_string(embedding_array.to_s) if embedding_array.present?)

        entity = content.entities.create(
          entity_type: canonical_type,
          value: clean_value,
          value_embedding: formatted_embedding
        )

        if entity.persisted?
          created_entities << entity
          log_safe("Created entity: #{canonical_type} - #{clean_value} with embedding dimensions: #{embedding_array&.size}", :info)
        else
          log_safe("Failed to create entity: #{entity.errors.full_messages.join(', ')}", :error)
        end
      rescue StandardError => e
        log_safe("Error creating entity: #{e.message}", :error)
      end
    end

    created_entities
  end

  private

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
    taxonomy_list = @taxonomy.map { |t| "- #{t['name']}: #{t['description']}" }.join("\n")
    output_example = JSON.pretty_generate(@output_format)

    <<~PROMPT
      IMPORTANT: You are NOT being asked to identify, describe, or provide information about people or faces in any image. Do NOT attempt to identify individuals. Your task is strictly to extract and summarize the contents of documents, receipts, images, or user notes, and to classify the type of document or image.

      You are an expert assistant for information extraction. Your job is to:
      1. Read the provided user notes and, if present, the uploaded document or image.
      2. Write a detailed, human-readable description that synthesizes information from BOTH the user note(s) and the document/image, making clear connections between them.
      3. Annotate each description with entity tags in the format [EntityType: Value], using ONLY the allowed entity types below. Be thorough in identifying all relevant entities.
      4. Provide a confidence rating between 0 and 1 (as a float, 1 = very sure, 0 = not sure) for your analysis of that piece of content.
      5. Output your result as a single JSON object matching the following strict schema. IMPORTANT: The output MUST be valid JSON and MUST match the schema exactly, with no extra text, comments, or Markdown. If you do not comply, your output will be rejected as an error.

      CRITICAL: Your description MUST include ALL specific identifying information visible in the content:
      - For license plates: Include the full plate number, state/province, expiration dates, and any visible registration tags or stickers
      - For vehicles: Include make, model, year (if visible), color, and any distinguishing features
      - For documents: Include all ID numbers, dates, names of organizations, and other key identifiers
      - For locations: Include full addresses, coordinates, or other location identifiers
      - For all items: Include serial numbers, model numbers, and other unique identifiers

      DO NOT omit any identifying information that is visible in the content. The description should be comprehensive enough that someone could identify the exact item without seeing the original content.

      - description: string (describe what the note and/or file is about, combining both)
      - annotated_description: string (with entity tags)
      - rating: float (0-1)

      EXAMPLE (for a receipt and note):
      {
        "description": "This is a receipt from Joe's Diner in Ocean City, NJ, dated April 5, 2024, for a meal with Steven, as referenced in the user's note.",
        "annotated_description": "This is a [Receipt: meal] at [Organization: Joe's Diner] in [Location: Ocean City, NJ], dated [Date: April 5, 2024], for a meal with [Person: Steven], as referenced in the user's note.",
        "rating": 0.98
      }

      Allowed entity types:
      #{taxonomy_list}

      Example output format:
      #{output_example}

      Provided user notes:
      #{notes.map.with_index { |n, i| "Note \\##{i + 1}: #{n}" }.join("\n")}

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

  # Validate that the OpenAI response matches the required flat output format
  def valid_output_format?(result)
    result.is_a?(Hash) &&
      result.key?("description") &&
      result.key?("annotated_description") &&
      result.key?("rating") &&
      result["rating"].is_a?(Numeric) &&
      result["rating"] >= 0 && result["rating"] <= 1
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
