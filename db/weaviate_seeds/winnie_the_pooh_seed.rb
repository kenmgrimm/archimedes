require_relative 'schema'
require_relative 'data/winnie_the_pooh_data'

module WeaviateSeeds
  class WinnieThePoohSeed
    class << self
      def run(weaviate)
        # Define the schema
        WeaviateSeeds::Schema.define_schema(weaviate)
        
        # Seed the data
        WeaviateSeeds::WinnieThePoohData.seed_data(weaviate)

        puts "\n✅ Successfully seeded Weaviate with initial data."
      rescue => e
        puts "Error seeding data: #{e.message}\n#{e.backtrace[0..5].join("\n")}"
      end
    end
  end
end
