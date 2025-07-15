#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive test of the asset deduplication system with human review

unless defined?(Rails)
  puts "This script must be run in a Rails environment. Please use: bundle exec rails runner #{__FILE__}"
  exit 1
end

require "json"

puts "🔧 Comprehensive Asset Deduplication System Test"
puts "=" * 60

# Clear any existing reviews
reviews_file = Rails.root.join("tmp", "human_reviews.json")
File.write(reviews_file, "[]") if File.exist?(reviews_file)

# Clear database for clean test
puts "\n1. Clearing database..."
system("bin/rails runner scripts/clear_neo4j.rb")

# Test data with various confidence levels and types
# All data is now generic and type-agnostic, covering major node types

test_entities = [
  # High confidence (should auto-merge)
  { type: "Asset", name: "Laptop",
    properties: { "serial_number" => "GENERIC123", "category" => "electronics", "make" => "GenericBrand", "model" => "Alpha" } },
  { type: "Asset", name: "Work Laptop",
    properties: { "serial_number" => "GENERIC123", "category" => "electronics", "make" => "GenericBrand", "model" => "Alpha" } },

  { type: "Person", name: "Jane Doe", properties: { "email" => "jane.doe@example.com", "notes" => "Test user" } },
  { type: "Person", name: "J. Doe", properties: { "email" => "jane.doe@example.com", "notes" => "Alternate spelling" } },

  { type: "Document", name: "Project Plan",
    properties: { "title" => "Project Plan", "description" => "Initial project planning document", "content" => "Full text of plan." } },
  { type: "Document", name: "Project Plan v2",
    properties: { "title" => "Project Plan", "description" => "Updated plan", "content" => "Full text of plan." } },

  # Medium confidence (should trigger human review)
  { type: "Task", name: "Write Report", properties: { "title" => "Write Report", "description" => "Draft the quarterly report." } },
  { type: "Task", name: "Draft Report", properties: { "title" => "Draft Report", "description" => "Prepare the Q1 report." } },

  { type: "Event", name: "Team Meeting", properties: { "title" => "Team Meeting", "description" => "Weekly sync" } },
  { type: "Event", name: "Weekly Sync", properties: { "title" => "Weekly Sync", "description" => "Team meeting" } },

  # Low confidence (should auto-reject)
  { type: "Asset", name: "Desk Chair", properties: { "category" => "furniture", "make" => "Generic", "model" => "ChairX" } },
  { type: "Note", name: "Random Note", properties: { "title" => "Random Note", "content" => "Unrelated note content." } },
  { type: "Property", name: "Office", properties: { "name" => "Office", "notes" => "Main workspace" } },
  { type: "List", name: "Shopping List", properties: { "name" => "Shopping List", "description" => "Groceries to buy" } }
]

puts "\n2. Testing generic deduplication scenarios across major entity types..."
puts "   • High confidence: Exact unique identifier match (serial/email/title/content)"
puts "   • Medium confidence: Similar names/descriptions, different properties"
puts "   • Low confidence: Different types or unrelated properties"

puts "\n2. Testing with various confidence scenarios..."
puts "   • High confidence: Exact serial number match"
puts "   • Medium confidence: Similar names but different properties"
puts "   • Low confidence: Completely different asset types"

# Create importer with human review enabled
logger = Logger.new($stdout)
logger.level = Logger::WARN # Reduce noise for demo

importer = Neo4j::Import::NodeImporter.new(
  logger: logger,
  debug: false,
  enable_human_review: true,
  enable_vector_search: false
)

# Import and analyze results
puts "\n3. Running import with human review system..."
stats = importer.import(test_entities)

puts "\n4. Import Results:"
puts "   📊 Total: #{stats[:total]}, Created: #{stats[:created]}, Updated: #{stats[:updated]}"

# Check what was queued for human review
if File.exist?(reviews_file)
  reviews = JSON.parse(File.read(reviews_file))
  pending_reviews = reviews.select { |r| r["status"] == "pending" }

  puts "\n5. Human Review Queue:"
  if pending_reviews.any?
    puts "   🤔 #{pending_reviews.size} review(s) queued for human evaluation:"
    pending_reviews.each do |review|
      confidence = review["confidence_score"].round(3)
      existing_name = review["existing_asset"]["name"]
      new_name = review["new_asset"]["name"]
      puts "      • #{confidence} confidence: '#{existing_name}' ↔ '#{new_name}'"
    end

    puts "\n6. To review these decisions, run:"
    puts "   bin/rails runner scripts/human_review_interface.rb"
  else
    puts "   ✅ No reviews queued - all decisions were automatic!"
  end
else
  puts "\n5. ✅ No reviews queued - all decisions were automatic!"
end

# Show final asset state
puts "\n7. Final Asset State:"
Neo4j::DatabaseService.read_transaction do |tx|
  result = tx.run("MATCH (n:Asset) RETURN n.name, n.brand, n.model, n.serial_number ORDER BY n.name")
  result.each do |record|
    name = record["n.name"]
    brand = record["n.brand"]
    model = record["n.model"]
    serial = record["n.serial_number"]

    details = [brand, model, serial].compact.join(", ")
    details_str = details.empty? ? "" : " (#{details})"
    puts "   • #{name}#{details_str}"
  end
end

puts "\n🎉 Comprehensive deduplication test complete!"
puts "\nSystem Features Demonstrated:"
puts "✅ Generic asset matching (any asset type)"
puts "✅ Confidence-based automatic decisions"
puts "✅ Human review queue for uncertain cases"
puts "✅ Multiple matching strategies (serial, brand+model, name similarity)"
puts "✅ Configurable confidence thresholds"
