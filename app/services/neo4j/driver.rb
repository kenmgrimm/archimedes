# frozen_string_literal: true

require "neo4j/driver"

module Neo4j
  # Wrapper around the Neo4j Ruby driver to provide a simpler interface for executing
  # Cypher queries and managing transactions.
  #
  # @example Basic query
  #   Neo4j::DriverWrapper.query('MATCH (n) RETURN count(n) AS count') do |records|
  #     puts "Node count: #{records.first['count']}"
  #   end
  #
  # @example Using transactions
  #   Neo4j::DriverWrapper.transaction do |tx|
  #     tx.query("CREATE (n:Node {name: $name})", name: "Test Node")
  #     tx.query("MATCH (n:Node) RETURN n") do |records|
  #       records.each { |r| puts r['n'].properties }
  #     end
  #   end
  class DriverWrapper
    class << self
      # Executes a read-only Cypher query and yields the results to the provided block.
      # The results are automatically converted to an array and consumed within the block.
      #
      # @param cypher [String] The Cypher query to execute
      # @param parameters [Hash] Parameters for the query
      # @yield [Array<Neo4j::Driver::Record>] The query results
      # @return [void]
      def query(cypher, parameters = {}, &block)
        session do |session|
          result = session.run(cypher, parameters)

          if block
            begin
              records = result.to_a
              yield(records)
            ensure
              result.consume if result.respond_to?(:consume)
            end
          else
            result.to_a.tap do |_|
              result.consume if result.respond_to?(:consume)
            end
          end
        end
      end

      # Executes write operations in a transaction.
      #
      # @yield [Neo4j::Driver::Transaction] The transaction object
      # @return [void]
      def write_transaction(&)
        session do |session|
          session.write_transaction(&)
        end
      end

      # Executes operations in a transaction with manual control.
      # Provides a transaction wrapper that supports the same interface as the main class.
      #
      # @yield [Object] A transaction wrapper that responds to #query
      # @return [Object] The result of the block
      def transaction
        session do |session|
          session.begin_transaction do |tx|
            tx_wrapper = Class.new do
              def initialize(tx)
                @tx = tx
              end

              # @see Neo4j::DriverWrapper.query
              def query(cypher, parameters = {}, &block)
                params = parameters.is_a?(Hash) ? parameters : {}
                result = @tx.run(cypher, **params)

                if block
                  begin
                    records = result.to_a
                    yield(records)
                  ensure
                    result.consume if result.respond_to?(:consume)
                  end
                else
                  result.to_a.tap do |_|
                    result.consume if result.respond_to?(:consume)
                  end
                end
              end
            end.new(tx)

            block_result = yield(tx_wrapper)
            tx.commit
            block_result
          end
        end
      end

      private

      # Establishes a session with the Neo4j database and yields it to the block.
      # The session is automatically closed when the block completes.
      #
      # @yield [Neo4j::Driver::Session] The Neo4j session
      # @return [Object] The result of the block
      # @raise [Neo4j::Driver::Exceptions::ServiceUnavailable] If the database is not available
      # @raise [Neo4j::Driver::Exceptions::AuthenticationException] If authentication fails
      def session
        # Build driver config with only the options that are supported by the driver
        driver_config = {
          # Explicitly disable encryption for local development
          encryption: false,
          # Connection pool settings
          max_connection_lifetime: NEO4J_CONFIG[:max_connection_lifetime],
          max_connection_pool_size: NEO4J_CONFIG[:max_connection_pool_size],
          connection_timeout: NEO4J_CONFIG[:connection_timeout],
          # Timeout settings
          connection_acquisition_timeout: NEO4J_CONFIG[:connection_acquisition_timeout],
          max_transaction_retry_time: NEO4J_CONFIG[:max_transaction_retry_time],
          # Disable SSL completely
          ssl: false,
          # Use IPv4 only to avoid IPv6 issues
          resolver: NEO4J_CONFIG[:resolver]
        }.compact

        # Create the driver
        driver = Neo4j::Driver::GraphDatabase.driver(
          NEO4J_CONFIG[:url],
          Neo4j::Driver::AuthTokens.basic(
            NEO4J_CONFIG[:username],
            NEO4J_CONFIG[:password]
          ),
          **driver_config
        )

        # Verify the connection
        verify_connection(driver)

        Rails.logger.info("Successfully created Neo4j driver")
        driver
      rescue StandardError => e
        Rails.logger.error("Failed to create Neo4j driver: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise
      end

      def verify_connection(driver)
        # Try to open a session and run a simple query to verify the connection
        session = driver.session
        begin
          result = session.run("RETURN 1 AS test")
          record = result.first
          Rails.logger.debug { "Connection test successful, result: #{record['test']}" }
        ensure
          session&.close
        end
      rescue StandardError => e
        Rails.logger.error("Connection test failed: #{e.message}")
        driver&.close
        raise
      end
    end
  end
end
