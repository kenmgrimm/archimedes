# frozen_string_literal: true

require_relative "openai/client_service"
require "yaml"
require "json"

# Service to analyze uploaded content and notes, and extract/annotate entities using OpenAI
# Refactored to use smaller, focused service components
class ContentAnalysisService
  def initialize(
    openai_service: OpenAI::ClientService.new,
    response_parser: OpenAI::ResponseParserService.new,
    entity_extraction_service: EntityExtractionService.new,
    statement_creation_service: StatementCreationService.new,
    verification_request_manager: VerificationRequestManager.new
  )
    @openai_service = openai_service
    @response_parser = response_parser
    @entity_extraction_service = entity_extraction_service
    @statement_creation_service = statement_creation_service
    @verification_request_manager = verification_request_manager

    Rails.logger.debug { "[ContentAnalysisService] Initialized with service dependencies" } if ENV["DEBUG"]

    @user = "John Smith"
    @taxonomy = Rails.root.join("app", "services", "openai", "entity_taxonomy.yml").read
    @instructions = Rails.root.join("app", "services", "openai", "entity_extraction_prompt.txt").read
  end

  # Analyze content: notes (array of strings) and files (array of hashes: {filename, text_content})
  # Returns the OpenAI response parsed as JSON
  # @param notes [Array<String>] Array of note strings
  # @param files [Array<Hash>] Array of file hashes with :filename and :data keys
  # @return [Array<Hash>] Analysis results for each note/file combination
  def analyze(prompt, files:)
    # Process files with the notes using the multimodal API
    Rails.logger.debug { "[ContentAnalysisService] Processing #{files.size} files with multimodal API" }

    # Build prompt for multimodal API
    prompt_with_instructions = "#{augment_prompt_with_instructions(prompt)}\n\nAnalyze this content: #{prompt}"

    # Call OpenAI API with multimodal endpoint
    Rails.logger.debug { "[ContentAnalysisService] Calling chat_with_files with #{files.size} files" }
    response = @openai_service.chat_with_files(prompt: prompt_with_instructions, files: files)

    # Log response structure for debugging
    @response_parser.log_response_structure(response)

    # Parse and validate the response
    @response_parser.parse_response(response)
  end

  # Process analysis results for a content item
  # @param content [Content] The content to process results for
  # @param result [Hash] The analysis result from analyze method
  # @return [Hash] Summary of processing including created entities and updated content
  def process_analysis_result(content, result)
    Rails.logger.debug { "[ContentAnalysisService] Processing analysis results for content ##{content.id}" } if ENV["DEBUG"]

    # Store the raw OpenAI response for debugging and future reference
    content.update!(openai_response: result)

    # Initialize tracking variables
    created_entities = []
    created_statements = []
    verification_requests = []
    errors = []

    # Extract and create entities from this result
    extraction_result = extract_and_create_entities(content, result)

    # Aggregate results
    created_entities.concat(extraction_result[:created_entities] || [])
    created_statements.concat(extraction_result[:created_statements] || [])
    verification_requests.concat(extraction_result[:verification_requests] || [])
    errors.concat(extraction_result[:errors] || [])

    # Update content with processing status if attributes exist
    update_attrs = {}

    # Only add attributes that exist in the Content model
    update_attrs[:processed_at] = Time.current if content.has_attribute?(:processed_at)

    if content.has_attribute?(:processing_status)
      update_attrs[:processing_status] = errors.any? ? "partial" : "complete"
    end

    if content.has_attribute?(:processing_errors)
      update_attrs[:processing_errors] = errors.any? ? errors.join("; ") : nil
    end

    # Only update if we have attributes to update
    content.update(update_attrs) if update_attrs.any?

    # Log debug information
    Rails.logger.debug do
      "[ContentAnalysisService] Content processing completed with status: #{errors.any? ? 'partial (with errors)' : 'complete'}"
    end

    # Return summary
    {
      content: content,
      created_entities: created_entities,
      created_statements: created_statements,
      verification_requests: verification_requests,
      errors: errors
    }
  end

  # Extract entities and statements from OpenAI result and create records for the given Content.
  # Delegates to specialized services for entity extraction, statement creation, and verification.
  # @param content [Content] The content being analyzed
  # @param openai_result [Hash] The parsed OpenAI result
  # @return [Hash] Summary of extraction including created entities, statements, and verification requests
  def extract_and_create_entities(content, openai_result)
    # Validate content is a Content model instance
    unless content.is_a?(Content)
      error_message = "Content must be a Content model instance, got #{content.class}"
      Rails.logger.error { "[ContentAnalysisService] #{error_message}" }
      return { errors: [error_message] }
    end

    # Initialize tracking variables
    created_entities = []
    created_statements = []
    verification_requests = []
    errors = []

    # Extract description and generate embedding if available
    process_description_embedding(content, openai_result["description"])

    # Process annotated description to extract entity names
    entity_names = @entity_extraction_service.extract_entity_names_from_annotation(
      openai_result["annotated_description"]
    )

    # Process statements from the result
    statements = openai_result["statements"] || []

    # First pass: Process entities
    entity_results = process_entities(content, entity_names)
    created_entities.concat(entity_results[:created_entities] || [])
    verification_requests.concat(entity_results[:verification_requests] || [])
    errors.concat(entity_results[:errors] || [])

    # Second pass: Process statements
    statement_results = process_statements(content, statements, entity_results[:entity_map] || {})
    created_statements.concat(statement_results[:created_statements] || [])
    verification_requests.concat(statement_results[:verification_requests] || [])
    errors.concat(statement_results[:errors] || [])

    # Return summary
    {
      created_entities: created_entities,
      created_statements: created_statements,
      verification_requests: verification_requests,
      errors: errors
    }
  end

  private

  # Build instructions for entity extraction
  # @return [String] The augmented prompt
  def augment_prompt_with_instructions(prompt)
    "#{@instructions}\n\n" \
      "ENTITY TAXONOMY:\n#{@taxonomy}\n\n" \
      "CONTENT TO ANALYZE:\n#{prompt}\n\n" \
      "USER:\n#{@user}\n\n"
  end

  # Process description and generate embedding
  # @param content [Content] The content to update
  # @param description [String] The description to process
  def process_description_embedding(content, description)
    return if description.blank?

    Rails.logger.debug { "[ContentAnalysisService] Generating embedding for description" } if ENV["DEBUG"]

    begin
      embedding_service = OpenAI::EmbeddingService.new
      description_embedding = embedding_service.embed(description)

      if description_embedding.present?
        # Format the embedding array as a PostgreSQL vector string
        # The format should be '[n1,n2,n3,...]' for pgvector
        formatted_embedding = "[#{description_embedding.join(',')}]"

        # Store the embedding with the content for future similarity searches
        content.update(note_embedding: formatted_embedding)
        Rails.logger.debug { "[ContentAnalysisService] Successfully stored description embedding" } if ENV["DEBUG"]
      end
    rescue StandardError => e
      Rails.logger.error { "[ContentAnalysisService] Error generating description embedding: #{e.message}" }
    end
  end

  # Process entities from entity names
  # @param content [Content] The content being analyzed
  # @param entity_names [Array<String>] The entity names to process
  # @return [Hash] Results including created entities, verification requests, and entity map
  def process_entities(content, entity_names)
    created_entities = []
    verification_requests = []
    errors = []
    entity_map = {}

    entity_names.each do |entity_name|
      # Find or create entity
      result = @entity_extraction_service.find_or_create_entity(entity_name, content)

      if result[:success]
        case result[:status]
        when :existing, :created
          entity_map[entity_name] = result[:entity]
          created_entities << result[:entity] if result[:status] == :created
        when :needs_verification
          verification_requests << result[:verification_request]
        end
      else
        errors << "Error processing entity '#{entity_name}': #{result[:error]}"
      end
    rescue StandardError => e
      errors << "Exception processing entity '#{entity_name}': #{e.message}"
    end

    {
      created_entities: created_entities,
      verification_requests: verification_requests,
      errors: errors,
      entity_map: entity_map
    }
  end

  # Process statements
  # @param content [Content] The content being analyzed
  # @param statements [Array<Hash>] The statements to process
  # @param entity_map [Hash] Map of entity names to Entity objects
  # @return [Hash] Results including created statements and verification requests
  def process_statements(content, statements, entity_map)
    created_statements = []
    verification_requests = []
    errors = []

    statements.each do |statement_data|
      # Skip if missing required fields
      unless statement_data["subject"].present? && statement_data["predicate"].present? && statement_data["object"].present?
        errors << "Statement missing required fields: #{statement_data.inspect}"
        next
      end

      # Find subject entity
      subject_name = statement_data["subject"]
      subject_entity = entity_map[subject_name]

      # If subject entity doesn't exist, add to pending verification
      unless subject_entity
        # Find or create entity/verification request
        result = @entity_extraction_service.find_or_create_entity(
          subject_name,
          content,
          [statement_data]
        )

        if result[:success]
          case result[:status]
          when :existing, :created
            subject_entity = result[:entity]
            entity_map[subject_name] = subject_entity
            created_statements << result[:statement] if result[:statement].present?
          when :needs_verification
            verification_requests << result[:verification_request]
          end
        else
          errors << "Error processing subject entity '#{subject_name}': #{result[:error]}"
        end

        # Skip further processing if subject entity still doesn't exist
        next unless subject_entity
      end

      # Create statement
      result = @statement_creation_service.create_statement(statement_data, subject_entity, content)

      if result[:success]
        if result[:status] == :pending_verification
          verification_requests << result[:verification_request]
        else
          created_statements << result[:statement]
        end
      else
        errors << "Error creating statement: #{result[:error]}"
      end
    rescue StandardError => e
      errors << "Exception processing statement: #{e.message}"
    end

    {
      created_statements: created_statements,
      verification_requests: verification_requests,
      errors: errors
    }
  end

  # Make a string safe for logging by removing sensitive information
  # @param text [String] The text to make safe
  # @return [String] The safe text
  def log_safe(text)
    return "" if text.nil?

    # Truncate long text
    if text.length > 100
      "#{text[0..100]}..."
    else
      text
    end
  end
end
