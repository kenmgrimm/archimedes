# frozen_string_literal: true

namespace :neo4j do
  desc "Import data into Neo4j from a directory of JSON files or a specific file"
  task :import, [:input_path] => :environment do |_t, args|
    require_relative "../../app/services/neo4j/knowledge_graph_builder_v2"
    require_relative "../../app/services/neo4j/deduplication_service"
    require "dotenv/load"

    # Set up logger
    logger = Logger.new($stdout)
    logger.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
    logger.formatter = proc do |severity, _datetime, _progname, msg|
      "[#{severity}] #{msg}\n"
    end

    # Initialize services
    begin
      # Initialize deduplication service if OpenAI API key is available
      deduplication_service = if ENV["OPENAI_API_KEY"].present?
                                openai_client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
                                Neo4j::DeduplicationService.new(openai_client, logger: logger)
                              end

      # Initialize the knowledge graph builder
      builder = Neo4j::KnowledgeGraphBuilderV2.new(
        logger: logger,
        deduplication_service: deduplication_service,
        dry_run: ENV["DRY_RUN"] == "true"
      )

      # Determine input path
      input_path = args[:input_path] || Rails.root.join("scripts", "output").to_s
      logger.info("Importing data from: #{input_path}")

      # Load extraction data
      extraction_data = load_extraction_data(input_path, logger)
      unless extraction_data
        logger.error("No extraction data found or invalid format")
        exit 1
      end

      # Run the import
      logger.info("Starting import...")
      result = builder.import(
        extraction_data,
        clear_database: ENV["CLEAR_DATABASE"] == "true",
        validate_schema: ENV["VALIDATE_SCHEMA"] != "false"
      )

      # Output results
      if result[:success]
        logger.info("\n✅ Import completed successfully!")
        logger.info("  - Nodes: #{result.dig(:stats, :nodes, :created) || 0} created, #{result.dig(:stats, :nodes, :updated) || 0} updated")
        logger.info("  - Relationships: #{result.dig(:stats, :relationships, :created) || 0} created")
        logger.info("  - Duration: #{result.dig(:stats, :duration).round(2)}s")
      else
        logger.error("\n❌ Import failed: #{result[:error]}")
        exit 1
      end
    rescue StandardError => e
      logger.error("\n❌ Fatal error during import: #{e.class.name} - #{e.message}")
      logger.error(e.backtrace.join("\n")) if ENV["DEBUG"]
      exit 1
    end
  end

  private

  # Load extraction data from a directory of JSON files or a specific file
  # @param input_path [String] Path to a directory or file
  # @param logger [Logger] Logger instance
  # @return [Hash, nil] The loaded data or nil if loading failed
  def load_extraction_data(input_path, logger)
    logger.debug("Loading data from: #{input_path}")

    if File.directory?(input_path)
      # Load all JSON files in the directory
      files = Dir.glob(File.join(input_path, "**/*.json"))
      if files.empty?
        logger.error("No JSON files found in directory: #{input_path}")
        return nil
      end

      logger.info("Found #{files.size} JSON files in: #{input_path}")
      logger.debug("Files: #{files.inspect}")

      # Merge all JSON files
      data = { entities: [], relationships: [] }
      files.each do |file|
        logger.debug("Loading file: #{file}")
        file_content = File.read(file)
        logger.debug("File content size: #{file_content.size} bytes")

        # Debug: Log first 200 characters of the file
        logger.debug("File content start: #{file_content[0..200]}...") if file_content

        file_data = JSON.parse(file_content, symbolize_names: true)
        logger.debug("Parsed JSON keys: #{file_data.keys.inspect}")

        # Check for nested extraction_result
        if file_data.key?(:extraction_result)
          logger.debug("Found nested :extraction_result key")
          file_data = file_data[:extraction_result]
        end

        # Process entities
        if file_data.key?(:entities)
          entities = Array(file_data[:entities])
          logger.debug("Found #{entities.size} entities in #{File.basename(file)}")
          data[:entities].concat(entities)
          logger.debug("Sample entity: #{entities.first.inspect}") unless entities.empty?
        else
          logger.debug("No entities found in #{File.basename(file)}")
        end

        # Process relationships
        if file_data.key?(:relationships)
          relationships = Array(file_data[:relationships])
          logger.debug("Found #{relationships.size} relationships in #{File.basename(file)}")
          data[:relationships].concat(relationships)
          logger.debug("Sample relationship: #{relationships.first.inspect}") unless relationships.empty?
        else
          logger.debug("No relationships found in #{File.basename(file)}")
        end
      rescue JSON::ParserError => e
        logger.error("Failed to parse JSON file: #{file} - #{e.message}")
        logger.error("File content start: #{file_content[0..200]}...") if file_content
      rescue StandardError => e
        logger.error("Unexpected error processing file #{file}: #{e.class} - #{e.message}")
        logger.error(e.backtrace.join("\n"))
      end

      logger.info("Loaded #{data[:entities].size} entities and #{data[:relationships].size} relationships total")
      logger.debug("Sample entities: #{data[:entities].first(2).inspect}") unless data[:entities].empty?
      logger.debug("Sample relationships: #{data[:relationships].first(2).inspect}") unless data[:relationships].empty?

      # Debug: Save the combined data to a file for inspection
      debug_file = Rails.root.join("tmp", "debug_combined_data.json")
      FileUtils.mkdir_p(File.dirname(debug_file))
      File.write(debug_file, JSON.pretty_generate(data))
      logger.debug("Saved combined data to: #{debug_file}")

      data
    elsif File.file?(input_path) && File.extname(input_path).downcase == ".json"
      # Load single JSON file
      logger.debug("Loading single file: #{input_path}")
      begin
        file_content = File.read(input_path)
        logger.debug("File content size: #{file_content.size} bytes")
        logger.debug("File content start: #{file_content[0..200]}...") if file_content

        file_data = JSON.parse(file_content, symbolize_names: true)
        logger.debug("Parsed JSON keys: #{file_data.keys.inspect}")

        # Check for nested extraction_result
        if file_data.key?(:extraction_result)
          logger.debug("Found nested :extraction_result key")
          file_data = file_data[:extraction_result]
        end

        result = {
          entities: Array(file_data[:entities] || []),
          relationships: Array(file_data[:relationships] || []),
          node_mapping: file_data[:node_mapping] || {}
        }

        logger.debug("Loaded #{result[:entities].size} entities and #{result[:relationships].size} relationships from #{File.basename(input_path)}")
        logger.debug("Sample entities: #{result[:entities].first(2).inspect}") unless result[:entities].empty?
        logger.debug("Sample relationships: #{result[:relationships].first(2).inspect}") unless result[:relationships].empty?

        # Debug: Save the loaded data to a file for inspection
        debug_file = Rails.root.join("tmp", "debug_single_file_data.json")
        FileUtils.mkdir_p(File.dirname(debug_file))
        File.write(debug_file, JSON.pretty_generate(result))
        logger.debug("Saved single file data to: #{debug_file}")

        result
      rescue JSON::ParserError => e
        logger.error("Failed to parse JSON file: #{input_path} - #{e.message}")
        logger.error("File content start: #{file_content[0..200]}...") if defined?(file_content) && file_content
        nil
      end
    else
      logger.error("Invalid input path: #{input_path}. Must be a directory or JSON file.")
      nil
    end
  end
end
