# GraphRAG with Neo4j Community Edition: Implementation Guide

This guide outlines how to set up a **GraphRAG** system using **Neo4j Community Edition** for a personal assistant framework, managing a knowledgebase of contacts, events, and interests. The stack leverages Microsoft GraphRAG for entity extraction and retrieval, with Neo4j for graph and vector storage, suitable for prototyping and potential scaling to millions of users.

## Prerequisites
- **Neo4j Community Edition**: Install Neo4j (version 5.11 or later for vector index support). Download from https://neo4j.com/download/.
- **Python 3.9+**: For GraphRAG and related libraries.
- **Microsoft GraphRAG**: Install via `pip install graphrag`.
- **LLM API Key**: OpenAI API key (e.g., for GPT-4) or local LLM (e.g., Llama 3.1 via Ollama).
- **Optional**: spaCy (`pip install spacy`) or Hugging Face transformers for custom entity extraction.

## Stack Components
- **Graph Database**: Neo4j Community Edition (v5.11+), storing knowledge graphs (nodes: `User`, `Person`, `Event`, `Interest`; edges: `OWNS`, `ATTENDED`, `FRIEND_OF`) and vector embeddings.
- **RAG Framework**: Microsoft GraphRAG for entity extraction, knowledge graph construction, and hybrid retrieval (graph + vector search).
- **LLM**: OpenAI GPT-4 or local Llama 3.1 for entity extraction and response generation.
- **Vector Storage**: Neo4j’s built-in vector indexes for semantic search.
- **API Layer**: Optional GraphQL API using `graphql-neo4j` for structured querying.

## Implementation Steps

