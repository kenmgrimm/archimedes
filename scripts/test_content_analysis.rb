#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test the ContentAnalysisService with sample content and image
# Run with: rails runner scripts/test_content_analysis.rb

# Enable debug logging
ENV["DEBUG"] = "true"

# Create a sample content
puts "Creating sample content..."
content = Content.create!(
  note: "This is a photo of the license plate on my truck."
)
puts "Created content ##{content.id}"

# Add debug logging
puts "Content attributes: #{content.attributes.inspect}"

# Load the license plate image
image_path = Rails.root.join("scripts", "license plate.jpeg").to_s
puts "Loading image from: #{image_path}"

# Variable to store the image file for OpenAI
image_file = nil

if File.exist?(image_path)
  puts "Image found! Loading..."
  # Read the image file binary data
  image_data = File.binread(image_path)

  # Create a file hash with the necessary information for ContentAnalysisService
  image_file = {
    filename: "license plate.jpeg",
    data: image_data,
    content_type: "image/jpeg"
  }

  puts "Image loaded (#{image_data.bytesize} bytes)"
else
  puts "ERROR: Image file not found at #{image_path}"
  exit 1
end

# Sample note describing the license plate image
sample_note = <<~NOTE
  This is a photo of the license plate on my truck.
NOTE

puts "Testing ContentAnalysisService..."
puts "Sample note: #{sample_note[0..100]}..."

# Initialize the service
service = ContentAnalysisService.new

# Analyze the sample note with license plate description and image
puts "Calling analyze method with image..."

# Add debug logging
puts "Image file details:"
puts "  - Filename: #{image_file[:filename]}"
puts "  - Size: #{image_file[:data].bytesize} bytes"
puts "  - Content Type: #{image_file[:content_type]}"

# Pass the image file to the analyze method
result = service.analyze(notes: [sample_note], files: [image_file])

# Process the results
puts "Processing analysis results..."
processing_result = service.process_analysis_result(content, result)

# Print summary
puts "\n=== ANALYSIS RESULTS ===\n"
puts "Created #{processing_result[:created_entities].size} entities:"
processing_result[:created_entities].each do |entity|
  puts "  - #{entity.name} (ID: #{entity.id})"
end

puts "\nCreated #{processing_result[:created_statements].size} statements:"
processing_result[:created_statements].each do |statement|
  puts "  - #{statement.text} (ID: #{statement.id})"
  puts "    Subject: #{statement.entity.name}, Predicate: #{statement.predicate}, Object: #{statement.object}"
end

puts "\nCreated #{processing_result[:verification_requests].size} verification requests:"
processing_result[:verification_requests].each do |vr|
  puts "  - #{vr.candidate_name} (ID: #{vr.id}, Status: #{vr.status})"
  puts "    Similar entities: #{vr.similar_entities.inspect}"
  puts "    Pending statements: #{vr.pending_statements.size}"
end

puts "\nErrors: #{processing_result[:errors].any? ? processing_result[:errors].join('; ') : 'None'}"

puts "\n=== DATABASE STATS ===\n"
puts "Entities: #{Entity.count}"
puts "Statements: #{Statement.count}"
puts "Verification Requests: #{VerificationRequest.count}"

puts "\nDone!"
