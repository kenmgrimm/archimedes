# Neo4j Pipeline

## relevant files / commands
app/services/neo4j/taxonomy.yml

### Import / extraction
be rails runner scripts/test_import.rb
be rails runner scripts/test_extraction.rb


## Steps
- adjust test_extraction.rb to either process all input directories or a single directory
- Fix extraction of Lists
- fix extraction of relationships between people
- adjust test_import.rb to either process all input directories or a single directory
- Possibly make Items into Possessions / Belongings / Assets
- create new project(s) for minimal gem extractions (neo4j, openai, )
