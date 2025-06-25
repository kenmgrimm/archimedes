# frozen_string_literal: true

# Custom log formatter that truncates vector embeddings in SQL queries
# This makes logs more readable by shortening the very long vector strings
module VectorLogFormatter
  # Patterns to match vector embeddings in SQL logs and general logs
  VECTOR_PATTERN = /(\((?:name|note|value)_embedding <=> '\[)([^\]]+)(\]'\))/
  ARRAY_VECTOR_PATTERN = /(ARRAY\[)([^\]]+)(\]::vector)/
  
  # Truncate vector embeddings in logs
  def self.format_vector_logs(message)
    # Handle non-string messages safely
    return message unless message.is_a?(String)
    
    result = message
    
    # Handle entity objects with vector attributes
    if result.include?("embedding") && result.include?("[")
      # Try to safely extract and truncate vector arrays in object inspections
      begin
        # Handle standard vector pattern in SQL
        result = result.gsub(VECTOR_PATTERN) do |_|
          prefix = Regexp.last_match(1)
          vector = Regexp.last_match(2)
          suffix = Regexp.last_match(3)
          
          # Extract first few values from the vector
          values = vector.split(",")
          truncated_values = values.first(3).join(", ")
          
          # Format the truncated vector
          "#{prefix}#{truncated_values}, ... (#{values.size} dimensions)#{suffix}"
        end
        
        # Handle ARRAY[...]::vector pattern
        result = result.gsub(ARRAY_VECTOR_PATTERN) do |_|
          prefix = Regexp.last_match(1)
          vector = Regexp.last_match(2)
          suffix = Regexp.last_match(3)
          
          # Extract first few values from the vector
          values = vector.split(",")
          truncated_values = values.first(3).join(", ")
          
          # Format the truncated vector
          "#{prefix}#{truncated_values}, ... (#{values.size} dimensions)#{suffix}"
        end
      rescue => e
        # If any error occurs during formatting, return the original message
        # This ensures we don't break logging completely
        Rails.logger.error("Error in VectorLogFormatter: #{e.message}") if defined?(Rails.logger)
        return message
      end
    end
    
    result
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
        # Safely handle block results
        begin
          result = yield
          formatted_result = VectorLogFormatter.format_vector_logs(result.to_s)
          super { formatted_result }
        rescue => e
          # If the block raises an error, log it without formatting
          super { "[ERROR in debug block] #{e.message}" }
        end
      else
        message = args.first
        super(VectorLogFormatter.format_vector_logs(message.to_s))
      end
    end
    
    def info(*args, &block)
      if block_given?
        # Safely handle block results
        begin
          result = yield
          formatted_result = VectorLogFormatter.format_vector_logs(result.to_s)
          super { formatted_result }
        rescue => e
          # If the block raises an error, log it without formatting
          super { "[ERROR in info block] #{e.message}" }
        end
      else
        message = args.first
        super(VectorLogFormatter.format_vector_logs(message.to_s))
      end
    end
  end)
end
