# Entity Extraction and Storage

## Overview
This document describes the process and requirements for extracting entities from OpenAI responses and storing them in the Archimedes application.

**Important:** All entities must strictly conform to the taxonomy defined in `app/services/openai/entity_taxonomy.yml`. Only entity types listed in this taxonomy are valid for extraction, classification, and storage.

## Requirements

1. **Entity Creation**
   - Use the OpenAI response (flat JSON with `description`, `annotated_description`, and `rating`) to extract and create related `Entity` records for each `Content`.
   - Entities must be classified by type and value, and the type must exactly match one of the types defined in `app/services/openai/entity_taxonomy.yml`.

2. **Classification**
   - Parse the `annotated_description` field to identify and classify entities.
   - Store each entity with its detected type and value.
   - Example: `[Organization: John Doe]` → type: `organization`, value: `John Doe`.

3. **Association**
   - Each extracted entity should be associated with the parent `Content` record.
   - Optionally, associate with the specific file if the entity was derived from an uploaded file.

4. **Audit and Review**
   - Store the full OpenAI response body with the `Content` or each `Entity` for future review and auditing.
   - Ensure the response is accessible from the admin interface or via the Content detail page.

5. **Extensibility**
   - The extraction logic should be modular to allow future improvements (e.g., support for new entity types, improved parsing, or alternate LLMs).

## Implementation Notes
- Use robust parsing to extract entities from the `annotated_description` field.
- Consider storing both the raw and parsed entity data for traceability.
- Ensure all entity extraction and storage is covered by RSpec tests.
- Add debug logging for entity creation and error handling.

---

This document is intended to guide the implementation and testing of entity extraction and storage features in the Archimedes application. For prompt design and OpenAI integration, see the related feature doc: `entity_extraction_with_openai.md`.
