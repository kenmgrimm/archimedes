require "neo4j/driver"
require "logger"
require "timeout"
require "socket"
require "json"

# Neo4j Import Service
# A robust service for importing data into Neo4j using the Bolt protocol
class Neo4jImportService
  attr_reader :logger

  def initialize(options = {})
    @uri = options[:uri] || ENV["NEO4J_BOLT_URL"] || "bolt://127.0.0.1:7687"
    @username = options[:username] || ENV["NEO4J_USERNAME"] || "neo4j"
    @password = options[:password] || ENV.fetch("NEO4J_PASSWORD", nil)
    @database = options[:database] || ENV["NEO4J_DATABASE"] || "neo4j"
    @batch_size = options[:batch_size] || 500
    @timeout = options[:timeout] || 60

    # Set up logging
    @logger = options[:logger] || Logger.new($stdout)
    @logger.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO

    # Debug mode for Neo4j driver
    ENV["NEO4J_DEBUG"] = "true" if ENV["DEBUG"]

    # Track created nodes for relationship creation
    @node_registry = {}
  end

  # Connect to Neo4j and yield a session
  def with_session
    verify_connection!

    driver = Neo4j::Driver::GraphDatabase.driver(
      @uri,
      Neo4j::Driver::AuthTokens.basic(@username, @password),
      connection_timeout: 5,
      max_connection_lifetime: 3_600,
      max_connection_pool_size: 100,
      connection_acquisition_timeout: 60
    )

    begin
      driver.session(database: @database) do |session|
        yield session if block_given?
      end
    ensure
      driver.close
    end
  end

  # Verify Neo4j connection before attempting operations
  def verify_connection!
    host, port = extract_host_port(@uri)

    unless port_open?(host, port, 2)
      raise ConnectionError, "Neo4j is not available at #{host}:#{port}. " \
                             "Check if Neo4j is running: brew services list | grep neo4j"
    end

    logger.debug "Neo4j connection verified at #{host}:#{port}"
  end

  # Clear the entire database (use with caution!)
  def clear_database
    logger.info "Clearing Neo4j database..."

    with_session do |session|
      # Get count first
      result = session.run("MATCH (n) RETURN count(n) as count").single
      total = result["count"]
      logger.info "Found #{total} nodes to delete"

      if total > 1000
        # Use batched deletion for large databases
        logger.info "Large database detected, using batched deletion"
        deleted = 0

        while deleted < total
          begin
            Timeout.timeout(@timeout) do
              result = session.run("MATCH (n) WITH n LIMIT #{@batch_size} DETACH DELETE n RETURN count(n) as deleted").single
              batch_deleted = result["deleted"]
              deleted += batch_deleted
              logger.info "Deleted #{deleted}/#{total} nodes (#{(deleted.to_f / total * 100).round(1)}%)"
            end
          rescue Timeout::Error
            logger.warn "Timeout during batch deletion, continuing with next batch"
          end
        end
      else
        # Simple deletion for small databases
        session.run("MATCH (n) DETACH DELETE n").consume
        logger.info "Database cleared successfully"
      end
    end
  end

  # Create a node with the given label and properties
  # Returns the internal Neo4j ID
  def create_node(label, properties = {}, registry_key = nil)
    with_session do |session|
      # Prepare properties by converting complex objects to JSON strings
      prepared_props = prepare_properties(properties)

      # Create Cypher query with parameters
      query = "CREATE (n:#{label} $props) RETURN id(n) as id"

      # Execute query
      result = session.run(query, props: prepared_props).single
      node_id = result["id"]

      # Store in registry if key provided
      @node_registry[registry_key] = node_id if registry_key

      logger.debug "Created #{label} node with ID: #{node_id}"
      node_id
    end
  end

  # Create a relationship between two nodes
  def create_relationship(from_id, relationship_type, to_id, properties = {})
    with_session do |session|
      # Resolve IDs from registry if they're keys
      from_id = @node_registry[from_id] || from_id
      to_id = @node_registry[to_id] || to_id

      # Prepare properties
      prepared_props = prepare_properties(properties)

      # Create relationship
      query = "MATCH (a), (b) WHERE id(a) = $from_id AND id(b) = $to_id " \
              "CREATE (a)-[r:#{relationship_type} $props]->(b) " \
              "RETURN id(r) as id"

      result = session.run(query, from_id: from_id, to_id: to_id, props: prepared_props).single
      rel_id = result["id"]

      logger.debug "Created #{relationship_type} relationship with ID: #{rel_id}"
      rel_id
    end
  end

  # Import a batch of nodes
  def import_nodes(nodes)
    count = 0
    with_session do |session|
      nodes.each_slice(@batch_size) do |batch|
        batch.each do |node|
          label = node[:label]
          properties = node[:properties] || {}
          key = node[:key]

          prepared_props = prepare_properties(properties)
          query = "CREATE (n:#{label} $props) RETURN id(n) as id"
          result = session.run(query, props: prepared_props).single
          node_id = result["id"]

          @node_registry[key] = node_id if key
          count += 1
        end

        logger.info "Imported #{count} nodes so far"
      end
    end

    count
  end

  # Import a batch of relationships
  def import_relationships(relationships)
    count = 0
    with_session do |session|
      relationships.each_slice(@batch_size) do |batch|
        batch.each do |rel|
          from_id = @node_registry[rel[:from]] || rel[:from]
          to_id = @node_registry[rel[:to]] || rel[:to]
          type = rel[:type]
          properties = rel[:properties] || {}

          prepared_props = prepare_properties(properties)
          query = "MATCH (a), (b) WHERE id(a) = $from_id AND id(b) = $to_id " \
                  "CREATE (a)-[r:#{type} $props]->(b) " \
                  "RETURN id(r) as id"

          session.run(query, from_id: from_id, to_id: to_id, props: prepared_props)
          count += 1
        end

        logger.info "Imported #{count} relationships so far"
      end
    end

    count
  end

  # Run a custom Cypher query
  def run_query(query, params = {})
    with_session do |session|
      result = session.run(query, params)
      result.to_a
    end
  end

  private

  # Extract host and port from URI
  def extract_host_port(uri)
    match = uri.match(%r{bolt://([^:]+)(?::(\d+))?})
    host = match[1] || "127.0.0.1"
    port = (match[2] || "7687").to_i
    [host, port]
  end

  # Check if port is open
  def port_open?(host, port, timeout_seconds = 2)
    Timeout.timeout(timeout_seconds) do
      s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      sockaddr = Socket.sockaddr_in(port, host)
      s.connect(sockaddr)
      s.close
      return true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return false
    end
  rescue Timeout::Error
    false
  end

  # Prepare properties for Neo4j by converting complex objects to JSON
  def prepare_properties(properties)
    properties.transform_values do |value|
      case value
      when Hash, Array
        JSON.generate(value)
      else
        value
      end
    end
  end

  # Custom error class
  class ConnectionError < StandardError; end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  # Set up environment variables or pass options directly
  ENV["NEO4J_PASSWORD"] = "LRzzbVvRv86xXKbpudk-"

  importer = Neo4jImportService.new

  # Test connection
  begin
    importer.verify_connection!
    puts "✅ Connected to Neo4j successfully!"

    # Clear database (optional)
    # importer.clear_database

    # Create some test data
    importer.logger.debug "Creating test user node"
    importer.create_node("User", {
                           name: "John Doe",
                           email: "john@example.com",
                           metadata: { role: "admin", preferences: { theme: "dark" } }
                         }, :john)

    importer.logger.debug "Creating test post node"
    importer.create_node("Post", {
                           title: "Hello Neo4j",
                           content: "This is a test post",
                           created_at: Time.now.to_s
                         }, :post1)

    # Create relationship
    importer.create_relationship(:john, "AUTHORED", :post1, { at: Time.now.to_s })

    puts "✅ Test data created successfully!"

    # Run a query to verify
    result = importer.run_query("MATCH (u:User)-[r:AUTHORED]->(p:Post) RETURN u.name, p.title")
    puts "Query result: #{result.inspect}"
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.join("\n")
  end
end
