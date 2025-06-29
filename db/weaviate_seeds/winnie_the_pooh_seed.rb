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
      end
    end
  end
end
