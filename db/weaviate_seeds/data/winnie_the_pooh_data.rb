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
        
        # Load and create pets from YAML if available
        if people_data['pets']
          people_data['pets'].each do |pet_key, pet_attrs|
            pet_id = weaviate.upsert_object("Pet", pet_attrs.symbolize_keys)
            object_ids[pet_key.to_sym] = pet_id
            pets << { id: pet_id, relationship: "pet" }
            puts "✅ Created #{pet_attrs['name']} (ID: #{pet_id})"
          end
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
        
        puts "📝 Adding documents..."
        documents = [
          {
            id: weaviate.upsert_object("Document", {
              title: "Winnie The Pooh - Professional Resume",
              description: "Comprehensive professional background, skills, and work history",
              file_name: "winnie_pooh_resume_2023.pdf",
              file_type: "pdf",
              file_size: 1024000,
              created_at: "2023-01-15",
              last_modified: "2023-01-15",
              author: "Winnie The Pooh",
              tags: ["professional", "cv", "experience", "education"],
              content_summary: "Detailed professional history including education, work experience, publications, and skills.",
              security: "confidential"
            }),
            created_by: winnie_the_pooh_id,
            related_to: []
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "Mountain Climbing Guide - Rocky Mountains",
              description: "Personal notes on climbing routes, conditions, and safety",
              file_name: "rocky_mountains_climbing_guide_2023.md",
              file_type: "markdown",
              file_size: 512000,
              created_at: "2023-03-22",
              last_modified: "2023-05-10",
              author: "Winnie The Pooh",
              tags: ["hobbies", "outdoors", "safety", "guide"],
              content_summary: "Comprehensive guide to climbing routes in the Rocky Mountains, including difficulty ratings, gear requirements, and personal notes.",
              security: "private"
            }),
            created_by: winnie_the_pooh_id,
            related_to: []
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "Woodworking Project Plans - 2023",
              description: "Detailed plans and sketches for woodworking projects",
              file_name: "woodworking_plans_2023.pdf",
              file_type: "pdf",
              file_size: 2048000,
              created_at: "2023-02-10",
              last_modified: "2023-06-15",
              author: "Winnie The Pooh",
              tags: ["woodworking", "projects", "plans", "diy"],
              content_summary: "Collection of detailed plans for furniture and woodworking projects, including materials lists and cut diagrams.",
              security: "private"
            }),
            created_by: winnie_the_pooh_id,
            related_to: []
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "AI Research Notes - Neural Networks",
              description: "Research notes on advanced neural network architectures",
              file_name: "ai_research_neural_networks_2023.ipynb",
              file_type: "ipynb",
              file_size: 3072000,
              created_at: "2023-04-05",
              last_modified: "2023-07-01",
              author: "Winnie The Pooh",
              tags: ["ai", "research", "neural-networks", "machine-learning"],
              content_summary: "Jupyter notebook containing research on transformer architectures and attention mechanisms.",
              security: "confidential"
            }),
            created_by: winnie_the_pooh_id,
            related_to: []
          },
          # Vehicle Documents
          {
            id: weaviate.upsert_object("Document", {
              title: "Ford Raptor - Front License Plate",
              description: "Front view of the Ford Raptor showing license plate COL-2022-RPT",
              file_name: "ford_raptor_front_license_plate_20220105.jpg",
              file_type: "jpg",
              file_size: 3520000,
              width: 4032,
              height: 3024,
              created_at: "2022-01-05",
              last_modified: "2022-01-05",
              author: "Winnie The Pooh",
              tags: ["vehicle", "raptor", "ford", "license_plate", "registration"],
              content_summary: "Front view of the Ford Raptor showing the license plate and front grille.",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/photos/front_license_plate_20220105.jpg",
              },
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle"}
            ]
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "Ford Raptor - VIN and Door Jamb Sticker",
              description: "Close-up of the door jamb sticker showing VIN and manufacturing details",
              file_name: "ford_raptor_vin_door_jamb_sticker_20211220.jpg",
              file_type: "jpg",
              file_size: 4120000,
              width: 3024,
              height: 4032,
              created_at: "2021-12-20",
              last_modified: "2021-12-20",
              author: "Winnie The Pooh",
              tags: ["vehicle", "raptor", "ford", "vin", "manufacturing", "specs"],
              content_summary: "Door jamb sticker showing VIN: 1FTFW1RGXNKE12345, manufacturing date, GVWR, and other specifications.",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/documents/vin_door_jamb_sticker_20211220.jpg",
              },
              extracted_text: "VIN: 1FTFW1RGXNKE12345\nManufactured: 11/2021\nGVWR: 7212 lbs\nGAWR FRT: 4000 lbs\nGAWR RR: 3875 lbs\nTire Size: 315/70R17\nPSI: 38 Front / 38 Rear\nPaint Code: UH",
              document_id: "doc_raptor_vin_sticker_001"
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "Ford Raptor - Window Sticker",
              description: "Original window sticker showing MSRP and factory options",
              file_name: "ford_raptor_window_sticker_20211215.pdf",
              file_type: "pdf",
              file_size: 1250000,
              created_at: "2021-12-15",
              last_modified: "2021-12-15",
              author: "Ford Motor Company",
              tags: ["vehicle", "raptor", "ford", "window_sticker", "specs", "msrp"],
              content_summary: "Original window sticker showing MSRP, standard features, and factory options for the 2022 Ford F-150 Raptor.",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/documents/window_sticker_20211215.pdf",
              },
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          # Registration Documents
          {
            id: weaviate.upsert_object("Document", {
              title: "2024 Vehicle Registration - Ford Raptor",
              description: "2024 Colorado DMV registration document",
              file_name: "ford_raptor_registration_2024.jpg",
              file_type: "jpg",
              file_size: 1850000,
              width: 2000,
              height: 3000,
              created_at: "2024-01-15",
              last_modified: "2024-01-15",
              author: "Colorado Department of Motor Vehicles",
              tags: ["vehicle", "raptor", "ford", "registration", "dmv", "2024"],
              content_summary: "2024 Colorado vehicle registration for Ford Raptor (1FTFW1RGXNKE12345)",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/documents/registration/registration_2024.jpg",
              },
              extracted_text: "COLORADO DEPARTMENT OF REVENUE\nVEHICLE REGISTRATION\n\nYEAR: 2022\nMAKE: FORD\nMODEL: F-150 RAPTOR\nVIN: 1FTFW1RGXNKE12345\nPLATE: COL-2022-RPT\nEXPIRES: 12/2024\n\nREGISTERED OWNER:\nWINNIE THE POOH\n123 HUNDRED ACRE WOOD\nDENVER, CO 80202\n\nVEHICLE USE: PERSONAL\nWEIGHT: 5,950 LBS\n\nFEES PAID: $1,256.00\nREGISTRATION DATE: 01/15/2024"
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "2023 Vehicle Registration - Ford Raptor",
              description: "2023 Colorado DMV registration document",
              file_name: "ford_raptor_registration_2023.jpg",
              file_type: "jpg",
              file_size: 1920000,
              width: 2000,
              height: 3000,
              created_at: "2023-01-10",
              last_modified: "2023-01-10",
              author: "Colorado Department of Motor Vehicles",
              tags: ["vehicle", "raptor", "ford", "registration", "dmv", "2023"],
              content_summary: "2023 Colorado vehicle registration for Ford Raptor (1FTFW1RGXNKE12345)",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/documents/registration/registration_2023.jpg",
              }
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          # Maintenance Records
          {
            id: weaviate.upsert_object("Document", {
              title: "30,000 Mile Service - Ford Raptor",
              description: "30,000 mile maintenance service invoice",
              file_name: "ford_raptor_30000_mile_service_20240315.pdf",
              file_type: "pdf",
              file_size: 1250000,
              created_at: "2024-03-15",
              last_modified: "2024-03-15",
              author: "Denver Auto Care",
              tags: ["vehicle", "raptor", "ford", "maintenance", "service", "invoice"],
              content_summary: "30,000 mile service including oil change, tire rotation, and multi-point inspection",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/maintenance/30000_mile_service_20240315.pdf",
              },
              extracted_text: "DENVER AUTO CARE\n1234 AUTO LANE, DENVER, CO 80202\nPHONE: (303) 555-0123\n\nINVOICE #DAC-2024-0315-001\n\nCUSTOMER: WINNIE THE POOH\nVEHICLE: 2022 FORD F-150 RAPTOR\nVIN: 1FTFW1RGXNKE12345\nMILEAGE: 30,125\n\nSERVICES PERFORMED:\n- SYNTHETIC OIL CHANGE\n- OIL FILTER REPLACEMENT\n- TIRE ROTATION\n- MULTI-POINT INSPECTION\n- FLUID LEVELS CHECKED\n- BRAKE INSPECTION\n\nTOTAL: $189.75\n\nTECHNICIAN NOTES: Vehicle in good condition. Brake pads at 70% life. Air filter slightly dirty, recommend replacement at next service.\n\nNEXT SERVICE DUE: 35,000 MILES OR 11/2024"
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "Tire Replacement - Ford Raptor",
              description: "Tire replacement and alignment service",
              file_name: "ford_raptor_tire_replacement_20231110.jpg",
              file_type: "jpg",
              file_size: 2450000,
              width: 3000,
              height: 4000,
              created_at: "2023-11-10",
              last_modified: "2023-11-10",
              author: "Mountain View Tire & Auto",
              tags: ["vehicle", "raptor", "ford", "maintenance", "tires", "alignment"],
              content_summary: "Replacement of all four tires with BFGoodrich All-Terrain T/A KO2 and 4-wheel alignment",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/maintenance/tire_replacement_20231110.jpg",
              },
              extracted_text: "MOUNTAIN VIEW TIRE & AUTO\n5678 PEAK STREET, BOULDER, CO 80301\nPHONE: (303) 555-9876\n\nINVOICE #MVT-2023-1110-045\n\nCUSTOMER: WINNIE THE POOH\nVEHICLE: 2022 FORD F-150 RAPTOR\nMILEAGE: 24,875\n\nSERVICES PERFORMED:\n- (4) BFGOODRICH ALL-TERRAIN T/A KO2 315/70R17\n- 4-WHEEL ALIGNMENT\n- TIRE DISPOSAL FEE\n- NITROGEN FILL\n\nTOTAL: $1,845.60\n\nWARRANTY: 50,000 MILE TREADWEAR\nNEXT ROTATION DUE: 5,000 MILES"
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "State Inspection - Ford Raptor",
              description: "Annual state safety and emissions inspection",
              file_name: "ford_raptor_state_inspection_20240501.pdf",
              file_type: "pdf",
              file_size: 980000,
              created_at: "2024-05-01",
              last_modified: "2024-05-01",
              author: "Quick Lube & Inspection",
              tags: ["vehicle", "raptor", "ford", "inspection", "emissions", "safety"],
              content_summary: "Annual state safety and emissions inspection for 2022 Ford Raptor",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/maintenance/state_inspection_20240501.pdf",
              },
              extracted_text: "COLORADO STATE INSPECTION CERTIFICATE\n\nFACILITY: QUICK LUBE & INSPECTION #42\nFACILITY #: 42-123456\nTECHNICIAN: JOHNSON, MIKE\n\nVEHICLE INFORMATION:\nYEAR: 2022\nMAKE: FORD\nMODEL: F-150 RAPTOR\nVIN: 1FTFW1RGXNKE12345\nODOMETER: 28,745 MILES\nPLATE: COL-2022-RPT\n\nINSPECTION RESULTS:\n- SAFETY INSPECTION: PASS\n- EMISSIONS INSPECTION: PASS\n\nCERTIFICATE #: CO987654321\nEXPIRES: 04/30/2025\n\nNOTES: No issues found. Vehicle in excellent condition. Next inspection due by 04/30/2025."
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          },
          {
            id: weaviate.upsert_object("Document", {
              title: "Brake Service - Ford Raptor",
              description: "Brake pad and rotor replacement",
              file_name: "ford_raptor_brake_service_20230822.pdf",
              file_type: "pdf",
              file_size: 1120000,
              created_at: "2023-08-22",
              last_modified: "2023-08-22",
              author: "Precision Auto Service",
              tags: ["vehicle", "raptor", "ford", "maintenance", "brakes", "repair"],
              content_summary: "Front and rear brake pad and rotor replacement",
              storage: {
                provider: "s3",
                bucket: "archimedes-documents-prod",
                key: "vehicles/ford-raptor-1FTFW1RGXNKE12345/maintenance/brake_service_20230822.pdf",
              },
              extracted_text: "PRECISION AUTO SERVICE\n7890 GEAR STREET, DENVER, CO 80210\nPHONE: (303) 555-4567\n\nINVOICE #PAS-2023-0822-112\n\nCUSTOMER: WINNIE THE POOH\nVEHICLE: 2022 FORD F-150 RAPTOR\nMILEAGE: 19,845\n\nSERVICES PERFORMED:\n- REPLACE FRONT BRAKE PADS\n- RESURFACE FRONT ROTORS\n- REPLACE REAR BRAKE PADS\n- REPLACE REAR ROTORS\n- BRAKE FLUID EXCHANGE\n- BRAKE SYSTEM INSPECTION\n\nPARTS:\n- (2) FRONT BRAKE PAD SETS\n- (2) FRONT ROTORS\n- (2) REAR BRAKE PAD SETS\n- (2) REAR ROTORS\n- BRAKE FLUID\n\nTOTAL: $1,287.45\n\nWARRANTY: 24 MONTHS / 24,000 MILES\n\nTECH NOTES: Brake system bled and tested. Rotors resurfaced within specification. Test drive confirmed proper brake operation."
            }),
            created_by: winnie_the_pooh_id,
            related_to: [
              {id: object_ids[:raptor], type: "Vehicle" }
            ]
          }
        ]

        puts "📋 Adding projects..."
        projects = [
          {
            id: weaviate.upsert_object("Project", {
              name: "AI Research Initiative",
              description: "Advanced research in machine learning and neural networks, focusing on self-supervised learning and model interpretability.",
              status: "Active",
              start_date: "2022-01-01",
              end_date: "2024-12-31",
              budget: 1250000,
              technologies: ["Python", "TensorFlow", "PyTorch", "JAX"],
              team_size: 8,
              goals: [
                "Develop novel self-supervised learning algorithms",
                "Improve model interpretability",
                "Publish research papers in top AI conferences",
                "Develop open-source tools for the ML community"
              ],
              milestones: [
                { date: "2022-06-30", description: "Literature review completed" },
                { date: "2022-12-15", description: "Initial prototype developed" },
                { date: "2023-06-30", description: "First paper submitted to NeurIPS" }
              ]
            }),
            members: [winnie_the_pooh_id, friends[1][:id], friends[2][:id]]
          },
          {
            id: weaviate.upsert_object("Project", {
              name: "Sustainable Cabin Project",
              description: "Development of off-grid living solutions and sustainable technologies for remote locations.",
              status: "Ongoing",
              start_date: "2021-06-15",
              budget: 750000,
              technologies: ["Solar Power", "Rainwater Harvesting", "Permaculture", "Sustainable Building"],
              team_size: 5,
              goals: [
                "Achieve complete energy independence",
                "Implement closed-loop water system",
                "Develop sustainable food production",
                "Create replicable model for off-grid living"
              ],
              features: [
                "10kW Solar Array", "Battery Storage System", "Greywater Recycling",
                "Aquaponics System", "Passive Solar Design", "Natural Building Materials"
              ]
            }),
            members: [
              winnie_the_pooh_id, 
              *family_members[0..1]&.compact&.map { |m| m[:id] } 
            ].compact
          },
          {
            id: weaviate.upsert_object("Project", {
              name: "Mountain Rescue Drone Network",
              description: "Development of autonomous drone network for search and rescue operations in mountainous terrain.",
              status: "Planning",
              start_date: "2023-09-01",
              budget: 500000,
              technologies: ["Autonomous Drones", "Computer Vision", "RFID Tracking"],
              team_size: 6,
              goals: [
                "Develop autonomous search algorithms",
                "Create reliable communication network",
                "Implement AI-based person detection",
                "Achieve 90% success rate in test scenarios"
              ]
            }),
            members: [winnie_the_pooh_id, friends[0][:id], friends[2][:id]]
          }
        ]

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
