# frozen_string_literal: true

module Neo4j
  # Service for managing Neo4j database connections and operations
  class DatabaseService
    # Raised when required configuration is missing
    class ConfigurationError < StandardError; end

    class << self
      # Returns a Neo4j driver instance
      # @return [Neo4j::Driver::Driver]
      def driver
        @driver ||= begin
          require "neo4j/driver"

          # Use explicit IPv4 address to match working test script
          uri = connection_url.gsub("localhost", "127.0.0.1")

          Neo4j::Driver::GraphDatabase.driver(
            uri,
            Neo4j::Driver::AuthTokens.basic(username, password),
            **connection_config
          )
        end
      end

      # Executes a read transaction
      # @yield [Neo4j::Driver::Transaction] The transaction to execute read operations
      # @return [Object] The result of the block
      def read_transaction(&)
        session = driver.session
        begin
          session.read_transaction(&)
        ensure
          session&.close
        end
      end

      # Executes a write transaction
      # @yield [Neo4j::Driver::Transaction] The transaction to execute write operations
      # @return [Object] The result of the block
      def write_transaction(&)
        session = driver.session
        begin
          session.write_transaction(&)
        ensure
          session&.close
        end
      end

      # Clears all nodes and relationships from the database
      # @param logger [Logger] Optional logger for progress output
      def clear_database(logger: nil)
        logger&.info("Clearing Neo4j database...")

        write_transaction do |tx|
          tx.run("MATCH (n) DETACH DELETE n")
          logger&.info("  - All nodes and relationships deleted")

          # Rebuild constraints and indexes if needed
          # create_constraints(tx)
        end

        logger&.info("Database cleared successfully")
      end

      # Checks if the database is accessible
      # @return [Boolean] true if the database is accessible
      def accessible?
        read_transaction { |tx| tx.run("RETURN 1 AS result") }
        true
      rescue StandardError => e
        Rails.logger.error("Neo4j connection failed: #{e.message}")
        false
      end

      private

      def connection_url
        ENV.fetch("NEO4J_URL") do
          raise ConfigurationError, "NEO4J_URL environment variable is required (e.g., 'bolt://localhost:7687')"
        end
      end

      def username
        ENV.fetch("NEO4J_USERNAME") do
          raise ConfigurationError, "NEO4J_USERNAME environment variable is required"
        end
      end

      def password
        ENV.fetch("NEO4J_PASSWORD") do
          raise ConfigurationError, "NEO4J_PASSWORD environment variable is required"
        end
      end

      def connection_config
        {
          max_connection_lifetime: 1.hour,
          connection_acquisition_timeout: 60, # seconds
          connection_timeout: 5, # seconds
          max_connection_pool_size: 100,
          logging: {
            level: :info, # Explicitly set to info for better debugging
            logger: Rails.logger
          }
        }
      end
    end
  end
end
