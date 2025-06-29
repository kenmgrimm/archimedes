# Load all Weaviate seed files
Dir[Rails.root.join('db', 'weaviate_seeds', '**', '*.rb')].sort.each { |f| require f }
