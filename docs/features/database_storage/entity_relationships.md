# Entity Relationships in Database Storage

This document describes how entities are related, linked, and referenced in the Personal Assistant's JSON-based storage model. It covers relationship types, linking strategies, and practical JSON examples for robust, extensible knowledge representation.

---

## 1. Relationship Types

- **Parent-Child:**
  - Each entity references its parent upload document (provenance).
- **Canonical Reference:**
  - Entities (notes, reminders, receipts, etc.) can reference a canonical entity (e.g., a possession or contact) via `canonical_entity_id`.
- **Peer/Related Entities:**
  - Entities can reference other entities (even across documents) via `related_entity_ids` for flexible linking (e.g., a note linked to a shopping list item).
- **Hierarchical:**
  - Entities can form trees (e.g., project → task → subtask) using parent/child or related IDs.

---

## 2. Example Relationship Scenarios

### A. Note Linked to Shopping List Item
```json
{
  "id": "entity_note1",
  "type": "note",
  "text": "Need a large quantity, not just a little can at the supermarket.",
  "related_entity_ids": ["entity_salt"],
  "parent_document_id": "doc_124"
}
```

### B. Reminder Linked to Possession
```json
{
  "id": "entity_reminder1",
  "type": "reminder",
  "label": "renew registration tags",
  "date": "2025-12-01",
  "canonical_entity_id": "entity_gmc_truck",
  "parent_document_id": "doc_125"
}
```

### C. Project, Task, Subtask Hierarchy
```json
{
  "id": "entity_project1",
  "type": "project",
  "label": "repair the garage"
}
```
```json
{
  "id": "entity_task1",
  "type": "task",
  "label": "paint the garage",
  "parent_entity_id": "entity_project1"
}
```
```json
{
  "id": "entity_subtask1",
  "type": "subtask",
  "label": "buy paint",
  "parent_entity_id": "entity_task1"
}
```

---

## 3. Linking Strategies
- **Explicit IDs:** All relationships are explicit via unique IDs, making the model flexible and easy to traverse.
- **Cross-Document Linking:** Entities can reference other entities regardless of their originating document, enabling knowledge graphs.
- **Relationship Types:** Use fields like `related_entity_ids`, `canonical_entity_id`, or `parent_entity_id` to express different relationship semantics.

---

## 4. Querying Relationships
- To find all notes about a shopping list item, filter notes with `related_entity_ids` containing the item's ID.
- To get all tasks for a project, find tasks with `parent_entity_id` equal to the project ID.
- To gather everything about a canonical entity (e.g., "GMC truck"), collect all entities with `canonical_entity_id` set to that entity's ID.

---

This approach enables rich, extensible, and auditable relationships between entities, supporting powerful queries and user experiences in your personal assistant system.
