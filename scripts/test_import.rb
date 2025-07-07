#!/usr/bin/env rails runner

# frozen_string_literal: true

require "dotenv/load"
require "openai"
require_relative "../app/services/neo4j/deduplication_service"

unless defined?(Rails)
  puts "This script must be run in a Rails environment. Please use: bundle exec rails runner #{__FILE__}"
  exit 1
end

# Initialize deduplication service with error handling and proper logging
def initialize_deduplication_service
  return nil if ENV["OPENAI_API_KEY"].blank?

  begin
    openai_client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY", nil))
    service = Neo4j::DeduplicationService.new(openai_client, logger: Rails.logger)
    puts "Deduplication service initialized with OpenAI integration"
    service
  rescue StandardError => e
    puts "WARNING: Failed to initialize deduplication service: #{e.message}"
    puts "Deduplication will be disabled for this import."
    nil
  end
end

# Initialize the deduplication service
deduplication_service = initialize_deduplication_service

# If OpenAI isn't available, we'll still run but with limited deduplication
if deduplication_service.nil? && ENV["OPENAI_API_KEY"].blank?
  puts "WARNING: OPENAI_API_KEY not set. Deduplication will be limited to exact matches."
end

# Configuration
NEO4J_URI = ENV.fetch("NEO4J_URL")
NEO4J_USERNAME = ENV.fetch("NEO4J_USERNAME")
NEO4J_PASSWORD = ENV.fetch("NEO4J_PASSWORD")

# Debug logging
require "fileutils"

DEBUG_LOG = File.expand_path("log/import_debug.log", Rails.root)
FileUtils.rm_f(DEBUG_LOG) # Safely remove existing debug log if it exists

def debug_log(*messages)
  return unless ENV["DEBUG"]

  timestamp = Time.zone.now.strftime("%Y-%m-%d %H:%M:%S.%L")
  log_entries = messages.map { |msg| "[#{timestamp}] #{msg}" }

  # Ensure the directory exists
  FileUtils.mkdir_p(File.dirname(DEBUG_LOG))

  # Write to log file
  File.open(DEBUG_LOG, "a") { |f| f.puts(log_entries) }

  # Also output to console if DEBUG is set
  puts log_entries.join("\n")
end

def ensure_default_user(driver)
  user_data = {
    id: "user_kenneth_grimm",
    username: "kenneth",
    email: "kenneth@example.com",
    type: "User",
    created_at: Time.now.iso8601,
    is_default_user: true
  }

  person_data = {
    id: "person_kenneth_grimm",
    name: "Kenneth Grimm",
    type: "Person",
    created_at: Time.now.iso8601,
    email: user_data[:email]
  }

  driver.session do |session|
    # Create or update the Person node
    session.write_transaction do |tx|
      tx.run(<<~CYPHER, id: person_data[:id], props: person_data)
        MERGE (p:Person {id: $id})
        SET p += $props
        REMOVE p:Entity
        RETURN p
      CYPHER
    end

    # Create or update the User node and link to Person
    session.write_transaction do |tx|
      tx.run(<<~CYPHER, id: user_data[:id], user_props: user_data, person_id: person_data[:id])
        // Create or update user
        MERGE (u:User {id: $id})
        SET u += $user_props
        REMOVE u:Entity

        // Ensure relationship to person exists
        WITH u
        MATCH (p:Person {id: $person_id})
        MERGE (u)-[:REPRESENTS]->(p)

        // Remove any other REPRESENTS relationships
        WITH u, p
        OPTIONAL MATCH (u)-[r:REPRESENTS]->(other:Person)
        WHERE other.id <> $person_id
        DELETE r
      CYPHER
    end

    puts "  ✓ Ensured user: #{user_data[:username]} (ID: #{user_data[:id]})"
    puts "  ✓ Ensured person: #{person_data[:name]} (ID: #{person_data[:id]})"
  end

  { user: user_data, person: person_data }
rescue StandardError => e
  puts "Error ensuring default user: #{e.message}"
  puts e.backtrace.join("\n")
  raise
end

