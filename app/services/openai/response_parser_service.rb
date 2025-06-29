# frozen_string_literal: true

# NOTE:  This is actually for ContentAnalysisService, not all OpenAI responses
# needs refactor

module OpenAI
  # Service for parsing and validating OpenAI API responses
  # Extracts structured data from responses and validates against expected schema
  class ResponseParserService
    # Initialize with optional output format path
    # @param output_format_path [String] Path to the output format JSON schema
    def initialize(output_format_path: nil)
      @output_format_path = output_format_path || Rails.root.join("app", "services", "openai", "statement_output_format.json")
      @output_format = JSON.parse(File.read(@output_format_path))
      Rails.logger.debug { "[OpenAI::ResponseParserService] Initialized with format: #{@output_format_path}" } if ENV["DEBUG"]
    end

    # Parse and validate OpenAI API response
    # @param response [Hash] The OpenAI API response
    # @return [Hash] Parsed and validated response
    # @raise [TypeError] if the response is not a valid hash
    # @raise [ArgumentError] if the response doesn't match the required format
    def parse_response(response)
      Rails.logger.debug { "[OpenAI::ResponseParserService] Parsing response: #{response.class}" } if ENV["DEBUG"]

      # Parse JSON content
      parsed_content = parse_json_content(response)

      # Validate parsed content against expected format
      validate_parsed_content(parsed_content)

      # Return the validated content
      parsed_content
    end

    # Log detailed information about the response structure
    # @param response [Hash] The OpenAI response hash
    # @return [void]
    def log_response_structure(response)
      return unless ENV["DEBUG"]

      Rails.logger.debug { "[OpenAI::ResponseParserService] Response structure:" }
      Rails.logger.debug { "  Class: #{response.class}" }

      return unless response.is_a?(Hash)

      Rails.logger.debug { "  Keys: #{response.keys.join(', ')}" }

      return unless response["choices"].is_a?(Array)

      Rails.logger.debug { "  Choices count: #{response['choices'].size}" }

      return unless response["choices"].first.is_a?(Hash)

      choice = response["choices"].first
      Rails.logger.debug { "  First choice keys: #{choice.keys.join(', ')}" }

      return unless choice["message"].is_a?(Hash)

      message = choice["message"]
      Rails.logger.debug { "  Message keys: #{message.keys.join(', ')}" }
      Rails.logger.debug { "  Content type: #{message['content'].class}" }
      Rails.logger.debug { "  Content snippet: #{message['content'].to_s[0..100]}..." }
    end

    # Log detailed information about analysis results
    # @param results [Array<Hash>] The analysis results
    def log_analysis_results(results)
      return unless ENV["DEBUG"]

      Rails.logger.debug { "[OpenAI::ResponseParserService] Analysis results:" }

      return unless results.is_a?(Hash)

      Rails.logger.debug { "  Keys: #{results.keys.join(', ')}" }

      Rails.logger.debug { "  Description: #{results['description'].to_s[0..100]}..." } if results["description"].present?

      if results["annotated_description"].present?
        Rails.logger.debug { "  Annotated description: #{results['annotated_description'].to_s[0..100]}..." }
      end

      return unless results["statements"].is_a?(Array)

      Rails.logger.debug { "  Statements count: #{results['statements'].size}" }

      results["statements"].first(3).each_with_index do |statement, index|
        Rails.logger.debug { "  Statement ##{index}: #{statement.inspect}" }
      end
    end

    # Validate a statement against the expected format
    # @param statement [Hash] The statement to validate
    # @param index [Integer] The index of the statement in the array
    # @return [Array<String>] Array of error messages, empty if valid
    def validate_statement(statement, index)
      errors = []

      # Required fields
      unless statement.is_a?(Hash)
        errors << "Statement ##{index} is not a hash (got #{statement.class})"
        return errors
      end

      # Validate required fields
      errors << "Statement ##{index} missing required field 'text'" if statement["text"].blank?

      # V3 Knowledge Graph fields
      errors << "Statement ##{index} missing required field 'predicate'" if statement["predicate"].blank?

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

    private

    # Extract content from OpenAI API response
    # @param response [Hash] The OpenAI API response
    # @return [String] The extracted content
    # @raise [ArgumentError] if the content cannot be extracted
    def extract_content(response)
      content = response.dig("choices", 0, "message", "content")

      # Check if content is present
      if content.blank?
        error_message = "OpenAI response message missing 'content'"
        Rails.logger.error { "[OpenAI::ResponseParserService] #{error_message}" }
        raise ArgumentError, error_message
      end

      content
    end

    # Parse JSON content from string
    # @param content [String] The content string
    # @return [Hash] The parsed JSON content
    # @raise [ArgumentError] if the content is not valid JSON
    def parse_json_content(response)
      content = response.dig("choices", 0, "message", "content")
      content.gsub!(/```(json)?/, "")

      JSON.parse(content)
    end

    # Validate parsed content against expected format
    # @param parsed_content [Hash] The parsed content
    # @return [Boolean] True if valid
    # @raise [ArgumentError] if the content doesn't match the required format
    def validate_parsed_content(parsed_content)
      # Check if parsed content is a hash
      unless parsed_content.is_a?(Hash)
        error_message = "Parsed content must be a hash, got #{parsed_content.class}"
        Rails.logger.error { "[OpenAI::ResponseParserService] #{error_message}" }
        raise ArgumentError, error_message
      end

      # Check if OpenAI reported any errors
      if parsed_content["errors"].is_a?(Array) && parsed_content["errors"].any?
        # Log all errors reported by OpenAI
        parsed_content["errors"].each do |error|
          error_type = error["type"] || "unknown"
          error_message = error["message"] || "No message provided"
          Rails.logger.error { "[OpenAI::ResponseParserService] OpenAI reported error: #{error_type} - #{error_message}" }
        end

        # If we have errors but also have entities or statements, we can continue processing
        # Only raise an exception if we have no useful data
        has_entities = parsed_content["entities"].is_a?(Array) && parsed_content["entities"].any?
        has_statements = parsed_content["statements"].is_a?(Array) && parsed_content["statements"].any?

        if !has_entities && !has_statements
          first_error = parsed_content["errors"].first
          error_message = "OpenAI processing error: #{first_error['message']}"
          Rails.logger.error { "[OpenAI::ResponseParserService] #{error_message}" }
          raise ArgumentError, error_message
        else
          Rails.logger.warn { "[OpenAI::ResponseParserService] OpenAI reported errors but provided some data, continuing with processing" }
        end
      end

      # Check for required fields
      required_fields = @output_format["required"] || []
      missing_fields = required_fields - parsed_content.keys

      if missing_fields.any?
        error_message = "Parsed content missing required fields: #{missing_fields.join(', ')}"
        Rails.logger.error { "[OpenAI::ResponseParserService] #{error_message}" }
        raise ArgumentError, error_message
      end

      # Validate statements if present
      if parsed_content["statements"].is_a?(Array)
        statement_errors = []

        parsed_content["statements"].each_with_index do |statement, index|
          errors = validate_statement(statement, index)
          statement_errors.concat(errors) if errors.any?
        end

        if statement_errors.any?
          error_message = "Statement validation errors: #{statement_errors.join('; ')}"
          Rails.logger.error { "[OpenAI::ResponseParserService] #{error_message}" }
          raise ArgumentError, error_message
        end
      end

      true
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
end
