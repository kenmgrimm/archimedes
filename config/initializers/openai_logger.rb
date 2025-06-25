# frozen_string_literal: true

# Custom logger for OpenAI API requests and responses
# This creates a dedicated log file for all OpenAI interactions

require "logger"
require "json"

# Create the logs directory if it doesn't exist
FileUtils.mkdir_p(Rails.root.join("log"))

# Create a dedicated logger for OpenAI
OPENAI_LOGGER = Logger.new(Rails.root.join("log", "openai.log"))

# Set the log level (debug will log everything)
OPENAI_LOGGER.level = Logger::DEBUG

# Custom formatter for better readability
class OpenAILogFormatter < Logger::Formatter
  def call(severity, time, progname, msg)
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S.%L")
    
    # Format the message with clear section separators
    formatted_msg = case msg
                    when String
                      msg
                    when Hash
                      JSON.pretty_generate(msg)
                    else
                      msg.inspect
                    end
    
    # Add clear visual separators
    "\n[#{timestamp}] #{severity} #{progname}\n" \
    "#{'-' * 80}\n" \
    "#{formatted_msg}\n" \
    "#{'-' * 80}\n\n"
  end
end

# Set the custom formatter
OPENAI_LOGGER.formatter = OpenAILogFormatter.new

# Log initialization
OPENAI_LOGGER.info("OpenAI Logger initialized")
