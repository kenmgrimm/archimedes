#!/usr/bin/env rails runner

# frozen_string_literal: true

require "dotenv/load"
require "json"

# Set up logging
logger = Logger.new($stdout)
logger.level = Logger::DEBUG

# Initialize services
openai_client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY", nil))
deduplication_service = Neo4j::DeduplicationService.new(openai_client, logger: logger)

# Test data
test_entities = [
  # Test 1: Laptop with serial number
  {
    "id" => "test_laptop_1",
    "name" => 'MacBook Pro 16"',
    "entity_type" => "Asset",
    "properties" => {
      "serialNumber" => "C02X12345678",
      "category" => "electronics",
      "make" => "Apple",
      "model" => 'MacBook Pro 16" M1 Max',
      "year" => "2021"
    }.to_json
  },

  # Test 2: Similar laptop, different serial
  {
    "id" => "test_laptop_2",
    "name" => "MacBook Pro 16 inch",
    "entity_type" => "Asset",
    "properties" => {
      "serialNumber" => "C02X87654321",
      "category" => "electronics",
      "make" => "Apple",
      "model" => 'MacBook Pro 16" M1 Max',
      "year" => "2021"
    }.to_json
  },

  # Test 3: Person with email
  {
    "id" => "test_person_1",
    "name" => "John Doe",
    "entity_type" => "Person",
    "properties" => {
      "email" => "john.doe@example.com",
      "phone" => "+1234567890"
    }.to_json
  },

  # Test 4: Same person, different name
  {
    "id" => "test_person_2",
    "name" => "John D.",
    "entity_type" => "Person",
    "properties" => {
      "email" => "john.doe@example.com",
      "phone" => "+1987654321"
    }.to_json
  },

  # Test 5: Component (keyboard)
  {
    "id" => "test_keyboard_1",
    "name" => "MacBook Pro Keyboard",
    "entity_type" => "Component",
    "properties" => {
      "partOf" => "test_laptop_1",
      "type" => "keyboard",
      "description" => 'Backlit keyboard for MacBook Pro 16"'
    }.to_json
  }
]

# Helper method to create test entities
def create_test_entity(attrs)
  # Use the correct model class (Entity instead of Neo4j::Entity)
  entity = Entity.find_or_initialize_by(id: attrs["id"])
  entity.assign_attributes(
    name: attrs["name"],
    entity_type: attrs["entity_type"],
    properties: attrs["properties"]
  )
  entity.save!
  entity
end

# Create test entities in the database
logger.info("Creating test entities...")
test_entities.each do |entity_attrs|
  create_test_entity(entity_attrs)
  logger.debug("Created test entity: #{entity_attrs['name']} (ID: #{entity_attrs['id']})")
end

# Test cases
test_cases = [
  {
    name: "Exact name match for asset",
    entity: {
      "name" => 'MacBook Pro 16"',
      "entity_type" => "Asset",
      "properties" => {
        "serialNumber" => "SN99999",
        "category" => "electronics",
        "make" => "Apple",
        "model" => 'MacBook Pro 16" M1 Max'
      }.to_json
    },
    expected_match: "test_laptop_1"
  },
  {
    name: "Similar name match for asset",
    entity: {
      "name" => "MacBook Pro 16 inch M1 Max",
      "entity_type" => "Asset",
      "properties" => {
        "serialNumber" => "SN99999",
        "category" => "electronics",
        "make" => "Apple"
      }.to_json
    },
    expected_match: "test_laptop_1"  # Should match by name similarity
  },
  {
    name: "Person by email",
    entity: {
      "name" => "John D.",
      "entity_type" => "Person",
      "properties" => {
        "email" => "john.doe@example.com",
        "phone" => "+1555555555"
      }.to_json
    },
    expected_match: "test_person_1"  # Should match by email
  },
  {
    name: "Component that's part of an asset",
    entity: {
      "name" => "Keyboard",
      "entity_type" => "Component",
      "properties" => {
        "type" => "keyboard",
        "description" => 'Keyboard for MacBook Pro 16"'
      }.to_json
    },
    expected_match: "test_keyboard_1" # Should be recognized as part of the laptop
  }
]

# Run test cases
logger.info("\n=== Starting deduplication tests ===\n")

test_cases.each_with_index do |test_case, index|
  logger.info("\n=== Test ##{index + 1}: #{test_case[:name]} ===")

  # Run deduplication
  result = deduplication_service.deduplicate(test_case[:entity], test_case[:entity]["entity_type"])

  # Check the result
  if result["id"] == test_case[:expected_match]
    logger.info("✅ Test passed: Found expected duplicate #{test_case[:expected_match]}")
  elsif result["id"] == test_case[:entity]["id"]
    logger.warn("⚠️  Test failed: Expected to find duplicate #{test_case[:expected_match]} but no duplicate was found")
  else
    logger.warn("⚠️  Test failed: Expected duplicate #{test_case[:expected_match]} but found #{result['id']}")
  end

  logger.debug("Result: #{result.to_json}")
end

# Clean up (optional)
if ENV["CLEANUP"] != "false"
  logger.info("\nCleaning up test data...")
  test_entities.each do |entity_attrs|
    Entity.find_by(id: entity_attrs["id"])&.destroy
  end
  logger.info("Cleanup complete")
end
