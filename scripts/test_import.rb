#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../config/environment"
require "rake"

# Load Rake tasks
Rails.application.load_tasks

# Clear the Neo4j database before import
def clear_neo4j_database
  puts "Clearing Neo4j database..."

  # Use the rake task to clear the database
  begin
    Rake::Task["neo4j:clear"].invoke
    puts "Database cleared.\n"
    true
  rescue LoadError, StandardError => e
    puts "Error clearing database: #{e.message}"
    puts "Make sure you have the neo4j:clear rake task available"
    puts e.backtrace.join("\n  ") if ENV["DEBUG"]
    exit 1
  end
end

# Import data directly to Neo4j using the driver
def import_to_neo4j(driver, data)
  results = {
    entities: { created: 0, errors: [] },
    relationships: { created: 0, errors: [] },
    start_time: Time.now
  }

  driver.session do |session|
    # Create nodes
    (data[:entities] || []).each_with_index do |entity, index|
      # Extract labels from type (support multiple labels separated by ':')
      labels = (entity[:type] || "Entity").to_s.split(":").map { |l| l.strip.capitalize }

      # Prepare properties
      props = (entity[:properties] || {}).merge(
        id: entity[:id],
        name: entity[:name],
        created_at: Time.now.iso8601
      )

      # Add metadata as JSON string if present
      props[:metadata] = entity[:metadata].to_json if entity[:metadata]

      # Create the node
      query = "CREATE (n:#{labels.join(':')} $props) RETURN id(n)"

      session.write_transaction do |tx|
        tx.run(query, props: props)
        results[:entities][:created] += 1
        puts "  ✓ Created #{labels.join(':')} node: #{entity[:name] || entity[:id]}" if (index + 1) % 10 == 0
      end
    rescue StandardError => e
      results[:entities][:errors] << {
        entity: entity,
        error: e.message,
        backtrace: e.backtrace.first(5)
      }
      puts "  ⚠️  Error creating node: #{e.message}"
    end

    # Create relationships
    (data[:relationships] || []).each_with_index do |rel, index|
      # Prepare relationship properties
      props = (rel[:properties] || {}).merge(
        id: rel[:id],
        type: rel[:type],
        created_at: Time.now.iso8601
      )

      # Add metadata as JSON string if present
      props[:metadata] = rel[:metadata].to_json if rel[:metadata]

      # Create the relationship
      query = <<~CYPHER
        MATCH (source {id: $source_id}), (target {id: $target_id})
        MERGE (source)-[r:#{rel[:type]}]->(target)
        SET r += $props
        RETURN id(r)
      CYPHER

      session.write_transaction do |tx|
        result = tx.run(query, {
                          source_id: rel[:source_id],
                          target_id: rel[:target_id],
                          props: props
                        })

        raise "Failed to create relationship: #{rel.inspect}" unless result.any?

        results[:relationships][:created] += 1
        puts "  ✓ Created relationship: #{rel[:source_id]} -[#{rel[:type]}]-> #{rel[:target_id]}" if (index + 1) % 10 == 0
      end
    rescue StandardError => e
      results[:relationships][:errors] << {
        relationship: rel,
        error: e.message,
        backtrace: e.backtrace.first(5)
      }
      puts "  ⚠️  Error creating relationship: #{e.message}"
    end
  end

  results[:end_time] = Time.now
  results[:duration] = results[:end_time] - results[:start_time]

  results
end

# Load extraction data from a directory of JSON files or a specific file
def load_extraction_data(input_path = nil)
  # Default to scripts/output directory if no path provided
  input_path ||= File.join(__dir__, "output")

  # If it's a directory, find all extraction.json files
  if File.directory?(input_path)
    json_files = Dir.glob(File.join(input_path, "**/extraction.json"))

    if json_files.empty?
      puts "No extraction.json files found in #{input_path}"
      return nil
    end

    puts "Found #{json_files.size} extraction files to process"

    # Combine all extractions into a single dataset
    combined = {
      entities: [],
      relationships: [],
      metadata: {
        source: "Combined import from #{json_files.size} files",
        timestamp: Time.now.iso8601,
        files: json_files
      }
    }

    # First pass: Load all entities and assign IDs
    entities_by_source = {} # Map of source file => { entity_name => id }

    json_files.each_with_index do |file, _index|
      puts "\nLoading extraction data from: #{file}"
      begin
        file_content = File.read(file)
        data = JSON.parse(file_content, symbolize_names: true)

        # Extract data from extraction_result if it exists
        extraction_data = data[:extraction_result] || data

        # Debug: Print the keys to understand the structure
        puts "  - Data keys: #{extraction_data.keys.inspect}"

        entities = extraction_data[:entities] || []

        # Initialize entities map for this file
        entities_by_source[file] = {}

        # Process entities
        entities.each_with_index do |entity, idx|
          # Ensure entity has an ID
          unless entity[:id]
            # Generate a unique ID based on file and index
            entity[:id] = "#{File.basename(file, '.json')}_entity_#{idx}"
          end

          # Store the entity name/type mapping for relationship resolution
          entity_name = entity[:name] || entity.dig(:properties, :name) || "unnamed_#{idx}"
          entities_by_source[file][entity_name] = entity[:id]

          # Add file metadata
          entity[:metadata] ||= {}
          entity[:metadata][:source_file] = file

          combined[:entities] << entity
        end

        puts "  - Loaded #{entities.size} entities"
      rescue JSON::ParserError => e
        puts "  ⚠️  Error parsing JSON from #{file}: #{e.message}"
        next
      rescue StandardError => e
        puts "  ⚠️  Error loading #{file}: #{e.class} - #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(3).join("\n    ")}" if ENV["DEBUG"]
        next
      end
    end

    # Second pass: Process relationships
    json_files.each do |file|
      next unless File.exist?(file) # Skip if file was deleted or had errors

      begin
        file_content = File.read(file)
        data = JSON.parse(file_content, symbolize_names: true)
        extraction_data = data[:extraction_result] || data
        relationships = extraction_data[:relationships] || []

        relationships.each_with_index do |rel, idx|
          # Ensure relationship has required fields
          unless rel[:source_id] && rel[:target_id]
            # Try to resolve source and target by name if IDs not provided
            source_name = rel[:source] || rel.dig(:properties, :source)
            target_name = rel[:target] || rel.dig(:properties, :target)

            if source_name && target_name
              # Try to find the entities in the current file first, then in all files
              source_id = entities_by_source[file][source_name] ||
                          entities_by_source.values.flat_map(&:to_a).to_h[source_name]

              target_id = entities_by_source[file][target_name] ||
                          entities_by_source.values.flat_map(&:to_a).to_h[target_name]

              if source_id && target_id
                rel[:source_id] = source_id
                rel[:target_id] = target_id
              else
                puts "  ⚠️  Could not resolve relationship: #{source_name} -> #{rel[:type]} -> #{target_name}"
                next
              end
            else
              # If we can't resolve the relationship, skip it
              puts "  ⚠️  Skipping relationship #{idx} - missing source or target"
              next
            end
          end

          # Ensure relationship has a type
          rel[:type] ||= "RELATES_TO"

          # Generate an ID if missing
          rel[:id] ||= "#{File.basename(file, '.json')}_rel_#{idx}"

          # Add file metadata
          rel[:metadata] ||= {}
          rel[:metadata][:source_file] = file

          combined[:relationships] << rel
        end

        puts "  - Loaded #{relationships.size} relationships from #{File.basename(file)}"
      rescue StandardError => e
        puts "  ⚠️  Error processing relationships in #{file}: #{e.class} - #{e.message}"
        next
      end
    end

    puts "\nTotal entities to import: #{combined[:entities].size}"
    puts "Total relationships to import: #{combined[:relationships].size}"

    combined

  # If it's a single file
  elsif File.exist?(input_path)
    puts "Loading extraction data from: #{input_path}"
    data = JSON.parse(File.read(input_path), symbolize_names: true)

    # Add source file info to metadata
    data[:metadata] ||= {}
    data[:metadata][:source_file] = input_path
    data[:metadata][:imported_at] = Time.now.iso8601

    data

  else
    puts "Error: No extraction files found at #{input_path}"
    exit 1
  end
end

# Main execution
begin
  # Require Neo4j driver
  require "neo4j/driver"

  # Get extraction data (from file if provided, otherwise use scripts/output directory)
  input_path = ARGV[0]
  extraction_data = load_extraction_data(input_path)

  unless extraction_data
    puts "No extraction data to import"
    exit 1
  end

  # Clear the database before import
  clear_neo4j_database

  # Initialize Neo4j driver
  puts "\nInitializing Neo4j driver..."

  neo4j_url = ENV["NEO4J_URL"] || "bolt://localhost:7687"

  # Check if we should use authentication based on URL
  use_auth = !(ENV["NEO4J_NO_AUTH"] == "true" || neo4j_url.include?("@"))

  if use_auth
    neo4j_username = ENV["NEO4J_USERNAME"] || "neo4j"
    neo4j_password = ENV.fetch("NEO4J_PASSWORD", nil)

    unless neo4j_password
      puts "  ⚠️  NEO4J_PASSWORD environment variable not set"
      puts "  Please set the NEO4J_PASSWORD environment variable or set NEO4J_NO_AUTH=true"
      exit 1
    end
  else
    puts "  ℹ️  Authentication disabled for Neo4j connection"
  end

  begin
    # Create driver with or without authentication
    driver = if use_auth
               Neo4j::Driver::GraphDatabase.driver(
                 neo4j_url,
                 Neo4j::Driver::AuthTokens.basic(neo4j_username, neo4j_password)
               )
             else
               Neo4j::Driver::GraphDatabase.driver(neo4j_url)
             end

    # Test the connection
    driver.session do |session|
      session.run("RETURN 1 AS test").first
    end

    puts "  ✓ Connected to Neo4j at #{neo4j_url}"

    # Run the import
    puts "\nStarting import of #{extraction_data[:entities].size} entities and #{extraction_data[:relationships].size} relationships..."
    start_time = Time.now

    result = import_to_neo4j(driver, extraction_data)

    duration = Time.now - start_time

    # Print results
    puts "\nImport completed in #{duration.round(2)} seconds"
    puts "\nEntities:"
    puts "  Created: #{result[:entities][:created]}"
    puts "  Errors: #{result[:entities][:errors].size}"

    puts "\nRelationships:"
    puts "  Created: #{result[:relationships][:created]}"
    puts "  Errors: #{result[:relationships][:errors].size}"

    # Print any errors
    if result[:entities][:errors].any? || result[:relationships][:errors].any?
      puts "\nErrors:"

      result[:entities][:errors].each_with_index do |error, index|
        puts "\n[#{index + 1}] Entity Error: #{error[:error]}"
        puts "  Entity: #{error[:entity].inspect}" if error[:entity]
        if ENV["DEBUG"]
          puts "  Backtrace:"
          error[:backtrace].each { |line| puts "    #{line}" }
        end
      end

      result[:relationships][:errors].each_with_index do |error, index|
        puts "\n[#{index + 1}] Relationship Error: #{error[:error]}"
        puts "  Relationship: #{error[:relationship].inspect}" if error[:relationship]
        if ENV["DEBUG"]
          puts "  Backtrace:"
          error[:backtrace].each { |line| puts "    #{line}" }
        end
      end
    end

    if result[:entities][:errors].empty? && result[:relationships][:errors].empty?
      puts "\n✅ Import completed successfully!"
    else
      puts "\n⚠️  Import completed with errors"
      exit 1
    end
  rescue Neo4j::Driver::Exceptions::AuthenticationException => e
    puts "  ❌ Failed to authenticate with Neo4j: #{e.message}"
    puts "  Please check your NEO4J_USERNAME and NEO4J_PASSWORD environment variables"
    exit 1
  rescue Neo4j::Driver::Exceptions::ServiceUnavailableException => e
    puts "  ❌ Could not connect to Neo4j at #{neo4j_url}"
    puts "  Make sure Neo4j is running and accessible at the specified URL"
    puts "  Error: #{e.message}"
    exit 1
  ensure
    driver&.close
  end
rescue StandardError => e
  puts "\n❌ Error during import: #{e.class.name} - #{e.message}"
  puts e.backtrace.join("\n  ") if ENV["DEBUG"]
  exit 1
end
