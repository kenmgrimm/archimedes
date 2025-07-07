# frozen_string_literal: true

namespace :import do
  desc "Import extraction files from scripts/output into Neo4j using Bolt protocol"
  task extractions: :environment do
    require "json"
    require "fileutils"

    # Configure logger
    logger = Logger.new($stdout)
    logger.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO

    # Get the output directory
    output_dir = Rails.root.join("scripts", "output")

    unless File.directory?(output_dir)
      logger.error("Output directory not found: #{output_dir}")
      exit 1
    end

    # Find all extraction JSON files
    extraction_files = Dir[File.join(output_dir, "**", "extraction.json")]

    if extraction_files.empty?
      logger.warn("No extraction files found in #{output_dir}")
      exit 0
    end

    logger.info("Found #{extraction_files.size} extraction files to process")

    # Initialize the knowledge graph builder with a new Neo4j session
    bolt_url = ENV["NEO4J_BOLT_URL"] || "bolt://localhost:7687"
    username = ENV["NEO4J_USERNAME"] || "neo4j"
    password = ENV.fetch("NEO4J_PASSWORD", nil)

    logger.info("Connecting to Neo4j at #{bolt_url} with username: #{username}")

    begin
      neo4j_service = Neo4j::Driver::GraphDatabase.driver(
        bolt_url,
        Neo4j::Driver::AuthTokens.basic(username, password)
      )

      # Test the connection
      neo4j_service.session do |session|
        result = session.run("RETURN 'Connected' as status")
        status = result.single&.first&.last
        logger.info("Neo4j connection test: #{status || 'Failed'}")
      end
    rescue StandardError => e
      logger.error("Failed to connect to Neo4j: #{e.class} - #{e.message}")
      logger.error(e.backtrace.join("\n"))
      exit 1
    end

    builder = Neo4j::KnowledgeGraphBuilder.new(
      neo4j_service: neo4j_service,
      logger: logger
    )

    # Process each extraction file
    extraction_files.each_with_index do |file_path, index|
      logger.info("\n[#{index + 1}/#{extraction_files.size}] Processing: #{file_path}")

      begin
        # Parse the extraction file
        file_content = JSON.parse(File.read(file_path), symbolize_names: true)

        # Extract the extraction result (it might be nested under :extraction_result)
        extraction_data = file_content[:extraction_result] || file_content

        # Import the extraction data
        options = {
          clear_database: ENV["CLEAR_DB"] == "true" && index.zero?, # Only clear on first import if requested
          logger: logger
        }

        result = builder.import(extraction_data, options)

        if result[:success]
          logger.info("Successfully imported #{result[:nodes]} nodes and #{result[:relationships]} relationships")
          logger.warn("  Encountered #{result[:errors].size} errors during import") if result[:errors]&.any?
        else
          logger.error("Import failed: #{result[:error]}")
        end
      rescue StandardError => e
        logger.error("Error processing #{file_path}: #{e.message}")
        logger.debug(e.backtrace.join("\n")) if ENV["DEBUG"]
      end
    end

    logger.info("\nImport completed")
  end
end
