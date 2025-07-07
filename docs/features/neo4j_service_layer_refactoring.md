# Neo4j Service Layer Refactoring

## Overview
This document outlines the plan to refactor the Neo4j-related code into a well-structured service layer, separating concerns and improving maintainability.

## Current Issues

1. **Overlapping Responsibilities**
   - `test_import.rb` contains business logic that should be in services
   - Duplicate code for entity/relationship handling
   - Mixed concerns in multiple files

2. **Limited Reusability**
   - Code is tightly coupled to specific use cases
   - Hard to extend or modify functionality

3. **Maintainability Issues**
   - Business logic mixed with script code
   - Tight coupling makes changes difficult

## Proposed Architecture

### 1. Service Layer Structure

```
app/services/neo4j/
├── import/
│   ├── base_importer.rb
│   ├── node_importer.rb
│   ├── relationship_importer.rb
│   ├── data_loader.rb
│   └── import_orchestrator.rb
├── database_service.rb
├── knowledge_graph_builder.rb
└── graph_rag_service.rb
```

### 2. Service Responsibilities

#### `Neo4j::DatabaseService`
- Manages database connections
- Handles database operations (clear, schema management)
- Provides session management

#### `Neo4j::Import::ImportOrchestrator`
- Coordinates the import process
- Manages transactions
- Handles error reporting

#### `Neo4j::Import::NodeImporter`
- Handles node creation/updates
- Manages deduplication
- Validates node data

#### `Neo4j::Import::RelationshipImporter`
- Handles relationship creation
- Validates relationships
- Manages relationship constraints

#### `Neo4j::KnowledgeGraphBuilder` (existing)
- High-level graph construction
- Document processing
- Entity extraction

#### `Neo4j::GraphRagService` (existing)
- Facade for RAG operations
- Coordinates between services
- Provides high-level API

## Implementation Plan

### Phase 1: Foundation (Week 1)
1. Create `DatabaseService`
2. Set up base import structure
3. Implement basic import services

### Phase 2: Core Functionality (Week 2)
1. Implement `NodeImporter` with deduplication
2. Implement `RelationshipImporter`
3. Create `ImportOrchestrator`

### Phase 3: Integration
1. Update `KnowledgeGraphBuilder` to use new services
2. Convert `test_import.rb` to a Rake task
3. Optimize performance

## Migration Strategy

1. **Incremental Changes**
   - Keep existing code working
   - Migrate functionality piece by piece
   - Focus on core functionality first

2. **Backward Compatibility**
   - Maintain existing interfaces where possible
   - Add deprecation warnings for old code paths

## Rake Task Implementation

### Import Task

Create a Rake task `neo4j:import` that will:
- Accept input directory as a parameter
- Use the new service layer
- Provide progress feedback
- Support dry-run mode

```ruby
# lib/tasks/neo4j.rake
namespace :neo4j do
  desc "Import data into Neo4j from directory (default: ./output)"
  task :import, [:input_dir] => :environment do |_t, args|
    input_dir = args[:input_dir] || Rails.root.join('output')
    
    puts "Starting Neo4j import from: #{input_dir}"
    
    # Initialize services
    importer = Neo4j::Import::ImportOrchestrator.new
    
    # Load and process data
    data = Neo4j::Import::DataLoader.load_from_directory(input_dir)
    
    # Run import
    result = importer.import(data)
    
    # Output results
    if result[:success]
      puts "Import completed successfully!"
      puts "  - Nodes processed: #{result[:stats][:nodes]}"
      puts "  - Relationships processed: #{result[:stats][:relationships]}"
    else
      puts "Import failed: #{result[:error]}"
      exit 1
    end
  end
end
```

### Usage

```bash
# Import from default directory (./output)
# This should import all subdirectories
bundle exec rake neo4j:import

# Import from specific directory
# This should import only the specified directory
bundle exec rake neo4j:import[/path/to/data]
```

## Dependencies

- Neo4j Ruby driver
- Rails 7.1+

## Risks & Mitigation

1. **Risk**: Breaking existing functionality
   - Mitigation: Keep old code working during transition
   - Mitigation: Gradual rollout

2. **Risk**: Performance impact
   - Mitigation: Benchmark critical paths
   - Mitigation: Optimize based on real usage

## Success Metrics

1. **Developer Experience**
   - Clearer code organization
   - Easier to add new features
   - Better error messages and logging

2. **Performance**
   - Maintain or improve import speed
   - Efficient memory usage
