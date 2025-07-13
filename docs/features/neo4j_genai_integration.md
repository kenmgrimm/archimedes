# Neo4j GenAI Integration Feature

## Overview
This document outlines the migration plan from our current custom similarity matching implementation to Neo4j's native GenAI capabilities. The GenAI plugin is already installed in our Neo4j instance, so this is primarily a refactoring effort.

## Current Implementation
- Custom Ruby-based similarity matching using Levenshtein distance
- Manual vector similarity calculations in Ruby
- Separate embedding generation and storage
- Custom query logic for similarity searches

## Benefits of Migration
1. **Performance**: Native vector operations in the database
2. **Simplified Codebase**: Remove custom similarity logic
3. **Advanced Features**: Access to Neo4j's built-in AI functions
4. **Maintainability**: Standardized approach using database-native features

## Migration Plan

### Phase 1: Setup and Configuration
- [ ] Verify GenAI plugin installation and version compatibility
- [ ] Configure embedding model (e.g., `text-embedding-3-large`)
- [ ] Set up vector indexes for similarity search

### Phase 2: Data Model Updates
- [ ] Add vector storage properties to relevant nodes
- [ ] Create migration for existing data
- [ ] Update schema documentation

### Phase 3: Code Refactoring
- [ ] Replace custom similarity methods with Neo4j GenAI functions
- [ ] Update query builders to use new vector functions
- [ ] Refactor embedding generation to use native functions

### Phase 4: Testing and Validation
- [ ] Verify matching accuracy
- [ ] Performance benchmarking
- [ ] Edge case testing

## Implementation Details

### Vector Index Creation
```cypher
// Create vector index for Address nodes
CREATE VECTOR INDEX `address-embeddings` 
FOR (n:Address) 
ON (n.embedding) 
OPTIONS {
  indexConfig: {
    `vector.dimensions`: 1536,
    `vector.similarity_function`: 'cosine'
  }
}
```

### Similarity Search Query
```cypher
// Find similar addresses using vector similarity
MATCH (a:Address)
WHERE id(a) = $addressId
WITH a, a.embedding AS embedding
MATCH (b:Address)
WHERE id(b) <> $addressId
WITH b, gds.similarity.cosine(embedding, b.embedding) AS similarity
WHERE similarity > 0.8
RETURN b, similarity
ORDER BY similarity DESC
LIMIT 10
```

### Ruby Integration
```ruby
def find_similar_addresses(address_id, threshold: 0.8, limit: 10)
  query = <<~CYPHER
    MATCH (a:Address)
    WHERE id(a) = $address_id
    WITH a, a.embedding AS embedding
    MATCH (b:Address)
    WHERE id(b) <> $address_id
    WITH b, gds.similarity.cosine(embedding, b.embedding) AS similarity
    WHERE similarity > $threshold
    RETURN b, similarity
    ORDER BY similarity DESC
    LIMIT $limit
  CYPHER
  
  Neo4j::DatabaseService.read_transaction do |tx|
    tx.run(query, address_id: address_id, threshold: threshold, limit: limit)
  end
end
```

## Performance Considerations
- **Indexing**: Ensure proper vector indexes are in place
- **Batch Processing**: For initial embedding generation
- **Query Optimization**: Monitor and optimize similarity search queries

## Rollback Plan
1. Keep existing code during initial rollout
2. Feature flag the new implementation
3. Maintain parallel implementations during testing
4. Full rollback capability by reverting to previous version

## Future Enhancements
1. Hybrid search combining vector and graph patterns
2. Automatic embedding updates on node changes
3. Integration with Neo4j's full-text search
4. Support for multiple embedding models

## Dependencies
- Neo4j 5.11+
- Neo4j GenAI plugin
- Appropriate model access/API keys

## Related Documents
- [Embedding Strategy](./embedding_strategy.md)
- [Neo4j Implementation Guide](../architecture/database_storage/neo4j_implementation_guide.md)
- [Vector Similarity Search](./vector_similarity_search.md)
