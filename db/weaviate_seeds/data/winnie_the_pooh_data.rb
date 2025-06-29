require 'yaml'

module WeaviateSeeds
  class WinnieThePoohData
    class << self
      def seed_data(weaviate)
        puts "\n👥 Adding people..."
        
        # Store all object IDs for reference creation
        object_ids = {}
        
        # --- Create all objects first ---
        
        # Load all people data from fixture
        people_data = YAML.load_file(Rails.root.join('test/fixtures/winnie_the_pooh/people.yml'))
        
        # Create all people from YAML (including Winnie the Pooh)
        winnie_the_pooh_id = nil
        people_data.each do |key, attrs|
          next if key == 'relationships'  # Skip relationships for now
          
          person_id = weaviate.upsert_object("Person", attrs.symbolize_keys)
          object_ids[key.to_sym] = person_id
          puts "✅ Created #{attrs['name']} (ID: #{person_id})"
          
          # Store Winnie's ID for later reference
          winnie_the_pooh_id = person_id if key == 'winnie_the_pooh'
        end
        
        # Ensure we have Winnie's ID
        unless winnie_the_pooh_id
          raise "Failed to find or create Winnie the Pooh in the people data"
        end
        
        # Initialize relationship collections
        family_members = []
        friends = []
        
        # Process all relationships from YAML
        if people_data['relationships']
          people_data['relationships'].each do |rel|
            from_key = rel['from'].to_sym
            to_key = rel['to'].to_sym
            rel_type = rel['type']
            
            # Skip if either end of the relationship doesn't exist
            unless object_ids.key?(from_key) && object_ids.key?(to_key)
              puts "⚠️  Warning: Could not find one or both entities for relationship: #{from_key} #{rel_type} #{to_key}"
              next
            end
            
            from_id = object_ids[from_key]
            to_id = object_ids[to_key]
            
            # Categorize relationships for later reference
            if from_key == :winnie_the_pooh
              if %w[father mother sister brother].include?(rel_type)
                family_members << { id: to_id, relationship: rel_type }
              else
                friends << { id: to_id, relationship: rel_type }
              end
              puts "✅ Added relationship: #{from_key} #{rel_type} #{to_key}"
            end
            
            # Handle bidirectional relationships
            if to_key == :winnie_the_pooh
              if %w[father mother].include?(rel_type)
                family_members << { id: from_id, relationship: rel_type == 'father' ? 'son' : 'daughter' }
              elsif %w[sister brother].include?(rel_type)
                family_members << { id: from_id, relationship: rel_type }
              else
                friends << { id: from_id, relationship: rel_type }
              end
              puts "✅ Added relationship: #{to_key} #{rel_type} #{from_key}"
            end
          end
        end
        
        # Deduplicate family_members and friends arrays
        family_members.uniq! { |m| m[:id] }
        friends.uniq! { |f| f[:id] }

        # --- Create pets from YAML ---
        puts "🐾 Adding pets..."
        pets = []
        
        # Load and create pets from YAML
        pets_file = Rails.root.join('test/fixtures/winnie_the_pooh/pets.yml')
        if File.exist?(pets_file)
          pets_data = YAML.load_file(pets_file)
          pets_data.each do |pet_key, pet_attrs|
            # Handle symbol references in the YAML
            pet_attrs = pet_attrs.deep_symbolize_keys
            
            # Process owner reference
            owner_ref = pet_attrs.delete(:owner)
            owner_id = case owner_ref&.to_s
                      when /^winnie_the_pooh_id$/
                        winnie_the_pooh_id
                      when /^friend_(\d+)_id$/
                        friends[$1.to_i - 1]&.dig(:id)
                      when /^family_member_(\d+)_id$/
                        family_members[$1.to_i - 1]&.dig(:id)
                      else
                        owner_ref ? binding.local_variable_get(owner_ref) : nil
                      end
            
            # Create the pet
            pet_id = weaviate.upsert_object("Pet", pet_attrs.except(:owner, :relationship))
            object_ids[pet_key.to_sym] = pet_id
            
            # Store pet info for relationships
            relationship = pet_attrs[:relationship] || "pet"
            pets << { id: pet_id, relationship: relationship }
            
            # Add pet-owner relationship if owner exists
            if owner_id
              weaviate.add_reference("Person", owner_id, "pets", "Pet", pet_id)
              weaviate.add_reference("Pet", pet_id, "owner", "Person", owner_id)
            end
            
            puts "✅ Created #{pet_attrs[:name]} (ID: #{pet_id})"
          end
        else
          puts "ℹ️  No pets.yml file found at #{pets_file}"
          # Initialize with empty pets array if no file found
          pets = []
        end

        # --- Create places from YAML ---
        puts "🏠 Adding places..."
        places = []

        # Load and create places from YAML
        places_file = Rails.root.join('test/fixtures/winnie_the_pooh/places.yml')
        if File.exist?(places_file)
          places_data = YAML.load_file(places_file)
          places_data.each do |place_key, place_attrs|
            place_id = weaviate.upsert_object("Place", place_attrs.symbolize_keys)
            object_ids[place_key.to_sym] = place_id
            places << { id: place_id, name: place_attrs['name'] }
            puts "✅ Created #{place_attrs['name']} (ID: #{place_id})"
          end
        else
          puts "ℹ️  No places.yml file found at #{places_file}"
          # Initialize with empty places if no file found
          places = []
        end

        # --- Create vehicles from YAML ---
        puts "🚗 Adding vehicles..."
        vehicles = []
        
        # Load and create vehicles from YAML
        vehicles_file = Rails.root.join('test/fixtures/winnie_the_pooh/vehicles.yml')
        if File.exist?(vehicles_file)
          vehicles_data = YAML.load_file(vehicles_file)
          vehicles_data.each do |vehicle_key, vehicle_attrs|
            vehicle_id = weaviate.upsert_object("Vehicle", vehicle_attrs.symbolize_keys)
            object_ids[vehicle_key.to_sym] = vehicle_id
            vehicles << { id: vehicle_id, name: vehicle_attrs['name'] }
            puts "✅ Created #{vehicle_attrs['name']} (ID: #{vehicle_id})"
          end
        else
          puts "ℹ️  No vehicles.yml file found at #{vehicles_file}"
          # Initialize with empty vehicles array if no file found
          vehicles = []
        end
        
        # --- Create documents from YAML ---
        puts "📝 Adding documents..."
        documents = []
        
        # Load and create documents from YAML
        documents_file = Rails.root.join('test/fixtures/winnie_the_pooh/documents.yml')
        if File.exist?(documents_file)
          documents_data = YAML.load_file(documents_file)
          documents_data.each do |doc_key, doc_attrs|
            # Handle symbol references in the YAML
            doc_attrs = doc_attrs.deep_symbolize_keys
            
            # Process related_to array to resolve object IDs
            related_to = Array.wrap(doc_attrs.delete(:related_to)).map do |ref|
              if ref[:id].is_a?(Symbol)
                { id: object_ids[ref[:id]], type: ref[:type] }
              else
                ref
              end
            end
            
            # Handle created_by reference
            created_by = if doc_attrs[:created_by].is_a?(Symbol)
                          binding.local_variable_get(doc_attrs.delete(:created_by))
                        else
                          doc_attrs.delete(:created_by)
                        end
            
            # Create the document
            doc_id = weaviate.upsert_object("Document", doc_attrs.except(:created_by, :related_to))
            
            # Store document info for relationships
            documents << {
              id: doc_id,
              created_by: created_by,
              related_to: related_to
            }
            
            puts "✅ Created document: #{doc_attrs[:title]} (ID: #{doc_id})"
          end
        else
          puts "ℹ️  No documents.yml file found at #{documents_file}"
          # Initialize with empty documents array if no file found
          documents = []
        end

        # --- Create projects from YAML ---
        puts "📋 Adding projects..."
        projects = []
        
        # Load and create projects from YAML
        projects_file = Rails.root.join('test/fixtures/winnie_the_pooh/projects.yml')
        if File.exist?(projects_file)
          projects_data = YAML.load_file(projects_file)
          projects_data.each do |project_key, project_attrs|
            # Handle symbol references in the YAML
            project_attrs = project_attrs.deep_symbolize_keys
            
            # Process members array to resolve IDs
            members = Array.wrap(project_attrs.delete(:members)).map do |member_ref|
              case member_ref.to_s
              when /^winnie_the_pooh_id$/
                winnie_the_pooh_id
              when /^friend_(\d+)_id$/
                friends[$1.to_i - 1]&.dig(:id)
              when /^family_member_(\d+)_id$/
                family_members[$1.to_i - 1]&.dig(:id)
              else
                binding.local_variable_get(member_ref) rescue nil
              end
            end.compact
            
            # Create the project
            project_id = weaviate.upsert_object("Project", project_attrs.except(:members, :related_documents, :related_places))
            
            # Store project info for relationships
            project_info = {
              id: project_id,
              key: project_key,
              members: members,
              related_documents: Array(project_attrs[:related_documents]),
              related_places: Array(project_attrs[:related_places])
            }
            
            projects << project_info
            
            # Add project members
            members.each do |member_id|
              weaviate.add_reference("Person", member_id, "projects", "Project", project_id)
            end
            
            puts "✅ Created project: #{project_attrs[:name]} (ID: #{project_id})"
          end
        else
          puts "ℹ️  No projects.yml file found at #{projects_file}"
          # Initialize with empty projects array if no file found
          projects = []
        end

        # Connect documents to projects
        documents[0][:related_to] = [
          {id: projects[0][:id], type: "Project" }
        ]  # Resume to AI Research
        documents[1][:related_to] = [
          {id: projects[2][:id], type: "Project" }
        ]  # Climbing Guide to Drone Network
        documents[3][:related_to] = [
          {id: projects[0][:id], type: "Project" }
        ]  # AI Notes to AI Research

        # Create relationships
        puts "\n🔗 Creating relationships..."
        
        # Family relationships
        family_members.each do |member|
          weaviate.add_reference("Person", winnie_the_pooh_id, "family", "Person", member[:id])
          weaviate.add_reference("Person", member[:id], "family", "Person", winnie_the_pooh_id)
          weaviate.add_reference("Person", member[:id], "home", "Place", places[2][:id]) # Family estate
        end

        # Friends and colleagues
        friends.each do |friend|
          weaviate.add_reference("Person", winnie_the_pooh_id, "friends", "Person", friend[:id])
          weaviate.add_reference("Person", friend[:id], "friends", "Person", winnie_the_pooh_id)
        end
        
        # Connect Kaiser to his pets
        pets.each do |pet|
          weaviate.add_reference("Person", winnie_the_pooh_id, "pets", "Pet", pet[:id])
          weaviate.add_reference("Pet", pet[:id], "owner", "Person", winnie_the_pooh_id)
          weaviate.add_reference("Pet", pet[:id], "home", "Place", places[0][:id])
        end
        
        # Connect vehicles to owner and home
        vehicles.each do |vehicle|
          if vehicle.is_a?(Hash) && vehicle[:id].present?
            if places.any? && places[0].is_a?(Hash) && places[0][:id].present?
              weaviate.add_reference("Vehicle", vehicle[:id], "home", "Place", places[0][:id])
              weaviate.add_reference("Person", winnie_the_pooh_id, "vehicles", "Vehicle", vehicle[:id])
            end
          end
        end
        
        # Connect documents to owner and projects
        documents.each do |doc|
          weaviate.add_reference("Document", doc[:id], "created_by", "Person", winnie_the_pooh_id)
          doc[:related_to].each do |related_to|
            related_to_id = related_to[:id]
            related_to_type = related_to[:type]
            weaviate.add_reference("Document", doc[:id], "related_to", related_to_type, related_to_id)
          end
        end
        
        # Connect project members
        projects.each do |project|
          project[:members].each do |member_id|
            weaviate.add_reference("Project", project[:id], "members", "Person", member_id)
            weaviate.add_reference("Person", member_id, "projects", "Project", project[:id])
          end
        end
        
        # Connect places to residents
        # Main residence (Mountain Retreat)
        weaviate.add_reference("Place", places[0][:id], "residents", "Person", winnie_the_pooh_id)
        weaviate.add_reference("Person", winnie_the_pooh_id, "homes", "Place", object_ids[:mountain_retreat])
        
        # Family estate residents
        family_members.each do |member|
          weaviate.add_reference("Place", object_ids[:family_estate], "residents", "Person", member[:id])
          weaviate.add_reference("Person", member[:id], "homes", "Place", object_ids[:family_estate])
        end

        # Add more relationships between entities
        # Colleagues (Rabbit)
        rabbit = friends.find { |f| f[:name] == "Rabbit" }
        if rabbit
          weaviate.add_reference("Person", winnie_the_pooh_id, "colleagues", "Person", rabbit[:id])
          weaviate.add_reference("Person", rabbit[:id], "colleagues", "Person", winnie_the_pooh_id)
        end
        
        # Mentor (Owl)
        owl = friends.find { |f| f[:name] == "Owl" }
        if owl
          weaviate.add_reference("Person", winnie_the_pooh_id, "mentor", "Person", owl[:id])
          weaviate.add_reference("Person", owl[:id], "mentor", "Person", winnie_the_pooh_id)
        end
        
        # Climbing partner (Tigger)
        tigger = friends.find { |f| f[:name] == "Tigger" }
        if tigger
          weaviate.add_reference("Person", winnie_the_pooh_id, "climbing_partners", "Person", tigger[:id])
          weaviate.add_reference("Person", tigger[:id], "climbing_partners", "Person", winnie_the_pooh_id)
          
          # Connect Shadow (dog) to Tigger as caretaker
          if object_ids[:shadow]
            weaviate.add_reference("Person", tigger[:id], "pets", "Pet", object_ids[:shadow])
            weaviate.add_reference("Pet", object_ids[:shadow], "caretakers", "Person", tigger[:id])
          end
        end

        # Generate knowledge graph visualization
        puts "\n🎨 Generating knowledge graph visualization..."
        weaviate.display_knowledge_graph

        puts "\n✅ Successfully seeded Weaviate with Winnie The Pooh knowledge graph!"
        puts "   Visualization saved to: winnie_the_pooh_knowledge_graph.html"
        
        # Print summary
        puts "\n📊 Data Summary:"
        puts "  👥 People: #{1 + family_members.size + friends.size}"
        puts "  🐾 Pets: #{pets.size}"
        puts "  🏠 Places: #{places.size}"
        puts "  🚗 Vehicles: #{vehicles.size}"
        puts "  📝 Documents: #{documents.size}"
        puts "  📋 Projects: #{projects.size}"
      end
    end
  end
end
