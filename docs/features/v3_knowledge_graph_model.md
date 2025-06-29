# V3 Data Model: Knowledge Graph Architecture

## Overview

This document outlines the V3 data model for the Archimedes application, evolving from the V2 entity-statement architecture to a more structured knowledge graph model. The V3 model maintains the flexibility of V2 while adding proper knowledge graph semantics, improved entity management, and a user-driven verification workflow.

## Key Concepts

### Knowledge Graph

A knowledge graph is a structured representation of knowledge where:
- **Entities** are represented as nodes
- **Statements** (triples) form the edges that connect entities
- **Literals** are simple values that describe entities

This structure allows for powerful querying, inference, and relationship discovery.

### Entity (Node)

In the V3 model, an entity represents a unique concept, person, organization, or thing that can have relationships with other entities. Each entity:

- Has a unique identifier
- Has a canonical name
- Has a name_embedding for similarity search
- May be associated with multiple statements
- Can be linked to source content

### Statement (Triple)

A statement follows the RDF (Resource Description Framework) triple format of subject-predicate-object. Each statement:

- Has a subject entity (the source node)
- Has a predicate (the relationship type)
- Has an object (either another entity or a literal value)
- Includes an object_type field to distinguish between entity and literal objects
- Has a confidence score
- Can be traced back to source content
- Is vectorized for semantic search

### Literal

A literal is a simple value that describes an entity but cannot have relationships of its own. Examples include:
- Dates
- Measurements
- Identification numbers
- Text values

## Data Model Changes

### V2 Model

```
Content
  |
  +-- has many --> Entities
                     |
                     +-- has attributes: name, name_embedding
                     |
                     +-- has many --> Statements
                                        |
                                        +-- has attributes: text, text_embedding, object_entity_id (optional)
```

### V3 Model

```
Content
  |
  +-- has many --> Entities (Nodes)
                     |
                     +-- has attributes: name, name_embedding
                     |
                     +-- has many --> Statements (Triples)
                                        |
                                        +-- has attributes: predicate, object, object_type, confidence, text_embedding
```

## Database Schema Changes

### Statement Table Changes

| Field | V2 | V3 | Notes |
|-------|----|----|-------|
| id | ✓ | ✓ | Primary key |
| entity_id | ✓ | ✓ | Foreign key to subject entity |
| object_entity_id | ✓ | ✓ | Optional foreign key to object entity (for entity objects) |
| text | ✓ | ✗ | Replaced by structured fields |
| predicate | ✗ | ✓ | The relationship type |
| object | ✗ | ✓ | The object value (entity name or literal value) |
| object_type | ✗ | ✓ | "entity" or "literal" |
| text_embedding | ✓ | ✓ | Vector representation of the complete statement |
| confidence | ✓ | ✓ | Score from 0.0 to 1.0 |
| content_id | ✓ | ✓ | Foreign key to source content |
| created_at | ✓ | ✓ | Timestamp |
| updated_at | ✓ | ✓ | Timestamp |

## User Workflow Changes

### V2 Workflow

1. User uploads content
2. System analyzes content and extracts entities and statements
3. Entities and statements are automatically created
4. User can view and edit entities and statements

### V3 Workflow

1. User uploads content
2. System analyzes content and extracts candidate entities and statements
3. System uses vector search to find potential matching existing entities
4. User is presented with entity choices:
   - Use an existing entity (from similar matches)
   - Create a new entity
   - Merge entities
5. Once entities are confirmed, statements are created
6. User can view, edit, and manage the knowledge graph

## Implementation Details

### Entity Deduplication

The V3 model introduces a robust entity deduplication process:

1. When new entities are detected, vector similarity search finds potential matches
2. User is presented with match options and confidence scores
3. User selects the appropriate entity or creates a new one
4. System maintains a clean knowledge graph with minimal duplication

### Entity Merging

When duplicate entities are identified:

1. User selects a source entity and target entity
2. All statements from the source entity are transferred to the target entity
3. References to the source entity are updated to point to the target entity
4. The source entity is marked as merged or deleted

### Statement Structure

Statements now follow a strict subject-predicate-object format:

1. Subject: Always an entity (node)
2. Predicate: The relationship type (edge)
3. Object: Either an entity (node) or a literal value
4. Object Type: Explicitly marked as "entity" or "literal"

### OpenAI Prompt Updates

The content analysis prompts have been updated to:

1. Explicitly instruct the AI to build a knowledge graph
2. Use proper knowledge graph terminology
3. Distinguish between entities and literals
4. Generate directional relationships with clear semantics
5. Use consistent predicate terminology

## Migration Plan

1. Create a database migration to add new fields to the Statement model
2. Update the ContentAnalysisService to use the new knowledge graph format
3. Implement entity deduplication and suggestion UI
4. Develop entity merging functionality
5. Update existing reports and views to use the new data structure

## Debug Logging

Comprehensive debug logging will be implemented throughout:

```ruby
# Entity suggestion process
Rails.logger.debug { "Found #{similar_entities.count} potential matches for '#{entity_name}'" } if ENV["DEBUG"]

# Entity selection
Rails.logger.debug { "User selected entity ##{selected_entity.id} for '#{candidate_entity}'" } if ENV["DEBUG"]

# Entity merging
Rails.logger.debug { "Merging entity ##{source_id} into ##{target_id}" } if ENV["DEBUG"]
Rails.logger.debug { "Transferred #{transferred_statements.count} statements during merge" } if ENV["DEBUG"]
```

## Benefits

1. **Cleaner Data Model**: Proper knowledge graph structure with clear semantics
2. **Better Entity Management**: Reduced duplication through user verification
3. **More Accurate Relationships**: Structured triples with entity/literal distinction
4. **Improved Querying**: Ability to traverse the graph in multiple directions
5. **Enhanced User Control**: Users verify and manage entity matching

## Conclusion

The V3 Knowledge Graph model represents a significant improvement in how Archimedes structures and manages information. By adopting standard knowledge graph practices and terminology while adding user verification, we create a more accurate, flexible, and powerful system for knowledge extraction and management.

---

This document is intended to guide the implementation of the V3 data model in the Archimedes application. Implementation details and specific code changes will be developed based on this architectural overview.
