
# Get all vehicles owned by Winnie The Pooh
curl -X POST http://localhost:8080/v1/graphql \
-H "Content-Type: application/json" \
-d @- <<EOF
{"query":"{ Get { Person(where: { path: [\\"name\\"], operator: Equal, valueString: \\"Winnie The Pooh\\" }) { name vehicles { ... on Vehicle { make model year vin } } } } }"}
EOF