# Clear the Neo4j database before import
def clear_neo4j_database
  puts "Clearing Neo4j database..."

  # Configure driver with the same settings as test_neo4j_driver.rb
  driver = Neo4j::Driver::GraphDatabase.driver(
    NEO4J_URI,
    Neo4j::Driver::AuthTokens.basic(NEO4J_USERNAME, NEO4J_PASSWORD),
    connection_timeout: 5, # seconds
    max_connection_lifetime: 3_600, # 1 hour
    max_connection_pool_size: 20,
    connection_acquisition_timeout: 5, # seconds
    max_transaction_retry_time: 30, # seconds
    encryption: false,
    ssl: false
  )

  begin
    # Clear the database using a direct Cypher query
    driver.session do |session|
      # First, disable constraints to speed up deletion
      begin
        session.run("CALL apoc.schema.assert({}, {}, true) YIELD label, key RETURN *")
      rescue StandardError => e
        puts "  ⚠️  Note: apoc.schema.assert failed (APOC may not be installed): #{e.message}"
      end

      # Delete all nodes and relationships
      result = session.run("MATCH (n) DETACH DELETE n")

      # Consume the result to get the summary
      summary = result.consume
      puts "Database cleared. Removed #{summary.counters.nodes_deleted} nodes and #{summary.counters.relationships_deleted} relationships.\n"

      # Rebuild constraints
      begin
        session.run("CREATE CONSTRAINT unique_user_id IF NOT EXISTS FOR (u:User) REQUIRE u.id IS UNIQUE")
      rescue StandardError => e
        puts "  ⚠️  Note: Could not create constraint: #{e.message}"
      end
    end
    true
  rescue StandardError => e
    puts "Error clearing database: #{e.message}"
    puts e.backtrace.join("\n  ") if ENV["DEBUG"]
    false
  ensure
    driver&.close
  end
end

# First, let's define a method to find existing entities
def find_existing_entity(session, entity)
  case entity[:type]
  when "Person"
    # For people, match on name and email if available
    query = "MATCH (e:Person) WHERE " \
            "e.name = $name " +
            (entity[:properties]&.key?(:email) ? "AND e.email = $email " : "") +
            "RETURN e.id as id LIMIT 1"

    params = { name: entity[:name] }
    params[:email] = entity[:properties][:email] if entity[:properties]&.key?(:email)

  when "Asset", "Photo", "Document"
    # For assets, use a combination of name and other unique attributes
    query = "MATCH (e:#{entity[:type]}) WHERE e.name = $name "
    params = { name: entity[:name] }

    # Add other unique identifiers if available
    if entity[:properties]&.key?(:checksum)
      query += "AND e.checksum = $checksum "
      params[:checksum] = entity[:properties][:checksum]
    end

    if entity[:properties]&.key?(:source_uri)
      query += "AND e.source_uri = $source_uri "
      params[:source_uri] = entity[:properties][:source_uri]
    end

    query += "RETURN e.id as id LIMIT 1"

  else
    # Default matching for other entity types
    query = "MATCH (e) WHERE e.name = $name AND labels(e) = $labels RETURN e.id as id LIMIT 1"
    params = {
      name: entity[:name],
      labels: [entity[:type]].flatten
    }
  end

  result = session.run(query, params)
  record = result.first
  record ? record[:id] : nil
rescue StandardError => e
  puts "Error finding existing entity: #{e.message}"
  puts e.backtrace.join("\n")
  raise
end

