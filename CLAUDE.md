# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Archimedes is a Personal Assistant RAG (Retrieval-Augmented Generation) system built with Ruby on Rails. It extracts entities from uploaded content using OpenAI, creates knowledge graphs in Neo4j, and provides semantic search capabilities. The system analyzes documents, images, and text to build a comprehensive knowledge base about personal information.

## Core Architecture

### Service Layer Architecture
- **Content Analysis**: `app/services/content_analysis_service.rb` - Main orchestrator for processing uploaded content
- **Entity Processing**: `app/services/entity_extraction_service.rb` - Extracts and creates entities from analyzed content
- **Neo4j Services**: `app/services/neo4j/` - Graph database operations including import, deduplication, and querying
- **OpenAI Integration**: `app/services/openai/` - AI model interactions for content analysis and embeddings

### Neo4j Knowledge Graph
- **Database Service**: `app/services/neo4j/database_service.rb` - Core Neo4j connection and transaction management
- **Import System**: `app/services/neo4j/import/` - Handles bulk import of entities and relationships
- **Node Matching**: Uses vector similarity search and fuzzy matching for entity deduplication
- **Vector Search**: `app/services/neo4j/import/vector_search.rb` - Semantic similarity using OpenAI embeddings

### Data Models
- **Content**: Uploaded documents/images with extracted text
- **Entity**: Knowledge graph nodes (Person, Address, Task, etc.)
- **Statement**: Relationships between entities
- **Verification Request**: Pending entity merges requiring user confirmation

## Development Commands

### Database Operations
```bash
# Standard Rails database operations
rails db:create
rails db:migrate
rails db:seed

# Neo4j operations
rails neo4j:clear                    # Clear Neo4j database
rails neo4j:import                   # Import entities from PostgreSQL to Neo4j
rails neo4j:migrate                  # Run Neo4j migrations
```

### Testing
```bash
# Run RSpec test suite
bundle exec rspec

# Run specific test files
bundle exec rspec spec/models/content_spec.rb
bundle exec rspec spec/services/neo4j/

# Run tests with coverage
COVERAGE=true bundle exec rspec
```

### Linting and Code Quality
```bash
# Run RuboCop linter
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a

# Run specific RuboCop cops
bundle exec rubocop --only Style/StringLiterals
```

### Asset Building
```bash
# Build JavaScript assets
npm run build

# Build CSS assets
npm run build:css

# Watch for changes during development
npm run build -- --watch
```

### Background Jobs
```bash
# Start Sidekiq for background processing
bundle exec sidekiq

# Run specific job
rails runner "OpenAI::EmbeddingJob.perform_now(content_id)"
```

## Key Configuration

### Environment Variables
Required environment variables for development:
- `NEO4J_URL` - Neo4j database URL (e.g., `bolt://localhost:7687`)
- `NEO4J_USERNAME` - Neo4j username
- `NEO4J_PASSWORD` - Neo4j password  
- `OPENAI_API_KEY` - OpenAI API key for content analysis and embeddings

### Database Configuration
- **PostgreSQL**: Primary database with pgvector extension for embeddings
- **Neo4j**: Graph database for knowledge graph storage and traversal
- **Vector Search**: Uses OpenAI embeddings stored in both PostgreSQL and Neo4j

## Testing Strategy

### Test Structure
- **Models**: `spec/models/` - ActiveRecord model tests
- **Services**: `spec/services/` - Business logic and service object tests
- **Controllers**: `spec/requests/` - API endpoint tests
- **Factories**: `spec/factories/` - FactoryBot data generation

### Test Dependencies
- **RSpec**: Main testing framework
- **FactoryBot**: Test data generation
- **WebMock**: HTTP request mocking for external APIs
- **Database Cleaner**: Test database cleanup
- **Shoulda Matchers**: Rails-specific test matchers

### Running Tests
Always run the full test suite before committing:
```bash
bundle exec rspec
```

## AI Integration Patterns

### OpenAI Service Usage
- All OpenAI calls are abstracted through `OpenAI::ClientService`
- Responses are parsed and validated through `OpenAI::ResponseParserService`
- Entity extraction uses structured prompts with taxonomies
- Embeddings are generated for semantic similarity matching

### Content Processing Pipeline
1. **Upload** - Content uploaded through Rails controllers
2. **Analysis** - OpenAI extracts entities and relationships
3. **Storage** - Entities stored in PostgreSQL with embeddings
4. **Graph Import** - Entities imported to Neo4j with deduplication
5. **Verification** - Ambiguous entities queued for user confirmation

## Neo4j Integration

### Import Process
The Neo4j import system handles:
- **Node Creation**: Creates typed nodes with properties
- **Relationship Creation**: Establishes connections between entities
- **Deduplication**: Uses vector similarity and fuzzy matching
- **Batching**: Processes large datasets efficiently

### Node Matching Strategy
- **Vector Similarity**: Primary matching using OpenAI embeddings
- **Fuzzy Matching**: Fallback using string similarity and business rules
- **Type-Specific Logic**: Different matching strategies per entity type
- **Confidence Scoring**: Matches above threshold are automatic, others require verification

## Important Development Notes

### Vector Search Implementation
The system uses a sophisticated node matching system with type-specific strategies:
- **Address Nodes**: Normalize street abbreviations and state codes
- **Person Nodes**: Match on email, phone, or name variations
- **Task Nodes**: Semantic similarity on title and description
- **Document Nodes**: Content-based matching with file hash fallbacks

### Entity Taxonomy
Entities follow a structured taxonomy defined in `app/services/openai/entity_taxonomy.yml`:
- **Core Entities**: Person, Address, ContactMethod
- **Time-based**: Event, Task, Reminder
- **Productivity**: List, ListItem, Project, Milestone
- **Knowledge**: Note, Document, Photo
- **Assets**: Asset, Property

### Performance Considerations
- **Embedding Generation**: Batched for efficiency, cached when possible
- **Neo4j Transactions**: Use read/write transactions appropriately
- **Database Connections**: Properly managed through connection pooling
- **Memory Usage**: Large imports are processed in batches

## Troubleshooting

### Common Issues
- **Neo4j Connection**: Ensure Neo4j is running and environment variables are set
- **OpenAI API**: Check API key and rate limits
- **Vector Search**: Verify pgvector extension is installed
- **Memory Issues**: Reduce batch sizes for large imports

### Debugging
- Enable debug logging with `ENV["DEBUG"] = "true"`
- Check logs in `log/development.log` and `log/openai.log`
- Use Rails console for interactive debugging: `rails console`

## Architecture Decisions

### Why Neo4j + PostgreSQL?
- **PostgreSQL**: Excellent for structured data, ACID compliance, and vector search
- **Neo4j**: Superior for graph traversal, relationship queries, and visualization
- **Hybrid Approach**: Leverages strengths of both databases

### Why OpenAI Integration?
- **Multimodal Analysis**: Handles text, images, and documents
- **Structured Extraction**: Reliable entity and relationship extraction
- **Semantic Embeddings**: Enables similarity matching and search
- **Future Migration**: Service abstraction allows for local model migration

This architecture provides a robust foundation for personal knowledge management while maintaining clear separation of concerns and extensibility for future enhancements.