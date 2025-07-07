#!/usr/bin/env ruby
# frozen_string_literal: true

# Ensure we're running in a Rails environment
unless defined?(Rails)
  puts "This script must be run in a Rails environment. Please use: bundle exec rails runner #{__FILE__}"
  exit 1
end

# Load environment variables
require "dotenv/load"
require "net/http"
require "uri"
require "json"
require "base64"
require "debug"
# Sample extraction data using Schema.org properties
extraction_data = {
  entities: [
    {
      type: "Person",
      id: "person1",
      properties: {
        "@type" => "Person",
        "givenName" => "John",
        "familyName" => "Doe",
        "email" => "john.doe@example.com",
        "additionalType" => "http://schema.org/Person"
      },
      metadata: {
        "source" => "test_data",
        "confidence" => 0.95
      }
    },
    {
      type: "Product",
      id: "item1",
      properties: {
        "@type" => "Product",
        "name" => "Test Item",
        "description" => "A test item for import",
        "additionalType" => "http://schema.org/Product"
      },
      metadata: {
        "source" => "test_data",
        "confidence" => 0.98
      }
    }
  ],
  relationships: [
    {
      type: "OWNS",
      source_id: "person1",
      target_id: "item1",
      properties: {
        "startDate" => "2023-01-01",
        "additionalType" => "http://schema.org/ownershipInfo"
      },
      metadata: {
        "source" => "test_data",
        "confidence" => 0.99
      }
    }
  ],
  metadata: {
    "source" => "http_import_test.rb",
    "timestamp" => Time.now.iso8601,
    "version" => "1.0"
  }
}

# Neo4j HTTP API settings for Neo4j 5.x
@neo4j_url = ENV.fetch("NEO4J_HTTP_URL", nil)
@neo4j_db = "neo4j" # Default database in Neo4j 5.x

# Set credentials
@neo4j_username = ENV.fetch("NEO4J_USERNAME", nil)
@neo4j_password = ENV.fetch("NEO4J_PASSWORD", nil)

# Set content type and accept headers
@headers = {
  "Content-Type" => "application/json",
  "Accept" => "application/json",
  "Authorization" => "Basic #{Base64.strict_encode64("#{@neo4j_username}:#{@neo4j_password}")}"
}

puts "=== Neo4j HTTP Import Test ==="
puts "Neo4j URL: #{@neo4j_url}"

# Helper method to make HTTP requests to Neo4j
def neo4j_http_request(method, path, body = nil)
  # If path is a full URL, use it directly; otherwise, join with base URL
  uri = path.start_with?("http") ? URI.parse(path) : URI.join(@neo4j_url, path)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == "https")

  request = case method.upcase
            when "GET" then Net::HTTP::Get.new(uri)
            when "POST" then Net::HTTP::Post.new(uri)
            when "PUT" then Net::HTTP::Put.new(uri)
            when "DELETE" then Net::HTTP::Delete.new(uri)
            else raise "Unsupported HTTP method: #{method}"
            end

  # Set headers
  @headers.each { |key, value| request[key] = value }

  # Add body if provided
  request.body = body.is_a?(String) ? body : body.to_json if body

  # Send request and handle response
  response = http.request(request)

  # Parse response
  begin
    parsed_body = response.body.present? ? JSON.parse(response.body, symbolize_names: true) : {}
  rescue JSON::ParserError
    parsed_body = { error: "Invalid JSON response", raw: response.body }
  end

  {
    code: response.code.to_i,
    body: parsed_body,
    headers: response.to_hash
  }
end

# Test connection to Neo4j
begin
  puts "\nTesting connection to Neo4j..."

  # Test connection by getting database info
  response = neo4j_http_request("GET", "/", nil)

  if response[:code] == 200
    puts "Successfully connected to Neo4j!"
    if response[:body].is_a?(Hash)
      puts "Neo4j Version: #{response[:body][:neo4j_version]}"

      # Construct the transaction endpoint
      @neo4j_tx_url = "#{@neo4j_url}/db/neo4j/tx/commit"
      puts "Using transaction URL: #{@neo4j_tx_url}"

      # Store the database URL for reference
      @neo4j_db_url = "#{@neo4j_url}/db/neo4j"

      # Set the transaction path for relative URL requests
      @neo4j_tx_path = "/db/neo4j/tx/commit"
    end
  else
    puts "Failed to connect to Neo4j. Status: #{response[:code]}"
    puts "Response: #{response[:body]}"
    puts "\nTroubleshooting steps:"
    puts "1. Make sure Neo4j is running and accessible at #{@neo4j_url}"
    puts "2. Check your username and password in the script"
    puts "3. Try connecting manually with: curl -X GET -H 'Authorization: Basic #{Base64.strict_encode64("#{@neo4j_username}:#{@neo4j_password}")}' #{@neo4j_url}/"
    exit 1
  end
