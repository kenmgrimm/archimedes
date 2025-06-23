# frozen_string_literal: true

# OpenAI API configuration
# Expects ENV['OPENAI_API_KEY'] to be set
require 'openai'

OpenAIClient = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
