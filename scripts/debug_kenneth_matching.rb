#!/usr/bin/env ruby

require_relative "../config/environment"

puts "Debug matching between first two Kenneth Grimm entities..."

# Properties from first entity
props1 = {
  "aliases" => ["Kenneth", "Ken", "Kenny"],
  "date_of_birth" => "2/19/1977",
  "current_address" => "1126 Excelsior Creek Ave, Montrose, CO 81401",
  "phone_number" => "303-214-8444",
  "email" => "kengrimm@gmail.com",
  "name" => "Kenneth Grimm"
}

# Properties from second entity
props2 = {
  "aliases" => ["Kenneth", "Ken", "Kenny"],
  "ID" => "1",
  "name" => "Kenneth Grimm"
}

puts "Props1: #{props1.inspect}"
puts "Props2: #{props2.inspect}"

# Test individual matcher methods
puts "\n=== Testing individual PersonNodeMatcher methods ==="

puts "Email match: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.exact_email_match(props1, props2)}"
puts "Phone match: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.exact_phone_match(props1, props2)}"
puts "Full name domain match: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name_email_domain_match(props1, props2)}"
puts "Full name similarity: #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name_similarity_match(props1, props2)}"

puts "\n=== Testing BaseNodeMatcher string_similar? method ==="
name1 = Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name(props1)
name2 = Neo4j::Import::NodeMatchers::PersonNodeMatcher.full_name(props2)
puts "Name1: '#{name1}'"
puts "Name2: '#{name2}'"
puts "string_similar?(name1, name2, 0.9): #{Neo4j::Import::NodeMatchers::PersonNodeMatcher.string_similar?(name1, name2, 0.9)}"

puts "\n=== Testing overall fuzzy matching ==="
result = Neo4j::Import::NodeMatcherRegistry.fuzzy_match?("Person", props1, props2, debug: true)
puts "Overall fuzzy match result: #{result}"
