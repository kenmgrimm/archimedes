# Todo

- use RAG to help to organize and deduplicate our data
- hook up simple RAG query interface and see if we can get some useful results

- debug our extractions and imports until satisfied.  Still some errors on import.  Also, some extractions not quite right
- switch to using neo4j plugin GenAI for embeddings / similarity search

## commands
```bash
be rails runner scripts/test_extraction.rb
be rails runner scripts/test_extraction.rb upload2b

be rake "neo4j:import[scripts/output/upload2b]" DEBUG=1 CLEAR_DATABASE=true
be rake "neo4j:import" DEBUG=1 CLEAR_DATABASE=true
```
