# frozen_string_literal: true

require "dotenv/load"
require_relative "../config/environment"

# Enable detailed logging
Rails.logger.level = Logger::DEBUG
ActiveRecord::Base.logger = Logger.new($stdout) if defined?(ActiveRecord::Base)

# This script provides a comprehensive test suite for the AI-powered vector similarity search
# It tests various scenarios including exact matches, similar matches, and edge cases

class AISimilarityTestSuite
  def initialize
    # Enable debug mode globally
    $debug_mode = true

    @importer = Neo4j::Import::NodeImporter.new(
      enable_vector_search: true,
      similarity_threshold: 0.8,
      logger: Logger.new($stdout),
      debug: true # Enable debug mode for the importer
    )

    @test_cases = []
    @results = { total: 0, passed: 0, failed: 0, skipped: 0 }

    setup_test_cases
  end

  def setup_test_cases
    # Test Case 1: Exact name match with different email formats
    add_test_case(
      name: "Person - Exact name, different email formats",
      type: "Person",
      existing_nodes: [
        { name: "John Smith", email: "john.smith@example.com", title: "Software Engineer" }
      ],
      new_node: { name: "John Smith", email: "john.smith@acme.com", title: "Senior Software Engineer" },
      should_match: true,
      reason: "Same name should match regardless of email domain"
    )

    # Test Case 2: Slightly different names with similar context
    add_test_case(
      name: "Person - Similar names, similar context",
      type: "Person",
      existing_nodes: [
        { name: "Jonathan Smith", email: "jon.smith@example.com", title: "Senior Developer" }
      ],
      new_node: { name: "John Smith", email: "j.smith@example.com", title: "Senior Developer" },
      should_match: true,
      reason: "Similar names with same title should match"
    )

    # Test Case 3: Same name, different companies
    add_test_case(
      name: "Person - Same name, different companies",
      type: "Person",
      existing_nodes: [
        { name: "Sarah Johnson", email: "sarah.j@company-a.com", company: "Company A" }
      ],
      new_node: { name: "Sarah Johnson", email: "sarah.j@company-b.com", company: "Company B" },
      should_match: false,
      reason: "Same name but different companies should not match"
    )

    # Test Case 4: Abbreviated vs full names
    add_test_case(
      name: "Person - Abbreviated vs full names",
      type: "Person",
      existing_nodes: [
        { name: "Robert Johnson", email: "robert.j@example.com", title: "CTO" }
      ],
      new_node: { name: "Rob Johnson", email: "rob.j@example.com", title: "Chief Technology Officer" },
      should_match: true,
      reason: "Abbreviated first name with expanded title should match"
    )

    # Test Case 5: Different people with similar names
    add_test_case(
      name: "Person - Different people with similar names",
      type: "Person",
      existing_nodes: [
        { name: "Michael Brown", email: "michael.b@example.com", company: "Acme Inc." }
      ],
      new_node: { name: "Michelle Brown", email: "michelle.b@example.com", company: "Acme Inc." },
      should_match: false,
      reason: "Different people with similar names should not match"
    )

    # Test Case 6: Product matching with different descriptions
    add_test_case(
      name: "Product - Similar descriptions",
      type: "Product",
      existing_nodes: [
        { name: "Wireless Earbuds", sku: "WEB-123", description: "Noise cancelling wireless earbuds with 20h battery life" }
      ],
      new_node: { name: "Bluetooth Earbuds", sku: "BTE-456", description: "Wireless noise-canceling earbuds with 24h battery" },
      should_match: true,
      reason: "Similar product descriptions with minor variations should match"
    )

    # Test Case 7: Address variations
    add_test_case(
      name: "Address - Different formats",
      type: "Address",
      existing_nodes: [
        {
          street: "123 Main St",
          city: "San Francisco",
          state: "CA",
          zip: "94105",
          country: "USA"
        }
      ],
      new_node: {
        street: "123 Main Street",
        city: "San Francisco",
        state: "California",
        zip: "94105-1234",
        country: "United States"
      },
      should_match: true,
      reason: "Address variations should be recognized as the same location"
    )
  end

  def add_test_case(test_case)
    @test_cases << test_case
  end

  def run
    puts "\n=== Starting AI Similarity Test Suite ===\n"

    @test_cases.each_with_index do |test_case, index|
      run_test_case(test_case, index + 1)
    end

    print_summary
  end

  private

  def run_test_case(test_case, test_number)
    puts "\n[Test ##{test_number}] #{test_case[:name]}"
    puts "Description: #{test_case[:reason]}"

    begin
      # Clear existing test data
      clear_test_data

      # Import existing nodes - don't capture the result since we don't need it
      import_test_nodes(test_case[:type], test_case[:existing_nodes])

      # Try to import the new node with a unique ID to avoid conflicts
      new_node_data = {
        type: test_case[:type],
        properties: test_case[:new_node].merge(
          test_id: SecureRandom.uuid, # Add a unique ID for tracking
          created_at: Time.current.iso8601
        )
      }

      # Convert to the format expected by import_nodes
      nodes = [new_node_data[:properties]]
      result = @importer.import_nodes(nodes, type: test_case[:type])

      # Check if the node was created or matched
      node_created = result[:created] == 1
      node_updated = result[:updated] == 1

      # Verify the result
      if test_case[:should_match]
        if node_updated
          puts "✅ PASS: Node was correctly matched to an existing node"
          @results[:passed] += 1
        else
          puts "❌ FAIL: Expected node to match existing node, but it was created as new"
          @results[:failed] += 1
        end
      elsif node_created
        puts "✅ PASS: Node was correctly created as a new entity"
        @results[:passed] += 1
      else
        puts "❌ FAIL: Expected node to be new, but it matched an existing node"
        @results[:failed] += 1
      end

      @results[:total] += 1
    rescue StandardError => e
      puts "❌ ERROR: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]
      @results[:failed] += 1
      @results[:total] += 1
    end
  end

  def import_test_nodes(type, nodes_data)
    nodes_data.map do |node_data|
      # Add test metadata to each node
      node_with_metadata = node_data.merge(
        test_id: SecureRandom.uuid,
        created_at: Time.current.iso8601,
        test_source: "ai_similarity_test_suite"
      )

      @importer.import_nodes([node_with_metadata], type: type)
      node_with_metadata
    end
  end

  def log_error(message)
    puts "[ERROR] #{message}"
    Rails.logger.error("[AI Similarity Test] #{message}")
  end

  def log_info(message)
    puts "[INFO] #{message}"
    Rails.logger.info("[AI Similarity Test] #{message}")
  end

  def clear_test_data
    Neo4j::DatabaseService.write_transaction do |tx|
      tx.run("MATCH (n:TestNode) DETACH DELETE n")
    end
  end

  def print_summary
    puts "\n=== Test Suite Summary ==="
    puts "Total tests: #{@results[:total]}"
    puts "Passed: #{@results[:passed]}"
    puts "Failed: #{@results[:failed]}"
    puts "Skipped: #{@results[:skipped]}"

    if @results[:failed].positive?
      puts "\n❌ Some tests failed. Please review the output above."
      exit 1
    else
      puts "\n✅ All tests passed!"
      exit 0
    end
  end
end

# Run the test suite
AISimilarityTestSuite.new.run
