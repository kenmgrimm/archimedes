# frozen_string_literal: true

# Configuration for vector similarity search
Rails.application.config.vector_search = ActiveSupport::OrderedOptions.new

# Default configuration
Rails.application.config.vector_search.enabled = ENV.fetch('VECTOR_SEARCH_ENABLED', 'true') == 'true'
Rails.application.config.vector_search.similarity_threshold = ENV.fetch('VECTOR_SIMILARITY_THRESHOLD', '0.8').to_f
Rails.application.config.vector_search.embedding_model = ENV.fetch('EMBEDDING_MODEL', 'text-embedding-3-small')
Rails.application.config.vector_search.chat_model = ENV.fetch('CHAT_MODEL', 'gpt-4')

# Log configuration
Rails.logger.info "Vector search configuration:"
Rails.logger.info "- Enabled: #{Rails.application.config.vector_search.enabled}"
Rails.logger.info "- Similarity threshold: #{Rails.application.config.vector_search.similarity_threshold}"
Rails.logger.info "- Embedding model: #{Rails.application.config.vector_search.embedding_model}"
Rails.logger.info "- Chat model: #{Rails.application.config.vector_search.chat_model}"
