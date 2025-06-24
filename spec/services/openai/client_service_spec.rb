# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/openai/client_service'

RSpec.describe OpenAI::ClientService, type: :service do
  let(:service) { described_class.new }
  let(:prompt) { "Extract entities from this text: John Doe went to Paris in 2022." }
  let(:model) { "gpt-3.5-turbo" }
  let(:max_tokens) { 100 }
  
  before do
    # Debug logging
    Rails.logger.debug { "[ClientServiceSpec] Setting up WebMock stub for OpenAI chat completions" }
    
    # Stub the OpenAI chat completions API
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(
        body: hash_including({
          "model" => model,
          "messages" => [
            {"role" => "system", "content" => "You are an AI assistant that extracts structured entities from user content."},
            {"role" => "user", "content" => prompt}
          ],
          "temperature" => 0.2,
          "max_tokens" => max_tokens
        })
      )
      .to_return(
        status: 200,
        body: {
          "id" => "chatcmpl-123",
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => model,
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => "Person: John Doe\nLocation: Paris\nDate: 2022"
              },
              "finish_reason" => "stop"
            }
          ],
          "usage" => {
            "prompt_tokens" => 20,
            "completion_tokens" => 15,
            "total_tokens" => 35
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns a valid response from OpenAI chat endpoint' do
    # Debug logging
    Rails.logger.debug { "[ClientServiceSpec] Running test for OpenAI chat completions" }
    
    response = service.chat(prompt, model: model, max_tokens: max_tokens)
    
    # Verify the response structure
    expect(response).to be_a(Hash)
    expect(response.dig('choices', 0, 'message', 'content')).to be_present
    expect(response['object']).to eq('chat.completion')
    
    # Verify the WebMock was called
    expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/chat/completions")
  end
end
