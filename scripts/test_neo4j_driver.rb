# frozen_string_literal: true

# Enable debug logging
ENV["RAILS_LOG_LEVEL"] = "debug"

# Load the Rails environment
require_relative "../config/environment"

# Configure logger to output to STDOUT
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = Logger::DEBUG

# Load Neo4j driver
require "neo4j/driver"
require_relative "../app/services/neo4j/driver"
require_relative "../app/services/neo4j/base_repository"

# Log environment variables (without sensitive data)
Rails.logger.info "Environment:"
Rails.logger.info "  NEO4J_URL: #{ENV.fetch('NEO4J_URL', nil)}"
Rails.logger.info "  NEO4J_USERNAME: #{ENV.fetch('NEO4J_USERNAME', nil)}"
Rails.logger.info "  NEO4J_ENCRYPTED: #{ENV.fetch('NEO4J_ENCRYPTED', nil)}"

# Test the Neo4j connection
begin
  Rails.logger.info "=" * 80
  Rails.logger.info "TESTING NEO4J CONNECTION"
  Rails.logger.info "=" * 80

  # Log the resolved NEO4J_CONFIG
  config_to_log = NEO4J_CONFIG.dup
  config_to_log[:password] = "***" if config_to_log[:password]
  Rails.logger.info "NEO4J_CONFIG: #{config_to_log.inspect}"

  Rails.logger.info "Testing Neo4j connection to: #{NEO4J_CONFIG[:url]}"

  # Check if Neo4j is running
  Rails.logger.info "\nBefore running this script, please ensure that:"
  Rails.logger.info "1. Neo4j Desktop is running"
  Rails.logger.info "2. A database is started"
  Rails.logger.info "3. The bolt connector is enabled on port 7687"
  Rails.logger.info "4. The database credentials in .env are correct\n"

  # Test basic TCP connection first
  require "socket"
  require "timeout"

  uri = URI.parse(NEO4J_CONFIG[:url])
  host = uri.host || "localhost"
  port = uri.port || 7687

  Rails.logger.info "Testing TCP connection to #{host}:#{port}..."
  begin
    Timeout.timeout(5) do
      s = TCPSocket.new(host, port)
      s.close
      Rails.logger.info "✓ Successfully connected to #{host}:#{port} via TCP"
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Timeout::Error => e
    Rails.logger.error "❌ Could not connect to Neo4j at #{host}:#{port} via TCP"
    Rails.logger.error "   Error: #{e.message}"
    Rails.logger.error ""
    Rails.logger.error "Please make sure Neo4j is running and accessible at #{NEO4J_CONFIG[:url]}"
    Rails.logger.error "If using Neo4j Desktop, check that the database is started and the bolt connector is enabled."
    exit 1
  end

  # Test connection with a simple query
  begin
    Rails.logger.info("\n" + ("=" * 80))
    Rails.logger.info "TESTING NEO4J DRIVER CONNECTION"
    Rails.logger.info "=" * 80

    Rails.logger.info "Attempting to connect to Neo4j with the following settings:"
    Rails.logger.info "  URL: #{NEO4J_CONFIG[:url]}"
    Rails.logger.info "  Username: #{NEO4J_CONFIG[:username]}"
    Rails.logger.info "  Encryption: #{NEO4J_CONFIG[:encryption]}"

    # Test with our wrapper
    Rails.logger.info "\nTesting with our wrapper..."

    # Test read operation first
    Rails.logger.info "\nTesting read operation..."
    Neo4j::DriverWrapper.query("MATCH (n) RETURN count(n) AS node_count") do |records|
      count = records.first["node_count"]
      Rails.logger.info "✅ Current node count: #{count}"
    end

    # Create a test node in a transaction
    Rails.logger.info "\nCreating test node..."

    # First, delete any existing test nodes to avoid duplicates
    Neo4j::DriverWrapper.query("MATCH (n:TestNode) DETACH DELETE n")

    # Create a new test node
    Neo4j::DriverWrapper.transaction do |tx|
      tx.query("CREATE (n:TestNode {name: $name, created_at: datetime()}) RETURN n", name: "Test Node") do |records|
        record = records.first
        node = record["n"]
        Rails.logger.info "✅ Created test node:"
        Rails.logger.info "  ID: #{node.id}"
        Rails.logger.info "  Name: #{node.properties[:name]}"
        Rails.logger.info "  Created at: #{node.properties[:created_at]}"
      end
    end

    # Verify the node was created
    Neo4j::DriverWrapper.query("MATCH (n:TestNode) RETURN n, n.name AS name, n.created_at AS created_at") do |records|
      records.each do |record|
        Rails.logger.info "\nFound TestNode:"
        Rails.logger.info "  ID: #{record['n'].id}"
        Rails.logger.info "  Name: #{record['name']}"
        Rails.logger.info "  Created at: #{record['created_at']}"
      end
    end

    # Get the count
    Neo4j::DriverWrapper.query("MATCH (n:TestNode) RETURN count(n) AS count") do |records|
      count = records.first["count"]
      Rails.logger.info "\n✅ Total TestNode count: #{count}"
    end
  rescue StandardError => e
    Rails.logger.error "\n❌ Failed to connect to Neo4j: #{e.message}"
    Rails.logger.error "\nPlease check the following:"
    Rails.logger.error "1. Is Neo4j Desktop running?"
    Rails.logger.error "2. Is the database started?"
    Rails.logger.error "3. Is the Bolt connector enabled on port 7687?"
    Rails.logger.error "4. Are the credentials in .env correct?"
    Rails.logger.error "5. Is the database accepting Bolt connections?"
    Rails.logger.error "\nError details:"
    Rails.logger.error e.backtrace.join("\n")
    exit 1
  end

  # Create a test node using raw query
  test_props = {
    name: "Test Node",
    created_at: Time.current.iso8601,
    description: "Test node created by test script"
  }

  # Create node using raw query with block syntax
  puts "\nCreating test node..."
  create_query = "CREATE (n:Test $props) RETURN n"
  Neo4j::DriverWrapper.query(create_query, { props: test_props }) do |records|
    if records.any?
      node = records.first["n"]
      puts "✅ Created test node with ID: #{node.id}"
      puts "   Properties: #{node.properties}"
    else
      puts "❌ Failed to create test node"
    end
  end

  # Find the test node using raw query with block syntax
  puts "\nFinding test nodes..."
  find_query = "MATCH (n:Test {name: $name}) RETURN n"
  Neo4j::DriverWrapper.query(find_query, { name: "Test Node" }) do |records|
    puts "✅ Found #{records.count} test nodes"
    records.each_with_index do |record, i|
      node = record["n"]
      puts "   Node #{i + 1}: ID=#{node.id}, Properties=#{node.properties}"
    end
  end

  # Update the test node using raw query with block syntax
  puts "\nUpdating test node..."
  update_query = "MATCH (n:Test {name: $name}) SET n.updated_at = datetime() RETURN n"
  Neo4j::DriverWrapper.query(update_query, { name: "Test Node" }) do |records|
    if records.any?
      updated_node = records.first["n"]
      puts "✅ Updated test node at: #{updated_node.properties['updated_at']}"
    else
      puts "❌ Failed to find test node to update"
    end
  end

  # Delete the test nodes using raw query with block syntax
  puts "\nDeleting test nodes..."
  delete_query = "MATCH (n:Test) DELETE n"
  Neo4j::DriverWrapper.query(delete_query) do |_|
    puts "✅ Deleted test nodes"
  end

  # Verify deletion with block syntax
  puts "\nVerifying deletion..."
  verify_query = "MATCH (n:Test) RETURN count(n) as count"
  Neo4j::DriverWrapper.query(verify_query) do |records|
    count_after_delete = records.first["count"]
    puts "✅ Verified deletion. Test nodes after delete: #{count_after_delete}"
  end

  puts "\n✅ All tests completed successfully!"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
