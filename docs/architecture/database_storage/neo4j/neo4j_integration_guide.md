# Neo4j Integration Guide

This document outlines the steps taken to integrate the Neo4j graph database with the Archimedes application, including manual verification steps and implementation details.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Manual Verification](#manual-verification)
3. [Implementation Details](#implementation-details)
4. [Usage Examples](#usage-examples)
5. [Troubleshooting](#troubleshooting)

## Prerequisites

- Neo4j Desktop installed and running
- A database created in Neo4j Desktop
- Bolt connector enabled on port 7687 (default)
- Database credentials (username/password)

## Manual Verification

### 1. Verify TCP Connectivity

First, verify that you can connect to the Neo4j server using `nc` (netcat):

```bash
nc -zv 127.0.0.1 7687
```

### 2. Test Connection with Cypher Shell

Use the Cypher shell to test basic operations:

```bash
# Start Cypher shell
cypher-shell -u neo4j -p your_password

# Run a test query
MATCH (n) RETURN count(n) AS node_count;
```

## Implementation Details

### 1. Configuration

Neo4j connection settings are configured in `config/initializers/neo4j_driver.rb`:

```ruby
# Force IPv4 and disable SSL for local development
NEO4J_CONFIG = {
  url: ENV.fetch('NEO4J_URL', 'bolt://127.0.0.1:7687'),
  username: ENV.fetch('NEO4J_USERNAME', 'neo4j'),
  password: ENV.fetch('NEO4J_PASSWORD', 'your_password'),
  max_connection_lifetime: 1.hour,
  max_connection_pool_size: 20,
  connection_timeout: 5.seconds,
  encryption: ENV.fetch('NEO4J_ENCRYPTED', 'false').casecmp?('true'),
  connection_acquisition_timeout: 5.seconds,
  max_transaction_retry_time: 30.seconds,
  ssl: false, # Explicitly disable SSL for local development
  resolver: ->(address) { [['127.0.0.1', 7687]] } # Force IPv4
}
```

### 2. Driver Wrapper

The `Neo4j::DriverWrapper` class provides a clean interface for executing Cypher queries:

```ruby
# Basic query execution
Neo4j::DriverWrapper.query('MATCH (n) RETURN count(n) AS count') do |records|
  puts "Node count: #{records.first['count']}"
end

# Using transactions
Neo4j::DriverWrapper.transaction do |tx|
  tx.query("CREATE (n:Node {name: $name})", name: "Test Node")
  tx.query("MATCH (n:Node) RETURN n") do |records|
    records.each { |r| puts r['n'].properties }
  end
end
```

## Usage Examples

### Creating Nodes

```ruby
# Create a node with properties
Neo4j::DriverWrapper.query(
  "CREATE (n:Person {name: $name, age: $age}) RETURN n",
  name: "Alice",
  age: 30
) do |records|
  puts "Created: #{records.first['n'].properties}"
end
```

### Querying Data

```ruby
# Find all people over a certain age
Neo4j::DriverWrapper.query(
  'MATCH (p:Person) WHERE p.age > $min_age RETURN p',
  min_age: 25
) do |records|
  records.each do |record|
    puts "Found: #{record['p'].properties}"
  end
end
```

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Ensure Neo4j Desktop is running
   - Verify the Bolt connector is enabled on port 7687
   - Check if the database is started

2. **Authentication Failed**
   - Verify your username and password
   - Check if you need to reset the password in Neo4j Desktop

3. **Result Already Consumed**
   - Make sure to process results within the block provided to `query`
   - If you need to use results later, convert them to an array first:
     ```ruby
     results = Neo4j::DriverWrapper.query('MATCH (n) RETURN n').to_a
     ```

### Debugging

Enable debug logging by setting the log level to `:debug` in `config/environments/development.rb`:

```ruby
config.log_level = :debug
```

## License

This integration is part of the Archimedes project. See the main README for license information.
