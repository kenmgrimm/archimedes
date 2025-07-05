#!/usr/bin/env ruby
# frozen_string_literal: true

# Ensure we're running in a Rails environment
unless defined?(Rails)
  puts "This script must be run in a Rails environment. Please use: bundle exec rails runner #{__FILE__}"
  exit 1
end

require "json"
require "fileutils"
require "logger"
require "neo4j/driver"
require "timeout"
require "socket"
require "securerandom"

# Configure logging
LOG_LEVEL = ENV.fetch("LOG_LEVEL", "info").downcase
LOGGER = Logger.new($stdout)
LOGGER.level = Logger.const_get(LOG_LEVEL.upcase)
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  formatted_datetime = datetime.strftime("%Y-%m-%d %H:%M:%S")
  "[#{formatted_datetime}] #{severity}: #{msg}\n"
end

# Neo4j Import Service
# A robust service for importing data into Neo4j using the Bolt protocol
class Neo4jImportService
  attr_reader :logger

  def initialize(options = {})
    # Always use explicit IPv4 address to avoid IPv6 issues
    @uri = options[:uri] || ENV["NEO4J_BOLT_URL"] || "bolt://127.0.0.1:7687"
    @uri = @uri.gsub("localhost", "127.0.0.1")
    @username = options[:username] || ENV["NEO4J_USERNAME"] || "neo4j"
    @password = options[:password] || ENV.fetch("NEO4J_PASSWORD", nil)
    @database = options[:database] || ENV["NEO4J_DATABASE"] || "neo4j"
    @batch_size = options[:batch_size] || 500
    @timeout = options[:timeout] || 60

    # Set up logging
    @logger = options[:logger] || LOGGER

    # Debug mode for Neo4j driver
    ENV["NEO4J_DEBUG"] = "true" if ENV["DEBUG"]

    # Track created nodes for relationship creation
    @node_registry = {}

    logger.debug "Initialized Neo4j import service with URI: #{@uri}, database: #{@database}"
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

  # Import extraction data from JSON
  def import_extraction(extraction_data)
    stats = { nodes: 0, relationships: 0, errors: [] }
    start_time = Time.now

    logger.info "Starting import of extraction data..."

    # Process entities (nodes)
    entities = extraction_data[:entities] || []

    if entities.any?
      logger.info "Importing #{entities.size} entities..."

      entities.each do |entity|
        # Extract required fields with fallbacks
        type = entity[:type] || entity["type"] || "Entity"

        # Generate ID if not present
        id = entity[:id] || entity["id"] || entity[:name] || entity["name"] || SecureRandom.uuid

        # Get properties, ensuring we have a hash
        properties = entity[:properties] || entity["properties"] || {}

        # If entity has name but not in properties, add it
        if (entity[:name] || entity["name"]) && !properties[:name] && !properties["name"]
          properties[:name] = entity[:name] || entity["name"]
        end

        # Handle confidence as metadata
        metadata = entity[:metadata] || entity["metadata"] || {}
        metadata[:confidence] = entity[:confidence] || entity["confidence"] if entity[:confidence] || entity["confidence"]

        logger.debug "Creating #{type} node with ID: #{id}"
        create_node(type, properties, id, metadata)
        stats[:nodes] += 1
      rescue StandardError => e
        error_msg = "Error creating node: #{e.class} - #{e.message}"
        logger.error error_msg
        stats[:errors] << { type: "node", entity: entity, error: error_msg }
      end
    else
      logger.warn "No entities found in extraction data"
    end

    # Process relationships
    relationships = extraction_data[:relationships] || []

    if relationships.any?
      logger.info "Importing #{relationships.size} relationships..."

      relationships.each do |rel|
        # Extract required fields with fallbacks
        type = rel[:type] || rel["type"] || "RELATED_TO"

        # Source and target IDs are required
        source_id = rel[:source_id] || rel["source_id"] || rel[:source] || rel["source"]
        target_id = rel[:target_id] || rel["target_id"] || rel[:target] || rel["target"]

        if !source_id || !target_id
          logger.warn "Skipping relationship missing source or target: #{rel.inspect}"
          next
        end

        # Get properties, ensuring we have a hash
        properties = rel[:properties] || rel["properties"] || {}

        # Handle confidence as metadata
        metadata = rel[:metadata] || rel["metadata"] || {}
        metadata[:confidence] = rel[:confidence] || rel["confidence"] if rel[:confidence] || rel["confidence"]

        logger.debug "Creating #{type} relationship from #{source_id} to #{target_id}"
        create_relationship(source_id, type, target_id, properties, metadata)
        stats[:relationships] += 1
      rescue StandardError => e
        error_msg = "Error creating relationship: #{e.class} - #{e.message}"
        logger.error error_msg
        stats[:errors] << { type: "relationship", relationship: rel, error: error_msg }
      end
    else
      logger.warn "No relationships found in extraction data"
    end

    end_time = Time.now
    stats[:duration] = end_time - start_time

    logger.info "Import completed in #{stats[:duration].round(2)}s: #{stats[:nodes]} nodes, #{stats[:relationships]} relationships, #{stats[:errors].size} errors"
    stats
  end

  # Create a node with the given label and properties
  # Returns the internal Neo4j ID
  def create_node(label, properties = {}, registry_key = nil, metadata = {})
    # Prepare properties by converting complex objects to JSON strings
    node_properties = properties.dup

    # Add metadata as a property if provided
    node_properties[:metadata] = metadata if metadata.present?

    # Ensure we have an id property (use name as fallback)
    node_id = registry_key || node_properties[:name] || SecureRandom.uuid
    node_properties[:id] = node_id

    # Ensure we have a name property
    node_properties[:name] ||= node_id

    prepared_props = prepare_properties(node_properties)

    logger.debug "Creating #{label} node with name: '#{node_properties[:name]}'"

    with_session do |session|
      # Create or merge node using MERGE to handle duplicates
      query = <<~CYPHER
        MERGE (n:#{label} {name: $name})
        ON CREATE SET n = $props
        ON MATCH SET n += $props
        RETURN id(n) as id, n.name as name
      CYPHER

      result = session.run(query, name: node_properties[:name], props: prepared_props).single

      if result
        node_id = result["id"]
        node_name = result["name"]

        # Store in registry for relationship creation
        @node_registry[node_id] = node_id
        @node_registry[node_name] = node_id

        @node_registry[registry_key] = node_id if registry_key && registry_key != node_id && registry_key != node_name

        logger.debug "Node #{label}:'#{node_name}' stored with ID: #{node_id}"
        node_id
      else
        logger.error "Failed to create node #{label}:'#{node_properties[:name]}'"
        nil
      end
    end
  rescue StandardError => e
    logger.error "Error in create_node: #{e.class} - #{e.message}"
    logger.debug e.backtrace.join("\n")
    nil
  end

  # Create a relationship between two nodes
  def create_relationship(from_id, relationship_type, to_id, properties = {}, metadata = {})
    logger.debug "Creating relationship #{relationship_type} from '#{from_id}' to '#{to_id}'"

    # Prepare properties
    rel_properties = properties.dup

    # Add metadata as a property if provided
    rel_properties[:metadata] = metadata if metadata.present?

    prepared_props = prepare_properties(rel_properties)

    with_session do |session|
      # Use MERGE to create relationship between nodes, matching on name
      query = <<~CYPHER
        MATCH (source), (target)
        WHERE source.name = $source_name AND target.name = $target_name
        MERGE (source)-[r:#{relationship_type}]->(target)
        ON CREATE SET r = $props
        ON MATCH SET r += $props
        RETURN id(r) as id, source.name as source_name, target.name as target_name
      CYPHER

      # Try to create relationship using names
      result = session.run(
        query,
        source_name: from_id,
        target_name: to_id,
        props: prepared_props
      ).single

      if result
        rel_id = result["id"]
        source_name = result["source_name"]
        target_name = result["target_name"]
        logger.debug "Created #{relationship_type} relationship from '#{source_name}' to '#{target_name}' with ID: #{rel_id}"
        rel_id
      else
        # If direct name match failed, try to find nodes by ID or other properties
        logger.debug "Direct name match failed, trying alternative node lookup"

        # More flexible relationship creation query
        flexible_query = <<~CYPHER
          MATCH (source), (target)
          WHERE (source.id = $source_id OR source.name = $source_name) AND#{' '}
                (target.id = $target_id OR target.name = $target_name)
          MERGE (source)-[r:#{relationship_type}]->(target)
          ON CREATE SET r = $props
          ON MATCH SET r += $props
          RETURN id(r) as id
        CYPHER

        flexible_result = session.run(
          flexible_query,
          source_id: from_id,
          source_name: from_id,
          target_id: to_id,
          target_name: to_id,
          props: prepared_props
        ).single

        if flexible_result
          rel_id = flexible_result["id"]
          logger.debug "Created #{relationship_type} relationship with flexible match, ID: #{rel_id}"
          rel_id
        else
          logger.warn "Failed to create relationship: source or target node not found (#{from_id} -> #{to_id})"
          nil
        end
      end
    end
  rescue StandardError => e
    logger.error "Error in create_relationship: #{e.class} - #{e.message}"
    logger.debug e.backtrace.join("\n")
    nil
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
    # Always ensure we're using an IPv4 address
    host = "127.0.0.1" if host == "localhost"

    logger.debug "Checking if port #{port} is open on #{host}"

    Timeout.timeout(timeout_seconds) do
      # Explicitly use IPv4
      addr = Socket.getaddrinfo(host, nil, Socket::AF_INET)
      s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      sockaddr = Socket.sockaddr_in(port, addr[0][3])
      s.connect(sockaddr)
      s.close
      logger.debug "Successfully connected to #{host}:#{port}"
      return true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      logger.debug "Connection failed: #{e.message}"
      return false
    end
  rescue Timeout::Error
    logger.debug "Connection timed out after #{timeout_seconds}s"
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

# Extraction Importer
class ExtractionImporter
  attr_reader :logger, :neo4j_service

  def initialize(options = {})
    @output_dir = options[:output_dir] || Rails.root.join("scripts", "output").to_s
    @logger = options[:logger] || LOGGER
    @neo4j_service = options[:neo4j_service] || Neo4jImportService.new(logger: @logger)
    @clear_db = options[:clear_db] || false

    logger.debug "Initialized ExtractionImporter with output_dir: #{@output_dir}"
  end

  def import_all
    logger.info "Starting import of all extraction files from #{@output_dir}"

    # Clear database if requested
    if @clear_db
      logger.info "Clearing database before import"
      neo4j_service.clear_database
    end

    # Find all extraction files
    extraction_files = find_extraction_files
    logger.info "Found #{extraction_files.size} extraction files"

    # Process each file
    results = {}
    extraction_files.each do |file_path|
      logger.info "Processing file: #{file_path}"
      results[file_path] = import_file(file_path)
    end

    # Summarize results
    total_nodes = results.sum { |_, stats| stats[:nodes] }
    total_relationships = results.sum { |_, stats| stats[:relationships] }
    total_errors = results.sum { |_, stats| stats[:errors].size }

    logger.info "Import complete: #{total_nodes} nodes, #{total_relationships} relationships, #{total_errors} errors"

    results
  end

  def import_file(file_path)
    logger.info "Importing extraction from #{file_path}"

    begin
      # Load JSON data
      json_data = File.read(file_path)
      raw_data = JSON.parse(json_data, symbolize_names: true)

      # Extract the actual extraction data from the nested structure
      extraction_data =
        if raw_data[:extraction_result]
          logger.debug "Found nested extraction_result structure"
          raw_data[:extraction_result]
        else
          logger.debug "Using flat extraction data structure"
          raw_data
        end

      # Log metadata about the extraction
      logger.info "Processing extraction from #{raw_data[:timestamp]} for folder #{raw_data[:input_folder]}" if raw_data[:timestamp]

      # Import to Neo4j
      neo4j_service.import_extraction(extraction_data)
    rescue JSON::ParserError => e
      logger.error "Failed to parse JSON file: #{e.message}"
      { nodes: 0, relationships: 0, errors: [{ type: "file", error: "JSON parse error: #{e.message}" }], duration: 0 }
    rescue StandardError => e
      logger.error "Error importing file: #{e.class} - #{e.message}"
      { nodes: 0, relationships: 0, errors: [{ type: "file", error: "#{e.class}: #{e.message}" }], duration: 0 }
    end
  end

  private

  def find_extraction_files
    Dir.glob(File.join(@output_dir, "**", "extraction.json"))
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    # Check if password is set
    unless ENV["NEO4J_PASSWORD"]
      LOGGER.error "NEO4J_PASSWORD environment variable is required"
      puts "Please set the NEO4J_PASSWORD environment variable"
      exit 1
    end

    # Parse command line options
    options = {}
    options[:clear_db] = ARGV.include?("--clear-db")
    options[:single_file] = ARGV.detect { |arg| arg.start_with?("--file=") }&.split("=")&.last

    # Initialize importer
    importer = ExtractionImporter.new(options)

    # Import specific file or all files
    if options[:single_file]
      file_path = options[:single_file]
      if File.exist?(file_path)
        LOGGER.info "Importing single file: #{file_path}"
        result = importer.import_file(file_path)
        LOGGER.info "Import result: #{result[:nodes]} nodes, #{result[:relationships]} relationships, #{result[:errors].size} errors"
      else
        LOGGER.error "File not found: #{file_path}"
        exit 1
      end
    else
      # Import all files
      importer.import_all
    end

    LOGGER.info "Import process completed successfully"
  rescue StandardError => e
    LOGGER.error "Unhandled error: #{e.class} - #{e.message}"
    LOGGER.debug e.backtrace.join("\n")
    exit 1
  end
end
