#!/usr/bin/env rails runner

# frozen_string_literal: true

require "dotenv/load"
require "neo4j-ruby-driver"
require "json"
require "logger"

# Set up logging
$log_file = File.open(File.expand_path("log/deduplication_test.log", Rails.root), "a")
$logger = Logger.new($stdout)
$logger.level = Logger::DEBUG
$logger.formatter = proc do |severity, datetime, _progname, msg|
  log_line = "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
  $log_file.puts(log_line)
  log_line
end

# Neo4j connection
NEO4J_URI = ENV.fetch("NEO4J_URL")
NEO4J_USERNAME = ENV.fetch("NEO4J_USERNAME")
NEO4J_PASSWORD = ENV.fetch("NEO4J_PASSWORD")

# Initialize Neo4j driver
def create_driver
  Neo4j::Driver::GraphDatabase.driver(
    NEO4J_URI,
    Neo4j::Driver::AuthTokens.basic(NEO4J_USERNAME, NEO4J_PASSWORD)
  )
end

# Clear all test data
def clear_test_data(driver)
  driver.session do |session|
    session.run("MATCH (n:Test) DETACH DELETE n")
  end
  $logger.info("Cleared all test data from Neo4j")
end

# Create a test entity in Neo4j
def create_test_entity(driver, entity_data)
  driver.session do |session|
    labels = [entity_data[:type], "Test"].compact.map { |l| "`#{l}`" }.join(":")

    # Prepare properties
    props = {
      id: entity_data[:id],
      name: entity_data[:name],
      created_at: Time.now.iso8601,
      updated_at: Time.now.iso8601
    }

    # Add all properties from the entity
    props.merge!(entity_data[:properties]) if entity_data[:properties].is_a?(Hash)

    # Create the node
    query = "CREATE (n:#{labels} $props) RETURN n"
    result = session.run(query, props: props)
    $logger.debug("Created test entity: #{entity_data[:type]} #{entity_data[:name]}")
    result.single[0]
  end
end

