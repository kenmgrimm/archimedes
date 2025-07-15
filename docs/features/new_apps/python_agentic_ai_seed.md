# archimedes_ai: Python Agentic AI System Seed

## Purpose
A template for the Python-based agentic AI system sub-project of Archimedes (named `archimedes_ai`). This service will handle all advanced reasoning, RAG, planning, and tool use, exposing a web API for interaction with the archimedes_rails backend and UI clients.

> **Reference:** For entity/relationship types and real-world usage patterns, see the taxonomy and usage docs from the main Archimedes project.

## Stack
- **Python 3.10+**
- **venv** for environment management
- **AutoGen** (Microsoft) for agent orchestration
- **FastAPI** (or Flask) for web API
- **httpx/requests** for backend API calls
- **(Optional) LangChain** for additional RAG tools
- **pytest** for testing

## Project Structure
```
archimedes_ai/
├── app/
│   ├── agents/           # Agent definitions (planner, retriever, executor, etc.)
│   ├── tools/            # Tool wrappers (API calls, utility functions)
│   ├── memory/           # Memory modules (vector store, knowledge cache)
│   ├── api/              # FastAPI endpoints
│   └── main.py           # Entrypoint
├── tests/
├── requirements.txt
├── README.md
└── .env.example
```

## Setup Instructions
1. **Create and activate venv**
   ```bash
   python -m venv venv
   source venv/bin/activate
   ```
2. **Install dependencies**
   ```bash
   pip install fastapi autogen httpx pytest
   ```
3. **Initialize project structure**
   - Copy the above directory layout.
   - Add `main.py` with a FastAPI app stub.
   - Add sample agent and tool modules.
4. **Configure environment**
   - Use `.env.example` to document needed variables (API keys, backend URLs).
5. **Run the API**
   ```bash
   uvicorn app.main:app --reload
   ```
6. **Test**
   ```bash
   pytest
   ```

## Next Steps
- Implement basic agent loop (planner → retriever → executor).
- Add API endpoints for chat, retrieval, and tool use.
- Integrate with Rails backend for knowledge storage/retrieval.
- Reference taxonomy and usage docs for entity/relationship types.
