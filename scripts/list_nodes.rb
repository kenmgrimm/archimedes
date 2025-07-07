#!/usr/bin/env ruby

require "neo4j/driver"
require "dotenv/load"

# Initialize the Neo4j driver
driver = Neo4j::Driver::GraphDatabase.driver(
  ENV.fetch("NEO4J_URL", nil),
  Neo4j::Driver::AuthTokens.basic(ENV.fetch("NEO4J_USERNAME", nil), ENV.fetch("NEO4J_PASSWORD", nil))
)

# Function to list all nodes
def list_nodes(session)
  query = "MATCH (n) RETURN n, id(n) as id, labels(n) as labels, properties(n) as props"

  puts "Listing all nodes in the database:"
  puts "=" * 80

  session.write_transaction do |tx|
    result = tx.run(query)

    if result.any?
      result.each_with_index do |record, index|
        puts "Node ##{index + 1}:"
        puts "  ID: #{record['id']}"
        puts "  Labels: #{record['labels'].inspect}"
        puts "  Properties:"
        record["props"].each { |k, v| puts "    #{k}: #{v.inspect}" }
        puts "-" * 80
      end
    else
      puts "No nodes found in the database."
    end
  end
end

# Execute the script
begin
  driver.session do |session|
    list_nodes(session)
  end
ensure
  driver&.close
end
