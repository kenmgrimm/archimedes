RSpec.configure do |config|
  config.before(:suite) do
    # Ensure pgvector extension is enabled in test database
    ActiveRecord::Base.connection.execute("CREATE EXTENSION IF NOT EXISTS vector")
  end
  
  # Database cleaner configuration
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
