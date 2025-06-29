# --- 3. Define Schema Classes ---
# Person class with all relationship properties included
weaviate = WeaviateService.new

weaviate.ensure_class("Pet", [
                        { name: "name", dataType: ["text"] },
                        { name: "species", dataType: ["text"] },
                        { name: "age", dataType: ["number"] },
                        { name: "description", dataType: ["text"] }
                      ], "A pet entity")

weaviate.ensure_class("Place", [
                        { name: "name", dataType: ["text"] },
                        { name: "type", dataType: ["text"] },
                        { name: "elevation", dataType: ["number"] },
                        { name: "description", dataType: ["text"] }
                      ], "A place entity")

weaviate.ensure_class("Project", [
                        { name: "name", dataType: ["text"] },
                        { name: "description", dataType: ["text"] }
                      ], "A project entity")

weaviate.ensure_class("Person", [
                        { name: "name", dataType: ["text"] },
                        { name: "birthDate", dataType: ["text"] },
                        { name: "occupation", dataType: ["text"] },
                        { name: "description", dataType: ["text"] },
                        { name: "spouse", dataType: ["Person"] },
                        { name: "children", dataType: ["Person"] },
                        { name: "parents", dataType: ["Person"] },
                        { name: "pets", dataType: ["Pet"] },
                        { name: "home", dataType: ["Place"] },
                        { name: "projects", dataType: ["Project"] }
                      ], "A person entity")

weaviate.ensure_class("Vehicle", [
                        { name: "make_model", dataType: ["text"] },
                        { name: "vin", dataType: ["text"] },
                        { name: "license_plate", dataType: ["text"] },
                        { name: "registration_status", dataType: ["text"] },
                        { name: "insurance", dataType: ["text"] },
                        { name: "odometer", dataType: ["number"] },
                        { name: "color", dataType: ["text"] }
                      ], "A vehicle entity")

weaviate.ensure_class("Document", [
                        { name: "file_name", dataType: ["text"] },
                        { name: "description", dataType: ["text"] }
                      ], "A scanned or attached document")

# Generic List and ListItem classes
weaviate.ensure_class("List", [
                        { name: "name", dataType: ["text"] },
                        { name: "description", dataType: ["text"] },
                        { name: "listType", dataType: ["text"] } # e.g., 'grocery', 'hardware', 'marketplace', 'supplies', 'process_steps'
                      ], "A generic list of items")

weaviate.ensure_class("ListItem", [
                        { name: "name", dataType: ["text"] },
                        { name: "quantity", dataType: ["number"] },
                        { name: "unit", dataType: ["text"] },
                        { name: "position", dataType: ["number"] },
                        { name: "category", dataType: ["text"] },
                        { name: "notes", dataType: ["text"] },
                        { name: "parentList", dataType: ["List"] } # Reference to parent list
                      ], "A generic item in a list")

# --- 4. Insert Entities ---
# Family
kaiser_id = weaviate.upsert_object("Person", {
                                     name: "Kaiser Soze",
                                     birthDate: "1965-11-01",
                                     occupation: "Entrepreneur, AI Enthusiast",
                                     description: "Legendary strategist and polymath. Enjoys mountaineering, AI/ML, woodworking, blacksmithing."
                                   })

heinrich_id = weaviate.upsert_object("Person", { name: "Heinrich Soze" })
greta_id    = weaviate.upsert_object("Person", { name: "Greta Soze" })
nancy_id    = weaviate.upsert_object("Person", { name: "Nancy Soze" })
sarah_id    = weaviate.upsert_object("Person", { name: "Sarah Soze" })
john_id     = weaviate.upsert_object("Person", { name: "John Soze" })

# Pets
max_id      = weaviate.upsert_object("Pet", { name: "Max", species: "Dog" })
whiskers_id = weaviate.upsert_object("Pet", { name: "Whiskers", species: "Cat" })

# Place (Home)
home_id = weaviate.upsert_object("Place", {
                                   name: "Soze Family Cabin",
                                   type: "Log Cabin",
                                   elevation: 10_200,
                                   description: "Custom log cabin at 10,200ft elevation, Leadville, CO."
                                 })

# Projects
leadville_db_id = weaviate.upsert_object("Project", {
                                           name: "Leadville Historical Database",
                                           description: "Digitizing and connecting Leadville's rich historical records."
                                         })

wildlife_id = weaviate.upsert_object("Project", {
                                       name: "Wildlife Monitoring System",
                                       description: "IoT and AI-powered wildlife tracking for the Rockies."
                                     })

summit_id = weaviate.upsert_object("Project", {
                                     name: 'Personal AI Assistant "Summit"',
                                     description: "Personal knowledge graph and AI assistant."
                                   })

cabin_upgrades_id = weaviate.upsert_object("Project", {
                                             name: "Sustainable Cabin Upgrades",
                                             description: "Solar, insulation, and eco-friendly improvements."
                                           })

# --- 5. Add Relationships (References) ---
# Kaiser's relationships
weaviate.add_reference("Person", kaiser_id, "spouse", "Person", nancy_id)
weaviate.add_reference("Person", kaiser_id, "children", "Person", sarah_id)
weaviate.add_reference("Person", kaiser_id, "children", "Person", john_id)
weaviate.add_reference("Person", kaiser_id, "parents", "Person", heinrich_id)
weaviate.add_reference("Person", kaiser_id, "parents", "Person", greta_id)
weaviate.add_reference("Person", kaiser_id, "pets", "Pet", max_id)
weaviate.add_reference("Person", kaiser_id, "pets", "Pet", whiskers_id)
weaviate.add_reference("Person", kaiser_id, "home", "Place", home_id)
weaviate.add_reference("Person", kaiser_id, "projects", "Project", leadville_db_id)
weaviate.add_reference("Person", kaiser_id, "projects", "Project", wildlife_id)
weaviate.add_reference("Person", kaiser_id, "projects", "Project", summit_id)
weaviate.add_reference("Person", kaiser_id, "projects", "Project", cabin_upgrades_id)

puts "Kaiser Soze knowledge graph loaded into Weaviate!"
