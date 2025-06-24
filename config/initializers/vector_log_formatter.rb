# frozen_string_literal: true

# Custom log formatter that truncates vector embeddings in SQL queries
# This makes logs more readable by shortening the very long vector strings
module VectorLogFormatter
  # Pattern to match vector embeddings in SQL logs
  VECTOR_PATTERN = /(\((?:note|value)_embedding <=> '\[)([^\]]+)(\]'\))/
  
  # Truncate vector embeddings in SQL logs
  def self.format_vector_logs(message)
    return message unless message.is_a?(String)
    
    # Check if this is a SQL query with vector embeddings
    if message.include?("<=>") && message.include?("embedding")
      # Replace the vector with a truncated version
      message.gsub(VECTOR_PATTERN) do |_|
        prefix = Regexp.last_match(1)
        vector = Regexp.last_match(2)
        suffix = Regexp.last_match(3)
        
        # Extract first few values from the vector
        values = vector.split(",")
        truncated_values = values.first(3).join(", ")
        
        # Format the truncated vector
        "#{prefix}#{truncated_values}, ... (#{values.size} dimensions)#{suffix}"
      end
    else
      message
    end
  end
end

# Patch the ActiveRecord::LogSubscriber to use our formatter
ActiveSupport.on_load(:active_record) do
  ActiveRecord::LogSubscriber.prepend(Module.new do
    def sql(event)
      payload = event.payload
      payload[:sql] = VectorLogFormatter.format_vector_logs(payload[:sql]) if payload[:sql]
      super(event)
    end
  end)
end

# Safer approach to patch Rails logger
if defined?(Rails.logger) && Rails.logger
  Rails.logger.singleton_class.prepend(Module.new do
    def debug(*args, &block)
      if block_given?
        super { VectorLogFormatter.format_vector_logs(yield) }
      else
        message = args.first
        super(VectorLogFormatter.format_vector_logs(message))
      end
    end
    
    def info(*args, &block)
      if block_given?
        super { VectorLogFormatter.format_vector_logs(yield) }
      else
        message = args.first
        super(VectorLogFormatter.format_vector_logs(message))
      end
    end
  end)
end
