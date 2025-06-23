# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/openai/client_service'

RSpec.describe OpenAI::ClientService, type: :service do
  let(:service) { described_class.new }

  it 'returns a valid response from OpenAI chat endpoint' do
    prompt = "Extract entities from this text: John Doe went to Paris in 2022."
    response = service.chat(prompt, model: 'gpt-3.5-turbo', max_tokens: 100)
    expect(response).to be_a(Hash)
    expect(response.dig('choices', 0, 'message', 'content')).to be_present
    expect(response['object']).to eq('chat.completion')
  end
end
