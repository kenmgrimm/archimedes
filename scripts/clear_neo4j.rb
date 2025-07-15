#!/usr/bin/env ruby

require_relative "../config/environment"

puts "Clearing Neo4j database..."

begin
  # Use write_transaction to clear the database
  Neo4j::DatabaseService.write_transaction do |tx|
    tx.run("MATCH (n) DETACH DELETE n")
    puts "Database cleared successfully!"
  end

  # Check current count
  Neo4j::DatabaseService.read_transaction do |tx|
    result = tx.run("MATCH (n) RETURN count(n) as count")
    count = result.first[:count]
    puts "Current node count: #{count}"
  end
rescue StandardError => e
  puts "Error: #{e.message}"
end
