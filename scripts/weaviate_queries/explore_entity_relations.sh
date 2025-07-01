#!/bin/bash

# Default values
WEAVIATE_URL="http://localhost:8080"
MAX_DEPTH=1  # Default to 1 level deep

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--max-depth)
      MAX_DEPTH="$2"
      if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
        echo "Error: Depth must be a positive integer"
        exit 1
      fi
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -d, --max-depth N   Maximum depth of relationship traversal (default: 1)"
      echo "  -h, --help          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

echo "Maximum relationship depth: $MAX_DEPTH"

# Function to get all classes from schema
get_all_classes() {
  echo "Fetching all classes from schema..."
  # Filter out any malformed class names and ensure they're valid
  curl -s -X GET "$WEAVIATE_URL/v1/schema" | \
    jq -r '.classes[].class | select(. != null and . != "" and test("^[a-zA-Z0-9]+"))' 2>/dev/null
}

# Function to get all objects of a class
get_all_objects() {
  local class_name=$1
  local limit=${2:-10}  # Default to 10 objects per class for better performance
  
  # Skip if class name is invalid
  if [[ ! "$class_name" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo -e "\nSkipping invalid class name: $class_name"
    return 1
  fi
  
  echo -e "\nFetching objects for class: $class_name"
  local response
  response=$(curl -s -X GET "$WEAVIATE_URL/v1/objects?class=$class_name&limit=$limit" 2>/dev/null)
  
  # Check if response is valid JSON and has objects
  if ! echo "$response" | jq -e '.objects?' >/dev/null 2>&1; then
    echo "  Error: Invalid response for class $class_name"
    return 1
  fi
  
  echo "$response" | jq -c '.objects[]?' 2>/dev/null
}

# Function to get an object with all its properties
get_object() {
  local class_name=$1
  local object_id=$2
  
  # Skip if either parameter is empty
  if [ -z "$class_name" ] || [ -z "$object_id" ]; then
    return 1
  fi
  
  local response
  response=$(curl -s -X GET "$WEAVIATE_URL/v1/objects/$class_name/$object_id" 2>/dev/null)
  
  # Check if response is valid JSON and contains properties
  if ! echo "$response" | jq -e '.properties?' >/dev/null 2>&1; then
    return 1
  fi
  
  echo "$response"
}

# Function to check if a property is a reference
is_reference() {
  local prop_value=$1
  
  # Check if it's a reference object with beacon
  if echo "$prop_value" | jq -e '.beacon' >/dev/null 2>&1; then
    return 0  # It's a single reference
  elif echo "$prop_value" | jq -e '.[0]?.beacon' >/dev/null 2>&1; then
    return 0  # It's an array of references
  fi
  
  return 1  # Not a reference
}

# Function to process a reference property with depth tracking
process_reference() {
  local ref_value=$1
  local current_depth=${2:-1}  # Default to depth 1 if not provided
  local indent=${3:-0}         # Current indentation level
  
  # Calculate indentation
  local indent_str=$(printf '%*s' $((indent * 2)))
  
  # Handle single reference
  if echo "$ref_value" | jq -e '.beacon' >/dev/null 2>&1; then
    local beacon=$(echo "$ref_value" | jq -r '.beacon')
    # Extract class and ID from beacon (format: weaviate://localhost/Class/UUID)
    local ref_class=$(echo "$beacon" | cut -d'/' -f4)
    local ref_id=$(echo "$beacon" | cut -d'/' -f5)
    
    # Get the referenced object
    local ref_obj=$(get_object "$ref_class" "$ref_id")
    
    if [ -n "$ref_obj" ] && [ "$ref_obj" != "null" ]; then
      # Extract name/title for display
      local name=$(echo "$ref_obj" | jq -r '.properties | .name // .title // .file_name // (.make + " " + .model) // .id')
      echo "${indent_str}- $ref_class: $name (ID: $ref_id) [Depth: $current_depth]"
      
      # If we haven't reached max depth, process this object's references
      if [ $current_depth -lt $MAX_DEPTH ]; then
        process_object_references "$ref_obj" $((current_depth + 1)) $((indent + 1))
      fi
    else
      echo "${indent_str}- $ref_class: [Could not load object] (ID: $ref_id) [Depth: $current_depth]"
    fi
  
  # Handle array of references
  elif echo "$ref_value" | jq -e '.[0]?.beacon' >/dev/null 2>&1; then
    echo "$ref_value" | jq -c '.[]' | while read -r ref_item; do
      local beacon=$(echo "$ref_item" | jq -r '.beacon')
      # Extract class and ID from beacon (format: weaviate://localhost/Class/UUID)
      local ref_class=$(echo "$beacon" | cut -d'/' -f4)
      local ref_id=$(echo "$beacon" | cut -d'/' -f5)
      
      # Get the referenced object
      local ref_obj=$(get_object "$ref_class" "$ref_id")
      
      if [ -n "$ref_obj" ] && [ "$ref_obj" != "null" ]; then
        # Extract name/title for display
        local name=$(echo "$ref_obj" | jq -r '.properties | .name // .title // .file_name // (.make + " " + .model) // .id')
        echo "${indent_str}- $ref_class: $name (ID: $ref_id) [Depth: $current_depth]"
        
        # If we haven't reached max depth, process this object's references
        if [ $current_depth -lt $MAX_DEPTH ]; then
          process_object_references "$ref_obj" $((current_depth + 1)) $((indent + 1))
        fi
      else
        echo "${indent_str}- $ref_class: [Could not load object] (ID: $ref_id) [Depth: $current_depth]"
      fi
    done
  fi
}

# Function to process all references of an object
process_object_references() {
  local obj=$1
  local current_depth=${2:-1}
  local indent=${3:-0}
  
  # Get all properties
  local properties=$(echo "$obj" | jq -c '.properties | to_entries[]' 2>/dev/null)
  
  if [ -z "$properties" ]; then
    return
  fi
  
  # Process each property
  while IFS= read -r prop; do
    # Skip if property is empty
    if [ -z "$prop" ] || [ "$prop" = "null" ]; then
      continue
    fi
    
    local prop_name=$(echo "$prop" | jq -r '.key' 2>/dev/null)
    local prop_value=$(echo "$prop" | jq -r '.value' 2>/dev/null)
    
    # Skip if we couldn't get the property name or value
    if [ -z "$prop_name" ] || [ "$prop_name" = "null" ] || [ -z "$prop_value" ] || [ "$prop_value" = "null" ]; then
      continue
    fi
    
    # Check if this property is a reference
    if is_reference "$prop_value"; then
      process_reference "$prop_value" $current_depth $((indent + 1))
    fi
  done <<< "$properties"
}

# Main execution
echo "=== WEAVIATE ENTITY RELATIONSHIP EXPLORER ==="

# Get all classes
CLASSES=$(get_all_classes)

if [ -z "$CLASSES" ]; then
  echo "No valid classes found in the schema. Is Weaviate running?"
  exit 1
fi

# Convert to array to handle class names with spaces
IFS=$'\n' read -r -d '' -a CLASSES_ARRAY <<< "$CLASSES"

echo -e "\nFound ${#CLASSES_ARRAY[@]} valid classes:"
for class in "${CLASSES_ARRAY[@]}"; do
  echo "- $class"
done

# For each class, process all objects and their relationships
for class in "${CLASSES_ARRAY[@]}"; do
  echo -e "\n\n=== PROCESSING CLASS: $class ==="
  
  # Get all objects for this class
  OBJECTS=$(get_all_objects "$class" 10)  # Limit to 10 objects per class for performance
  
  if [ -z "$OBJECTS" ]; then
    echo "  No objects found in class $class"
    continue
  fi
  
  # Process each object
  while IFS= read -r obj; do
    # Skip if object is empty
    if [ -z "$obj" ] || [ "$obj" = "null" ]; then
      continue
    fi
    
    # Extract object ID and name/title for display
    obj_id=$(echo "$obj" | jq -r '.id' 2>/dev/null)
    
    # Skip if no valid ID
    if [ -z "$obj_id" ] || [ "$obj_id" = "null" ]; then
      continue
    fi
    
    # Extract display name, safely handling potential errors
    obj_name=$(echo "$obj" | jq -r '.properties | .name // .title // .file_name // (.make + " " + .model) // .id' 2>/dev/null || echo "[Unnamed Object]")
    
    # Skip objects without properties
    if ! echo "$obj" | jq -e '.properties' >/dev/null 2>&1; then
      continue
    fi
    
    echo -e "\n  Object: $class/$obj_id ($obj_name)"
    
    # Get all properties
    properties=$(echo "$obj" | jq -c '.properties | to_entries[]' 2>/dev/null)
    
    if [ -z "$properties" ]; then
      echo "    No properties found for this object"
      continue
    fi
    
    # Flag to track if we found any references
    has_references=0
    
    # Process each property
    while IFS= read -r prop; do
      # Skip if property is empty
      if [ -z "$prop" ] || [ "$prop" = "null" ]; then
        continue
      fi
      
      prop_name=$(echo "$prop" | jq -r '.key' 2>/dev/null)
      prop_value=$(echo "$prop" | jq -r '.value' 2>/dev/null)
      
      # Skip if we couldn't get the property name or value
      if [ -z "$prop_name" ] || [ "$prop_name" = "null" ] || [ -z "$prop_value" ] || [ "$prop_value" = "null" ]; then
        continue
      fi
      
      # Skip null or empty values
      if [ "$prop_value" = "null" ] || [ -z "$prop_value" ]; then
        continue
      fi
      
      # Check if this property is a reference
      if is_reference "$prop_value"; then
        if [ $has_references -eq 0 ]; then
          echo "    References (max depth: $MAX_DEPTH):"
          has_references=1
        fi
        
        echo "    - $prop_name:"
        process_reference "$prop_value" 1 2  # Start at depth 1, indent 2 spaces
      fi
    done <<< "$properties"
    
    # Only show the object if it has references
    if [ $has_references -eq 0 ]; then
      echo "    No reference properties found for this object"
    fi
  done <<< "$OBJECTS"
done

echo -e "\n=== EXPLORATION COMPLETE ==="
