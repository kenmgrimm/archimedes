# Weaviate (Python) - Example Content to Graph (Core Types)
# Core Types: Person, Place, Event, Project, Idea, Experience

# 1. Schema (run once)
client.schema.create_class({
    "class": "Person",
    "properties": [{"name": "name", "dataType": ["text"]}]
})
client.schema.create_class({
    "class": "Place",
    "properties": [
        {"name": "name", "dataType": ["text"]},
        {"name": "type", "dataType": ["text"]},
        {"name": "state", "dataType": ["text"]},
        {"name": "elevation", "dataType": ["number"]}
    ]
})
client.schema.create_class({
    "class": "Project",
    "properties": [
        {"name": "name", "dataType": ["text"]},
        {"name": "status", "dataType": ["text"]},
        {"name": "inspiration", "dataType": ["text"]}
    ]
})
client.schema.create_class({
    "class": "Idea",
    "properties": [
        {"name": "name", "dataType": ["text"]},
        {"name": "topics", "dataType": ["text[]"]}
    ]
})
client.schema.create_class({
    "class": "Experience",
    "properties": [
        {"name": "description", "dataType": ["text"]},
        {"name": "startDate", "dataType": ["text"]},
        {"name": "durationDays", "dataType": ["number"]},
        {"name": "durationMonths", "dataType": ["number"]},
        {"name": "distanceMiles", "dataType": ["number"]},
        {"name": "mentor", "dataType": ["text"]},
        {"name": "product", "dataType": ["text"]},
        {"name": "inspirationFor", "dataType": ["text"]}
    ]
})
client.schema.create_class({
    "class": "Event",
    "properties": [
        {"name": "name", "dataType": ["text"]},
        {"name": "date", "dataType": ["text"]},
        {"name": "activity", "dataType": ["text"]}
    ]
})

# 2. Data objects
kaiser_id = client.data_object.create({"name": "Kaiser Soze"}, "Person")
nancy_id = client.data_object.create({"name": "Nancy Soze"}, "Person")
collegiate_id = client.data_object.create({"name": "Collegiate Peaks Wilderness", "type": "Wilderness", "state": "Colorado"}, "Place")
princeton_id = client.data_object.create({"name": "Mount Princeton", "type": "Mountain", "elevation": 14197, "state": "Colorado"}, "Place")
salida_id = client.data_object.create({"name": "Salida", "type": "Town", "state": "Colorado"}, "Place")
wildlife_id = client.data_object.create({"name": "Wildlife Monitoring", "status": "Concept", "inspiration": "Collegiate Peaks trip"}, "Project")
resilience_id = client.data_object.create({"name": "Community Resilience Through Technology", "topics": ["mesh networks", "resource sharing", "AI disaster response"]}, "Idea")
backpacking_id = client.data_object.create({"description": "Solo backpacking trip", "startDate": "2024-06", "durationDays": 8, "distanceMiles": 85, "inspirationFor": "Wildlife Monitoring"}, "Experience")
anniversary_id = client.data_object.create({"name": "24th Wedding Anniversary", "date": "2024-09", "activity": "Climbed Mount Princeton"}, "Event")
blacksmithing_id = client.data_object.create({"description": "Learned blacksmithing in Salida", "startDate": "2024-12", "durationMonths": 3, "mentor": "Old-timer in Salida", "product": "Custom door handles"}, "Experience")

# 3. Cross-references (relationships)
client.data_object.reference_add(kaiser_id, "participatedIn", backpacking_id)
client.data_object.reference_add(kaiser_id, "inspired", wildlife_id)
client.data_object.reference_add(backpacking_id, "tookPlaceAt", collegiate_id)
client.data_object.reference_add(kaiser_id, "marriedTo", nancy_id)
client.data_object.reference_add(kaiser_id, "celebrated", anniversary_id)
client.data_object.reference_add(nancy_id, "celebrated", anniversary_id)
client.data_object.reference_add(anniversary_id, "tookPlaceAt", princeton_id)
client.data_object.reference_add(kaiser_id, "learnedSkill", blacksmithing_id)
client.data_object.reference_add(blacksmithing_id, "tookPlaceAt", salida_id)
client.data_object.reference_add(kaiser_id, "generatedIdea", resilience_id)
