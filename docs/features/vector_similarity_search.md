# Vector Similarity Search for Node Deduplication

## Prerequisites

### Required Neo4j Plugins

1. **GenAI Plugin** (v2025.06.0)
   - Provides vector indexes and vector functions for similarity calculations
   - Enables creation of vector embeddings using GenAI providers
   - Required for: Vector similarity search functionality

2. **Graph Data Science (GDS) Plugin** (v2.19.0)
   - Provides analytical capabilities including similarity algorithms
   - Includes graph algorithms, node embeddings, and machine learning pipelines
   - Required for: Advanced graph analytics and similarity calculations

### Installation

1. Install Neo4j Desktop if not already installed:
   ```bash
   brew install --cask neo4j
   ```

2. Open Neo4j Desktop and create a new database

3. Install the required plugins:
   - Go to your database in Neo4j Desktop
   - Click on the "Plugins" tab
   - Install both "GenAI" and "Graph Data Science" plugins
   - Restart the database after installation

4. Verify installation by running in Neo4j Browser:
   ```cypher
   CALL gds.version()
   CALL genai.version()
   ```

## Purpose
Enhance node deduplication by finding semantically similar nodes using vector embeddings from OpenAI.

## Implementation Details

### 1. `NodeImporter`
- **File**: `app/services/neo4j/import/node_importer.rb`
- **Features**:
  - Uses `OpenAI::EmbeddingService` for embedding generation
  - Uses `OpenAI::ChatService` for AI verification of matches
  - Falls back to vector similarity search after exact matching
  - Updates embeddings when nodes are created or updated
  - Configurable similarity threshold (default: 0.8)

### 2. Vector Index
- **Migration**: `db/migrate/*_add_vector_index_for_embeddings.rb`
  - Creates a vector index on node embeddings
  - Uses cosine similarity for vector comparisons
  - Configurable dimensions (default: 1536 for text-embedding-3-small)

### 3. Configuration
- **File**: `config/initializers/vector_search.rb`
- **Environment Variables**:
  - `VECTOR_SEARCH_ENABLED`: Enable/disable vector search (default: true)
  - `VECTOR_SIMILARITY_THRESHOLD`: Minimum similarity score (0-1, default: 0.8)
  - `EMBEDDING_MODEL`: OpenAI model for embeddings (default: text-embedding-3-small)
  - `CHAT_MODEL`: OpenAI model for verification (default: gpt-4)

## Usage

### Basic Usage
```ruby
# In your import code
importer = Neo4j::Import::NodeImporter.new(
  logger: Rails.logger,
  dry_run: false,
  enable_vector_search: true,  # Can be overridden via config
  similarity_threshold: 0.8    # Can be overridden via config
)

# Import nodes as usual
importer.import(nodes)
```

### Testing
Run the test script to verify the functionality:
```bash
bundle exec rails runner scripts/test_vector_similarity.rb
```

## How It Works

1. **During Import**:
   - For each node, first try exact property matching
   - If no exact match found, generate an embedding for the node
   - Query for similar nodes using vector similarity
   - If matches found, verify with OpenAI chat for semantic similarity
   - Update or create node based on results

2. **Vector Search**:
   - Uses Neo4j's GDS plugin for cosine similarity
   - Only considers nodes with non-null embeddings
   - Returns top 5 matches by similarity score

3. **AI Verification**:
   - Sends top matches to OpenAI for verification
   - Considers nodes as matches if confidence > threshold
   - Includes reasoning in logs for debugging

## Performance Considerations

- **Embedding Generation**:
  - Cached per node to avoid redundant API calls
  - Only regenerated when node properties change

- **Vector Index**:
  - Ensure the vector index is properly created
  - Monitor index size and performance

- **API Usage**:
  - OpenAI API calls are made for both embeddings and verification
  - Consider rate limits and costs when processing large datasets

## Troubleshooting

1. **Missing Vector Index**:
   ```ruby
   # Create the vector index
   Neo4j::DatabaseService.write_transaction do |tx|
     tx.run(<<~CYPHER)
       CREATE VECTOR INDEX `node-embeddings` 
       FOR (n) ON (n.embedding) 
       OPTIONS {
         indexConfig: {
           `vector.dimensions`: 1536,
           `vector.similarity_function`: 'cosine'
         }
       }
     CYPHER
   end
   ```

2. **Debugging**:
   - Set `DEBUG=true` for detailed logs
   - Check OpenAI API responses for verification details
   - Monitor Neo4j logs for query performance
