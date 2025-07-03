# frozen_string_literal: true

# Load environment variables
require 'dotenv/load'

# Configure Neo4j driver
NEO4J_CONFIG = {
  # Force IPv4 by using 127.0.0.1 instead of localhost
  url: ENV.fetch('NEO4J_URL', 'bolt://127.0.0.1:7687').gsub('localhost', '127.0.0.1'),
  username: ENV.fetch('NEO4J_USERNAME', 'neo4j'),
  password: ENV.fetch('NEO4J_PASSWORD', 'password'),
  max_connection_lifetime: 1.hour,
  max_connection_pool_size: 20,
  connection_timeout: 5.seconds,
  # Disable encryption for local development
  encryption: false,
  # Additional connection settings
  connection_acquisition_timeout: 5.seconds,
  max_transaction_retry_time: 30.seconds,
  # SSL settings - explicitly disable for local development
  ssl: false,
  # Force IPv4 to avoid IPv6 issues
  resolver: ->(address) { [Resolv::IPv4.create(address.to_s)] rescue [address] }
}.freeze

# Log Neo4j configuration (without password)
Rails.logger.info "Neo4j configured with URL: #{NEO4J_CONFIG[:url]}, User: #{NEO4J_CONFIG[:username]}"

# Log the full configuration (except password) for debugging
config_to_log = NEO4J_CONFIG.dup
debug_config = {
  url: config_to_log[:url],
  username: config_to_log[:username],
  max_connection_lifetime: config_to_log[:max_connection_lifetime],
  max_connection_pool_size: config_to_log[:max_connection_pool_size],
  connection_timeout: config_to_log[:connection_timeout],
  encryption: config_to_log[:encryption]
}
Rails.logger.debug "Neo4j configuration: #{debug_config.inspect}"
