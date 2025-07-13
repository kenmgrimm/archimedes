class AddVectorIndexForEmbeddings < Neo4j::Migrations::Base
  def up
    # Create vector index if it doesn't exist
    execute <<~CYPHER
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

  def down
    # Drop the vector index
    execute 'DROP INDEX `node-embeddings` IF EXISTS'
  end
end
