# Neo4j Chat Assistant

A terminal-based AI assistant that leverages the knowledge graph to answer questions and help manage personal information, with controlled Neo4j updates.

## Core Features

### Chat Interface
- Terminal-based readline interface with command history
- Markdown formatting for responses
- Session context maintenance
- Exit command and basic shell-like commands

### Knowledge Graph Queries
- Natural language queries translated to Cypher
- Vector similarity search for relevant nodes
- Context-aware relationship traversal
- Query result formatting and summarization

### Controlled Graph Updates
- AI suggests Neo4j updates as explicit Cypher commands
- Commands shown to user for review before execution
- Ability to modify/reject proposed changes
- Transaction rollback on errors

### Safety Features
- Read-only mode option
- Query execution timeout limits
- Transaction size limits
- Audit logging of all changes

## Technical Implementation

### Components
- `Neo4jChatService`: Main orchestrator
- `PromptBuilder`: Constructs context-aware prompts
- `CypherGenerator`: Translates natural language to Cypher
- `ResultFormatter`: Formats Neo4j results for terminal
- `ChangeReviewer`: Handles update approvals

### Example Usage
```
> Tell me about Alice's recent tasks
[Assistant retrieves and summarizes tasks]

> Add a task for Alice to review the Q3 report
[Assistant shows proposed Cypher]
CREATE (t:Task {title: "Review Q3 Report", assigned: "Alice"})
MATCH (p:Person {name: "Alice"})
CREATE (p)-[:ASSIGNED]->(t)
Execute this change? [y/n/edit]:

> What documents are related to the Q3 report?
[Assistant queries and displays related nodes]
```

### Integration Points
- Uses existing Neo4j connection management
- Leverages current entity taxonomy
- Integrates with OpenAI service layer
- Builds on existing vector search