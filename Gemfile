source "https://rubygems.org"

ruby "3.4.2"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.5.1" # Full Rails stack to ensure all dependencies are available

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

gem "dotenv-rails", groups: [:development, :test]
gem "ruby-openai", "~> 5.0"

gem "httparty"

# Weaviate - using version compatible with Faraday < 2.0
gem "weaviate-ruby", "~> 0.8.0", require: false

# Neo4j Ruby driver - Official driver for Neo4j
gem "neo4j-ruby-driver", "~> 4.4.0"

# ActiveSupport for Ruby on Rails
gem "activesupport", "~> 7.1.5.1"

# Background processing
gem "sidekiq", "~> 7.2.4" # Background processing (8.x requires Rails 8+)

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Sidekiq is already included above with version specification
# gem "sidekiq"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

gem "devise"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: [:windows, :jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# ---
# Testing
# ---

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "amazing_print"
  gem "database_cleaner-active_record"
  gem "debug", platforms: [:mri, :windows]
  gem "factory_bot_rails"
  gem "faker"
  gem "rspec-rails", "~> 6.1"
  gem "shoulda-matchers"
  gem "webmock"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Linting and Rails best practices
  gem "rubocop", require: false
  gem "rubocop-factory_bot", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

gem "active_storage_validations", "~> 3.0"

gem "mimemagic", "~> 0.4.3"
