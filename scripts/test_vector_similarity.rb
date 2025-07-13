# frozen_string_literal: true

require "dotenv/load"
require_relative "../config/environment"

# Enable debug logging
Rails.logger.level = Logger::DEBUG

# This script tests the vector similarity search functionality
# by creating test nodes with similar properties and verifying deduplication

begin
  # Clear the database before starting the test
  puts "Clearing database..."
  Neo4j::DatabaseService.clear_database

  # Test data with potential duplicates, components, and related items
  test_data = [
    # Person with potential duplicates
    {
      type: "Person",
      properties: {
        name: "John Smith",
        email: "john.smith@example.com",
        title: "Senior Software Engineer",
        company: "Acme Inc."
      }
    },
    {
      type: "Person",
      properties: {
        name: "Jonathan Smith",
        email: "jon.smith@example.com",
        title: "Senior Software Developer",
        company: "Acme Corporation"
      }
    },
    {
      type: "Person",
      properties: {
        name: "John S.",
        email: "john.smith@acme.com",
        title: "Sr. Software Engineer",
        company: "Acme Inc."
      }
    },

    # Vehicle with components
    {
      type: "Vehicle",
      properties: {
        name: "My Truck",
        make: "GMC",
        model: "Sierra 1500",
        year: 2017,
        color: "Black",
        vin: "1GTU7BED0HZ123456"
      }
    },

    # Vehicle components that should be linked to the vehicle
    {
      type: "Tire",
      properties: {
        name: "Front Left Tire",
        position: "Front Left",
        brand: "BFGoodrich",
        model: "All-Terrain T/A KO2",
        size: "275/65R18",
        installed_date: "2024-03-15"
      }
    },
    {
      type: "Tire",
      properties: {
        name: "Front Right Tire",
        position: "Front Right",
        brand: "BFGoodrich",
        model: "All-Terrain T/A KO2",
        size: "275/65R18",
        installed_date: "2024-03-15"
      }
    },

    # Home with components
    {
      type: "Home",
      properties: {
        name: "My House",
        address: "123 Main St, Anytown, USA",
        square_feet: 2500,
        bedrooms: 4,
        bathrooms: 2.5
      }
    },

    # Room that should be linked to the home
    {
      type: "Room",
      properties: {
        name: "Master Bedroom",
        room_type: "bedroom",
        square_feet: 400,
        floor: 2
      }
    }
  ]

  # Import the test data
  puts "\n=== Importing Test Data ==="
  importer = Neo4j::Import::NodeImporter.new(
    enable_vector_search: true,
    similarity_threshold: 0.8,
    logger: Rails.logger
  )

  result = importer.import(test_data)

  # Print import results
  puts "\n=== Import Results ==="
  puts "Nodes created: #{result[:created]}"
  puts "Nodes updated: #{result[:updated]}"
  puts "Nodes skipped: #{result[:skipped]}"
  puts "Errors: #{result[:errors]}"

  # Verify the state of the database
  Neo4j::DatabaseService.read_transaction do |tx|
    # Check for duplicate people
    people = tx.run("MATCH (p:Person) RETURN p, id(p) as id").to_a
    puts "\n=== People in Database (#{people.size}) ==="
    people.each_with_index do |record, i|
      p = record["p"]
      puts "#{i + 1}. #{p[:name]} (#{p[:email]})"
      puts "   Title: #{p[:title]}" if p[:title]
      puts "   Company: #{p[:company]}" if p[:company]

      # Check for relationships
      rels = tx.run("MATCH (p)-[r]->(o) WHERE id(p) = $id RETURN type(r) as type, o", id: record["id"]).to_a
      rels.each do |rel|
        puts "   - #{rel['type']} -> #{rel['o'].labels.first}: #{rel['o'][:name]}"
      end
    end

    # If we have fewer nodes than imported, deduplication worked
    if people.size < test_data.size
      puts "✅ Vector similarity deduplication worked!"
      puts "   Combined #{test_data.size} similar nodes into #{people.size} unique nodes."
    else
      puts "❌ Vector similarity deduplication did not work as expected."
      puts "   Expected fewer than #{test_data.size} nodes, but found #{people.size}."
    end

    # Show all Person nodes
    puts "\nAll Person nodes in the database:"
    result = tx.run("MATCH (n:Person) RETURN n.name as name, n.email as email, n.title as title, n.company as company")
    result.each do |record|
      puts "- #{record['name']} (#{record['email']})"
      puts "  Title: #{record['title']}"
      puts "  Company: #{record['company']}"
      puts
    end

    # Check for vehicles and components
    puts "\n=== Vehicles and Components ==="
    vehicles = tx.run("MATCH (v:Vehicle) RETURN v, id(v) as id").to_a
    vehicles.each do |vehicle|
      v = vehicle["v"]
      puts "Vehicle: #{v[:name]} (#{v[:year]} #{v[:make]} #{v[:model]})"

      # Find components
      components = tx.run("MATCH (v)-[:HAS_COMPONENT]->(c) WHERE id(v) = $id RETURN c", id: vehicle["id"]).to_a
      if components.any?
        puts "  Components:"
        components.each_with_index do |comp, i|
          c = comp["c"]
          puts "  #{i + 1}. #{c.labels.first}: #{c[:name]}"
          puts "     Type: #{c[:type]}" if c[:type]
          puts "     Position: #{c[:position]}" if c[:position]
        end
      else
        puts "  No components found"
      end
    end

    # Check for homes and rooms
    puts "\n=== Homes and Rooms ==="
    homes = tx.run("MATCH (h:Home) RETURN h, id(h) as id").to_a
    homes.each do |home|
      h = home["h"]
      puts "Home: #{h[:name]} - #{h[:address]}"

      # Find rooms
      rooms = tx.run("MATCH (h)-[:HAS_ROOM]->(r:Room) WHERE id(h) = $id RETURN r", id: home["id"]).to_a
      if rooms.any?
        puts "  Rooms:"
        rooms.each_with_index do |room, i|
          r = room["r"]
          puts "  #{i + 1}. #{r[:name]} (#{r[:room_type]})"
          puts "     Size: #{r[:square_feet]} sq ft"
          puts "     Floor: #{r[:floor]}" if r[:floor]
        end
      else
        puts "  No rooms found"
      end
    end

    # Check for any component relationships
    puts "\n=== Component Relationships ==="
    component_rels = tx.run("MATCH (c)-[r:IS_PART_OF]->(p) RETURN c, type(r) as rel_type, p").to_a
    if component_rels.any?
      component_rels.each do |rel|
        c = rel["c"]
        p = rel["p"]
        puts "- #{c.labels.first} '#{c[:name]}' is part of #{p.labels.first} '#{p[:name]}'"
      end
    else
      puts "No component relationships found"
    end
  end

  puts "\n=== Test Complete ==="
rescue StandardError => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.join("\n") if ENV["DEBUG"]
  exit 1
end

# Clean up the database before running the test
puts "\n=== Cleaning up test data ==="
Neo4j::DatabaseService.write_transaction do |tx|
  tx.run("MATCH (n:Person) WHERE n.id STARTS WITH 'test_person_' DETACH DELETE n")
  puts "- Deleted existing test nodes"
end
