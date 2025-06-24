# V2 Data Model: Entity-Statement Architecture

## Overview

This document outlines the proposed V2 data model for the Archimedes application, moving from the current entity-centric model to a more flexible entity-statement architecture. This new approach simplifies the conceptual model while enabling more powerful semantic search and relationship mapping.

## Key Concepts

### Entity

In the V2 model, an entity represents a unique concept, person, organization, or thing. Each entity:

- Has a unique identifier
- Has a name (the canonical representation)
- Has a name_embedding for direct entity similarity search
- May be associated with multiple statements
- Does not have a "type" field as in V1 (type information is captured in statements)
- Can be linked to source content

### Statement

A statement is a simple English text description about an entity or a relationship between entities. Each statement:

- Describes a single fact, attribute, or relationship
- Is vectorized for semantic search
- Links to its subject entity (and optionally an object entity for relationships)
- Can be traced back to source content
- May include metadata about confidence, source reliability, etc.

## Data Model Changes

### Current Model (V1)

```
Content
  |
  +-- has many --> Entities
                     |
                     +-- has attributes: type, value, value_embedding
```

### Proposed Model (V2)

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

## Database Schema Changes

### Entity Table Changes

| Field | V1 | V2 | Notes |
|-------|----|----|-------|
| id | ✓ | ✓ | Primary key |
| name | ✗ | ✓ | Replaces "value" |
| value | ✓ | ✗ | Replaced by "name" |
| type | ✓ | ✗ | Removed (captured in statements) |
| value_embedding | ✓ | ✗ | Moved to statements |
| content_id | ✓ | ✓ | Foreign key to source content |
| created_at | ✓ | ✓ | Timestamp |
| updated_at | ✓ | ✓ | Timestamp |

### New Statement Table

| Field | Type | Description |
|-------|------|-------------|
| id | integer | Primary key |
| entity_id | integer | Foreign key to subject entity |
| object_entity_id | integer | Optional foreign key to object entity (for relationships) |
| text | text | The statement text |
| text_embedding | vector | Vector representation of the statement |
| content_id | integer | Foreign key to source content |
| confidence | float | Optional confidence score (0-1) |
| created_at | datetime | Timestamp |
| updated_at | datetime | Timestamp |

## Benefits

1. **Simplified Conceptual Model**: An entity is simply a "thing" with a name, and statements describe it.
2. **More Flexible Relationships**: Statements can express relationships between entities.
3. **Better Semantic Search**: Vectorizing statements rather than entity names provides more context for search.
4. **Reduced Duplication**: Entities are unique, with multiple statements providing different perspectives.
5. **Improved Knowledge Graph**: The subject-predicate-object pattern in statements enables knowledge graph construction.

## Implementation Plan

X 1. Create new database migrations for the updated Entity model and new Statement model
X 2. Update the ContentAnalysisService to extract statements about entities
X 3. Modify the OpenAI prompt to generate statements rather than entity types
X 4. Update the search functionality to search across statements
5. Create a data migration path from V1 to V2 model
6. Update UI to display entities with their statements

## Technical Considerations

### Migration Strategy

For existing data, we'll need to:
1. Create entities based on unique name+type combinations
2. Generate statements like "[Entity] is a [type]" from the type field
3. Convert any existing entity embeddings to statement embeddings

### Search Performance

- Index statements table for efficient vector search
- Consider caching frequently accessed entities and their statements
- Optimize query patterns for common search scenarios

### API Changes

- Update API endpoints to reflect the new data model
- Maintain backward compatibility during transition period
- Document new entity-statement relationship patterns

## Conclusion

The V2 data model represents a significant conceptual shift that simplifies our approach to entity management while enabling more powerful semantic relationships. By focusing on statements about entities rather than typed entities, we gain flexibility and expressiveness while maintaining searchability.

---

This document is intended to guide the implementation of the V2 data model in the Archimedes application. Implementation details and specific code changes will be developed based on this architectural overview.
