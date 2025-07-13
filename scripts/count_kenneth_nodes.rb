#!/usr/bin/env ruby

require_relative '../config/environment'

puts "Counting Kenneth Grimm Person nodes in Neo4j..."

begin
  Neo4j::DatabaseService.read_transaction do |tx|
    # Count Kenneth Grimm nodes
    result = tx.run('MATCH (p:Person) WHERE p.name = "Kenneth Grimm" RETURN count(p) as count')
    count = result.first[:count]
    puts "Found #{count} Kenneth Grimm Person nodes"
    
    if count > 1
      puts "\n❌ Multiple Kenneth Grimm nodes detected - deduplication is NOT working"
      
      # Show details of each Kenneth Grimm node
      result = tx.run('MATCH (p:Person) WHERE p.name = "Kenneth Grimm" RETURN p.name, p.email, p.phone_number, p.ID, id(p) as neo4j_id')
      
      puts "\nKenneth Grimm nodes:"
      result.each_with_index do |record, i|
        puts "  #{i+1}. Neo4j ID: #{record[:neo4j_id]}, Name: #{record[:name]}, Email: #{record[:email]}, Phone: #{record[:phone_number]}, ID: #{record[:ID]}"
      end
    else
      puts "\n✅ Deduplication working correctly - only #{count} Kenneth Grimm node"
    end
  end
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n")
end