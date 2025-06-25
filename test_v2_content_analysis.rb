#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for ContentAnalysisService with V2 data model
# Run with: bundle exec rails runner test_v2_content_analysis.rb

require "json"

# Enable debug logging
ENV["DEBUG"] = "true"

# Mock OpenAI service for testing
class MockOpenAIService
  # rubocop:disable Lint/UnusedMethodArgument
  def chat(prompt, model: nil, temperature: nil, max_tokens: nil)
    # rubocop:enable Lint/UnusedMethodArgument
    puts "Mock OpenAI Service received prompt: #{prompt.truncate(100)}..."

    # Return a mock response with statements
    {
      "choices" => [
        {
          "message" => {
            "content" => JSON.generate({
                                         "description" => "This is a Florida license plate CJ8 9NF on a GMC Sierra 1500 truck, expiring in February 2026.",
                                         "annotated_description" => "This is a [Entity: Florida license plate] [Entity: CJ8 9NF] on a [Entity: GMC Sierra 1500 truck], expiring in [Entity: February 2026].",
                                         "statements" => [
                                           {
                                             "subject" => "CJ8 9NF",
                                             "text" => "is a license plate number",
                                             "confidence" => 1.0
                                           },
                                           {
                                             "subject" => "Florida license plate",
                                             "text" => "has number",
                                             "object" => "CJ8 9NF",
                                             "confidence" => 1.0
                                           },
                                           {
                                             "subject" => "GMC Sierra 1500 truck",
                                             "text" => "has license plate",
                                             "object" => "CJ8 9NF",
                                             "confidence" => 0.95
                                           },
                                           {
                                             "subject" => "CJ8 9NF",
                                             "text" => "expires in",
                                             "object" => "February 2026",
                                             "confidence" => 0.9
                                           }
                                         ],
                                         "rating" => 0.95
                                       })
          }
        }
      ]
    }
  end
end

# Test function
def test_content_analysis_service
  puts "=== Testing ContentAnalysisService with V2 Data Model ==="

  # Create a test content
  content = Content.create!(
    note: "This is a test note about a Florida license plate CJ8 9NF on a GMC Sierra 1500 truck."
  )

  puts "Created test content: #{content.id} - Note: #{content.note.truncate(50)}"

  # Initialize service with mock OpenAI
  service = ContentAnalysisService.new(openai_service: MockOpenAIService.new)

  # Test the service
  puts "Running content analysis..."
  results = service.analyze(notes: [content.note], files: [])

  puts "Analysis complete!"

  # Extract entities and statements
  result = service.extract_and_create_entities(content, results.first[:result])

  # Display results
  puts "\n=== Results ==="
  puts "Created #{result[:entities].size} entities:"
  result[:entities].each do |entity|
    puts "- Entity: #{entity.id} - #{entity.name}"
  end

  puts "\nCreated #{result[:statements].size} statements:"
  result[:statements].each do |statement|
    subject = statement.entity.name
    object = statement.object_entity&.name
    text = statement.text

    if object
      puts "- Statement: #{subject} -> #{text} -> #{object}"
    else
      puts "- Statement: #{subject} -> #{text}"
    end
  end

  puts "\n=== Testing Entity Search Methods ==="

  # Test finding entities by name similarity
  puts "\nFinding entities by name similarity to 'license':"
  Entity.find_by(name_similarity: "license").each do |entity|
    puts "- #{entity.name} (similarity: #{entity.similarity})"
  end

  # Test finding entities by statement similarity
  puts "\nFinding entities by statement similarity to 'truck with license plate':"
  Entity.find_by(statement: "truck with license plate").each do |entity|
    puts "- #{entity.name} (similarity: #{entity.similarity})"
  end

  puts "\n=== Test Complete ==="
end

# Run the test
begin
  test_content_analysis_service
rescue StandardError => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.join("\n")
end
