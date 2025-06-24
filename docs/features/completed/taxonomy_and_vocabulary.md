# Entity Taxonomy and Controlled Vocabulary

This document describes the taxonomy and controlled vocabulary approach for entity types, categories, and subtypes in the Personal Assistant database storage model. A clear taxonomy prevents duplication, ensures consistency, and enables powerful querying and automation.

---

## 1. Why a Taxonomy?
- **Avoids duplication:** Prevents creation of overlapping types like `reminder`, `calendar_reminder`, `event_reminder`, etc.
- **Enforces consistency:** All entities use a known set of types and subtypes, making data clean and predictable.
- **Supports smart logic:** Enables the system to reason about relationships (e.g., all reminders, all calendar events).
- **Improves UI and search:** Allows for reliable filtering, grouping, and user-facing organization.

---

## 2. Structure of the Taxonomy

The taxonomy is a centrally defined list of allowed entity types, categories, and subtypes. For the MVP, this can be a JSON or YAML file, or a dedicated table in the database.

### Example (JSON Format)
```json
{
  "reminder": {
    "label": "Reminder",
    "description": "A generic reminder for anything.",
    "subtypes": ["calendar_event", "todo", "goal_deadline"]
  },
  "calendar_event": {
    "label": "Calendar Event",
    "parent": "reminder",
    "description": "A time-based reminder that appears on your calendar."
  },
  "todo": {
    "label": "To-Do",
    "parent": "reminder",
    "description": "A task that needs to be completed."
  },
  "possession": {
    "label": "Possession",
    "description": "A physical or digital item owned by the user."
  },
  "note": {
    "label": "Note",
    "description": "A free-form text note."
  }
}
```

---

## 3. How Entities Use the Taxonomy

- **Type and Subtype:** Each entity stores a `type` and, if needed, a `subtype` field.
- **Validation:** Entity creation and extraction logic checks against the taxonomy to ensure only valid types/subtypes are used.
- **Mapping:** If input data suggests a new or ambiguous type (e.g., "calendar reminder"), the system maps it to the closest allowed type/subtype.

### Example Entity
```json
{
  "id": "entity_123",
  "type": "reminder",
  "subtype": "calendar_event",
  "label": "Dentist appointment",
  "date": "2025-07-01"
}
```

---

## 4. Extending and Updating the Taxonomy
- **Start simple:** Begin with a small set of types and subtypes that cover your MVP needs.
- **Expand as needed:** Add new types or subtypes as real-world usage reveals new requirements.
- **Central management:** Keep the taxonomy definition in a single place for easy updates and enforcement.

---

## 5. Benefits for Querying and Automation
- **Unified queries:** Easily find all entities of a parent type (e.g., all reminders, regardless of subtype).
- **UI filtering:** Present users with a consistent set of options and categories.
- **Automation:** Build rules and triggers based on type/subtype, e.g., "alert me for all calendar events next week."

---

This taxonomy-driven approach keeps your knowledge base clean, extensible, and easy to reason about—now and as your assistant grows in capability.
