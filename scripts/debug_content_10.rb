#!/usr/bin/env ruby
# Debug script to investigate why content 10 has no entities despite OpenAI processing

ENV["DEBUG"] = "true" # Enable debug logging

# Find content 10
content = Content.find(10)
puts "Found content: #{content.id}"
puts "Content note: #{content.note.inspect}"

# Check if it has OpenAI response
if content.openai_response.present?
  puts "\nOpenAI response exists:"
  puts "Response type: #{content.openai_response.class.name}"
  puts "Response keys: #{content.openai_response.keys.inspect}"

  # Check for statements in the response
  if content.openai_response["statements"].present?
    puts "\nStatements found in response:"
    puts "Statements count: #{content.openai_response['statements'].size}"
    puts "Sample statements:"
    content.openai_response["statements"].first(3).each_with_index do |stmt, i|
      puts "  #{i + 1}. #{stmt.inspect}"
    end
  else
    puts "\nNo statements found in OpenAI response!"
  end

  # Check for other potential entity sources
  puts "\nChecking other potential entity sources in response:"
  content.openai_response.each do |key, value|
    if value.is_a?(Array) && value.first.is_a?(Hash)
      puts "  Key '#{key}' contains array of hashes: #{value.size} items"
      puts "  Sample: #{value.first.inspect}"
    end
  end
else
  puts "\nNo OpenAI response found!"
end

# Check existing entities
puts "\nExisting entities:"
entities = content.entities.reload
if entities.any?
  puts "Entity count: #{entities.count}"
  entities.each do |entity|
    puts "  - #{entity.name} (ID: #{entity.id})"
  end
else
  puts "No entities found for this content"
end

# Try to manually extract entities using the service
puts "\nAttempting to manually extract entities:"
service = ContentAnalysisService.new

# Monkey patch the extract_and_create_entities method to add more debugging
original_method = ContentAnalysisService.instance_method(:extract_and_create_entities)
ContentAnalysisService.define_method(:extract_and_create_entities) do |content, openai_result|
  puts "INTERCEPTED: Inside extract_and_create_entities"
  puts "OpenAI result type: #{openai_result.class.name}"
  puts "OpenAI result keys: #{openai_result.keys.inspect}"

  if openai_result["statements"].present?
    puts "Found #{openai_result['statements'].size} statements"
    openai_result["statements"].each_with_index do |stmt, i|
      puts "Statement #{i + 1}: #{stmt.inspect}"

      # Check if this statement would create an entity
      puts "  Would create entity: #{stmt['subject']}" if stmt["subject"].present?
      puts "  Would create object entity: #{stmt['object']}" if stmt["object"].present? && stmt["object"] != stmt["subject"]
    end
  else
    puts "No statements found in result!"
  end

  # Call the original method
  result = original_method.bind_call(self, content, openai_result)
  puts "Extract method returned: #{result.inspect}"
  result
end

# Try to process the existing OpenAI response
if content.openai_response.present?
  puts "\nProcessing existing OpenAI response:"
  created_entities = service.extract_and_create_entities(content, content.openai_response)
  puts "Created entities: #{created_entities.inspect}"
else
  puts "\nCannot process: No OpenAI response to extract entities from"
end

# Check if any entities were created
puts "\nFinal entity count: #{content.entities.reload.count}"
