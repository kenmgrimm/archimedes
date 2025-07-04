module Neo4j
  class FixtureService
    class FixtureError < Error; end

    # @param output_dir [String] Directory to store fixture files
    # @param logger [Logger] Logger instance
    def initialize(output_dir: Rails.root.join("tmp", "neo4j_fixtures"), logger: nil)
      @output_dir = Pathname.new(output_dir)
      @logger = logger || Rails.logger
      ensure_output_directory
    end

    # Save extracted entities and relationships to a fixture file
    # @param data [Hash] The extracted data (entities and relationships)
    # @param source [String] Source identifier (e.g., document path)
    # @param metadata [Hash] Additional metadata to include
    # @return [String] Path to the saved fixture file
    def save_extraction(data, source: nil, metadata: {})
      raise FixtureError, "Data cannot be empty" if data.blank?

      fixture_data = {
        metadata: {
          extracted_at: Time.current.iso8601,
          source: source,
          version: "1.0"
        }.merge(metadata),
        data: data
      }

      filename = generate_filename(source)
      filepath = @output_dir.join(filename)

      File.write(filepath, JSON.pretty_generate(fixture_data))
      @logger.info("Saved extraction fixture to #{filepath}")

      filepath.to_s
    rescue StandardError => e
      @logger.error("Failed to save fixture: #{e.message}")
      raise FixtureError, "Failed to save fixture: #{e.message}"
    end

    # Load a fixture file
    # @param filepath [String] Path to the fixture file
    # @return [Hash] The loaded fixture data
    def load_fixture(filepath)
      raise FixtureError, "File not found: #{filepath}" unless File.exist?(filepath)

      JSON.parse(File.read(filepath), symbolize_names: true)
    rescue JSON::ParserError => e
      raise FixtureError, "Invalid JSON in fixture: #{e.message}"
    rescue StandardError => e
      @logger.error("Failed to load fixture: #{e.message}")
      raise FixtureError, "Failed to load fixture: #{e.message}"
    end

    # List all available fixtures
    # @return [Array<String>] List of fixture file paths
    def list_fixtures
      Dir.glob(@output_dir.join("*.json")).sort
    end

    private

    def ensure_output_directory
      FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)
    end

    def generate_filename(source = nil)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      source_hash = source ? "_#{Digest::MD5.hexdigest(source.to_s)[0..7]}" : ""
      "extraction_#{timestamp}#{source_hash}.json"
    end
  end
end
