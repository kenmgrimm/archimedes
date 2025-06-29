module WeaviateSeeds
  class WinnieThePoohData
    class << self
      def seed_data(weaviate)
        puts "\n👥 Adding people..."
        
        # Store all object IDs for reference creation
        object_ids = {}
        
        # --- Create all objects first ---
        
        # Main character with enhanced attributes
        winnie_the_pooh_id = weaviate.upsert_object("Person", {
          name: "Winnie the Pooh",
          birthDate: "1965-11-01",
          occupation: "Entrepreneur, AI Researcher, Craftsman",
          email: "winnie@pooh.com",
          phone: "+1 (555) 123-4567",
          skills: ["AI/ML", "Woodworking", "Blacksmithing", "Mountaineering", "Strategy"],
          description: "A legendary strategist and polymath with a mysterious past. Known for his expertise in multiple disciplines and his secluded mountain lifestyle.",
          address: "123 Mountain View Rd, Aspen, CO 81611",
          website: "https://pooh.com",
          social_media: {
            twitter: "@winniethepooh",
            github: "winnie-the-pooh",
            linkedin: "in/winnie-the-pooh",
            other: {}
          },
          education: [
            {
              institution: "MIT",
              degree: "PhD in Computer Science",
              field_of_study: "Artificial Intelligence",
              start_date: "1990-09-01",
              end_date: "1995-05-30",
              description: "Doctoral research in neural networks and machine learning"
            },
            {
              institution: "ETH Zurich",
              degree: "MSc in Robotics",
              field_of_study: "Robotics and Control Systems",
              start_date: "1988-09-01",
              end_date: "1990-07-15",
              description: "Master's degree with focus on autonomous systems"
            }
          ]
        })
        
        object_ids[:winnie_the_pooh] = winnie_the_pooh_id
        puts "✅ Created Winnie the Pooh (ID: #{winnie_the_pooh_id})"

        # --- Create family members ---
        family_members = []
        
        # Father
        heinrich_id = weaviate.upsert_object("Person", { 
          name: "Heinrich Pooh",
          birthDate: "1935-07-15",
          occupation: "Retired Mechanical Engineer",
          relationship: "Father",
          description: "Master craftsman and engineer who taught Winnie the value of precision and hard work.",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:heinrich] = heinrich_id
        family_members << { id: heinrich_id, relationship: "father" }
        puts "✅ Created Heinrich Pooh (ID: #{heinrich_id})"
        
        # Mother
        greta_id = weaviate.upsert_object("Person", { 
          name: "Greta Pooh",
          birthDate: "1940-03-22",
          occupation: "Botanist (Retired)",
          relationship: "Mother",
          description: "Renowned botanist with a passion for alpine plants and sustainable living.",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:greta] = greta_id
        family_members << { id: greta_id, relationship: "mother" }
        puts "✅ Created Greta Pooh (ID: #{greta_id})"
        
        # Sister 1
        nancy_id = weaviate.upsert_object("Person", { 
          name: "Nancy Pooh",
          birthDate: "1968-09-14",
          occupation: "Neuroscientist",
          relationship: "Sister",
          description: "Leading researcher in neural networks and brain-computer interfaces.",
          workplace: "MIT Media Lab",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:nancy] = nancy_id
        family_members << { id: nancy_id, relationship: "sister" }
        puts "✅ Created Nancy Pooh (ID: #{nancy_id})"
        
        # Sister 2
        sarah_id = weaviate.upsert_object("Person", { 
          name: "Sarah Pooh",
          birthDate: "1971-05-30",
          occupation: "Aerospace Engineer",
          relationship: "Sister",
          description: "Senior engineer at SpaceX working on next-generation space vehicles.",
          workplace: "SpaceX",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:sarah] = sarah_id
        family_members << { id: sarah_id, relationship: "sister" }
        puts "✅ Created Sarah Pooh (ID: #{sarah_id})"
        
        # Brother
        john_id = weaviate.upsert_object("Person", { 
          name: "John Pooh",
          birthDate: "1975-12-05",
          occupation: "Executive Chef",
          relationship: "Brother",
          description: "Michelin-starred chef specializing in alpine cuisine.",
          workplace: "The Pooh Table",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:john] = john_id
        family_members << { id: john_id, relationship: "brother" }
        puts "✅ Created John Pooh (ID: #{john_id})"

        # --- Create friends and colleagues ---
        friends = []
        
        # Best Friend - Tigger
        tigger_id = weaviate.upsert_object("Person", { 
          name: "Tigger",
          birthDate: "1968-10-31",
          occupation: "Extreme Sports Athlete",
          relationship: "Best Friend",
          description: "Energetic and adventurous, always ready for the next challenge.",
          skills: ["Rock Climbing", "Base Jumping", "Mountain Biking"],
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:tigger] = tigger_id
        friends << { id: tigger_id, relationship: "best_friend" }
        puts "✅ Created Tigger (ID: #{tigger_id})"
        
        # Close Friend - Piglet
        piglet_id = weaviate.upsert_object("Person", { 
          name: "Piglet",
          birthDate: "1969-04-25",
          occupation: "Therapist",
          relationship: "Close Friend",
          description: "Compassionate listener and trusted confidant.",
          workplace: "Hundred Acre Counseling Center",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:piglet] = piglet_id
        friends << { id: piglet_id, relationship: "close_friend" }
        puts "✅ Created Piglet (ID: #{piglet_id})"
        
        # Friend - Rabbit
        rabbit_id = weaviate.upsert_object("Person", { 
          name: "Rabbit",
          birthDate: "1965-03-18",
          occupation: "Organic Farmer",
          relationship: "Friend",
          description: "Sustainable farming expert and local community leader.",
          workplace: "Hundred Acre Organic Farm",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:rabbit] = rabbit_id
        friends << { id: rabbit_id, relationship: "friend" }
        puts "✅ Created Rabbit (ID: #{rabbit_id})"
        
        # Mentor - Owl
        owl_id = weaviate.upsert_object("Person", { 
          name: "Owl",
          birthDate: "1955-11-15",
          occupation: "University Professor",
          relationship: "Mentor",
          description: "Wise advisor and professor of philosophy and ethics.",
          workplace: "Ivy League University",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:owl] = owl_id
        friends << { id: owl_id, relationship: "mentor" }
        puts "✅ Created Owl (ID: #{owl_id})"
        
        # Friend - Eeyore
        eeyore_id = weaviate.upsert_object("Person", { 
          name: "Eeyore",
          birthDate: "1967-07-07",
          occupation: "Poet",
          relationship: "Friend",
          description: "Thoughtful poet with a unique perspective on life's challenges.",
          workplace: "Freelance Writer",
          social_media: {
            twitter: "",
            github: "",
            linkedin: "",
            other: {}
          },
          education: []
        })
        object_ids[:eeyore] = eeyore_id
        friends << { id: eeyore_id, relationship: "friend" }
        puts "✅ Created Eeyore (ID: #{eeyore_id})"

        puts "🐾 Adding pets..."
        pets = []
        
        # Pet 1 - Shadow
        shadow_id = weaviate.upsert_object("Pet", {
          name: "Shadow",
          species: "German Shepherd",
          breed: "Working Line",
          birthDate: "2018-05-15",
          description: "Loyal companion and skilled search and rescue dog.",
          color: "Black and Tan",
          personality: ["Loyal", "Intelligent", "Energetic", "Protective"],
          training: ["Search and Rescue", "Obedience", "Protection"],
          medical_history: [
            {
              date: "2023-11-10",
              veterinarian: "Dr. Smith",
              diagnosis: "Annual Checkup",
              treatment: "Routine examination and vaccinations",
              medications: ["Rabies", "Distemper", "Parvovirus"],
              notes: "Healthy and active. Regular checkups every 6 months. No known allergies.",
              follow_up_date: "2024-05-10"
            },
            {
              date: "2023-05-10",
              veterinarian: "Dr. Smith",
              diagnosis: "Routine Checkup",
              treatment: "Physical examination and nail trim",
              medications: [],
              notes: "In excellent health. Maintain current exercise and diet regimen.",
              follow_up_date: "2023-11-10"
            }
          ]
        })
        object_ids[:shadow] = shadow_id
        pets << { id: shadow_id, relationship: "pet" }
        puts "✅ Created Shadow (ID: #{shadow_id})"
        
        # Pet 2 - Luna
        luna_id = weaviate.upsert_object("Pet", {
          name: "Luna",
          species: "Cat",
          breed: "Domestic Shorthair",
          birthDate: "2020-03-15",
          description: "Mysterious black cat with a penchant for napping in sunbeams.",
          color: "Black",
          personality: ["Independent", "Playful", "Affectionate"],
          favorite_spot: "Sunny window sill",
          medical_history: [
            {
              date: "2023-09-15",
              veterinarian: "Dr. Johnson",
              diagnosis: "Annual Checkup",
              treatment: "Routine examination and vaccinations",
              medications: ["Rabies", "FVRCP"],
              notes: "Indoor cat. Prefers a quiet environment. Allergic to fish-based foods.",
              follow_up_date: "2024-03-15"
            },
            {
              date: "2023-03-15",
              veterinarian: "Dr. Johnson",
              diagnosis: "Dental Cleaning",
              treatment: "Routine dental cleaning under anesthesia",
              medications: ["Antibiotics"],
              notes: "Teeth in good condition. No extractions needed.",
              follow_up_date: "2023-09-15"
            }
          ]
        })
        object_ids[:luna] = luna_id
        pets << { id: luna_id, relationship: "pet" }
        puts "✅ Created Luna (ID: #{luna_id})"
        
        # Pet 3 - Thunder
        thunder_id = weaviate.upsert_object("Pet", {
          name: "Thunder",
          species: "Horse",
          breed: "Friesian",
          birthDate: "2015-05-10",
          description: "Majestic black Friesian horse with a gentle temperament.",
          color: "Black",
          height: 16.2, # hands
          training: ["Dressage", "Trail Riding", "Driving", "Liberty"],
          medical_history: [
            {
              date: "2023-10-15",
              veterinarian: "Dr. Wilson",
              diagnosis: "Annual Checkup",
              treatment: "Routine examination, vaccinations, and dental float",
              medications: ["Tetanus", "West Nile", "Rabies", "Dewormer"],
              notes: "Regular farrier visits every 6-8 weeks. Deworming every 3 months.",
              follow_up_date: "2024-04-15"
            },
            {
              date: "2023-04-15",
              veterinarian: "Dr. Wilson",
              diagnosis: "Lameness Evaluation",
              treatment: "Joint injection and rest",
              medications: ["Adequan", "Bute"],
              notes: "Mild arthritis in hocks. Responding well to treatment.",
              follow_up_date: "2023-10-15"
            }
          ],
          diet: {
            type: "Hay and Grain",
            schedule: "Twice daily feeding with free-choice hay",
            supplements: ["Joint Supplement", "Electrolytes in summer"]
          }
        })
        object_ids[:thunder] = thunder_id
        pets << { id: thunder_id, relationship: "pet" }
        puts "✅ Created Thunder (ID: #{thunder_id})"

        puts "🏠 Adding places..."
        places = []
        
        # Pooh Family Cabin
        cabin_id = weaviate.upsert_object("Place", {
          name: "Pooh Family Cabin",
          type: "Log Cabin",
          description: "A cozy log cabin nestled in the woods near the Hundred Acre Wood, surrounded by tall pine trees and wildflowers.",
          address: "123 Forest Lane, Hundred Acre Wood",
          coordinates: "47.6062,-122.3321",
          features: ["Wood-burning Fireplace", "Wrap-around Porch", "Solar Panels", "Nearby Stream"],
          year_built: 1995,
          size_sqft: 1800,
          rooms: [
            { type: "Bedroom", count: 3, description: "Spacious bedrooms with wooden beams and large windows" },
            { type: "Bathroom", count: 2, description: "Rustic yet modern with clawfoot tubs" },
            { type: "Kitchen", count: 1, description: "Fully equipped with modern appliances and a large island" },
            { type: "Living Room", count: 1, description: "Vaulted ceilings with a stone fireplace" },
            { type: "Study", count: 1, description: "Wood-paneled office with built-in bookshelves" }
          ],
          outdoor_features: ["Fire Pit", "Vegetable Garden", "Hammock", "Hot Tub"],
          sustainability: {
            solar_panels: true,
            rainwater_harvesting: true,
            composting: true,
            garden: true
          },
          nearby_attractions: ["Hundred Acre Wood Trails", "Pooh Bridge", "Rabbit's Garden", "Eeyore's Gloomy Place"]
        })
        object_ids[:cabin] = cabin_id
        places << { id: cabin_id, name: "Pooh Family Cabin" }
        puts "✅ Created Pooh Family Cabin (ID: #{cabin_id})"
        
        # The Workshop
        workshop_id = weaviate.upsert_object("Place", {
          name: "The Workshop",
          type: "Woodworking Shop",
          description: "A fully equipped workshop where Winnie crafts furniture and builds custom projects.",
          address: "Behind the Cabin, Hundred Acre Wood",
          coordinates: "47.6063,-122.3322", # Slightly offset from the cabin
          elevation: 1200, # In feet
          year_built: 2015,
          features: ["Dust Collection System", "Wood Storage", "Hand Tools", "Power Tools", "Finishing Area"],
          size_sqft: 1200,
          equipment: [
            "Table Saw",
            "Band Saw",
            "Jointer",
            "Planer",
            "Router Table",
            "Lathe",
            "Drill Press",
            "Hand Tools Collection"
          ],
          materials: [
            "Hardwood Lumber",
            "Plywood",
            "Exotic Veneers",
            "Wood Glue & Finishes"
          ],
          safety_equipment: ["Dust Masks", "Safety Glasses", "Hearing Protection", "First Aid Kit"],
          projects: [
            { name: "Dining Table", status: "Completed", year: 2022 },
            { name: "Rocking Chair", status: "In Progress", started: "2023-03-15" },
            { name: "Bookshelves", status: "Planned", priority: "Medium" }
          ]
        })
        object_ids[:workshop] = workshop_id
        places << { id: workshop_id, name: "The Workshop" }
        puts "✅ Created The Workshop (ID: #{workshop_id})"
        # Mountain Retreat
        mountain_retreat_id = weaviate.upsert_object("Place", {
          name: "Mountain Retreat",
          type: "Cabin",
          address: "123 Mountain View Rd, Aspen, CO 81611",
          coordinates: "39.1880,-106.8170",
          elevation: 2500,
          size_sqft: 3500,
          year_built: 2010,
          description: "A secluded mountain retreat with stunning views and modern amenities. Built with sustainable materials and powered by renewable energy.",
          features: [
            "Solar Panels", "Wood Stove", "Hot Tub", 
            "Satellite Internet", "Water Well", "Greenhouse"
          ],
          rooms: [
            { type: "Bedroom", count: 3, description: "Master suite with mountain views" },
            { type: "Bathroom", count: 2, description: "One with a sauna" },
            { type: "Kitchen", description: "Fully equipped with commercial-grade appliances" },
            { type: "Great Room", description: "Open concept living area with floor-to-ceiling windows" },
            { type: "Study", description: "Home office with extensive library" }
          ],
          sustainability: {
            solar_panels: true,
            rainwater_harvesting: true,
            composting: true,
            garden: true
          }
        })
        object_ids[:mountain_retreat] = mountain_retreat_id
        places << { id: mountain_retreat_id, name: "Mountain Retreat" }
        puts "✅ Created Mountain Retreat (ID: #{mountain_retreat_id})"
        
        # Kaiser's Workshop
        kaisers_workshop_id = weaviate.upsert_object("Place", {
          name: "Kaiser's Workshop",
          type: "Workshop",
          location: "Adjacent to main cabin",
          size_sqft: 1200,
          year_built: 2012,
          description: "A well-equipped workshop for woodworking and metalworking projects. Features advanced tools and safety equipment.",
          equipment: [
            "CNC Router", "3D Printers", "Laser Cutter", "Metal Lathe", 
            "Milling Machine", "Welding Station", "Dust Collection System"
          ],
          projects: [
            { name: "Custom Furniture", status: "In Progress" },
            { name: "Blacksmithing Tools", status: "Planned" },
            { name: "Electronics Prototyping", status: "Ongoing" }
          ]
        })
        object_ids[:kaisers_workshop] = kaisers_workshop_id
        places << { id: kaisers_workshop_id, name: "Kaiser's Workshop" }
        puts "✅ Created Kaiser's Workshop (ID: #{kaisers_workshop_id})"
        
        # Pooh Family Estate
        family_estate_id = weaviate.upsert_object("Place", {
          name: "Pooh Family Estate",
          type: "Estate",
          address: "1 Pooh Lane, Aspen, CO 81611",
          description: "The original Pooh family home, now used for family gatherings and special events.",
          features: [
            "Guest House", "Stables", "Greenhouse", "Orchard",
            "Swimming Pool", "Tennis Court"
          ],
          size_sqft: 10000,
          year_built: 1985,
          rooms: [
            { type: "Bedroom", count: 6, description: "Spacious bedrooms with en-suite bathrooms" },
            { type: "Bathroom", count: 7, description: "Luxurious bathrooms with modern amenities" },
            { type: "Kitchen", description: "Professional-grade kitchen with butler's pantry" },
            { type: "Dining Room", description: "Formal dining room with seating for 12" },
            { type: "Living Room", description: "Grand living room with fireplace" },
            { type: "Library", description: "Two-story library with rolling ladder" },
            { type: "Home Theater", description: "State-of-the-art home theater" }
          ]
        })
        object_ids[:family_estate] = family_estate_id
        places << { id: family_estate_id, name: "Pooh Family Estate" }
        puts "✅ Created Pooh Family Estate (ID: #{family_estate_id})"

        puts "🚗 Adding vehicles..."
        
        # Ford F-150 Raptor
        raptor_id = weaviate.upsert_object("Vehicle", {
          name: "Ford F-150 Raptor",
          make: "Ford",
          model: "F-150 Raptor",
          year: 2022,
          vin: "1FTFW1RGXNKE12345",
          color: "Magnetic Gray",
          type: "Truck",
          fuel_type: "Gasoline",
          transmission: "10-Speed Automatic",
          engine: "3.5L EcoBoost V6",
          mileage: 12500,
          registration: "COL-2022-RPT",
          insurance: "Geico",
          purchase_date: "2021-12-15",
          description: "Off-road capable truck for mountain adventures. Equipped with off-road package and custom modifications.",
          features: [
            "4x4", "Twin-Turbo V6 (450hp)", "FOX Live Valve Shocks",
            "Baja Mode", "Trail Control", "360-Degree Camera",
            "Twin-Panel Moonroof", "Recaro Seats"
          ],
          maintenance: [
            { date: "2023-01-10", mileage: 5000, service: "Oil Change" },
            { date: "2023-07-22", mileage: 10000, service: "Tire Rotation" },
            { date: "2023-07-22", mileage: 10000, service: "Oil Change" }
          ]
        })
        object_ids[:raptor] = raptor_id
        
        # Toyota 4Runner TRD Pro
        toyota_id = weaviate.upsert_object("Vehicle", {
          name: "Toyota 4Runner TRD Pro",
          make: "Toyota",
          model: "4Runner TRD Pro",
          year: 2021,
          vin: "JTERU5JRXML567890",
          color: "Army Green",
          type: "SUV",
          fuel_type: "Gasoline",
          transmission: "5-Speed Automatic",
          engine: "4.0L V6",
          mileage: 18750,
          registration: "COL-2021-4RN",
          insurance: "Geico",
          purchase_date: "2021-03-10",
          description: "Reliable off-road SUV for backcountry exploration. Equipped with roof rack and off-road accessories.",
          features: [
            "4x4", "TRD-Tuned Suspension", "Multi-Terrain Select",
            "Crawl Control", "Rear Locking Differential", "Skid Plates"
          ],
          maintenance: [
            { date: "2022-06-15", mileage: 7500, service: "Oil Change" },
            { date: "2022-12-10", mileage: 12500, service: "Tire Rotation" },
            { date: "2023-05-20", mileage: 17500, service: "Oil Change" }
          ]
        })
        object_ids[:toyota] = toyota_id
        
        # Honda CRF450L Motorcycle
        honda_id = weaviate.upsert_object("Vehicle", {
          name: "Honda CRF450L",
          make: "Honda",
          model: "CRF450L",
          year: 2022,
          vin: "MLHNC7600N2001234",
          color: "Red",
          type: "Dual-Sport Motorcycle",
          fuel_type: "Gasoline",
          engine: "449cc Single-Cylinder",
          mileage: 3250,
          registration: "COL-2022-CRF",
          insurance: "Progressive",
          purchase_date: "2022-04-15",
          description: "Lightweight and powerful dual-sport motorcycle for trail riding and backcountry exploration.",
          features: [
            "Electric Start", "Six-Speed Transmission", "Fuel Injection",
            "LED Lighting", "Off-Road Tires", "Hand Guards"
          ],
          maintenance: [
            { date: "2022-07-01", mileage: 1000, service: "Break-in Service" },
            { date: "2022-10-15", mileage: 2000, service: "Oil Change" },
            { date: "2023-04-01", mileage: 3000, service: "Oil Change" }
          ]
        })
        object_ids[:honda] = honda_id
        
        # Store vehicle references for relationship creation
        vehicles = [
          { id: raptor_id, name: "Ford F-150 Raptor" },
          { id: toyota_id, name: "Toyota 4Runner TRD Pro" },
          { id: honda_id, name: "Honda CRF450L" }
        ]

        puts "📝 Adding documents..."
        documents = [
          {
            id: weaviate.upsert_object("Document", {
              title: "Winnie The Pooh - Professional Resume",
              description: "Comprehensive professional background, skills, and work history",
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
            members: [winnie_the_pooh_id, family_members[0][:id], family_members[1][:id]]
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
          weaviate.add_reference("Vehicle", vehicle[:id], "owner", "Person", winnie_the_pooh_id)
          weaviate.add_reference("Vehicle", vehicle[:id], "home", "Place", places[0][:id])
          weaviate.add_reference("Person", winnie_the_pooh_id, "vehicles", "Vehicle", vehicle[:id])
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
        weaviate.add_reference("Place", object_ids[:mountain_retreat], "residents", "Person", winnie_the_pooh_id)
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
