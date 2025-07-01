require 'yaml'

module WeaviateSeeds
  class WinnieThePoohData
    class << self
      def seed_data(weaviate)
        @weaviate = weaviate
        @object_ids = {}
        
        fixture_loader = WeaviateSeeds::FixtureLoader.new
        puts "\n👥 Adding people..."
        
        # --- Create all objects first ---
        # Load all people data from fixture
        people_data = fixture_loader.people_data
        
        people_data.each do |key, attrs|
          create_and_store_object("Person", key, attrs.except(:references))
        end
        
        # --- Create pets from YAML ---
        puts "🐾 Adding pets..."
        
        # Load and create pets from YAML
          pets_data = fixture_loader.pets_data
          pets_data.each do |pet_key, pet_attrs|
            pet_id = create_and_store_object("Pet", pet_key, pet_attrs.except(:references))
            
            puts "✅ Created #{pet_attrs[:name]} (ID: #{pet_id})"
          end

        # --- Create places from YAML ---
        puts "🏠 Adding places..."

        # Load and create places from YAML
          places_data = fixture_loader.places_data
          places_data.each do |place_key, place_attrs|
            place_id = create_and_store_object("Place", place_key, place_attrs.except(:references))
            
            puts "✅ Created #{place_attrs['name']} (ID: #{place_id})"
          end

        # --- Create vehicles from YAML ---
        puts "🚗 Adding vehicles..."
        
        # Load and create vehicles from YAML
        vehicles_data = fixture_loader.vehicles_data
        vehicles_data.each do |vehicle_key, vehicle_attrs|
          vehicle_id = create_and_store_object("Vehicle", vehicle_key, vehicle_attrs.except(:references))
          puts "✅ Created #{vehicle_attrs['name']} (ID: #{vehicle_id})"
        end
        
        # --- Create documents from YAML ---
        puts "📝 Adding documents..."
        
        # Load and create documents from YAML
        documents_data = fixture_loader.documents_data
        documents_data.each do |doc_key, doc_attrs|
          # Create the document
          doc_id = create_and_store_object("Document", doc_key, doc_attrs.except(:references))
          puts "✅ Created document: #{doc_attrs[:title]} (ID: #{doc_id})"
        end

        # --- Create projects from YAML ---
        puts "📋 Adding projects..."
        
        # Load and create projects from YAML
        projects_data = fixture_loader.projects_data
        projects_data.each do |project_key, project_attrs|
          project_id = create_and_store_object("Project", project_key, project_attrs.except(:references))
          puts "✅ Created project: #{project_attrs[:name]} (ID: #{project_id})"
        end

        puts "addings lists..."
        
        # Load and create lists from YAML
        lists_data = fixture_loader.lists_data
        lists_data.each do |list_key, list_attrs|
          list_id = create_and_store_object("List", list_key, list_attrs.except(:references))
          puts "✅ Created list: #{list_attrs[:name]} (ID: #{list_id})"
        end

        # Create relationships
        puts "\n🔗 Creating relationships..."

        people_data.each do |key, attrs|
          next unless relationships = attrs.dig(:references, :relationships)

          relationships.each do |relationship|
            weaviate.add_relationship(
              lookup_object("Person", key),
              lookup_object("Person", relationship[:to]),
              :relationships,
              bidirectional: true,
              inverse_relationship: relationship[:inverse]
            )
          end
        end

        documents_data.each do |document_key, document_attrs|
          next unless references = document_attrs.dig(:references)

          document = lookup_object("Document", document_key)

          created_by_key = references[:created_by]
          related_to_key = references[:related_to] || []

          if created_by_key
            created_by = lookup_object("Person", created_by_key)
            weaviate.add_relationship(document, created_by, :created_by)
          end

          related_to_key.each do |related_to|
            related_to = lookup_object(related_to[:type], related_to[:key])
            weaviate.add_relationship(document, related_to, :related_to)
          end
        end
        
        # Connect pets
        pets_data.each do |pet_key, pet_attrs|
          next unless references = pet_attrs.dig(:references)

          pet = lookup_object("Pet", pet_key)
          owner = lookup_object("Person", references[:owner])
          weaviate.add_relationship(pet, owner, :owner)
        end

        # Connect vehicles to owner
        vehicles_data.each do |vehicle_key, vehicle_attrs|
          next unless references = vehicle_attrs.dig(:references)

          vehicle = lookup_object("Vehicle", vehicle_key)
          owner = lookup_object("Person", references[:owner])
          weaviate.add_relationship(vehicle, owner, :owner)
        end
        
        # Connect project members
        projects_data.each do |project_key, project_attrs|
          next unless references = project_attrs.dig(:references)

          project = lookup_object("Project", project_key)
          references[:members].each do |member_key|
            member = lookup_object("Person", member_key)
            weaviate.add_relationship(project, member, :members, bidirectional: true, inverse_relationship: :projects)
          end
        end

        # Connect list documents
        lists_data.each do |list_key, list_attrs|
          next unless references = list_attrs.dig(:references)

          list = lookup_object("List", list_key)
          owner = lookup_object("Person", references[:owner])
          weaviate.add_relationship(list, owner, :documents, bidirectional: true, inverse_relationship: :lists)
        end

        # Generate knowledge graph visualization
        puts "\n🎨 Generating knowledge graph visualization..."
        weaviate.display_knowledge_graph

        puts "\n✅ Successfully seeded Weaviate with Winnie The Pooh knowledge graph!"
        puts "   Visualization saved to: winnie_the_pooh_knowledge_graph.html"
        
        # Print summary
        puts "\n📊 Data Summary:"
        puts "  👥 People: #{people_data.size}"
        puts "  🐾 Pets: #{pets_data.size}"
        puts "  🏠 Places: #{places_data.size}"
        puts "  🚗 Vehicles: #{vehicles_data.size}"
        puts "  📝 Documents: #{documents_data.size}"
        puts "  📋 Projects: #{projects_data.size}"
      end
      
      private

      def lookup_object(class_name, key)
        debugger if class_name.nil? || key.nil?
        object_id = @object_ids[class_name.to_sym][key.to_sym]
        @weaviate.find_by_id(class_name, object_id)
      end
      
      # Creates a new object in Weaviate and stores its ID in the object_ids hash
      # @param class_name [Symbol] The class of the object (e.g., :Person, :Pet)
      # @param key [String, Symbol] The key to store the object ID under
      # @param attrs [Hash] The attributes for the object
      # @return [String] The ID of the created object
      def create_and_store_object(class_name, key, attrs)
        class_sym = class_name.to_sym
        key_sym = key.to_sym
        
        # Create the object in Weaviate
        id = @weaviate.upsert_object(class_name.to_s, attrs.symbolize_keys)
        
        # Store the ID in our tracking hash
        @object_ids[class_sym] ||= {}
        @object_ids[class_sym][key_sym] = id
        
        puts "✅ Created #{attrs['name']} (ID: #{id})"
        id
      end
    end
  end
end
