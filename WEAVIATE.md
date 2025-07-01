# Weaviate Knowledge Graph Integration

This document provides a comprehensive guide to the Weaviate vector search and knowledge graph functionality in the Archimedes application.

## Table of Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Running Weaviate with Docker](#running-weaviate-with-docker)
- [Seeding Data](#seeding-data)
- [Visualizing the Knowledge Graph](#visualizing-the-knowledge-graph)
- [Exploring Data](#exploring-data)
- [Key Components](#key-components)
- [Troubleshooting](#troubleshooting)
- [Development Notes](#development-notes)

## Overview

This application uses [Weaviate](https://weaviate.io/) as a vector database to power a knowledge graph that connects various entities (People, Documents, Projects, etc.) with rich relationships. The implementation includes:

- Vector embeddings for semantic search
- Graph relationships between entities
- Interactive visualization
- Data import/export capabilities

## Quick Start

1. Start Weaviate:
   ```bash
   docker-compose up weaviate
   ```

2. Seed the database with sample data:
   ```bash
   bundle exec rake "weaviate:seed_pooh[true]"
   ```

3. Start the Rails server:
   ```bash
   bin/dev
   ```

4. Access the knowledge graph visualization:
   - Main visualization: http://localhost:3000/visualizations/knowledge_graph
   - Connection statistics: http://localhost:3000/visualizations/connection_stats.json

## Running Weaviate with Docker

Weaviate runs as a Docker container defined in `docker-compose.yml`. Key configuration:

```yaml
weaviate:
  image: semitechnologies/weaviate:1.20.0
  ports:
    - "8080:8080"
  environment:
    QUERY_DEFAULTS_LIMIT: 25
    AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
    PERSISTENCE_DATA_PATH: "/var/lib/weaviate"
    DEFAULT_VECTORIZER_MODULE: "none"
    CLUSTER_HOSTNAME: "node1"
  volumes:
    - weaviate_data:/var/lib/weaviate
```

To start Weaviate:
```bash
docker-compose up -d weaviate
```

## Seeding Data

The system includes a comprehensive seed system that loads data from YAML fixtures and creates corresponding Weaviate objects with proper relationships.

### Main Seed Task
```bash
# Full seed with verbose output
bundle exec rake "weaviate:seed_pooh[true]"

# Silent mode (no output)
bundle exec rake weaviate:seed_pooh
```

### Seed Data Locations
- `db/weaviate_seeds/data/winnie_the_pooh_data.rb` - Main seed data definition
- `test/fixtures/winnie_the_pooh/` - YAML fixture files
  - `people.yml`
  - `pets.yml`
  - `vehicles.yml`
  - `documents.yml`
  - `projects.yml`
  - `lists.yml`

## Visualizing the Knowledge Graph

The application includes an interactive knowledge graph visualization built with D3.js.

### Accessing Visualizations
- **Interactive Graph**: http://localhost:3000/visualizations/knowledge_graph
- **Connection Statistics**: http://localhost:3000/visualizations/connection_stats.json

### Features
- Interactive zooming and panning
- Node selection for details
- Color-coded by entity type
- Force-directed layout

## Pros and Cons of Weaviate Implementation

### Strengths

1. **Built-in Vector Search**
   - Automatic vector embeddings for semantic search
   - Native support for similarity searches
   - Easy integration with machine learning models

2. **Developer Experience**
   - Comprehensive GraphQL API
   - Well-documented REST endpoints
   - Active community and good documentation

3. **Performance**
   - Fast vector search capabilities
   - Efficient storage of embeddings
   - Good horizontal scaling options

4. **Flexibility**
   - Schema-less design with optional schema validation
   - Support for custom modules and extensions
   - Multi-tenancy support

### Limitations and Challenges

1. **Graph Relationship Limitations**
   - Relationships in Weaviate are simple and cannot contain attributes
   - No support for relationship types or properties on edges
   - Workaround requires either:
     - Creating separate relationship types for each relationship kind, or
     - Using a single generic relationship type

2. **Learning Curve**
   - Complex setup for advanced features
   - Requires understanding of vector search concepts
   - Some operations require direct HTTP calls instead of the Ruby client

3. **Resource Intensive**
   - Can be memory-heavy with large datasets
   - Vector operations are CPU-intensive

## Exploring Data

### Query Tools and Scripts

The `scripts/weaviate_queries/` directory contains several utility scripts for exploring and debugging the Weaviate data:

```bash
# Explore entity relationships and their properties
./scripts/weaviate_queries/explore_entity_relations.sh

# Dump the complete schema with all types and fields
./scripts/weaviate_queries/dump_schema.sh

# Example queries for common operations
./scripts/weaviate_queries/example_queries.sh
```

These scripts demonstrate various Weaviate operations and can be used as templates for building custom queries.

### Weaviate Console and GraphQL

Access the Weaviate GraphQL console at:
http://localhost:8080/v1/graphql

For a more interactive experience, you can use the Weaviate Playground at:
http://localhost:8080/playground

#### Useful GraphQL Patterns

1. **Basic Entity Query with References**
```graphql
{
  Get {
    Person(limit: 5) {
      name
      _additional {
        id
      }
      ... on Person {
        ownsPets {
          ... on Pet {
            name
            species
          }
        }
      }
    }
  }
}
```

2. **Vector Similarity Search**
```graphql
{
  Get {
    Document(
      nearText: {
        concepts: ["honey"],
        certainty: 0.7
      },
      limit: 3
    ) {
      title
      content
      _additional {
        certainty
      }
    }
  }
}
```

Example query:
```graphql
{
  Get {
    Person(limit: 5) {
      name
      _additional {
        id
      }
    }
  }
}
```

## Key Components

### Services
- `WeaviateService` - Core service for Weaviate operations
  - Schema management
  - CRUD operations
  - Reference handling

### Concerns
- `WeaviateVisualization` - Knowledge graph generation and display
- `WeaviateCleanup` - Database maintenance utilities

### Controllers
- `VisualizationsController` - Handles graph visualization endpoints

## Troubleshooting

### Common Issues

#### Connection Errors
- Ensure Weaviate is running: `docker ps | grep weaviate`
- Check logs: `docker-compose logs weaviate`

#### Data Loading Issues
- Clear existing data: `bundle exec rake weaviate:clean`
- Reseed: `bundle exec rake "weaviate:seed_pooh[true]"`

### Logs
- Application logs: `tail -f log/development.log`
- Weaviate logs: `docker-compose logs -f weaviate`

## Development Notes

### Data Model
- All entities are stored with vector embeddings
- Relationships are maintained through Weaviate references
- The schema is defined in `db/weaviate_seeds/schema.rb`

### Adding New Entity Types
1. Add YAML fixtures in `test/fixtures/winnie_the_pooh/`
2. Update the schema in `db/weaviate_seeds/schema.rb`
3. Add seed logic in `db/weaviate_seeds/data/winnie_the_pooh_data.rb`
4. Update visualization colors in `WeaviateVisualization` if needed

### Performance Considerations

1. **Batch Operations**
   - Always use batch operations when creating multiple objects
   - The `batch_references` API is more efficient than individual reference creation

2. **Query Optimization**
   - Use `include: ["all"]` sparingly as it increases response size
   - Be specific about the properties you need in your queries
   - Use pagination for large result sets with `limit` and `offset`

3. **Indexing**
   - Consider adding inverted indexes for frequently filtered properties
   - Use the correct data types for better query performance

## Example Use Cases

1. **Semantic Search**
   - Find documents similar to a query
   - Implement "more like this" functionality
   - Cluster similar content

2. **Knowledge Graph**
   - Visualize relationships between entities
   - Discover indirect connections
   - Analyze network properties

3. **Recommendation Engine**
   - Content-based recommendations
   - User similarity matching
   - Context-aware suggestions

## License

This project is licensed under the terms of the MIT license.
