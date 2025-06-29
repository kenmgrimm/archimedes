# Weaviate Ruby Client Usage Guide

## Overview

The `weaviate-ruby` gem is a Ruby wrapper for the Weaviate vector database API. This guide covers proper usage patterns, known issues, and best practices based on real-world implementation experience.

## Installation & Setup

```ruby
gem 'weaviate-ruby'
```

```ruby
require "weaviate"

client = Weaviate::Client.new(url: "http://localhost:8080")
```

## Schema Management

### Creating Schema Classes

```ruby
def ensure_class(class_name, properties, description = nil)
  return if client.schema.list["classes"].any? { |c| c["class"] == class_name }

  client.schema.create(
    class_name: class_name,
    description: description,
    properties: properties,
    vectorizer: "text2vec-openai"
  )
end

# Example properties structure
properties = [
  { name: "name", dataType: ["text"] },
  { name: "description", dataType: ["text"] },
  { name: "birthDate", dataType: ["date"] }
]
```

### Schema Operations

```ruby
# List all classes
client.schema.list

# Delete a class
client.schema.delete(class_name: "ClassName")

# Get specific class
client.schema.get(class_name: "ClassName")
```

## Object Operations

### Creating Objects

```ruby
# Create single object
result = client.objects.create(
  class_name: "Person",
  properties: {
    name: "John Doe",
    description: "Software engineer"
  }
)
object_id = result["id"]

# Batch create objects
output = client.objects.batch_create(objects: [
  {
    class: "Person",
    properties: { name: "Alice", occupation: "Designer" }
  },
  {
    class: "Person", 
    properties: { name: "Bob", occupation: "Developer" }
  }
])
```

### Updating Objects

```ruby
# Partial update
client.objects.update(
  class_name: "Person",
  id: object_id,
  properties: { occupation: "Senior Engineer" }
)

# Full replace
client.objects.replace(
  class_name: "Person",
  id: object_id,
  properties: { name: "John Doe", occupation: "CTO" }
)
```

### Object Queries

```ruby
# List all objects
client.objects.list()

# Get specific object
client.objects.get(class_name: "Person", id: object_id)

# Check if object exists
client.objects.exists?(class_name: "Person", id: object_id)

# Delete object
client.objects.delete(class_name: "Person", id: object_id)
```

## GraphQL Queries - CRITICAL ISSUES & SOLUTIONS

### Known Issues with GraphQL Response Parsing

The weaviate-ruby gem has **critical issues** with GraphQL response parsing:

1. **System field access**: Cannot query `id` directly - must use `_additional { id }`
2. **Response object incompatibility**: `result.data` may not support standard hash methods like `dig`
3. **Version compatibility**: Issues with graphql gem versions 2.1.x+

### Robust GraphQL Query Pattern

```ruby
def robust_graphql_query(query)
  result = client.graphql.query(query)
  
  # Handle response parsing with fallbacks
  data = nil
  
  # First try standard approach
  if result.respond_to?(:data) && result.data
    begin
      if result.data.respond_to?(:[]) && result.data["Get"]
        data = result.data["Get"]
      elsif result.data.respond_to?(:Get)
        data = result.data.Get if result.data.Get
      end
    rescue => e
      logger.debug("Standard access failed: #{e.message}")
    end
  end
  
  # Fallback to original_hash if needed
  if data.nil? && result.respond_to?(:instance_variable_get)
    begin
      response_data = result.instance_variable_get(:@original_hash)
      data = response_data.dig("data", "Get") if response_data
    rescue => e
      logger.debug("Fallback access failed: #{e.message}")
    end
  end
  
  data
end
```

### Correct GraphQL Query Patterns

#### Finding Objects by Property

```ruby
# CORRECT: Use _additional for system fields
query = <<~GRAPHQL
  {
    Get {
      Person(where: {path: ["name"], operator: Equal, valueString: "John Doe"}) {
        _additional {
          id
        }
        name
        occupation
      }
    }
  }
GRAPHQL

# WRONG: Direct id access will fail
# id  # This will cause "Field 'id' doesn't exist" error
```

#### Reference Queries

```ruby
# CORRECT: Use _additional in fragments
query = <<~GRAPHQL
  {
    Get {
      Person(where: {path: ["_id"], operator: Equal, valueString: "#{person_id}"}) {
        children {
          ... on Person {
            _additional {
              id
            }
            name
          }
        }
      }
    }
  }
GRAPHQL
```

### Query Methods

