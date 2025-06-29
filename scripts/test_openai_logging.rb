#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify OpenAI logging functionality
# Run with: rails runner tmp/test_openai_logging.rb

puts "=== Testing OpenAI Logging ==="
puts "Logs will be written to log/openai.log"

# Set debug mode
ENV["DEBUG"] = "true"

# Test the OpenAI client service
puts "\n1. Testing OpenAI::ClientService#chat"
begin
  client_service = OpenAI::ClientService.new
  prompt = "Extract entities from this text: Florida license plate CJ8 9NF on a GMC Sierra 1500 truck, expiring in February 2026."

  puts "Sending chat request..."
  response = client_service.chat(prompt)

  puts "Chat response received:"
  puts "- ID: #{response['id']}"
  puts "- Model: #{response['model']}"
  puts "- Usage: #{response['usage'].inspect}"
  puts "- First few characters of content: #{response['choices'].first['message']['content'][0..100]}..."
rescue StandardError => e
  puts "Error in chat test: #{e.message}"
end

# Test the OpenAI embedding service
puts "\n2. Testing OpenAI::EmbeddingService#embed"
begin
  embedding_service = OpenAI::EmbeddingService.new
  text = "Florida license plate CJ8 9NF"

  puts "Generating embedding..."
  embedding = embedding_service.embed(text)

  puts "Embedding generated:"
  puts "- Dimensions: #{embedding.size}"
  puts "- First 5 values: #{embedding.first(5).map { |v| v.round(4) }}"
rescue StandardError => e
  puts "Error in embedding test: #{e.message}"
end

# Test batch embeddings
puts "\n3. Testing OpenAI::EmbeddingService#embed_batch"
begin
  embedding_service = OpenAI::EmbeddingService.new
  texts = [
    "Florida license plate CJ8 9NF",
    "GMC Sierra 1500 truck",
    "Expiring in February 2026"
  ]

  puts "Generating batch embeddings..."
  embeddings = embedding_service.embed_batch(texts)

  puts "Batch embeddings generated:"
  puts "- Count: #{embeddings.size}"
  puts "- Dimensions per embedding: #{embeddings.first.size}"
  puts "- First 3 values of first embedding: #{embeddings.first.first(3).map { |v| v.round(4) }}"
rescue StandardError => e
  puts "Error in batch embedding test: #{e.message}"
end

puts "\n=== Tests Complete ==="
puts "Check log/openai.log for detailed request and response logs"