rescue StandardError => e
  puts "Error connecting to Neo4j: #{e.message}"
  puts e.backtrace.take(5).join("\n")
  puts "\nTroubleshooting steps:"
  puts "1. Make sure Neo4j is running and accessible at #{@neo4j_url}"
  puts "2. Check your username and password in the script"
  puts "3. Try connecting manually with: curl -X GET -H 'Authorization: Basic #{Base64.strict_encode64("#{@neo4j_username}:#{@neo4j_password}")}' #{@neo4j_url}/"
  exit 1
end

# Clear the database before import (for testing)
puts "\nClearing Neo4j database..."
clear_query = {
  statements: [
    {
      statement: "MATCH (n) DETACH DELETE n",
      resultDataContents: [],
      includeStats: true
    }
  ]
}

# Use the full transaction URL for the clear operation
response = neo4j_http_request("POST", @neo4j_tx_path, clear_query)

if response[:code] == 200
  puts "Database cleared successfully"

  # Verify the database is empty
  check_query = {
    statements: [
      {
        statement: "MATCH (n) RETURN count(n) as node_count",
        resultDataContents: ["row"],
        includeStats: false
      }
    ]
  }

  check_response = neo4j_http_request("POST", @neo4j_tx_path, check_query)

  if check_response[:code] == 200 && check_response[:body][:results]&.first&.dig(:data, 0, :row, 0)&.zero?
    puts "Verified database is empty"
  else
    puts "Warning: Could not verify database is empty"
    puts "Response: #{check_response[:body]}"
  end
else
  puts "Failed to clear database. Status: #{response[:code]}"
  puts "Response: #{response[:body]}"
  exit 1
end

# Import the test data
puts "\nImporting test data..."

# First, create nodes
node_queries = extraction_data[:entities].map.with_index do |entity, _index|
  labels = [entity[:type]].compact

  # Prepare properties, converting metadata to JSON string if it's a hash
  properties = entity[:properties].merge(id: entity[:id])

  # Handle metadata - convert to JSON string if it's a hash
  if entity[:metadata].is_a?(Hash) || entity[:metadata].is_a?(Array)
    properties[:metadata] = JSON.generate(entity[:metadata])
  elsif !entity[:metadata].nil?
    properties[:metadata] = entity[:metadata].to_s
  end

  {
    statement: "CREATE (n:#{labels.join(':')} $props) RETURN id(n) as id, $id as entity_id",
    parameters: {
      props: properties,
      id: entity[:id]
    },
    resultDataContents: ["row"],
    includeStats: true
  }
end

# Execute node creation in a single transaction
puts "\nCreating #{node_queries.size} nodes..."
node_import = {
  statements: node_queries
}

response = neo4j_http_request("POST", @neo4j_tx_path, node_import)

if response[:code] == 200 && !response[:body][:errors]&.any?
  created_nodes = response[:body][:results].map.with_index do |result, i|
    {
      id: result[:data].first[:row].first, # Neo4j internal ID
      entity_id: node_queries[i][:parameters][:id] # Our entity ID
    }
  end

  # Create a mapping of our entity IDs to Neo4j internal IDs
  @node_id_map = {}
  created_nodes.each do |node|
    @node_id_map[node[:entity_id]] = node[:id]
  end

  puts "✅ Successfully created #{created_nodes.size} nodes"
else
  puts "❌ Failed to create nodes. Status: #{response[:code]}"
  if response[:body][:errors]&.any?
    puts "Errors:"
    response[:body][:errors].each { |err| puts "- #{err[:message]}" }
  else
    puts "Response: #{response[:body]}"
  end
  exit 1
end

