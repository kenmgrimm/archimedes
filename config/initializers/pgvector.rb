# frozen_string_literal: true

# Configure Rails to ignore unknown OIDs from pgvector extension
# This suppresses warnings like "unknown OID: failed to recognize type of vector column"
if defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.ignore_unknown_oids = true
  
  Rails.logger.debug { "[PGVector] Configured ActiveRecord to ignore unknown OIDs for vector columns" }
end
