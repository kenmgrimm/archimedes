# Todo

- modify write operations to be based on operation type, id, and params
  - query will be constructed based on values provided by LLM
- probably can stick with dynamic read queries constructed by LLM for now?
  - or do we want to try to construct them based on LLM output and limit to certain types of queries?
- test suite that involves - seed the db, run a chat, and then verify the results

- debug our extractions and imports until satisfied.  Still some errors on import.  Also, some extractions not quite right
- switch to using neo4j plugin GenAI for embeddings / similarity search

## commands
```bash
be rails runner scripts/test_extraction.rb
be rails runner scripts/test_extraction.rb upload2b

be rake "neo4j:import[scripts/output/upload2b]" DEBUG=1 CLEAR_DATABASE=true
be rake "neo4j:import" DEBUG=1 CLEAR_DATABASE=true
```
