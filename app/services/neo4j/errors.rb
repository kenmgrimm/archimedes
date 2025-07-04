module Neo4j
  # Base error class for all Neo4j service errors
  class Error < StandardError; end

  # Raised when document processing fails
  class ProcessingError < Error; end

  # Raised when a query is invalid or cannot be executed
  class QueryError < Error; end

  # Raised when entity extraction fails
  class ExtractionError < Error; end

  # Raised when there are issues with the Neo4j connection
  class ConnectionError < Error; end
end
