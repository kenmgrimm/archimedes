# Neo4j Import System

This document describes the new Neo4j import system and how to use it.

## Overview

The new import system provides a more modular and maintainable way to import data into Neo4j. It consists of several components:

- `DatabaseService`: Manages Neo4j connections and transactions
- `Import::BaseImporter`: Base class for importers
- `Import::NodeImporter`: Handles node creation and updates
- `Import::RelationshipImporter`: Manages relationship creation
- `Import::ImportOrchestrator`: Coordinates the import process
- `KnowledgeGraphBuilderV2`: High-level interface for imports

## Rake Task

A new Rake task has been added to simplify running imports:

```bash
# Basic usage (imports from scripts/output by default)
bundle exec rake neo4j:import

# Import from a specific directory or file
bundle exec rake neo4j:import[/path/to/data]

# Clear the database before import
CLEAR_DATABASE=true bundle exec rake neo4j:import

# Run in dry-run mode (no changes to the database)
DRY_RUN=true bundle exec rake neo4j:import

# Enable debug logging
DEBUG=1 bundle exec rake neo4j:import

# Disable schema validation
VALIDATE_SCHEMA=false bundle exec rake neo4j:import
```

### Environment Variables

- `NEO4J_URL`: Neo4j connection URL (required)
- `NEO4J_USERNAME`: Neo4j username (required)
- `NEO4J_PASSWORD`: Neo4j password (required)
- `OPENAI_API_KEY`: Required for deduplication (optional)
- `CLEAR_DATABASE`: Set to "true" to clear the database before import
- `DRY_RUN`: Set to "true" to run without making changes
- `DEBUG`: Set to "1" to enable debug logging
- `VALIDATE_SCHEMA`: Set to "false" to disable schema validation

## Data Format

The import system expects data in the following format:

```json
{
  "entities": [
    {
      "type": "Person",
      "properties": {
        "id": "person1",
        "name": "John Doe",
        "email": "john@example.com"
      }
    }
  ],
  "relationships": [
    {
      "from_id": "person1",
      "to_id": "person2",
      "type": "KNOWS",
      "properties": {
        "since": "2020-01-01"
      }
    }
  ]
}
```

## Migration from Old System

The old `test_import.rb` script has been replaced by the new Rake task. The main differences are:

1. More modular and maintainable code
2. Better error handling and logging
3. Support for dry-run mode
4. More flexible configuration via environment variables
5. Better support for incremental imports

To migrate existing code:

1. Replace direct calls to the old import script with the new Rake task
2. Update any scripts that relied on the old script's output format
3. Update documentation to reference the new Rake task

## Performance Considerations

- For large imports, consider batching the data into smaller chunks
- Use the `DRY_RUN` flag to test imports without making changes
- Monitor memory usage for very large imports
- Consider disabling schema validation for faster imports with `VALIDATE_SCHEMA=false`
