# Archimedes: Next-Gen Personal AI Assistant Overview

## Project Structure and Naming
Archimedes is composed of two primary sub-projects:
- **archimedes_ai**: Python-based agentic AI system (AutoGen, FastAPI)
- **archimedes_rails**: Rails/Postgres/pgvector knowledge store and web/CLI interface

## Purpose
This initiative aims to create a modular, production-grade AI assistant that learns about its user, manages knowledge, and provides actionable support for tasks, reminders, suggestions, and efficiency. The system is designed to:
- Build and maintain a personal knowledge graph (PKG) of the user's life.
- Use a dynamic vector store for semantic search and retrieval-augmented generation (RAG).
- Employ an agentic AI system (AutoGen-based) to reason, plan, and act on behalf of the user.
- Deliver assistance via CLI or web chat, with a focus on privacy, extensibility, and user agency.

## Types of Personal Data Managed
The system ingests, processes, and manages a wide variety of personal data, including:
- **Personal Notes & Documents**: Text notes, documents, PDFs
- **To-Do Lists**: Task lists with priorities, deadlines, and completion tracking
- **Grocery Lists**: Shopping items with categories, quantities, and store preferences
- **Reminders**: Time and location-based notifications for important tasks
- **Financial Information**: Receipts, expenses, budgets
- **Goal Tracking**: Personal and professional goals with milestones
- **Media**: Photos, videos, audio recordings
- **Calendar & Events**: Meetings, appointments, deadlines
- **Shopping & Marketplace**: Wishlists, shopping needs, marketplace listings
- **Location Data**: Frequent locations, stores visited

## Autonomous Features
The assistant operates with significant autonomy to provide proactive value:
- **Web Scraping & Monitoring**: Monitors marketplaces (e.g., Facebook, eBay, Craigslist) for items of interest
- **Proactive Notifications**: Alerts for relevant deals, calendar events, goal deadlines
- **Location-Aware Assistance**: Recognizes when you're at specific stores and provides relevant shopping lists
- **Schedule Management**: Plans daily/weekly/monthly activities based on goals and commitments
- **Order Management**: Checks order status and notifies user of updates
- **Account Actions**: Can log in, fill forms, and perform actions requiring authentication (with user consent and secure credential handling)

## Architecture
The system is split into two core sub-projects:

### 1. **archimedes_ai (Python, AutoGen)**
- Handles all agent reasoning, planning, and RAG workflows.
- Exposes a web API for interaction with the archimedes_rails backend and UI clients.
- Integrates with the knowledge store (Postgres/pgvector) via API.

### 2. **archimedes_rails (Rails, Postgres/pgvector)**
- Manages all user data, knowledge graph entities, relationships, and embeddings.
- Provides a CLI for interaction with the agentic AI system.
- Provides a Hotwire/Turbo/Stimulus-powered web UI for data exploration and management.
- Exposes APIs for agent interaction and chat service endpoints.

## Key Principles
- **No Neo4j or Weaviate**: All data and relationships in Postgres (ActiveRecord, JSONB, pgvector).
- **Mobile-first, responsive UI**: Rails app uses Hotwire, Turbo, and Stimulus, minimal custom JS.
- **Extensible, modular design**: Each project is a template for rapid iteration and future features.
- **Strong documentation**: Each project bootstrapped with clear setup, architecture, and usage docs.

## Reference & Migration
- This legacy project (Archimedes) serves as a reference for taxonomy, usage patterns, and prior lessons learned.
- Taxonomy and usage docs will seed the new Rails project.

---

## Next Steps
1. Scaffold the Python agentic AI system (AutoGen, web API, venv).
2. Scaffold the Rails/Postgres knowledge store (models, JSONB, pgvector, Hotwire UI).
3. Integrate, iterate, and expand capabilities as needed.

See the following docs for detailed setup instructions for each subproject.
