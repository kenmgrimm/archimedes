module WeaviateSeeds
  class Schema
    class << self
      def define_schema(weaviate)
        puts "\n🏗️  Setting up schema..."

        # Define all classes without references first
        define_base_classes(weaviate)
        
        # Then define reference properties
        define_reference_properties(weaviate)
        
        # Small delay to ensure schema updates are applied
        sleep 2
      end
      
      private
      
      def define_base_classes(weaviate)
        # Define Place class with enhanced attributes
        weaviate.ensure_class("Place", [
          { name: "name", dataType: ["text"] },
          { name: "type", dataType: ["text"] },
          { name: "address", dataType: ["text"] },
          { name: "coordinates", dataType: ["text"] },
          { name: "elevation", dataType: ["number"] },
          { name: "size", dataType: ["text"] },
          { name: "year_built", dataType: ["number"] },
          { name: "description", dataType: ["text"] },
          { name: "features", dataType: ["text[]"] },
          { name: "equipment", dataType: ["text[]"] },
          { name: "materials", dataType: ["text[]"] },
          { name: "safety_equipment", dataType: ["text[]"] },
          { 
            name: "projects",
            dataType: ["object[]"],
            nestedProperties: [
              { name: "name", dataType: ["text"] },
              { name: "status", dataType: ["text"] },
              { name: "year", dataType: ["number"] },
              { name: "started", dataType: ["text"] },
              { name: "priority", dataType: ["text"] }
            ]
          },
          { 
            name: "rooms", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "name", dataType: ["text"] },
              { name: "type", dataType: ["text"] },
              { name: "size", dataType: ["text"] },
              { name: "description", dataType: ["text"] },
              { name: "floor_level", dataType: ["number"] },
              { name: "has_windows", dataType: ["boolean"] },
              { name: "features", dataType: ["text[]"] }
            ]
          }
        ], "A place entity with detailed attributes and room information")

        # Define Person class with enhanced attributes
        weaviate.ensure_class("Person", [
          { name: "name", dataType: ["text"] },
          { name: "birthDate", dataType: ["text"] },
          { name: "occupation", dataType: ["text"] },
          { name: "email", dataType: ["text"] },
          { name: "phone", dataType: ["text"] },
          { name: "skills", dataType: ["text[]"] },
          { name: "description", dataType: ["text"] },
          { name: "address", dataType: ["text"] },
          { name: "website", dataType: ["text"] },
          { 
            name: "social_media", 
            dataType: ["object"],
            nestedProperties: [
              { name: "twitter", dataType: ["text"] },
              { name: "linkedin", dataType: ["text"] },
              { name: "github", dataType: ["text"] },
              { 
                name: "other", 
                dataType: ["object"],
                nestedProperties: [
                  { name: "platform", dataType: ["text"] },
                  { name: "url", dataType: ["text"] },
                  { name: "username", dataType: ["text"] }
                ]
              }
            ]
          },
          { 
            name: "education", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "institution", dataType: ["text"] },
              { name: "degree", dataType: ["text"] },
              { name: "field_of_study", dataType: ["text"] },
              { name: "start_date", dataType: ["text"] },
              { name: "end_date", dataType: ["text"] },
              { name: "description", dataType: ["text"] }
            ]
          },
          { name: "relationship", dataType: ["text"] },
          { name: "workplace", dataType: ["text"] }
        ], "A person entity with detailed personal and professional information")

        # Define Project class with enhanced attributes
        weaviate.ensure_class("Project", [
          { name: "name", dataType: ["text"] },
          { name: "description", dataType: ["text"] },
          { name: "status", dataType: ["text"] },
          { name: "start_date", dataType: ["text"] },
          { name: "end_date", dataType: ["text"] },
          { name: "budget", dataType: ["number"] },
          { name: "goals", dataType: ["text[]"] },
          { 
            name: "milestones", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "name", dataType: ["text"] },
              { name: "description", dataType: ["text"] },
              { name: "due_date", dataType: ["text"] },
              { name: "status", dataType: ["text"] },
              { name: "completed_at", dataType: ["text"] },
              { name: "dependencies", dataType: ["text[]"] }
            ]
          },
          { name: "technologies", dataType: ["text[]"] },
          { 
            name: "team_members", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "name", dataType: ["text"] },
              { name: "role", dataType: ["text"] },
              { name: "email", dataType: ["text"] },
              { name: "skills", dataType: ["text[]"] },
              { name: "allocation_percentage", dataType: ["number"] }
            ]
          },
          { name: "repository_url", dataType: ["text"] },
          { name: "documentation_url", dataType: ["text"] }
        ], "A project entity with detailed planning and execution information")

        # Define Pet class with enhanced attributes
        weaviate.ensure_class("Pet", [
          { name: "name", dataType: ["text"] },
          { name: "species", dataType: ["text"] },
          { name: "breed", dataType: ["text"] },
          { name: "age", dataType: ["number"] },
          { name: "birthDate", dataType: ["text"] },
          { name: "color", dataType: ["text"] },
          { name: "description", dataType: ["text"] },
          { name: "skills", dataType: ["text[]"] },
          { name: "personality", dataType: ["text[]"] },
          { name: "favorite_spot", dataType: ["text"] },
          { name: "training", dataType: ["text[]"] },
          { 
            name: "medical_history", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "date", dataType: ["text"] },
              { name: "veterinarian", dataType: ["text"] },
              { name: "diagnosis", dataType: ["text"] },
              { name: "treatment", dataType: ["text"] },
              { name: "medications", dataType: ["text[]"] },
              { name: "notes", dataType: ["text"] },
              { name: "follow_up_date", dataType: ["text"] }
            ]
          }
        ], "A pet entity with detailed attributes and medical history")

        # Define Document class with enhanced attributes
        weaviate.ensure_class("Document", [
          { name: "title", dataType: ["text"] },
          { name: "file_name", dataType: ["text"] },
          { name: "description", dataType: ["text"] },
          { name: "file_type", dataType: ["text"] },
          { name: "file_size", dataType: ["number"] },
          { name: "content", dataType: ["text"] },
          { name: "created_at", dataType: ["text"] },
          { name: "updated_at", dataType: ["text"] },
          { name: "author", dataType: ["text"] },
          { name: "tags", dataType: ["text[]"] },
          { name: "security_level", dataType: ["text"] },
          { name: "version", dataType: ["text"] },
          { name: "summary", dataType: ["text"] },
          { name: "keywords", dataType: ["text[]"] },
          { name: "status", dataType: ["text"] }
        ], "A document entity with detailed metadata and content information")

        # Define List class with enhanced attributes
        weaviate.ensure_class("List", [
          { name: "title", dataType: ["text"] },
          { name: "description", dataType: ["text"] },
          { name: "category", dataType: ["text"] },
          { name: "created_at", dataType: ["text"] },
          { name: "updated_at", dataType: ["text"] },
          { name: "due_date", dataType: ["text"] },
          { name: "priority", dataType: ["text"] },
          { name: "status", dataType: ["text"] },
          { name: "tags", dataType: ["text[]"] },
          { name: "is_shared", dataType: ["boolean"] },
          { name: "shared_with", dataType: ["text[]"] },
          { name: "reminder_date", dataType: ["text"] },
          { name: "color_code", dataType: ["text"] },
          { name: "is_pinned", dataType: ["boolean"] }
        ], "A list entity with enhanced organization and sharing features")

        # Define ListItem class with enhanced attributes
        weaviate.ensure_class("ListItem", [
          { name: "content", dataType: ["text"] },
          { name: "description", dataType: ["text"] },
          { name: "completed", dataType: ["boolean"] },
          { name: "due_date", dataType: ["text"] },
          { name: "created_at", dataType: ["text"] },
          { name: "updated_at", dataType: ["text"] },
          { name: "priority", dataType: ["text"] },
          { name: "status", dataType: ["text"] },
          { name: "tags", dataType: ["text[]"] },
          { name: "assignee", dataType: ["text"] },
          { name: "estimated_time", dataType: ["number"] },
          { name: "time_spent", dataType: ["number"] },
          { name: "start_date", dataType: ["text"] },
          { name: "completed_at", dataType: ["text"] },
          { name: "reminder_date", dataType: ["text"] },
          { name: "recurring", dataType: ["boolean"] },
          { name: "recurrence_pattern", dataType: ["text"] },
          { name: "notes", dataType: ["text"] },
          { name: "attachments", dataType: ["text[]"] },
          { 
            name: "custom_fields", 
            dataType: ["object"],
            nestedProperties: [
              { name: "field_name", dataType: ["text"] },
              { name: "field_type", dataType: ["text"] },
              { name: "value", dataType: ["text"] }
            ]
          }
        ], "A list item entity with detailed task management capabilities")

        # Define Vehicle class with enhanced attributes
        weaviate.ensure_class("Vehicle", [
          { name: "make", dataType: ["text"] },
          { name: "model", dataType: ["text"] },
          { name: "year", dataType: ["number"] },
          { name: "vin", dataType: ["text"] },
          { name: "color", dataType: ["text"] },
          { name: "type", dataType: ["text"] },
          { name: "fuel_type", dataType: ["text"] },
          { name: "transmission", dataType: ["text"] },
          { name: "engine", dataType: ["text"] },
          { name: "mileage", dataType: ["number"] },
          { name: "registration", dataType: ["text"] },
          { name: "insurance", dataType: ["text"] },
          { name: "purchase_date", dataType: ["text"] },
          { name: "description", dataType: ["text"] },
          { name: "features", dataType: ["text[]"] },
          { 
            name: "maintenance", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "type", dataType: ["text"] },
              { name: "description", dataType: ["text"] },
              { name: "frequency_miles", dataType: ["number"] },
              { name: "frequency_months", dataType: ["number"] },
              { name: "last_completed_date", dataType: ["text"] },
              { name: "next_due_date", dataType: ["text"] },
              { name: "cost", dataType: ["number"] },
              { name: "notes", dataType: ["text"] }
            ]
          },
          { name: "last_service_date", dataType: ["text"] },
          { name: "next_service_due", dataType: ["text"] },
          { 
            name: "service_history", 
            dataType: ["object[]"],
            nestedProperties: [
              { name: "date", dataType: ["text"] },
              { name: "odometer", dataType: ["number"] },
              { name: "service_type", dataType: ["text"] },
              { name: "description", dataType: ["text"] },
              { name: "service_provider", dataType: ["text"] },
              { name: "cost", dataType: ["number"] },
              { name: "receipt_reference", dataType: ["text"] },
              { name: "warranty_claim", dataType: ["boolean"] },
              { name: "notes", dataType: ["text"] }
            ]
          },
          { name: "warranty_expiry", dataType: ["text"] },
          { name: "license_plate", dataType: ["text"] },
          { name: "status", dataType: ["text"] }
        ], "A vehicle entity with detailed specifications and maintenance history")
      end
      
      def define_reference_properties(weaviate)
        # Update Person class with references
        weaviate.update_class_properties("Person", [
          { name: "pets", dataType: ["Pet"] },
          { name: "vehicles", dataType: ["Vehicle"] },
          { name: "documents", dataType: ["Document"] },
          { name: "projects", dataType: ["Project"] },
          { name: "home", dataType: ["Place"] },
          { name: "homes", dataType: ["Place"] },
          { name: "family", dataType: ["Person"] },
          { name: "friends", dataType: ["Person"] }
        ])

        # Update Pet class with references
        weaviate.update_class_properties("Pet", [
          { name: "owner", dataType: ["Person"] },
          { name: "home", dataType: ["Place"] }
        ])

        # Update Place class with references
        weaviate.update_class_properties("Place", [
          { name: "residents", dataType: ["Person"] },
          { name: "pets", dataType: ["Pet"] },
          { name: "vehicles", dataType: ["Vehicle"] },
          { name: "documents", dataType: ["Document"] },
          { name: "lists", dataType: ["List"] },
          { name: "projects", dataType: ["Project"] }
        ])

        # Update Project class with references
        weaviate.update_class_properties("Project", [
          { name: "members", dataType: ["Person"] },
          { name: "documents", dataType: ["Document"] },
          { name: "lists", dataType: ["List"] },
          { name: "related_to", dataType: ["Place", "Project"] },
          { name: "vehicles", dataType: ["Vehicle"] }
        ])

        # Update Document class with references
        weaviate.update_class_properties("Document", [
          { name: "created_by", dataType: ["Person"] },
          { name: "related_to", dataType: ["Document", "Place", "Project", "Person", "Pet", "Vehicle"] },
          { name: "in_list", dataType: ["List"] }
        ])

        # Update List class with references
        weaviate.update_class_properties("List", [
          { name: "created_by", dataType: ["Person"] },
          { name: "items", dataType: ["ListItem"] },
          { name: "related_to", dataType: ["Place", "Project"] },
          { name: "documents", dataType: ["Document"] }
        ])

        # Update ListItem class with references
        weaviate.update_class_properties("ListItem", [
          { name: "list", dataType: ["List"] },
          { name: "assigned_to", dataType: ["Person"] },
          { name: "related_to", dataType: ["Document", "Project", "Place"] }
        ])

        # Update Vehicle class with references
        weaviate.update_class_properties("Vehicle", [
          { name: "owner", dataType: ["Person"] },
          { name: "home", dataType: ["Place"] },
          { name: "documents", dataType: ["Document"] }
        ])
      end
    end
  end
end
