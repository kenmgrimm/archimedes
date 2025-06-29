# Neo4j Implementation Guide: Entities, Relationships, Vectorization, Querying, Visualization

## 1. Entity and Relationship Creation

### Example: Creating People, Mountains, and Relationships
```cypher
CREATE (k:Person {name: 'Kaiser Soze', hobby: 'mountaineering', location: 'Colorado'})
CREATE (n:Person {name: 'Nancy Soze', location: 'Colorado'})
CREATE (m:Mountain {name: 'Mount Elbert', elevation: 14440, location: 'Colorado'})
CREATE (k)-[:MARRIED_TO]->(n)
CREATE (k)-[:CLIMBED]->(m)
CREATE (n)-[:CLIMBED]->(m)
```

## 2. Vectorization (Embeddings)

- **Native vector indexes:** Neo4j supports native vector indexes and similarity search as of 5.13+ (GA).
- **Embedding generation:** You still generate embeddings externally (e.g., OpenAI, Cohere, local model), then store them as a property on nodes or relationships.

### Example Workflow
1. **Generate embedding** (external):
   ```python
   embedding = openai_client.embeddings('Kaiser Soze mountaineering Colorado')
   ```
2. **Store embedding in Neo4j** (as a property):
   ```cypher
   MATCH (k:Person {name: 'Kaiser Soze'})
   SET k.embedding = [0.123, 0.456, ...]
   ```
3. **Create a vector index** (one time):
   ```cypher
   CREATE VECTOR INDEX personEmbeddings IF NOT EXISTS FOR (p:Person) ON p.embedding OPTIONS { indexConfig: { `vector.dimensions`: 1536, `vector.similarity_function`: 'cosine' } }
   ```
4. **Query the vector index** (find similar people):
   ```cypher
   CALL db.index.vector.queryNodes('personEmbeddings', 5, $kaiserEmbedding)
   YIELD node, score
   RETURN node.name, score
   ```

- **Note:** Neo4j does not perform automatic vectorization (embedding generation) itself; you must provide the embedding.
- **But:** Once stored, all indexing, similarity search, and graph traversal are native and highly performant.

## 3. Querying: Vector Search & Graph Traversal

### Vector Similarity Search
```cypher
// Find top 5 people similar to Kaiser (by vector)
CALL db.index.vector.queryNodes('person_embeddings', 5, $kaiserEmbedding)
YIELD node, score
RETURN node.name, score
```

### Graph Traversal
```cypher
// Find all mountains climbed by people married to Kaiser
MATCH (k:Person {name: 'Kaiser Soze'})-[:MARRIED_TO]->(spouse)-[:CLIMBED]->(m:Mountain)
RETURN spouse.name, m.name
```

## 4. Deduplication (Entity Resolution)

- **Manual process:** Use vector similarity + property matching
```cypher
// Find potential duplicates for Kaiser Soze
CALL db.index.vector.queryNodes('person_embeddings', 10, $kaiserEmbedding)
YIELD node, score
WHERE node.name <> 'Kaiser Soze' AND score > 0.9
RETURN node.name, score
```

## 5. Visualization

- **Neo4j Browser**: Built-in graph visualization (web UI at http://localhost:7474)
- **Bloom**: Advanced visualization tool (commercial)
- **Export**: Use APOC procedures to export to D3.js/Cytoscape

---

### Summary Table
| Feature            | Neo4j Approach                                      |
|--------------------|-----------------------------------------------------|
| Entity Creation    | Cypher CREATE (node {props})                        |
| Relationship      | Cypher CREATE (a)-[:REL]->(b)                       |
| Vectorization     | Native vector index (embedding generation external)   |
| Vector Search     | Native, db.index.vector.queryNodes                   |
| Graph Traversal   | Cypher MATCH patterns                                |
| Deduplication     | Vector + property matching, manual                   |
| Visualization     | Neo4j Browser, Bloom, export to D3/Cytoscape         |
