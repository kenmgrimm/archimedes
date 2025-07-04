# Knowledge Graph Import System

## Overview
This document outlines the design and implementation of the system responsible for importing extraction results into the Neo4j knowledge graph. The system will process JSON extraction outputs, validate them against the taxonomy, and create or update nodes and relationships in the knowledge graph.

## Goals

1. **Reliable Import**: Accurately import entities and relationships from extraction results
2. **Data Integrity**: Ensure data consistency and prevent duplicates
3. **Traceability**: Maintain links between source data and graph elements
4. **Performance**: Efficiently handle large volumes of extractions
5. **Idempotency**: Support re-running imports without creating duplicates

## Architecture

### Components

1. **KnowledgeGraphBuilder**
   - Main service class that orchestrates the import process
   - Handles transaction management
   - Coordinates between different importers and validators

2. **Entity Importers**
   - Specialized classes for different entity types (Person, Item, etc.)
   - Handle entity-specific validation and transformation
   - Implement merge/update logic
   - Located in `app/services/neo4j/importers/entities/`

3. **Relationship Importers**
   - Handle creation of relationships between entities
   - Manage relationship properties
   - Ensure referential integrity
   - Located in `app/services/neo4j/importers/relationships/`

4. **Validators**
   - Validate entities and relationships against the taxonomy
   - Check required properties and data types
   - Enforce business rules

#### Directory Structure

```
app/
  services/
    neo4j/
      importers/
        base_importer.rb
        base_entity_importer.rb
        base_relationship_importer.rb
        entities/
          person_importer.rb
          item_importer.rb
          address_importer.rb
          # Other entity importers...
        relationships/
          ownership_importer.rb
          family_relationship_importer.rb
          # Other relationship importers...
      knowledge_graph_builder.rb
      taxonomy.yml
```

This structure provides:
- Clear separation of concerns between different entity types and relationships
- Easy discovery of importers through consistent naming and location
- Base classes to reduce code duplication
- Scalability for adding new entity and relationship types

### Data Flow

1. **Input**: JSON extraction files from the extraction service
2. **Validation**: Validate against schema and taxonomy
3. **Entity Processing**: Create or update entities
4. **Relationship Processing**: Create or update relationships
5. **Output**: Updated knowledge graph with new/modified nodes and relationships

## Detailed Design

### Entity Import Process

1. **Entity Resolution**
   - Generate a unique fingerprint for each entity based on its type and identifying properties
   - Check for existing entities with matching fingerprints
   - Decide whether to create new or update existing entities

2. **Property Handling**
   - Map extraction properties to graph node properties
   - Handle type conversion and formatting
   - Preserve metadata (source, confidence, timestamps)

3. **Versioning**
   - Maintain version history for entities
   - Track changes to important properties
   - Support rollback if needed

### Relationship Import Process

1. **Resolution**
   - Resolve source and target entities
   - Check for existing relationships between the same nodes

2. **Property Handling**
   - Map relationship properties
   - Handle temporal aspects (valid_from, valid_to)
   - Preserve metadata

3. **Consistency**
   - Ensure relationship types are valid according to the taxonomy
   - Validate cardinality constraints

### Deduplication Strategy

1. **Entity Matching**
   - Use deterministic matching for exact matches
   - Implement fuzzy matching for potential duplicates
   - Allow for manual review of potential duplicates

2. **Merge Rules**
   - Define rules for merging properties from duplicate entities
   - Handle conflicts (e.g., different birth dates)
   - Preserve all source information in version history

### Error Handling

1. **Validation Errors**
   - Collect and report all validation errors
   - Support partial imports when possible
   - Provide detailed error messages

2. **Database Errors**
   - Handle constraint violations
   - Manage transaction rollback on failure
   - Provide recovery options

## Technical Implementation

### KnowledgeGraphBuilder Interface

```ruby
class KnowledgeGraphBuilder
  # Import a single extraction result
  # @param extraction_result [Hash] The parsed extraction result
  # @param source_info [Hash] Metadata about the source
  # @return [ImportResult] Result of the import operation
  def import_extraction(extraction_result, source_info = {})
    # Implementation
  end
  
  # Import all extractions from a directory
  # @param directory_path [String] Path to directory containing extraction files
  def import_directory(directory_path)
    # Implementation
  end
  
  # Validate an extraction result against the taxonomy
  # @param extraction_result [Hash] The extraction result to validate
  # @return [ValidationResult] Validation results
  def validate_extraction(extraction_result)
    # Implementation
  end
end
```

### Import Script

A new script will be created at `scripts/import_extractions.rb` with the following functionality:

1. Scan a directory for extraction files
2. Process each file through the KnowledgeGraphBuilder
3. Generate a report of imported items and any issues
4. Support dry-run mode for validation

```ruby
# scripts/import_extractions.rb

require_relative '../config/environment'

def main
  # Parse command line arguments
  options = parse_arguments
  
  # Initialize the builder
  builder = KnowledgeGraphBuilder.new
  
  if options[:dry_run]
    # Run validation only
    results = builder.validate_directory(options[:directory])
    print_validation_report(results)
  else
    # Run the import
    results = builder.import_directory(options[:directory])
    print_import_report(results)
  end
end

main if __FILE__ == $0
```

## Testing Strategy

1. **Unit Tests**
   - Test individual importers in isolation
   - Verify entity resolution logic
   - Test validation rules

2. **Integration Tests**
   - Test end-to-end import process
   - Verify graph structure after import
   - Test error handling scenarios

3. **Performance Testing**
   - Test with large numbers of entities/relationships
   - Measure import times
   - Identify and optimize bottlenecks

## Future Enhancements

1. **Incremental Import**
   - Track which extractions have been imported
   - Support delta updates

2. **Batch Processing**
   - Process multiple extractions in parallel
   - Implement bulk import for better performance

3. **User Interface**
   - Web interface for reviewing and confirming imports
   - Tools for resolving conflicts and duplicates

4. **Advanced Matching**
   - Machine learning for improved entity resolution
   - Suggestion engine for potential matches

## Security Considerations

1. **Input Validation**
   - Sanitize all input data
   - Protect against injection attacks

2. **Access Control**
   - Restrict import capabilities to authorized users
   - Log all import operations

3. **Data Privacy**
   - Handle sensitive information appropriately
   - Support data anonymization where needed
