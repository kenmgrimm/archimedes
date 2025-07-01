#!/bin/bash

# Set the Weaviate server URL
WEAVIATE_URL="http://localhost:8080"

# Function to get the complete schema with all types and their fields
get_complete_schema() {
  echo "Fetching complete schema from Weaviate..."
  
  # First, get the schema to find all class names
  local SCHEMA_JSON=$(curl -s -X GET "$WEAVIATE_URL/v1/schema")
  
  # Extract all class names
  local CLASS_NAMES=$(echo "$SCHEMA_JSON" | jq -r '.classes[].class' 2>/dev/null)
  
  if [ -z "$CLASS_NAMES" ]; then
    echo "No classes found in the schema. Is Weaviate running?"
    exit 1
  fi
  
  echo -e "\n=== SCHEMA OVERVIEW ==="
  
  # For each class, get its properties and identify reference fields
  for class in $CLASS_NAMES; do
    echo -e "\nClass: $class"
    echo "Properties:"
    
    # Get the class definition
    local CLASS_DEF=$(echo "$SCHEMA_JSON" | jq -r --arg class "$class" '.classes[] | select(.class == $class)')
    
    # Extract and display properties
    echo "$CLASS_DEF" | jq -r '.properties[] | "- " + .name + " (" + (.dataType | join(", ")) + ")"'
    
    # Identify reference properties
    echo -e "\nReference fields:"
    local HAS_REFS=0
    
    echo "$CLASS_DEF" | jq -c '.properties[] | select(.dataType[0] != null and (.dataType[0] | startswith("[") | not) and (.dataType[0] | . != "text" and . != "string" and . != "int" and . != "number" and . != "boolean" and . != "date" and . != "geoCoordinates" and . != "phoneNumber" and . != "blob" and . != "uuid" and . != "string[]" and . != "int[]" and . != "number[]" and . != "boolean[]" and . != "date[]" and . != "uuid[]")) | "- " + .name + " -> " + (.dataType | join(", "))' | while read -r ref; do
      if [ -n "$ref" ] && [ "$ref" != "null" ]; then
        echo "  $ref"
        HAS_REFS=1
      fi
    done
    
    if [ $HAS_REFS -eq 0 ]; then
      echo "  (No reference fields found)"
    fi
  done
}

# Function to query a single object with all its references
query_object_with_references() {
  local class_name=$1
  local object_id=$2
  
  echo -e "\n=== QUERYING OBJECT $class_name/$object_id WITH REFERENCES ==="
  
  # Get the object with all its properties
  local OBJECT_JSON=$(curl -s -X GET "$WEAVIATE_URL/v1/objects/$class_name/$object_id")
  
  if [ -z "$OBJECT_JSON" ] || [ "$OBJECT_JSON" = "{}" ]; then
    echo "Object not found or error retrieving object"
    return
  fi
  
  # Display the object
  echo -e "\nObject:"
  echo "$OBJECT_JSON" | jq .
  
  # Get the class definition to find reference fields
  local SCHEMA_JSON=$(curl -s -X GET "$WEAVIATE_URL/v1/schema")
  local CLASS_DEF=$(echo "$SCHEMA_JSON" | jq -r --arg class "$class_name" '.classes[] | select(.class == $class)')
  
  # Find all reference fields
  local REF_FIELDS=$(echo "$CLASS_DEF" | jq -r '.properties[] | select(.dataType[0] != null and (.dataType[0] | startswith("[") | not) and (.dataType[0] | . != "text" and . != "string" and . != "int" and . != "number" and . != "boolean" and . != "date" and . != "geoCoordinates" and . != "phoneNumber" and . != "blob" and . != "uuid" and . != "string[]" and . != "int[]" and . != "number[]" and . != "boolean[]" and . != "date[]" and . != "uuid[]")) | .name')
  
  if [ -z "$REF_FIELDS" ]; then
    echo -e "\nNo reference fields found for this object's class."
    return
  fi
  
  echo -e "\n=== REFERENCED OBJECTS ==="
  
  # For each reference field, get the referenced objects
  for ref_field in $REF_FIELDS; do
    local REF_VALUE=$(echo "$OBJECT_JSON" | jq -r ".properties.$ref_field // empty")
    
    if [ -n "$REF_VALUE" ] && [ "$REF_VALUE" != "null" ] && [ "$REF_VALUE" != "[]" ]; then
      echo -e "\nReferences in field '$ref_field':"
      
      # Handle both single references and arrays of references
      if echo "$REF_VALUE" | jq -e 'type == "array"' > /dev/null; then
        # Array of references
        echo "$REF_VALUE" | jq -c '.[]' | while read -r ref; do
          local beacon=$(echo "$ref" | jq -r '.beacon // empty')
          if [ -n "$beacon" ]; then
            local ref_class=$(echo "$beacon" | sed -E 's|.*//[^/]+/([^/]+)/.*|\1|')
            local ref_id=$(echo "$beacon" | sed -E 's|.*//[^/]+/[^/]+/([^/]+)|\1|')
            
            echo -e "\n  Referenced $ref_class ($ref_id):"
            curl -s -X GET "$WEAVIATE_URL/v1/objects/$ref_class/$ref_id" | jq .
          fi
        done
      else
        # Single reference
        local beacon=$(echo "$REF_VALUE" | jq -r '.beacon // empty')
        if [ -n "$beacon" ]; then
          local ref_class=$(echo "$beacon" | sed -E 's|.*//[^/]+/([^/]+)/.*|\1|')
          local ref_id=$(echo "$beacon" | sed -E 's|.*//[^/]+/[^/]+/([^/]+)|\1|')
          
          echo -e "\n  Referenced $ref_class ($ref_id):"
          curl -s -X GET "$WEAVIATE_URL/v1/objects/$ref_class/$ref_id" | jq .
        fi
      fi
    fi
  done
}

# Main execution
echo "=== WEAVIATE SCHEMA EXPLORER ==="

# Show the complete schema first
get_complete_schema

# If a class and ID are provided as arguments, query that specific object
if [ $# -eq 2 ]; then
  query_object_with_references "$1" "$2"
else
  echo -e "\nTo explore a specific object with its references, run:"
  echo "  $0 <class_name> <object_id>"
  echo -e "\nFor example:"
  echo "  $0 Document 123e4567-e89b-12d3-a456-426614174000"
fi

echo -e "\n=== EXPLORATION COMPLETE ==="