# Find potential duplicates in Neo4j
def find_potential_duplicates(driver, entity_data)
  session = driver.session
  begin
    # Initialize variables
    query = ""
    params = {}

    # First, try to find exact matches on unique identifiers
    case entity_data[:type]
    when "Person"
      # For people, check for matching email (case-insensitive)
      if entity_data[:properties]&.key?(:email)
        email = entity_data[:properties][:email].to_s.downcase
        query = %{
          MATCH (e:Person:Test)
          WHERE toLower(e.email) = $email
          RETURN e, e.name as name
          LIMIT 10
        }

        exact_matches = session.run(query, email: email).to_a
        if exact_matches.any?
          $logger.debug("Found #{exact_matches.size} exact email matches")
          return exact_matches.pluck("e")
        end
      end

      # If no email match, try fuzzy name matching
      query = %{
        MATCH (e:Person:Test)
        WHERE toLower(e.name) CONTAINS toLower($name_part1)
        OR toLower(e.name) CONTAINS toLower($name_part2)
        RETURN e, e.name as name
        LIMIT 10
      }

      # Extract first and last name parts for better matching
      name_parts = entity_data[:name].split
      params = {
        name_part1: name_parts.first || "",
        name_part2: name_parts.last || ""
      }

    when "Asset"
      # For assets, check for matching serial number first
      if entity_data[:properties]&.key?(:serialNumber)
        serial = entity_data[:properties][:serialNumber].to_s.upcase
        query = %{
          MATCH (e:Asset:Test)
          WHERE toUpper(toString(e.serialNumber)) = $serial
          RETURN e, e.name as name
          LIMIT 10
        }

        exact_matches = session.run(query, serial: serial).to_a
        if exact_matches.any?
          $logger.debug("Found #{exact_matches.size} exact serial number matches")
          return exact_matches.pluck("e")
        end
      end

      # If no serial match, try fuzzy name and model matching
      query = %{
        MATCH (e:Asset:Test)
        WHERE toLower(e.name) CONTAINS toLower($name_part)
        OR (exists(e.model) AND toLower(e.model) CONTAINS toLower($name_part))
        RETURN e, e.name as name
        LIMIT 10
      }

      # Use the first word of the name for matching
      name_part = entity_data[:name].split.first || ""
      params = { name_part: name_part }

    else
      # Default behavior for other entity types
      query = %{
        MATCH (e:#{entity_data[:type]}:Test)
        WHERE toLower(e.name) CONTAINS toLower($name)
        RETURN e, e.name as name
        LIMIT 10
      }
      params = { name: entity_data[:name] }
    end

    $logger.debug("Running duplicate check query: #{query} with params: #{params}")
    result = session.run(query, params).to_a

    # Sort results by similarity to the original name (case-insensitive)
    original_name = entity_data[:name].to_s.downcase

    sorted_results = result.sort_by do |record|
      record_name = record["name"].to_s.downcase
      # Calculate a simple similarity score based on string inclusion
      if record_name.include?(original_name) || original_name.include?(record_name)
        0 # Higher priority for contained/containing names
      else
        # Otherwise, use Levenshtein distance as a fallback
        require "levenshtein"
        Levenshtein.distance(original_name, record_name)
      end
    end

    sorted_results.pluck("e")
  ensure
    session&.close
  end
end

# Main test
begin
  driver = create_driver

  # Clear any existing test data
  clear_test_data(driver)

  # Test data
  test_entities = [
    # Test 1: Laptop with serial number
    {
      id: "test_laptop_1",
      name: "MacBook Pro 16\"",
      type: "Asset",
      properties: {
        serialNumber: "C02X12345678",
        category: "electronics",
        make: "Apple",
        model: "MacBook Pro 16\" M1 Max",
        year: "2021"
      }
    },

    # Test 2: Similar laptop, different serial
    {
      id: "test_laptop_2",
      name: "MacBook Pro 16 inch",
      type: "Asset",
      properties: {
        serialNumber: "C02X87654321",
        category: "electronics",
        make: "Apple",
        model: "MacBook Pro 16\" M1 Max",
        year: "2021"
      }
    },

    # Test 3: Person with email
    {
      id: "test_person_1",
      name: "John Doe",
      type: "Person",
      properties: {
        email: "john.doe@example.com",
        phone: "+1234567890"
      }
    },

    # Test 4: Same person, different name
    {
      id: "test_person_2",
      name: "John D.",
      type: "Person",
      properties: {
        email: "john.doe@example.com",
        phone: "+1987654321"
      }
    },

    # Test 5: Same laptop, different case in name
    {
      id: "test_laptop_3",
      name: "macbook pro 16\"",
      type: "Asset",
      properties: {
        serialNumber: "C02X12345678",
        category: "electronics",
        make: "Apple",
        model: "MacBook Pro 16\" M1 Max",
        year: "2021"
      }
    }
  ]

  # Create test entities
  $logger.info("Creating test entities...")
  test_entities.each do |entity_data|
    create_test_entity(driver, entity_data)
  end

  # Test deduplication
  $logger.info("\nTesting deduplication...")

  test_entities.each_with_index do |entity_data, _index|
    $logger.info("\nTesting deduplication for #{entity_data[:type]}: #{entity_data[:name]}")
    duplicates = find_potential_duplicates(driver, entity_data)

    if duplicates.any?
      $logger.info("  Found #{duplicates.size} potential duplicates:")
      duplicates.each_with_index do |dup, i|
        $logger.info("    #{i + 1}. #{dup[:name]} (ID: #{dup[:id]})")
        $logger.info("       Type: #{dup.labels.join(', ')}")
        $logger.info("       Properties: #{dup.properties.except(:created_at, :updated_at)}")
      end
    else
      $logger.info("  No duplicates found")
    end
  end

  $logger.info("\nDeduplication test complete!")
rescue StandardError => e
  $logger.error("Error during deduplication test: #{e.message}")
  $logger.error(e.backtrace.join("\n"))
  exit 1
ensure
  driver&.close
  $log_file&.close
end