1. **Set Up Neo4j Community Edition**:
   - Install Neo4j Community Edition (https://neo4j.com/docs/operations-manual/current/installation/).
   - Start the Neo4j server: `neo4j start`.
   - Access Neo4j Browser at `http://localhost:7474` (default credentials: `neo4j/neo4j`).
   - Create a database and enable vector index support:
     ```cypher
     CALL db.index.vector.createNodeIndex('entity-embeddings', 'Entity', 'embedding', 1536, 'cosine')
     ```

2. **Install and Configure GraphRAG**:
   - Install GraphRAG: `pip install graphrag`.
   - Create a project directory (e.g., `personal-assistant`).
   - Initialize GraphRAG configuration:
     ```bash
     graphrag init --dir ./personal-assistant
     ```
   - Edit `settings.yaml` in the project directory:
     ```yaml
     llm:
       api_key: "your_openai_api_key"
       model: "gpt-4"
     storage:
       type: neo4j
       uri: "neo4j://localhost:7687"
       username: "neo4j"
       password: "your_password"
     embeddings:
       provider: openai
       model: "text-embedding-ada-002"
     ```
   - This configures GraphRAG to use Neo4j for graph storage and OpenAI for embeddings.

3. **Prepare Input Data**:
   - Collect personal data (e.g., journal entries, calendars, emails) in text format (e.g., `input.txt`).
   - Example input:
     ```
     I attended a birthday party with Alice on July 1, 2023. We both enjoy hiking.
     ```
   - Place input files in the `./personal-assistant/input` directory.

4. **Run GraphRAG Indexing**:
   - Extract entities (e.g., `Person:Alice`, `Event:Birthday Party`, `Interest:Hiking`) and build the knowledge graph:
     ```bash
     graphrag index --dir ./personal-assistant
     ```
   - GraphRAG processes input files, extracts entities/relationships using the LLM, and stores them in Neo4j as nodes and edges. Embeddings are stored in Neo4j’s vector index.

5. **Define Schema in Neo4j**:
   - Create a schema for user-specific subgraphs to support multi-tenancy:
     ```cypher
     CREATE CONSTRAINT user_id_unique IF NOT EXISTS FOR (u:User) REQUIRE u.user_id IS UNIQUE;
     CREATE (u:User {user_id: "123", name: "YourName"});
     CREATE (p:Person {name: "Alice", embedding: [0.1, 0.2, ...]})-[:OWNS {user_id: "123"}]->(u);
     CREATE (e:Event {name: "Birthday 2023", date: "2023-07-01"})-[:OWNS {user_id: "123"}]->(u);
     CREATE (i:Interest {name: "Hiking"})-[:OWNS {user_id: "123"}]->(u);
     CREATE (p)-[:ATTENDED]->(e);
     CREATE (p)-[:INTERESTED_IN]->(i);
     ```
   - The `user_id` property ensures data isolation for multi-tenancy.

6. **Query the Knowledgebase**:
   - Use GraphRAG for hybrid retrieval (graph + vector search):
     ```bash
     graphrag query --dir ./personal-assistant --query "Who attended my birthday in 2023?"
     ```
   - Example Cypher query for manual retrieval:
     ```cypher
     MATCH (u:User {user_id: "123"})-[:OWNS]->(p:Person)-[:ATTENDED]->(e:Event {name: "Birthday 2023"})
     RETURN p.name
     ```
   - For vector search:
     ```cypher
     CALL db.index.vector.queryNodes('entity-embeddings', 10, [0.1, 0.2, ...])
     YIELD node, score
     MATCH (node)-[:OWNS {user_id: "123"}]->(:User)
     RETURN node.name, score
     ```

7. **Optional: Add GraphQL API**:
   - Install `graphql-neo4j` (https://github.com/neo4j-graphql/neo4j-graphql-py):
     ```bash
     pip install neo4j-graphql
     ```
   - Define a GraphQL schema:
     ```graphql
     type User {
       user_id: ID!
       name: String
       events: [Event] @relation(name: "OWNS")
     }
     type Event {
       name: String
       date: String
       attendees: [Person] @relation(name: "ATTENDED")
     }
     type Person {
       name: String
       interests: [Interest] @relation(name: "INTERESTED_IN")
     }
     type Interest {
       name: String
     }
     type Query {
       user(id: ID!): User
     }
     ```
   - Deploy a GraphQL server to query the knowledgebase (e.g., `query { user(id: "123") { events { name } } }`).

8. **Scale Considerations**:
   - **Neo4j Community Limitations**: Single-node, limited to machine resources. Suitable for prototyping but not for millions of users.
   - **Scaling Path**: Migrate to **Neo4j Aura Enterprise** (https://neo4j.com/cloud/aura) for clustering, auto-scaling, and multi-tenancy (subgraphs via `user_id`).
   - **Optimization**: Index `user_id` (`CREATE INDEX FOR (u:User) ON (u.user_id)`) and optimize vector queries for performance.
   - **Cost**: Community Edition is free; Aura Enterprise requires contacting Neo4j for pricing.

## Example Workflow
- **Input**: Journal entry: “I attended a birthday party with Alice on July 1, 2023. We both enjoy hiking.”
- **GraphRAG Output**: Nodes (`Person:Alice`, `Event:Birthday 2023`, `Interest:Hiking`), edges (`Alice-[:ATTENDED]->Birthday`, `Alice-[:INTERESTED_IN]->Hiking`), stored in Neo4j.
- **Query**: “Who shares my hiking interest?” retrieves `Alice` via vector search and graph traversal.
- **GraphQL Query**:
  ```graphql
  query {
    user(id: "123") {
      name
      events { name }
      persons { name, interests { name } }
    }
  }
  ```

## Notes
- **Entity Extraction**: Microsoft GraphRAG uses LLMs for robust extraction but can be customized with spaCy (`python -m spacy download en_core_web_sm`) for lightweight processing.
- **Local LLM**: Use Ollama with Llama 3.1 to reduce costs (e.g., `ollama run llama3.1`).
- **Scaling**: For millions of users, plan for Neo4j Aura Enterprise with RBAC for multi-tenancy and clustering for high throughput.
- **Resources**:
  - Neo4j Documentation: https://neo4j.com/docs
  - GraphRAG GitHub: https://github.com/microsoft/graphrag
  - Neo4j GraphQL: https://neo4j.com/docs/graphql
