require_relative "../../db/weaviate_seeds/winnie_the_pooh_seed"
require "httparty"

namespace :weaviate do
  desc "Drop all objects from Weaviate while preserving schemas"
  task clean: :environment do
    puts "\n🔍 Cleaning up Weaviate objects (preserving schemas)..."
    begin
      weaviate = WeaviateService.new
      weaviate.delete_all_objects
      puts "✅ Successfully deleted all objects from Weaviate while preserving schemas."
    rescue StandardError => e
      puts "\n❌ Error during Weaviate cleanup: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]
      exit 1
    end
  end

  desc "Drop all objects and schemas from Weaviate (COMPLETE WIPE)"
  task "clean:hard" => :environment do
    puts "\n🔥 WARNING: Deleting ALL objects AND SCHEMAS from Weaviate..."
    begin
      weaviate = WeaviateService.new
      weaviate.delete_schema_classes
      puts "✅ Successfully deleted all objects and schemas from Weaviate."
    rescue StandardError => e
      puts "\n❌ Error during Weaviate cleanup: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]
      exit 1
    end
  end

  desc "Seed Weaviate with initial data"
  task :seed, [:reset_schema] => :environment do |_t, args|
    args.with_defaults(reset_schema: false)
    reset_schema = args.reset_schema == "true"

    puts "\n🌱 Seeding Weaviate with Winnie the Pooh knowledge graph..."

    begin
      puts "\n🔌 Initializing Weaviate client..."
      weaviate = WeaviateService.new

      # Test connection to Weaviate
      begin
        puts "\n🔍 Testing connection to Weaviate..."
        # Use HTTParty to check if Weaviate is running by getting the schema
        response = HTTParty.get("http://localhost:8080/v1/schema")
        raise "Received status #{response.code} from Weaviate server" unless response.code == 200

        puts "✅ Successfully connected to Weaviate."
      rescue StandardError => e
        puts "\n❌ Failed to connect to Weaviate: #{e.message}"
        puts "   Please ensure the Weaviate server is running at http://localhost:8080"
        exit 1
      end

      # Clean up existing data
      if reset_schema
        puts "\n🧹 Resetting schema and cleaning up data..."
        weaviate.delete_schema_classes
      else
        puts "\n🧹 Cleaning up existing objects (preserving schemas)..."
        weaviate.delete_all_objects
      end

      # Run the seed with detailed error handling
      begin
        puts "\n🏗️  Running seed script..."
        WeaviateSeeds::SchemaSeed.run(weaviate)
        puts "\n✅ Successfully seeded Weaviate with initial data."
      rescue StandardError => e
        puts "\n❌ Error during seeding: #{e.class}: #{e.message}"
        puts "Backtrace:"
        puts e.backtrace.join("\n")
        exit 1
      end
    rescue StandardError => e
      puts "\n❌ Unexpected error: #{e.class}: #{e.message}"
      puts "Backtrace:"
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end
