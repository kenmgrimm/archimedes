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
  task :seed_pooh, [:reset_schema] => :environment do |_t, args|
    args.with_defaults(reset_schema: false)
    reset_schema = args.reset_schema == "true"

    puts "\n🌱 Seeding Weaviate with Winnie the Pooh knowledge graph..."

    begin
      # Initialize and verify connection
      puts "\n🔌 Initializing Weaviate client..."
      weaviate = WeaviateService.new
      verify_weaviate_connection!

      # Clean up existing data
      cleanup_weaviate_data(weaviate, reset_schema)

      # Run the seed
      puts "\n🏗️  Running seed script..."
      WeaviateSeeds::WinnieThePoohSeed.run(weaviate)
      puts "\n✅ Successfully seeded Weaviate with initial data."
    rescue StandardError => e
      handle_error(e)
    end
  end

  private

  def verify_weaviate_connection!
    puts "\n🔍 Testing connection to Weaviate..."
    response = HTTParty.get("http://localhost:8080/v1/schema")
    raise "Received status #{response.code} from Weaviate server" unless response.code == 200

    puts "✅ Successfully connected to Weaviate."
  rescue StandardError => e
    puts "\n❌ Failed to connect to Weaviate: #{e.message}"
    puts "   Please ensure the Weaviate server is running at http://localhost:8080"
    exit 1
  end

  def cleanup_weaviate_data(weaviate, reset_schema)
    if reset_schema
      puts "\n🧹 Resetting schema and cleaning up data..."
      weaviate.delete_schema_classes
    else
      puts "\n🧹 Cleaning up existing objects (preserving schemas)..."
      weaviate.delete_all_objects
    end
  end

  def handle_error(error)
    puts "\n❌ Error: #{error.class}: #{error.message}"
    if ENV["DEBUG"]
      puts "Backtrace:"
      puts error.backtrace.join("\n")
    else
      puts "   Run with DEBUG=1 for full backtrace"
    end
    exit 1
  end
end
