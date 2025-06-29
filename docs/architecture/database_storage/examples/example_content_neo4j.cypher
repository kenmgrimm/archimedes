// Neo4j (Cypher) - Example Content to Graph (Core Types)
// Core Types: Person, Place, Event, Project, Idea, Experience

// 1. People
CREATE (kaiser:Person {name: "Kaiser Soze"});
CREATE (nancy:Person {name: "Nancy Soze"});

// 2. Places
CREATE (collegiatePeaks:Place {name: "Collegiate Peaks Wilderness", type: "Wilderness", state: "Colorado"});
CREATE (mountPrinceton:Place {name: "Mount Princeton", type: "Mountain", elevation: 14197, state: "Colorado"});
CREATE (salida:Place {name: "Salida", type: "Town", state: "Colorado"});

// 3. Projects & Ideas
CREATE (wildlifeProject:Project {name: "Wildlife Monitoring", status: "Concept", inspiration: "Collegiate Peaks trip"});
CREATE (resilienceIdea:Idea {name: "Community Resilience Through Technology", topics: ["mesh networks", "resource sharing", "AI disaster response"]});

// 4. Experiences
CREATE (backpacking:Experience {description: "Solo backpacking trip", startDate: "2024-06", durationDays: 8, distanceMiles: 85, inspirationFor: "Wildlife Monitoring"});
CREATE (anniversary:Event {name: "24th Wedding Anniversary", date: "2024-09", activity: "Climbed Mount Princeton"});
CREATE (blacksmithing:Experience {description: "Learned blacksmithing in Salida", startDate: "2024-12", durationMonths: 3, mentor: "Old-timer in Salida", product: "Custom door handles"});

// 5. Relationships
CREATE (kaiser)-[:PARTICIPATED_IN]->(backpacking);
CREATE (kaiser)-[:INSPIRED]->(wildlifeProject);
CREATE (backpacking)-[:TOOK_PLACE_AT]->(collegiatePeaks);
CREATE (kaiser)-[:MARRIED_TO]->(nancy);
CREATE (kaiser)-[:CELEBRATED]->(anniversary);
CREATE (nancy)-[:CELEBRATED]->(anniversary);
CREATE (anniversary)-[:TOOK_PLACE_AT]->(mountPrinceton);
CREATE (kaiser)-[:LEARNED_SKILL]->(blacksmithing);
CREATE (blacksmithing)-[:TOOK_PLACE_AT]->(salida);
CREATE (kaiser)-[:GENERATED_IDEA]->(resilienceIdea);
