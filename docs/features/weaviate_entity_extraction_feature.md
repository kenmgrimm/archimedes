# Feature: Entity & Relationship Extraction to Knowledge Graph with Weaviate (Rails Stack)

## Objective
Implement an automated pipeline that extracts entities and relationships from unstructured biographies (or similar text) and populates a deduplicated, queryable knowledge graph in Weaviate. The solution should integrate with the existing Ruby on Rails web and worker stack, but may use Python for extraction/embedding if necessary.

---

## 1. Technology Stack

- **Web/Worker Framework:** Ruby on Rails (existing stack)
- **Knowledge Graph/Vector DB:** Weaviate (Docker container)
- **External Embedding Service:** OpenAI API (or local embedding service)
- **Optional Extraction Service:** Python (for advanced NLP/LLM integration, if needed)
- **Inter-service Communication:** HTTP (REST), gRPC, or background jobs (Sidekiq/ActiveJob)
- **Schema/Ontology:** Schema.org + FOAF + minimal custom extensions (as per project vocabularies)

---

## 2. Installation & Setup

### 2.1. Install Weaviate
- **Docker (recommended):**
  ```bash
  docker run -d \
    -p 8080:8080 \
    -e QUERY_DEFAULTS_LIMIT=25 \
    -e AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true \
    -e PERSISTENCE_DATA_PATH="/var/lib/weaviate" \
    semitechnologies/weaviate:latest
  ```
- **Configure vectorization module** (e.g., OpenAI) via environment variables if using auto-vectorization.

### 2.2. Add Weaviate Client to Rails
- Use the [weaviate-ruby gem](https://github.com/weaviate/weaviate-ruby) or generic HTTP client (Faraday, HTTParty, etc.)
  ```ruby
  # Gemfile
  gem 'weaviate-ruby'
  # or
  gem 'httparty'
  ```
- `bundle install`

---

## 3. Define Core Schema in Weaviate

- Use a small set of reusable types (e.g., `Person`, `Place`, `Organization`, `Event`, `Project`, `Document`, `Experience`).
- Define the schema via Rails initializer, Rake task, or manually via Weaviate UI or Python script.

**Example Ruby (using Faraday/HTTParty):**
```ruby
# POST to /v1/schema
schema = {
  class: "Person",
  properties: [
    { name: "name", dataType: ["text"] },
    { name: "birthDate", dataType: ["text"] },
    { name: "occupation", dataType: ["text"] }
  ]
}
HTTParty.post("http://localhost:8080/v1/schema", body: schema.to_json, headers: { 'Content-Type' => 'application/json' })
```
- Repeat for other types and references.

---

## 4. Extraction & Ingestion Service

### 4.1. Service Overview
- Input: Unstructured biography or document (e.g., from `example content to graph.md`)
- Output: Populated Weaviate knowledge graph (entities, relationships, deduplication)

### 4.2. Steps

#### A. Entity & Relationship Extraction
- **Option 1:** Use a Ruby LLM/NLP library (e.g., HuggingFace via Python, or OpenAI via API from Rails).
- **Option 2:** Call out to a Python microservice for advanced extraction (recommended for best NLP/LLM support).
- Extract:
  - Entities (Person, Place, Event, etc.)
  - Relationships (e.g., `PARTICIPATED_IN`, `MARRIED_TO`)
  - Properties (e.g., dates, descriptions)

#### B. Deduplication
- Before inserting, check for existing entities using:
  - Name (exact or fuzzy match)
  - Vector similarity (Weaviate's nearText or nearVector)
- If a match is found (above a confidence threshold), update or merge; else, create new.

#### C. Insertion
- Insert entities as objects in Weaviate via REST API.
- Insert relationships as cross-references between objects.

#### D. Embedding
- Use Weaviate's built-in modules for auto-vectorization, or provide your own vectors (via OpenAI API or local model).

---

## 5. Example Rails Controller/Service (Pseudocode)

```ruby
class BiographyIngestController < ApplicationController
  def create
    bio_text = params[:bio]
    # 1. Extract entities/relationships (via OpenAI API or Python service)
    extraction = ExtractionService.extract(bio_text)
    # 2. Deduplicate and insert entities
    extraction[:entities].each do |entity|
      # Search Weaviate for existing entity
      # If found, update; else, create
      # ...
    end
    # 3. Insert relationships (cross-references)
    extraction[:relationships].each do |rel|
      # ...
    end
    render json: { status: :ok }
  end
end
```

---

## 6. Testing & Verification
- Test with sample biographies (e.g., Kaiser Soze example).
- Query Weaviate to verify:
  - No duplicate entities
  - Relationships are correctly established
  - Vector search returns relevant entities

---

## 7. (Optional) Visualization
- Export data for visualization in D3.js, Cytoscape, or similar.
- Or use Weaviate’s admin UI for browsing.

---

## 8. Maintenance & Iteration
- Periodically review deduplication thresholds and schema.
- Update extraction logic as LLMs improve.

---

## Summary Table

| Step                | Tool/Tech         | Notes                        |
|---------------------|-------------------|------------------------------|
| Install Weaviate    | Docker            | Vector modules optional      |
| Rails Integration   | weaviate-ruby/HTTP| Use gem or HTTP client       |
| Define Schema       | Ruby/REST         | Core types + references      |
| Extraction Service  | OpenAI/Python/Ruby| Entity/rel extraction        |
| Deduplication       | Weaviate search   | Name + vector similarity     |
| Ingestion           | Rails/REST        | Insert objects/references    |
| Visualization       | Export, UI        | Optional, for QA             |

---

## Notes
- Python is **not strictly necessary**—all steps can be performed from Rails, but Python offers richer NLP/LLM libraries and may be easier for advanced extraction or embedding tasks.
- For maximum Rails-native integration, use the weaviate-ruby gem and OpenAI API directly from Rails.
- For best NLP/LLM results, consider a Python microservice for extraction, called from Rails as needed.
