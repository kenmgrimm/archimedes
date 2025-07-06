#!/usr/bin/env ruby

require "json"
require "fileutils"
require "pathname"
require "base64"
require "mimemagic"
require_relative "../config/environment"

# add description of script purpose, usage and arguments
# usage: `be rails runner scripts/test_extraction.rb <directory>`
# if directory is specified, only process that directory
# if directory is not specified, process all directories in input

# Check for required environment variables
unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is not set"
  puts "Please set your OpenAI API key and try again"
  exit 1
end

input_base = File.join(File.dirname(__FILE__), "input")
target_dirs = if ARGV[0]
                # Use the first argument as a specific directory to process
                specified_dir = File.join(input_base, ARGV[0])
                if Dir.exist?(specified_dir)
                  puts "Processing specified directory: #{ARGV[0]}"
                  [specified_dir]
                else
                  puts "Error: Directory not found - #{specified_dir}"
                  exit 1
                end
              else
                # Process all directories in the input base
                puts "No directory specified, processing all directories in: #{input_base}"
                Dir.glob(File.join(input_base, "*"))
              end

# Set up directories
input_base = File.join(File.dirname(__FILE__), "input")
output_base = File.join(File.dirname(__FILE__), "output")
FileUtils.mkdir_p(output_base)

# Initialize the OpenAI client with debug logging
puts "Initializing OpenAI client..."
openai_service = OpenAI::ClientService.new(logger: Logger.new(STDOUT))

# Initialize the extractor
puts "Initializing entity extractor..."
extractor = Neo4j::EntityExtractionService.new(openai_service, logger: Logger.new(STDOUT))

# Helper method to encode image to base64
def encode_image(image_path)
  base64_image = Base64.strict_encode64(File.binread(image_path))
  mime_type = MimeMagic.by_magic(File.open(image_path, "rb"))&.type
  "data:#{mime_type};base64,#{base64_image}"
rescue StandardError => e
  puts "  Error encoding image #{File.basename(image_path)}: #{e.message}"
  nil
end

# Process each folder in the target directories
target_dirs.each do |input_folder|
  next unless File.directory?(input_folder)

  folder_name = File.basename(input_folder)
  puts "\n=== Processing folder: #{folder_name} ==="

  begin
    # Find all files in the folder
    files = Dir.glob(File.join(input_folder, "*")).select { |f| File.file?(f) }

    # Separate text files from other document types
    text_files = files.select { |f| File.extname(f).downcase == ".txt" }
    other_files = files.reject { |f| File.extname(f).downcase == ".txt" }

    # If no text file found, skip this folder
    if text_files.empty?
      puts "  No text file found in folder. Skipping..."
      next
    end

    # Read the first text file as the main description
    main_text_file = text_files.first
    puts "Processing main text file: #{File.basename(main_text_file)}"

    description = File.read(main_text_file)

    # Prepare documents array for additional files
    documents = []

    # Process other supporting documents if any
    other_files.each do |file_path|
      file_ext = File.extname(file_path).downcase
      file_name = File.basename(file_path)

      # Skip unsupported file types
      supported_docs = [".pdf", ".png", ".jpg", ".jpeg", ".gif", ".doc", ".docx", ".xls", ".xlsx"]
      next unless supported_docs.include?(file_ext)

      puts "  Found supporting document: #{file_name}"
      documents << {
        path: file_path,
        name: file_name,
        type: file_ext[1..-1] # Remove the dot
      }
    end

    # Prepare messages array for the API
    messages = []

    # Add the main text
    messages << { role: "user", content: description }

    # Add any images to the messages
    image_docs = documents.select { |doc| [".png", ".jpg", ".jpeg", ".gif"].include?(File.extname(doc[:path]).downcase) }

    image_docs.each do |doc|
      image_data = encode_image(doc[:path])
      next unless image_data

      messages << {
        role: "user",
        content: [
          { type: "text", text: "Content of file: #{doc[:name]}" },
          { type: "image_url", image_url: { url: image_data } }
        ]
      }
      puts "  Added image to prompt: #{doc[:name]}"
    end

    # Add any remaining non-image documents as text
    other_docs = documents.reject { |doc| [".png", ".jpg", ".jpeg", ".gif"].include?(File.extname(doc[:path]).downcase) }
    unless other_docs.empty?
      other_docs_text = other_docs.map { |doc| "- #{doc[:name]}" }.join("\n")
      messages << {
        role: "user",
        content: "Supporting documents (content not processed):\n#{other_docs_text}"
      }
    end

    # Process the content with images
    puts "Processing content (#{description.size} characters, #{image_docs.size} images)..."

    # Get the taxonomy context and build the system prompt
    taxonomy_context = extractor.send(:build_taxonomy_context) # Use send to access private method
    system_prompt = extractor.send(:build_neo4j_extraction_prompt, taxonomy_context)

    # Prepare the full messages array that will be sent to the API
    full_messages = [
      { role: "system", content: system_prompt },
      *messages
    ]

    # Save the full prompt to a file
    prompt_content = "# System Prompt\n\n#{system_prompt}\n\n# Messages Sent\n"
    full_messages.each_with_index do |msg, i|
      prompt_content += "\n## Message #{i + 1} (#{msg[:role]})\n"
      if msg[:content].is_a?(String)
        prompt_content += msg[:content]
      elsif msg[:content].is_a?(Array)
        msg[:content].each do |part|
          if part.is_a?(Hash) && part[:type] == "text"
            prompt_content += part[:text].to_s
          elsif part.is_a?(Hash) && part[:type] == "image_url"
            prompt_content += "[Image: #{part[:image_url][:url][0..100]}...]"
          end
        end
      end
    end

    # Use the extractor with the messages array
    result = extractor.extract_with_messages(messages)

    # Prepare output
    output = {
      timestamp: Time.current.iso8601,
      input_folder: folder_name,
      main_text_file: File.basename(main_text_file),
      supporting_documents: documents.map { |doc| doc[:name] },
      files_processed: files.size,
      extraction_result: result
    }

    # Create output directory for this folder
    output_folder = File.join(output_base, folder_name)
    FileUtils.mkdir_p(output_folder)

    # Save the results (overwrite existing file)
    output_file = File.join(output_folder, "extraction.json")
    prompt_file = File.join(output_folder, "prompt.txt")

    # Save the extraction results
    File.write(output_file, JSON.pretty_generate(output))

    # Save the complete prompt to a separate file
    File.write(prompt_file, prompt_content)

    puts "✓ Results saved to: #{output_file}"
    puts "✓ Full prompt saved to: #{prompt_file}"
  rescue StandardError => e
    puts "Error processing folder #{folder_name}: #{e.message}"
    puts e.backtrace.join("\n") if ENV["DEBUG"]
  end
end

puts "\n=== Processing complete ==="
