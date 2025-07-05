#!/usr/bin/env ruby
# This script checks what data is in the Neo4j database

require "neo4j-ruby-driver"
require "logger"

# Initialize logger
logger = Logger.new(STDOUT)
logger.level = ENV["LOG_LEVEL"] ? Logger.const_get(ENV["LOG_LEVEL"].upcase) : Logger::INFO

# Neo4j connection details
uri = ENV["NEO4J_BOLT_URL"] || "bolt://127.0.0.1:7687"
uri = uri.gsub("localhost", "127.0.0.1")
username = ENV["NEO4J_USERNAME"] || "neo4j"
password = ENV.fetch("NEO4J_PASSWORD", nil)
database = ENV["NEO4J_DATABASE"] || "neo4j"

if password.nil?
  logger.error "Please set the NEO4J_PASSWORD environment variable"
  exit 1
end

# Connect to Neo4j
begin
  driver = Neo4j::Driver::GraphDatabase.driver(
    uri,
    Neo4j::Driver::AuthTokens.basic(username, password),
    encryption: false,
    max_connection_pool_size: 10,
    connection_acquisition_timeout: 30
  )

  driver.session(database: database) do |session|
    # Count nodes by label
    logger.info "=== Node counts by label ==="
    result = session.run("MATCH (n) RETURN DISTINCT labels(n) as labels, count(*) as count ORDER BY count DESC")
    result.each do |record|
      logger.info "#{record['labels'].join(', ')}: #{record['count']} nodes"
    end

    # Count relationships by type
    logger.info "\n=== Relationship counts by type ==="
    result = session.run("MATCH ()-[r]->() RETURN DISTINCT type(r) as type, count(*) as count ORDER BY count DESC")
    result.each do |record|
      logger.info "#{record['type']}: #{record['count']} relationships"
    end

    # Sample of nodes
    logger.info "\n=== Sample nodes ==="
    result = session.run("MATCH (n) RETURN n.name as name, labels(n) as labels LIMIT 5")
    result.each do |record|
      logger.info "#{record['labels'].join(', ')}: #{record['name']}"
    end

    # Sample of relationships
    logger.info "\n=== Sample relationships ==="
    result = session.run("MATCH (a)-[r]->(b) RETURN a.name as from, type(r) as type, b.name as to LIMIT 5")
    result.each do |record|
      logger.info "#{record['from']} -[#{record['type']}]-> #{record['to']}"
    end
  end

  driver.close
rescue StandardError => e
  logger.error "Error: #{e.class} - #{e.message}"
  logger.debug e.backtrace.join("\n") if ENV["DEBUG"]
  exit 1
end

logger.info "Check completed successfully"