# Create relationships
relationship_queries = extraction_data[:relationships].filter_map do |rel|
  source_id = @node_id_map[rel[:source_id]]
  target_id = @node_id_map[rel[:target_id]]

  unless source_id && target_id
    puts "❌ Could not find source or target node for relationship: #{rel.inspect}"
    next nil
  end

  # Prepare relationship properties, converting metadata to JSON string if it's a hash
  rel_props = rel[:properties] || {}

  # Handle metadata - convert to JSON string if it's a hash or array
  if rel[:metadata].is_a?(Hash) || rel[:metadata].is_a?(Array)
    rel_props[:metadata] = JSON.generate(rel[:metadata])
  elsif !rel[:metadata].nil?
    rel_props[:metadata] = rel[:metadata].to_s
  end

  {
    statement: <<~CYPHER,
      MATCH (a), (b)
      WHERE id(a) = $source_id AND id(b) = $target_id
      CREATE (a)-[r:#{rel[:type]} $props]->(b)
      RETURN type(r) as type, id(r) as id
    CYPHER
    parameters: {
      source_id: source_id,
      target_id: target_id,
      props: rel_props
    },
    resultDataContents: ["row"],
    includeStats: true
  }
end

# Execute relationship creation in a single transaction
puts "\nCreating #{relationship_queries.size} relationships..."
if relationship_queries.any?
  relationship_import = {
    statements: relationship_queries
  }

  response = neo4j_http_request("POST", @neo4j_tx_path, relationship_import)

  if response[:code] == 200 && !response[:body][:errors]&.any?
    created_rels = response[:body][:results].map do |result|
      result[:data].first[:row]
    end

    puts "✅ Successfully created #{created_rels.size} relationships"
  else
    puts "❌ Failed to create relationships. Status: #{response[:code]}"
    if response[:body][:errors]&.any?
      puts "Errors:"
      response[:body][:errors].each { |err| puts "- #{err[:message]}" }
    else
      puts "Response: #{response[:body]}"
    end
    exit 1
  end
else
  puts "⚠️  No relationships to create"
end

# Verify the import
puts "\nVerifying import..."

# Prepare verification queries
verification_queries = [
  {
    statement: "MATCH (n) RETURN count(n) as node_count",
    label: "Total nodes"
  },
  {
    statement: "MATCH ()-[r]->() RETURN count(r) as rel_count",
    label: "Total relationships"
  },
  {
    statement: "MATCH (p:Person) RETURN count(p) as person_count",
    label: "Person nodes"
  },
  {
    statement: "MATCH (p:Product) RETURN count(p) as product_count",
    label: "Product nodes"
  },
  {
    statement: "MATCH ()-[r:OWNS]->() RETURN count(r) as owns_count",
    label: "OWNS relationships"
  }
]

# Execute verification queries
verification_results = {}
verification_queries.each do |query|
  response = neo4j_http_request("POST", @neo4j_tx_path, {
                                  statements: [{
                                    statement: query[:statement],
                                    resultDataContents: ["row"]
                                  }]
                                })

  if response[:code] == 200 && response[:body][:results]&.first&.dig(:data, 0, :row, 0)
    verification_results[query[:label]] = response[:body][:results].first[:data].first[:row].first
  else
    puts "❌ Failed to verify #{query[:label].downcase}"
    verification_results[query[:label]] = "Error"
  end
end

# Print verification results
puts "\n=== Import Verification ==="
verification_results.each do |label, count|
  puts "#{label}: #{count}"
end

# Check expected counts
expected_nodes = extraction_data[:entities].size
expected_people = extraction_data[:entities].count { |e| e[:type] == "Person" }
expected_products = extraction_data[:entities].count { |e| e[:type] == "Product" }
expected_owns = extraction_data[:relationships].count { |r| r[:type] == "OWNS" }

verification_passed = true

if verification_results["Total nodes"] != expected_nodes
  puts "❌ Node count mismatch: expected #{expected_nodes}, found #{verification_results['Total nodes']}"
  verification_passed = false
end

if verification_results["Person nodes"] != expected_people
  puts "❌ Person node count mismatch: expected #{expected_people}, found #{verification_results['Person nodes']}"
  verification_passed = false
end

if verification_results["Product nodes"] != expected_products
  puts "❌ Product node count mismatch: expected #{expected_products}, found #{verification_results['Product nodes']}"
  verification_passed = false
end

if verification_results["OWNS relationships"] != expected_owns
  puts "❌ OWNS relationship count mismatch: expected #{expected_owns}, found #{verification_results['OWNS relationships']}"
  verification_passed = false
end

if verification_passed
  puts "\n✅ Import verification successful!"
else
  puts "\n❌ Import verification failed. See above for details."
end

# Print helpful information
puts "\nYou can view the imported data at: #{@neo4j_url.gsub(%r{/+$}, '')}/browser/"
puts "Run 'MATCH (n) RETURN n LIMIT 25' to see nodes and relationships."
puts "Run 'MATCH (n) DETACH DELETE n' to clear the database."
