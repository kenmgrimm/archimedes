# frozen_string_literal: true

# Custom logger for OpenAI API requests and responses
# This creates a dedicated log file for all OpenAI interactions

require "logger"
require "json"
require "fileutils"

# Define the OpenAI logger in the global namespace to ensure it's available everywhere
module OpenAILogging
  # Create the logs directory if it doesn't exist
  FileUtils.mkdir_p(Rails.root.join("log"))

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

  # Create a dedicated logger for OpenAI
  def self.logger
    @logger ||= begin
      logger = Logger.new(Rails.root.join("log", "openai.log"))
      logger.level = Logger::DEBUG
      logger.formatter = OpenAILogFormatter.new
      logger
    end
  end
end

# Create a global constant for easy access
OPENAI_LOGGER = OpenAILogging.logger

# Log initialization
OPENAI_LOGGER.info("OpenAI Logger initialized")

# Ensure the logger is available in the OpenAI module
module OpenAI
  def self.logger
    OPENAI_LOGGER
  end
end
