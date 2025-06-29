#!/bin/bash

### Get all vehicles owned by Winnie The Pooh
echo "Vehicles owned by Winnie The Pooh:"
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ Get { Person(where: { path: [\"name\"], operator: Equal, valueString: \"Winnie The Pooh\" }) { name vehicles { ... on Vehicle { make model year vin } } } }"}' | jq

echo -e "\nSearching for vehicles similar to 'Ford F-150 Raptor'..."


### Find vehicle using vector search
VEHICLE_QUERY='{
  "query": "query {\n    Get {\n      Vehicle(\n        nearText: {\n          concepts: [\"Ford F-150 Raptor\"],\n          certainty: 0.7\n        },\n        limit: 1\n      ) {\n        _additional {\n          id\n          certainty\n        }\n        make\n        model\n        year\n        vin\n      }\n    }\n  }"
}'

# Get vehicle data
VEHICLE_RESPONSE=$(curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d "$VEHICLE_QUERY")

# Extract vehicle information
VEHICLE_DATA=$(echo "$VEHICLE_RESPONSE" | jq -c '.data.Get.Vehicle[0]')

if [ "$VEHICLE_DATA" = "null" ] || [ -z "$VEHICLE_DATA" ]; then
  echo "Error: No vehicle found matching the query"
  exit 1
fi

VEHICLE_ID=$(echo "$VEHICLE_DATA" | jq -r '._additional.id')
VEHICLE_MAKE=$(echo "$VEHICLE_DATA" | jq -r '.make')
VEHICLE_MODEL=$(echo "$VEHICLE_DATA" | jq -r '.model')
CERTAINTY=$(echo "$VEHICLE_DATA" | jq -r '._additional.certainty')

echo -e "\nFound vehicle: $VEHICLE_MAKE $VEHICLE_MODEL (ID: $VEHICLE_ID, Certainty: $CERTAINTY)"

### Query for documents related to this vehicle
DOCUMENTS_QUERY='{
  "query": "{\n    Get {\n      Document(\n        where: {\n          operator: And,\n          operands: [\n            {\n              path: [\"related_to\", \"Vehicle\", \"_id\"],\n              operator: Equal,\n              valueString: \"'$VEHICLE_ID'\"\n            }\n          ]\n        }\n      ) {\n        title\n        description\n        file_name\n        file_type\n        content_summary\n        extracted_text\n        created_at\n        _additional {\n          id\n        }\n      }\n    }\n  }"
}'

# Execute the documents query
echo -e "\nDocuments related to $VEHICLE_MAKE $VEHICLE_MODEL:"
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d "$DOCUMENTS_QUERY" | jq


