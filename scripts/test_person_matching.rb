#!/usr/bin/env ruby

require_relative '../config/environment'

# Test PersonNodeMatcher
puts "Testing PersonNodeMatcher..."

# Test data - first Kenneth Grimm (full profile)
props1 = {
  "aliases" => ["Kenneth", "Ken", "Kenny"],
  "date_of_birth" => "2/19/1977",
  "current_address" => "1126 Excelsior Creek Ave, Montrose, CO 81401",
  "phone_number" => "303-214-8444",
  "email" => "kengrimm@gmail.com",
  "name" => "Kenneth Grimm"
}

# Test data - second Kenneth Grimm (with ID)
props2 = {
  "aliases" => ["Kenneth", "Ken", "Kenny"],
  "ID" => "1",
  "name" => "Kenneth Grimm"
}

puts "Props1: #{props1.inspect}"
puts "Props2: #{props2.inspect}"

# Test fuzzy matching
puts "\nTesting fuzzy matching..."
result = Neo4j::Import::NodeMatcherRegistry.fuzzy_match?("Person", props1, props2, debug: true)
puts "Result: #{result}"

# Test individual methods
puts "\nTesting individual methods..."
puts "Email match: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.exact_email_match(props1, props2)}"
puts "Phone match: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.exact_phone_match(props1, props2)}"
puts "Full name similarity: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name_similarity_match(props1, props2)}"

# Test name extraction
puts "\nTesting name extraction..."
puts "Full name 1: '#{Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name(props1)}'"
puts "Full name 2: '#{Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name(props2)}'"

# Test embedding text
puts "\nTesting embedding text..."
puts "Embedding 1: '#{Neo4j::Import::NodeMatchers::PersonNodeMatcher.generate_embedding_text(props1)}'"
puts "Embedding 2: '#{Neo4j::Import::NodeMatchers::PersonNodeMatcher.generate_embedding_text(props2)}'"