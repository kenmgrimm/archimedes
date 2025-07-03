# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/sidekiq_adapter'
require 'sidekiq'

# Configure Redis connection for Sidekiq
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
  
  # Configure error handling
  config.error_handlers << lambda do |ex, context|
    Rails.logger.error("Sidekiq error: #{ex.message}")
    Rails.logger.error("Context: #{context.inspect}")
  end
end

# Configure Redis connection for Sidekiq client
Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end

# Configure ActiveJob to use Sidekiq
Rails.application.config.active_job.queue_adapter = :sidekiq