```ruby
# Get objects with conditions
client.query.get(
  class_name: 'Person',
  where: '{ operator: Equal, valueText: "Engineer", path: ["occupation"] }',
  fields: 'name occupation _additional { id }',
  limit: "10"
)

# Near text search
client.query.get(
  class_name: 'Person',
  near_text: '{ concepts: ["developer"] }',
  fields: 'name occupation _additional { distance }'
)

# Aggregation queries
client.query.aggs(
  class_name: "Person",
  fields: 'meta { count }',
  group_by: ["occupation"]
)
```

## Reference Management

### Adding References

References must be added via HTTP calls due to gem limitations:

```ruby
def add_reference(from_class, from_id, prop, to_class, to_id)
  uri = URI("http://localhost:8080/v1/objects/#{from_class}/#{from_id}/references/#{prop}")
  http = Net::HTTP.new(uri.host, uri.port)
  
  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request.body = {
    beacon: "weaviate://localhost/#{to_class}/#{to_id}"
  }.to_json
  
  response = http.request(request)
  raise "Failed to add reference: #{response.message}" unless response.code == "200"
end
```

### Checking Reference Existence

```ruby
def reference_exists?(from_class, from_id, prop, to_id)
  query = <<~GRAPHQL
    {
      Get {
        #{from_class}(where: {path: ["_id"], operator: Equal, valueString: "#{from_id}"}) {
          #{prop} {
            ... on Person {
              _additional { id }
            }
          }
        }
      }
    }
  GRAPHQL
  
  # Use robust parsing here
  data = robust_graphql_query(query)
  refs = data[from_class]&.first&.[](prop)
  
  return false unless refs
  refs.any? { |ref| ref["_additional"]["id"] == to_id }
end
```

## Upsert Pattern

```ruby
def upsert_object(class_name, properties)
  existing = find_existing_object(class_name, properties)
  
  if existing
    client.objects.update(
      class_name: class_name,
      id: existing["id"],
      properties: properties
    )
    existing["id"]
  else
    result = client.objects.create(
      class_name: class_name,
      properties: properties
    )
    result["id"]
  end
end

def find_existing_object(class_name, properties)
  unique_field = case class_name
                 when "Document" then "file_name"
                 when "Vehicle" then "vin"
                 else "name"
                 end
  
  unique_value = properties[unique_field.to_sym] || properties[unique_field]
  return nil unless unique_value
  
  query = <<~GRAPHQL
    {
      Get {
        #{class_name}(where: {path: ["#{unique_field}"], operator: Equal, valueString: "#{unique_value}"}) {
          _additional { id }
          #{unique_field}
        }
      }
    }
  GRAPHQL
  
  data = robust_graphql_query(query)
  objects = data[class_name] if data
  
  if objects && objects.any?
    return { "id" => objects.first["_additional"]["id"] }
  end
  
  nil
end
```

## Database Management

### Cleanup Operations

```ruby
def delete_all_objects
  classes = client.schema.list["classes"]
  classes.each do |cls|
    class_name = cls["class"]
    client.objects.batch_delete(
      class_name: class_name,
      where: { operator: "Like", valueText: "*", path: ["name"] }
    )
  end
end

def delete_schema_classes
  classes = client.schema.list["classes"]
  classes.each do |cls|
    client.schema.delete(class_name: cls["class"])
  end
end
```

## Best Practices

### 1. Error Handling
Always wrap GraphQL queries in try-catch blocks due to gem instability.

### 2. Logging
Use comprehensive debug logging to track GraphQL response issues.

### 3. Fallback Patterns
Implement multiple response parsing approaches for reliability.

### 4. System Fields
Always use `_additional { id }` for system metadata access.

### 5. Reference Management
Use direct HTTP calls for reference operations due to gem limitations.

### 6. Version Pinning
Pin graphql gem to compatible versions (< 2.1.0) if possible.

## Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `Field 'id' doesn't exist on type 'X'` | Direct id access | Use `_additional { id }` |
| `undefined field 'dig' on WeaviateObj` | Response object incompatibility | Use robust parsing pattern |
| `interface conversion: interface {} is nil` | Weaviate version compatibility | Update gem or use HTTP workaround |
| Reference creation fails | Gem limitation | Use direct HTTP calls |

## Alternative Approaches

For production systems, consider:

1. **Direct HTTP/GraphQL calls** instead of the gem
2. **Weaviate Python client** with Ruby bridge
3. **Custom HTTP wrapper** for critical operations

## Version Compatibility

- **weaviate-ruby**: Latest (with fallbacks)
- **graphql gem**: < 2.1.0 (if possible)
- **Weaviate server**: 1.26.4+ (known issues with some versions)

This guide reflects real-world usage patterns and known issues as of 2024. Always test thoroughly in your specific environment.