# Then modify the import_to_neo4j method to use this
def import_to_neo4j(driver, data, deduplication_service = nil)
  puts "Starting import with #{data[:entities]&.size || 0} entities and #{data[:relationships]&.size || 0} relationships"
  name_to_id = {}

  begin
    driver.session do |session|
      # First pass: process all entities
      (data[:entities] || []).each do |entity|
        # Skip if entity is already marked as a duplicate
        next if entity[:_is_duplicate]

        # Use the entity type as label, default to 'Entity'
        labels = [entity[:type] || "Entity"].flatten.map(&:to_s).reject(&:empty?).map(&:capitalize)

        # Use the name as ID if available, otherwise generate a UUID
        entity_id = entity[:id] || "#{entity[:type]&.downcase}_#{entity[:name]&.downcase&.gsub(/[^a-z0-9]/,
                                                                                               '_')}" || "entity_#{SecureRandom.uuid}"
        entity_name = entity[:name] || entity_id

        # Create properties hash, merging in any additional properties
        props = {
          id: entity_id,
          name: entity_name,
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        }

        # Process entity properties
        params = (entity[:properties] || {}).each_with_object({}) do |(key, value), hash|
          # Skip nil values
          next if value.nil?

          # Convert keys to symbols for consistency
          key = key.to_sym

          # Handle different property types
          hash[key] = case value
                      when Hash, Array
                        # Convert complex objects to JSON strings
                        value.to_json
                      else
                        value
                      end
        end

        # Merge the processed properties
        props.merge!(params)

        # Debug log the properties being set for photo nodes
        if labels.include?("Photo")
          debug_log(
            "  Setting properties for Photo #{entity_name}:",
            *params.map { |k, v| "    #{k}: #{v.inspect}" }
          )
        end

        # Store the original properties as JSON for reference
        props[:_original_properties] = entity[:properties].to_json

        # Only run deduplication if the service is available
        if deduplication_service
          puts "  Checking for duplicates of: #{entity_name} (Type: #{entity[:type]})"

          # Convert entity to the format expected by deduplication service
          dedupe_entity = {
            "id" => entity_id,
            "name" => entity_name,
            "type" => entity[:type],
            "properties" => entity[:properties] || {}
          }

          begin
            # Find potential duplicates
            potential_duplicates = deduplication_service.find_potential_duplicates(dedupe_entity, entity[:type])

            if potential_duplicates.any?
              puts "  Found #{potential_duplicates.size} potential duplicates"

              begin
                # Use AI to check if any of these are actual duplicates
                duplicate = deduplication_service.check_for_duplicate(dedupe_entity, potential_duplicates, entity[:type])

                if duplicate
                  puts "  Found duplicate: #{duplicate.name} (ID: #{duplicate.id})"
                  # Update the name_to_id mapping to point to the duplicate
                  name_to_id[entity_name] = duplicate.id
                  # Skip creating this entity
                  next
                end
              rescue StandardError => e
                puts "  Error during AI deduplication: #{e.message}"
                puts "  Continuing with entity creation..."
              end
            end
          rescue StandardError => e
            puts "  Error finding potential duplicates: #{e.message}"
            puts "  Continuing with entity creation..."
          end
        end

        # If we get here, either no duplicates were found or deduplication is disabled
        puts "  Creating new entity: #{entity_name} (ID: #{entity_id})"

        # Store the mapping from name to ID for relationships
        name_to_id[entity_name] = entity_id

        # Debug logging for photo nodes
        if labels.include?("Photo")
          debug_log(
            "Processing Photo Node:",
            "  ID: #{entity_id}",
            "  Name: #{entity_name}",
            "  Raw properties: #{entity[:properties].inspect}",
            "  Labels: #{labels.inspect}"
          )
        end

        session.write_transaction do |tx|
          # Create a single parameters hash with all properties at the top level
          params = { id: entity_id }.merge(props)

          # Debug log the parameters if debug mode is enabled
          if ENV["DEBUG"] || labels.include?("Photo")
            debug_log(
              "  Processing entity:",
              "  Name: #{entity_name}",
              "  ID: #{entity_id}",
              "  Type: #{entity[:type]}",
              "  Labels: #{labels.inspect}",
              "  Raw properties: #{entity[:properties].inspect}",
              "  Processed properties:",
              *props.map { |k, v| "    - #{k}: #{v.inspect} (#{v.class.name})" },
              ""
            )
          end

          # First, ensure the node exists with the right labels and set all properties
          query = [
            "MERGE (n {id: $id})",
            "SET n:#{labels.join(':')}",
            "SET n += $props",
            "RETURN id(n) as internal_id"
          ].join(" ")

          # Create a params hash with just the properties we want to set
          params = {
            id: entity_id,
            props: props.except(:id)
          }

          # Debug log the query for photo nodes
          if labels.include?("Photo")
            debug_log(
              "  Executing Cypher for Photo #{entity_name}:",
              "  Query: #{query}",
              "  Params: #{params.inspect}"
            )
          end

          if ENV["DEBUG"]
            debug_log(
              "  Executing Cypher:",
              "  Query: #{query}",
              "  Params: #{params.except(:password).inspect}"
            )
          end

          # Execute the query
          result = tx.run(query, **params)

          debug_log("  Query result: #{result.to_a.inspect}") if ENV["DEBUG"]
        end
      end

      # Second pass: process relationships
      (data[:relationships] || []).each do |rel|
        # Look up IDs by name if needed
        source_id = name_to_id[rel[:source]] || rel[:source]
        target_id = name_to_id[rel[:target]] || rel[:target]

        # Skip if either end of the relationship is missing
        next unless source_id && target_id

        # Create relationship properties
        props = (rel[:properties] || {}).merge(
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        puts "  Creating relationship: #{rel[:source]} -[#{rel[:type]}]-> #{rel[:target]}"

        session.write_transaction do |tx|
          # Create a single parameters hash with all properties at the top level
          params = {
            source_id: source_id,
            target_id: target_id
          }

          # Add each property as a separate parameter
          props.each { |k, v| params["prop_#{k}"] = v }

          # Build the SET clause with direct parameter references
          set_clause = props.keys.map { |k| "r.#{k} = $prop_#{k}" }.join(", ")

          query = <<~CYPHER
            MATCH (source {id: $source_id}), (target {id: $target_id})
            MERGE (source)-[r:#{rel[:type]}]->(target)
            SET #{set_clause}
            RETURN type(r) as rel_type
          CYPHER

          puts "    Running query: #{query}" if ENV["DEBUG"]
          puts "    With params: #{params.inspect}" if ENV["DEBUG"]

          # Run the query with parameters as a single hash
          result = tx.run(query, **params)

          puts "    Query result: #{result.inspect}" if ENV["DEBUG"]
          result
        rescue StandardError => e
          puts "    Error executing relationship query: #{e.class}: #{e.message}"
          puts "    Query: #{query}"
          puts "    Params: #{params.inspect}"
          raise
        end
      end

      {
        success: true,
        entities: {
          created: data[:entities]&.size || 0,
          errors: []
        },
        relationships: {
          created: data[:relationships]&.size || 0,
          errors: []
        },
        duration: 0 # We're not tracking duration currently
      }
    end
  rescue StandardError => e
    puts "Error importing to Neo4j: #{e.class}: #{e.message}"
    puts e.backtrace.join("\n")
    { success: false, error: e.message }
  end
end

# Load extraction data from a directory of JSON files or a specific file
def load_extraction_data(_input_path = nil)
  data_dir = File.join(File.dirname(__FILE__), "output")
  puts "\nLoading extraction data from: #{data_dir}"

  unless File.directory?(data_dir)
    puts "  Error: Directory not found: #{data_dir}"
    return { entities: [], relationships: [] }
  end

  # Initialize data structures
  all_entities = []
  all_relationships = []

  # Process each extraction file
  Dir.glob(File.join(data_dir, "**/extraction.json")).each do |file|
    json_data = JSON.parse(File.read(file), symbolize_names: true)

    # Extract entities and relationships from the nested extraction_result
    if json_data[:extraction_result].is_a?(Hash)
      # Extract from extraction_result
      entities = Array(json_data.dig(:extraction_result, :entities) || [])
      relationships = Array(json_data.dig(:extraction_result, :relationships) || [])
    else
      # Fallback to root level (old format)
      entities = Array(json_data[:entities] || [])
      relationships = Array(json_data[:relationships] || [])
    end

    # Add source information to each entity
    entities.each do |entity|
      entity[:source_file] = file

      # Debug log for photo entities
      next unless entity[:type] == "Photo"

      debug_log(
        "Found photo entity in #{File.basename(File.dirname(file))}:",
        "  Name: #{entity[:name]}",
        "  Properties: #{entity[:properties]}"
      )
    end

    all_entities.concat(entities)
    all_relationships.concat(relationships)

    puts "  - Loaded #{entities.size} entities and #{relationships.size} relationships from #{File.basename(File.dirname(file))}/#{File.basename(file)}"
  rescue StandardError => e
    puts "  - Error loading #{file}: #{e.message}"
    puts e.backtrace.first(3).map { |line| "    #{line}" }.join("\n") if ENV["DEBUG"]
  end

  # Remove duplicates based on ID
  all_entities.uniq! { |e| e[:id] } if all_entities.first&.key?(:id)

  puts "  - Total: #{all_entities.size} entities and #{all_relationships.size} relationships\n"

  { entities: all_entities, relationships: all_relationships }
end

# Validate photo properties against required criteria
# @param photo [Neo4j::Driver::Types::Node] The photo node to validate
# @return [Array<String>] Array of validation issues, empty if photo is valid
def validate_photo_properties(photo)
  issues = []

  # Check dimensions
  issues << "missing dimensions" unless photo.properties.key?(:width) && photo.properties.key?(:height)

  # Check URL
  if photo.properties[:url].to_s.empty? || !photo.properties[:url].to_s.start_with?("http")
    issues << "invalid URL: #{photo.properties[:url]}"
  end

  # Check content type
  content_type = photo.properties[:content_type].to_s.downcase
  unless ["image/jpeg", "image/png", "image/gif"].include?(content_type)
    issues << "unsupported content type: #{photo.properties[:content_type]}"
  end

  issues
end

# Verify photo properties in Neo4j
def verify_photo_properties(driver)
  puts "\nVerifying Photo nodes in Neo4j..."

  driver.session do |session|
    # Find all photo nodes
    query = "MATCH (p:Photo) RETURN p"
    result = session.run(query)

    # Process each photo and collect validation results
    validation_results = []
    photos_processed = 0

    # Process each record and collect validation results
    result.each do |record|
      photo = record["p"]
      photos_processed += 1

      # Check for issues
      issues = validate_photo_properties(photo)
      validation_results << { id: photo.id, issues: issues } if issues.any?

      # Print debug info if requested
      next unless ENV["DEBUG"]

      puts "\n  Photo #{photos_processed} (ID: #{photo.id}):"
      puts "    Labels: #{photo.labels.join(', ')}"
      puts "    Properties:"
      photo.properties.each { |k, v| puts "      #{k}: #{v.inspect}" }
      puts "    Validation issues: #{issues.any? ? issues.join(', ') : 'None'}"
    end

    # Report results
    if photos_processed.zero?
      puts "  No Photo nodes found in the database"
      return
    end

    puts "  Verified #{photos_processed} photos"

    if validation_results.any?
      puts "  Found #{validation_results.size} photos with issues"
      if ENV["DEBUG"]
        puts "\n  Issues found:"
        validation_results.each do |result|
          puts "  - Photo #{result[:id]}:"
          result[:issues].each { |issue| puts "    • #{issue}" }
        end
      end
    else
      puts "  All photos are valid"
    end
  end
end

# Main execution
begin
  # Parse command line arguments
  input_path = ARGV[0] || File.join(__dir__, "output")

  # Load the extraction data
  data = load_extraction_data(input_path)
  unless data
    puts "No valid extraction data found"
    exit 1
  end

  # Initialize Neo4j driver
  puts "\nInitializing Neo4j driver..."
  puts "  URL: #{NEO4J_URI}"
  puts "  Username: #{NEO4J_USERNAME}"
  puts "  Password: #{NEO4J_PASSWORD}"

  # Configure driver with the same settings as test_neo4j_driver.rb
  driver = Neo4j::Driver::GraphDatabase.driver(
    NEO4J_URI,
    Neo4j::Driver::AuthTokens.basic(NEO4J_USERNAME, NEO4J_PASSWORD),
    connection_timeout: 5, # seconds
    max_connection_lifetime: 3_600, # 1 hour
    max_connection_pool_size: 20,
    connection_acquisition_timeout: 5, # seconds
    max_transaction_retry_time: 30, # seconds
    encryption: false,
    ssl: false
  )

  # Verify connection
  begin
    driver.session do |session|
      session.run("RETURN 1 AS test")
      puts "  Connected to Neo4j at #{NEO4J_URI}"
    end
  rescue StandardError => e
    puts "  Failed to connect to Neo4j: #{e.message}"
    puts "  Make sure Neo4j is running and accessible at #{NEO4J_URI}"
    puts "  Error details: #{e.class.name} - #{e.message}"
    puts e.backtrace.join("\n  ") if ENV["DEBUG"]
    exit 1
  end

  # Clear the database before import
  unless clear_neo4j_database
    puts "  Failed to clear Neo4j database"
    exit 1
  end

  # Ensure default user exists and get the user data
  default_user = ensure_default_user(driver)

  # Import the data
  puts "\nStarting import..."

  # Get the user and person data
  user_data = default_user[:user]
  person_data = default_user[:person]

  # Remove any existing user or person entities for the default user to prevent duplicates
  data[:entities]&.reject! do |e|
    [user_data[:id], person_data[:id]].include?(e[:id]) ||
      (e[:type] == "Person" && e[:name] == person_data[:name])
  end

  # Add the default user and person to the data
  data[:entities] ||= []

  # Add the User node if it doesn't exist
  unless data[:entities].any? { |e| e[:id] == user_data[:id] }
    data[:entities] << {
      id: user_data[:id],
      username: user_data[:username],
      type: "User",
      properties: user_data.except(:id, :username, :type)
    }
  end

  # Add the Person node if it doesn't exist in the import data
  unless data[:entities].any? { |e| e[:id] == person_data[:id] }
    data[:entities] << {
      id: person_data[:id],
      name: person_data[:name],
      type: "Person",
      properties: person_data.except(:id, :name, :type)
    }
  end

  # Add a relationship between the User and Person nodes if it doesn't exist
  data[:relationships] ||= []
  unless data[:relationships].any? { |r| r[:source] == user_data[:id] && r[:target] == person_data[:id] && r[:type] == "REPRESENTS" }
    data[:relationships] << {
      source: user_data[:id],
      target: person_data[:id],
      type: "REPRESENTS",
      properties: {
        created_at: Time.now.iso8601
      }
    }
  end

  # Replace any references to the person's name with their ID in relationships
  data[:relationships].each do |rel|
    rel[:source] = person_data[:id] if rel[:source].is_a?(String) && rel[:source] == person_data[:name] && rel[:source] != person_data[:id]
    rel[:target] = person_data[:id] if rel[:target].is_a?(String) && rel[:target] == person_data[:name] && rel[:target] != person_data[:id]
  end

  # Ensure we don't have any duplicate relationships
  data[:relationships].uniq! { |r| [r[:source], r[:target], r[:type]] }

  # Update any entity IDs that match the person's name to use the person's ID
  data[:entities].each do |entity|
    entity[:id] = person_data[:id] if entity[:id] == person_data[:name] && entity[:id] != person_data[:id]
  end

  # Run the import
  results = import_to_neo4j(driver, data, deduplication_service)

  # Verify photo properties after import
  verify_photo_properties(driver)

  # Check if the import was successful
  if results[:success]
    # Print success message
    puts "\n Import completed successfully!"
    puts "  - Created #{results[:entities][:created]} entities"
    puts "  - Created #{results[:relationships][:created]} relationships"
    puts "  - Duration: #{'%.2f' % results[:duration]} seconds"

    # Print any errors if they occurred
    if results[:entities][:errors].any? || results[:relationships][:errors].any?
      puts "\n⚠️  Some errors occurred during import:"
      puts "  - #{results[:entities][:errors].size} entity errors"
      puts "  - #{results[:relationships][:errors].size} relationship errors"

      if ENV["DEBUG"]
        puts "\nEntity errors:"
        results[:entities][:errors].each_with_index do |error, i|
          puts "  #{i + 1}. #{error[:error]}"
          puts "     #{error[:entity].inspect}"
        end

        puts "\nRelationship errors:"
        results[:relationships][:errors].each_with_index do |error, i|
          puts "  #{i + 1}. #{error[:error]}"
          puts "     #{error[:relationship].inspect}"
        end
      end
    end
  else
    # Print error message if the import failed
    puts "\n❌ Import failed: #{results[:error]}"
    puts "  - Check the error message above for details"
    puts "  - Set DEBUG=true for more detailed error information" if ENV["DEBUG"].nil?
    exit 1
  end
rescue StandardError => e
  puts "\n❌ Error during import: #{e.class.name} - #{e.message}"
  puts e.backtrace.join("\n  ") if ENV["DEBUG"]
  exit 1
ensure
  # Ensure the driver is always closed
  driver&.close
end
