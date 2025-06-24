require 'webmock/rspec'

# Allow real connections in development/test by default
WebMock.disable_net_connect!(allow_localhost: true)

# Helper for stubbing OpenAI API calls
module OpenAIStubs
  # Stub for embedding API calls
  def stub_openai_embedding_api(text: nil, embedding: nil, status: 200)
    # Generate a random embedding if none provided
    embedding ||= Array.new(1536) { rand(-1.0..1.0) }
    
    # Create response body
    response_body = {
      data: [
        {
          embedding: embedding,
          index: 0,
          object: "embedding"
        }
      ],
      model: "text-embedding-3-small",
      object: "list",
      usage: {
        prompt_tokens: 8,
        total_tokens: 8
      }
    }
    
    # Debug log
    Rails.logger.debug { "[WebMock] Stubbing OpenAI embedding API with text: #{text&.truncate(50)}" }
    
    # Stub the request
    stub_request(:post, %r{https://api.openai.com/v1/embeddings})
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
  
  # Stub for batch embedding API calls
  def stub_openai_batch_embedding_api(texts: nil, embeddings: nil, status: 200)
    # Generate random embeddings if none provided
    embeddings ||= texts&.map { Array.new(1536) { rand(-1.0..1.0) } } || []
    
    # Create response body
    response_body = {
      data: embeddings.map.with_index do |embedding, index|
        {
          embedding: embedding,
          index: index,
          object: "embedding"
        }
      end,
      model: "text-embedding-3-small",
      object: "list",
      usage: {
        prompt_tokens: texts&.size || 0 * 8,
        total_tokens: texts&.size || 0 * 8
      }
    }
    
    # Debug log
    Rails.logger.debug { "[WebMock] Stubbing OpenAI batch embedding API with #{texts&.size || 0} texts" }
    
    # Stub the request
    stub_request(:post, %r{https://api.openai.com/v1/embeddings})
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end

RSpec.configure do |config|
  config.include OpenAIStubs
  
  config.before(:each) do
    # Clear any previous stubs
    WebMock.reset!
  end
end
