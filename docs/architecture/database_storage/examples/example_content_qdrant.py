# Qdrant (Python) - Example Content to Graph (Core Types)
# Core Types: Person, Place, Event, Project, Idea, Experience

# 1. Embeddings (assume generated externally)
kaiser_embedding = ...
nancy_embedding = ...
collegiate_embedding = ...
princeton_embedding = ...
salida_embedding = ...
wildlife_embedding = ...
resilience_embedding = ...
backpacking_embedding = ...
anniversary_embedding = ...
blacksmithing_embedding = ...

# 2. Store entities in a single collection (e.g., 'entities')
qdrant_client.upsert(
    collection_name="entities",
    points=[
        {"id": "kaiser", "vector": kaiser_embedding, "payload": {"type": "Person", "name": "Kaiser Soze"}},
        {"id": "nancy", "vector": nancy_embedding, "payload": {"type": "Person", "name": "Nancy Soze"}},
        {"id": "collegiate", "vector": collegiate_embedding, "payload": {"type": "Place", "name": "Collegiate Peaks Wilderness", "placeType": "Wilderness", "state": "Colorado"}},
        {"id": "princeton", "vector": princeton_embedding, "payload": {"type": "Place", "name": "Mount Princeton", "placeType": "Mountain", "elevation": 14197, "state": "Colorado"}},
        {"id": "salida", "vector": salida_embedding, "payload": {"type": "Place", "name": "Salida", "placeType": "Town", "state": "Colorado"}},
        {"id": "wildlife", "vector": wildlife_embedding, "payload": {"type": "Project", "name": "Wildlife Monitoring", "status": "Concept", "inspiration": "Collegiate Peaks trip"}},
        {"id": "resilience", "vector": resilience_embedding, "payload": {"type": "Idea", "name": "Community Resilience Through Technology", "topics": ["mesh networks", "resource sharing", "AI disaster response"]}},
        {"id": "backpacking", "vector": backpacking_embedding, "payload": {"type": "Experience", "description": "Solo backpacking trip", "startDate": "2024-06", "durationDays": 8, "distanceMiles": 85, "inspirationFor": "Wildlife Monitoring"}},
        {"id": "anniversary", "vector": anniversary_embedding, "payload": {"type": "Event", "name": "24th Wedding Anniversary", "date": "2024-09", "activity": "Climbed Mount Princeton"}},
        {"id": "blacksmithing", "vector": blacksmithing_embedding, "payload": {"type": "Experience", "description": "Learned blacksmithing in Salida", "startDate": "2024-12", "durationMonths": 3, "mentor": "Old-timer in Salida", "product": "Custom door handles"}}
    ]
)

# 3. Relationships (as payload references)
# To represent relationships, add reference IDs in payloads (manual traversal in app):
# Example: Add 'participatedIn' to Kaiser
qdrant_client.upsert(
    collection_name="entities",
    points=[
        {"id": "kaiser", "payload": {"participatedIn": ["backpacking"], "inspired": ["wildlife"], "marriedTo": ["nancy"], "celebrated": ["anniversary"], "learnedSkill": ["blacksmithing"], "generatedIdea": ["resilience"]}}
    ]
)
# Similarly, update other entities as needed for relationships.
