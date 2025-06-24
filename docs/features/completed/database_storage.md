# Database Storage Model: Personal Assistant

This document outlines the JSON-based storage approach for upload documents, canonical entities, and other document entities. This structure enables flexible, extensible, and semantically rich storage in Postgres (JSONB) with vector search support.

---

## 1. Upload Document
Represents a single user upload session (one or more files + optional text input). All extracted entities are linked to this document.

```json
{
  "id": "doc_123",
  "type": "upload",
  "uploaded_at": "2025-06-22T19:30:00Z",
  "user_id": "user_abc",
  "source_files": [
    {"file_id": "file_1", "type": "image/jpeg"},
    {"file_id": "file_2", "type": "audio/m4a"}
  ],
  "input_text": "This is my license, note the registration tags and when I will need to renew.",
  "canonical_text": "Photo of license plate: ABC1234 2025. This is my GMC truck. Note the registration tags and when I will need to renew.",
  "entity_ids": ["entity_1", "entity_2", "entity_3"],
  "vector_id": "vec_123",
  "status": "processed"
}
```

---

## 2. Canonical Entity Document
Represents a unique, real-world entity (e.g., your GMC truck). All related uploads, reminders, notes, etc. can link to this canonical entity.

```json
{
  "id": "entity_gmc_truck",
  "type": "possession",
  "label": "GMC truck",
  "attributes": {
    "vin": "1234567890ABCDEFG",
    "license_plate": "ABC1234"
  },
  "created_at": "2025-06-22T19:30:01Z",
  "updated_at": "2025-06-22T19:35:00Z"
}
```

---

## 3. Other Document Entities
Represents extracted data points (reminders, notes, receipts, etc.) from uploads. Each references its parent upload document and can link to canonical entities.

### Example: Reminder Entity
```json
{
  "id": "entity_2",
  "type": "reminder",
  "parent_document_id": "doc_123",
  "label": "renew registration tags",
  "date": "2025-12-01",
  "canonical_entity_id": "entity_gmc_truck",
  "vector_id": "vec_457",
  "created_at": "2025-06-22T19:30:01Z"
}
```

### Example: Note Entity
```json
{
  "id": "entity_3",
  "type": "note",
  "parent_document_id": "doc_123",
  "text": "This is my GMC truck. Note the registration tags and when I will need to renew.",
  "canonical_entity_id": "entity_gmc_truck",
  "vector_id": "vec_458",
  "created_at": "2025-06-22T19:30:01Z"
}
```

---

## 4. Relationships & Linking
- **Upload documents** contain references to all extracted entity IDs.
- **Entities** reference their parent document and, if applicable, a canonical entity.
- **Canonical entities** act as the source of truth for real-world things (e.g., a vehicle, a person, a recurring event).
- All objects can be vectorized for semantic search and linked by ID.

---

## 5. De-duplication & Entity Management
- When a new entity is extracted, attempt to match it to an existing canonical entity (using semantic similarity, fuzzy matching, or user confirmation).
- If a match is found, link to the canonical entity; otherwise, create a new one.
- This enables a single source of truth for each real-world entity, with all related uploads and extracted data points linked together.

---

This model supports flexible, extensible, and user-correctable knowledge representation for your personal assistant MVP and beyond.
