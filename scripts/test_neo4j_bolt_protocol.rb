require "neo4j/driver"
require "socket"
require "timeout"

# Enable debug logging for Neo4j driver
ENV["NEO4J_DEBUG"] = "true"

def test_connection
  # Use explicit IPv4 address instead of localhost to avoid IPv6 issues
  uri = "bolt://127.0.0.1:7687"
  username = "neo4j"
  password = "LRzzbVvRv86xXKbpudk-"

  puts "=== Neo4j Connection Test ==="
  puts "Attempting to connect to Neo4j at: #{uri}"

  # Check if port is open
  host = "127.0.0.1" # Explicitly use IPv4 address
  port = 7687

  puts "\n=== Network Diagnostics ==="
  puts "Testing connection to: #{host} (port #{port})"

  # Check if port is open
  if port_open?(host, port, 2)
    puts "✅ Port #{port} is open and accepting connections"
  else
    puts "❌ Port #{port} is not responding"
    puts "   - Check if Neo4j is running: brew services list | grep neo4j"
    puts "   - Check Neo4j logs: tail -f /opt/homebrew/var/log/neo4j/neo4j.log"
    return false
  end

  # Try to connect with the driver
  puts "\n=== Bolt Connection Attempt ==="
  begin
    puts "Creating driver with URI: #{uri}"

    # Try with connection timeout
    driver = Neo4j::Driver::GraphDatabase.driver(
      uri,
      Neo4j::Driver::AuthTokens.basic(username, password),
      connection_timeout: 5, # seconds
      max_connection_lifetime: 3_600,
      max_connection_pool_size: 100,
      connection_acquisition_timeout: 60 # seconds
    )

    puts "Driver created, attempting to create session..."

    # Test the connection with a simple query
    success = false
    driver.session(database: "neo4j") do |session|
      puts "Session created, running test query..."
      result = session.run("RETURN 2+2 AS value")
      record = result.single
      puts "✅ Successfully connected to Neo4j!"
      puts "Result: #{record['value']}"

      # Try to create a node
      puts "\n=== Creating Test Node ==="
      begin
        create_result = session.run("CREATE (n:TestNode) RETURN id(n) as id").single
        puts "✅ Node created with ID: #{create_result['id']}"
        success = true
      rescue StandardError => e
        puts "❌ Failed to create node: #{e.class}: #{e.message}"
      end
    end

    return success
  rescue Neo4j::Driver::Exceptions::ServiceUnavailableException => e
    puts "\n❌ Neo4j Service Unavailable: #{e.message}"
    puts "\nTroubleshooting steps:"
    puts "1. Check if Neo4j is running:"
    puts "   brew services list | grep neo4j"
    puts "   If not, start it with: brew services start neo4j"
    puts "\n2. Check Neo4j logs for errors:"
    puts "   tail -f /opt/homebrew/var/log/neo4j/neo4j.log"
    puts "\n3. Verify Bolt is enabled in config:"
    puts "   grep '^dbms.connector.bolt' /opt/homebrew/etc/neo4j/neo4j.conf"
    puts "   Should see: dbms.connector.bolt.enabled=true"
  rescue Neo4j::Driver::Exceptions::AuthenticationException => e
    puts "\n❌ Authentication failed: #{e.message}"
    puts "\nTroubleshooting steps:"
    puts "1. Check your Neo4j password"
    puts "2. Try using cypher-shell to verify credentials:"
    puts "   cypher-shell -u neo4j -p LRzzbVvRv86xXKbpudk- 'RETURN 1'"
  rescue StandardError => e
    puts "\n❌ Unexpected error: #{e.class}: #{e.message}"
    puts "Backtrace:"
    puts e.backtrace.first(10).join("\n")
  ensure
    driver&.close
  end

  false
end

def port_open?(host, port, timeout_seconds = 2)
  Timeout.timeout(timeout_seconds) do
    s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    sockaddr = Socket.sockaddr_in(port, host)
    s.connect(sockaddr)
    s.close
    return true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    return false
  end
rescue Timeout::Error
  false
end

# Run the test
if test_connection
  puts "\n✅ Connection test successful!"
else
  puts "\n❌ Connection test failed. Please check the error messages above."
  exit 1
end
