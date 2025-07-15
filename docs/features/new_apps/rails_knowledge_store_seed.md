# archimedes_rails: Knowledge Store & App Seed

## Purpose
A template for the Rails/Postgres/pgvector knowledge store sub-project of Archimedes (named `archimedes_rails`). This app manages the user’s knowledge graph, entities, relationships, and embeddings. Provides a modern, mobile-first UI and APIs for agentic AI integration.

> **Reference:** For entity/relationship types and real-world usage patterns, see the taxonomy and usage docs from the main Archimedes project.

## Stack
### Core
- **Ruby 3.2+**
- **Rails 7+**
- **Postgres** (with **pgvector** extension)
- **ActiveRecord**
- **Hotwire** (Turbo, Stimulus)
- **TailwindCSS**

### Testing
- **rspec-rails**: Main testing framework
- **factory_bot_rails**: Factories for test data
- **webmock**: Stubbing HTTP requests in tests
- **VCR** (optional): Record/replay HTTP interactions for tests

### HTTP & API
- **httparty**: HTTP client for external API calls

### Authentication & User Management
- **devise**: Authentication and user management

### File & Media Storage
- **activestorage**: File uploads and attachments

## Project Structure
```
archimedes_rails/
├── app/
│   ├── models/           # Entity, Relationship, etc. (taxonomy-driven)
│   ├── controllers/      # API and web controllers
│   ├── views/            # Hotwire/Turbo-powered UI
│   ├── javascript/       # Stimulus controllers
│   └── ...
├── db/
│   ├── migrate/          # Migrations for core and dynamic attributes
│   └── seeds.rb
├── config/
├── spec/ or test/
├── README.md
└── .env.example
```

## Setup Instructions
1. **Create new Rails app**
   ```bash
   rails new archimedes_rails -d postgresql --css=tailwind --skip-javascript
   cd archimedes_rails
   ```
2. **Add dependencies**
   - Add `pgvector` gem and run migrations to enable vector columns.
   - Add Hotwire (Turbo, Stimulus) via Rails defaults.
3. **Generate models**
   - Scaffold `Person`, `Item`, etc. using taxonomy definitions.
   - Use `jsonb` columns for custom/dynamic attributes.
   - Add `vector` columns for embeddings.
4. **Configure environment**
   - Use `.env.example` for DB and API config.
5. **Run the app**
   ```bash
   rails db:create db:migrate
   rails server
   ```
6. **Test**
   ```bash
   rspec
   ```

## Next Steps
- Flesh out models to match taxonomy and usage docs.
- Build mobile-first Hotwire UI for entity/relationship exploration.
- Expose REST/GraphQL endpoints for agentic AI integration.
- Reference taxonomy and usage docs for property/relationship types.
