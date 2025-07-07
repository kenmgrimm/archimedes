#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../config/environment"

puts "Listing all nodes in Neo4j database:"

Neo4j::DatabaseService.read_transaction do |tx|
  # Get total count of nodes
  count_result = tx.run("MATCH (n) RETURN count(n) as count")
  total_nodes = count_result.first["count"]

  puts "Total nodes in database: #{total_nodes}"

  # Get first 10 nodes with their properties
  result = tx.run("MATCH (n) RETURN n, labels(n) as labels, id(n) as id, properties(n) as props LIMIT 10")

  if result.any?
    puts "\nFirst 10 nodes:"
    result.each_with_index do |record, idx|
      puts "\nNode ##{idx + 1}:"
      puts "  ID: #{record['id']}"
      puts "  Labels: #{record['labels'].inspect}"

      # Format properties for better readability
      props = record["props"]
      if props.any?
        puts "  Properties:"
        props.each { |k, v| puts "    #{k}: #{v.inspect}" }
      else
        puts "  No properties"
      end

      # Get relationships
      rels = tx.run("MATCH (n)-[r]->() WHERE id(n) = $id RETURN type(r) as type, id(r) as rel_id", id: record["id"])
      if rels.any?
        puts "  Outgoing relationships:"
        rels.each { |rel| puts "    -[:#{rel['type']}]-> (id: #{rel['rel_id']})" }
      end

      # Get incoming relationships
      in_rels = tx.run("MATCH (n)<-[r]-() WHERE id(n) = $id RETURN type(r) as type, id(r) as rel_id", id: record["id"])
      if in_rels.any?
        puts "  Incoming relationships:"
        in_rels.each { |rel| puts "    <-[:#{rel['type']}]-" }
      end
    end
  else
    puts "No nodes found in the database."
  end

  # Get some statistics
  puts "\nNode statistics:"
  stats = tx.run("MATCH (n) RETURN labels(n) as labels, count(*) as count ORDER BY count DESC")
  stats.each do |stat|
    puts "  #{stat['labels'].inspect}: #{stat['count']} nodes"
  end

  # Get relationship statistics
  puts "\nRelationship statistics:"
  rel_stats = tx.run("MATCH ()-[r]->() RETURN type(r) as type, count(*) as count ORDER BY count DESC")
  rel_stats.each do |stat|
    puts "  -[:#{stat['type']}]-> : #{stat['count']} relationships"
  end
end
