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
        size = if file.respond_to?(:byte_size)
                 file.byte_size
               elsif file[:byte_size]
                 file[:byte_size]
               elsif file[:data]
                 file[:data].respond_to?(:bytesize) ? file[:data].bytesize : file[:data].to_s.bytesize
               end
        mime_type = if file.respond_to?(:content_type)
                      file.content_type
                    elsif file[:content_type]
                      file[:content_type]
                    elsif file[:filename]
                      ext = File.extname(file[:filename]).downcase
                      case ext
                      when ".pdf"
                        "application/pdf"
                      when ".txt"
                        "text/plain"
                      when ".jpg", ".jpeg" then "image/jpeg"
                      when ".png" then "image/png"
                      when ".gif" then "image/gif"
                      else
                        "application/octet-stream"
                      end
                    else
                      "application/octet-stream"
                    end

        allowed_types = ["application/pdf", "text/plain", "image/jpeg", "image/png", "image/gif"]
        max_size = 4 * 1024 * 1024 # 4 MB

        unless size.nil? || size <= max_size
          Rails.logger.warn("[ContentAnalysisService] Skipping file #{file[:filename] || (file.respond_to?(:filename) && file.filename.to_s)} due to size > 4MB (#{size} bytes)")
          next
        end
        image_types = ["image/jpeg", "image/png", "image/gif"]
        unless allowed_types.include?(mime_type) || image_types.any? { |type| mime_type.start_with?(type.split("/").first) }
          Rails.logger.warn("[ContentAnalysisService] Skipping file #{file[:filename] || (file.respond_to?(:filename) && file.filename.to_s)} due to unsupported mime type: #{mime_type}")
          next
        end

        prompt = build_prompt(notes)
        file_data = file.respond_to?(:download) ? file.download : file[:data]
        filename = file.respond_to?(:filename) ? file.filename.to_s : file[:filename].to_s
        file_arg = { io: StringIO.new(file_data), filename: filename }
        response = @openai_service.chat_with_files(note: prompt, files: [file_arg], model: "gpt-4o", max_tokens: 4096)
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

  private

  def build_prompt(notes)
    taxonomy_list = @taxonomy.map { |t| "- #{t['name']}: #{t['description']}" }.join("\n")
    output_example = JSON.pretty_generate(@output_format)

    <<~PROMPT
      IMPORTANT: You are NOT being asked to identify, describe, or provide information about people or faces in any image. Do NOT attempt to identify individuals. Your task is strictly to extract and summarize the contents of documents, receipts, images, or user notes, and to classify the type of document or image.

      You are an expert assistant for information extraction. Your job is to:
      1. Read the provided user notes and, if present, the uploaded document or image.
      2. Write a concise, human-readable description that synthesizes information from BOTH the user note(s) and the document/image, making clear connections between them. Do NOT output the note as a separate field.
      3. Annotate each description with entity tags in the format [EntityType: Value], using ONLY the allowed entity types below.
      4. Provide a confidence rating between 0 and 1 (as a float, 1 = very sure, 0 = not sure) for your analysis of that piece of content.
      5. Output your result as a single JSON object matching the following strict schema. IMPORTANT: The output MUST be valid JSON and MUST match the schema exactly, with no extra text, comments, or Markdown. If you do not comply, your output will be rejected as an error.

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
end
