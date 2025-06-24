# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenAI::EmbeddingService do
  let(:service) { described_class.new }
  let(:sample_text) { "This is a sample text for embedding" }
  let(:sample_embedding) { Array.new(1536) { rand(-1.0..1.0) } }
  let(:sample_texts) { ["Text 1", "Text 2", "Text 3"] }
  let(:sample_embeddings) { 3.times.map { Array.new(1536) { rand(-1.0..1.0) } } }
  
  describe "#embed" do
    context "when text is present" do
      before do
        stub_request(:post, %r{https://api.openai.com/v1/embeddings})
          .with(body: hash_including({
            "model" => "text-embedding-3-small",
            "input" => sample_text
          }))
          .to_return(
            status: 200,
            body: {
              "data" => [
                {
                  "embedding" => sample_embedding,
                  "index" => 0,
                  "object" => "embedding"
                }
              ],
              "model" => "text-embedding-3-small",
              "object" => "list",
              "usage" => {
                "prompt_tokens" => 8,
                "total_tokens" => 8
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end
      
      it "calls the OpenAI API with the correct parameters" do
        service.embed(sample_text)
        
        expect(WebMock).to have_requested(:post, %r{https://api.openai.com/v1/embeddings})
          .with(body: hash_including({
            "model" => "text-embedding-3-small",
            "input" => sample_text
          }))
      end
      
      it "returns the embedding from the API response" do
        result = service.embed(sample_text)
        
        expect(result).to eq(sample_embedding)
      end
      
      it "logs debug information" do
        expect(Rails.logger).to receive(:debug).at_least(:once)
        
        service.embed(sample_text)
      end
    end
    
    context "when text is blank" do
      it "returns nil without calling the API" do
        result = service.embed("")
        
        expect(WebMock).not_to have_requested(:post, %r{https://api.openai.com/v1/embeddings})
        expect(result).to be_nil
      end
    end
    
    context "when API call fails" do
      before do
        # Simulate a network error by raising an exception
        stub_request(:post, %r{https://api.openai.com/v1/embeddings})
          .with(body: hash_including({
            "model" => "text-embedding-3-small",
            "input" => sample_text
          }))
          .to_raise(StandardError.new("API connection error"))
        
        allow(Rails.logger).to receive(:error)
      end
      
      it "logs the error and returns nil" do
        result = service.embed(sample_text)
        
        # Use a regex pattern to match the error message since the exact message may vary
        expect(Rails.logger).to have_received(:error) do |message|
          expect(message).to include("[OpenAI::EmbeddingService] Error generating embedding")
        end
        expect(result).to be_nil
      end
    end
    
    context "when API returns unexpected response format" do
      before do
        stub_request(:post, %r{https://api.openai.com/v1/embeddings})
          .to_return(
            status: 200, 
            body: { "data" => [] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end
      
      it "returns nil when embedding is not present" do
        result = service.embed(sample_text)
        
        expect(result).to be_nil
      end
    end
  end
  
  describe "#embed_batch" do
    context "when texts are present" do
      before do
        stub_request(:post, %r{https://api.openai.com/v1/embeddings})
          .with(body: hash_including({
            "model" => "text-embedding-3-small",
            "input" => sample_texts
          }))
          .to_return(
            status: 200,
            body: {
              "data" => sample_embeddings.map.with_index do |embedding, index|
                {
                  "embedding" => embedding,
                  "index" => index,
                  "object" => "embedding"
                }
              end,
              "model" => "text-embedding-3-small",
              "object" => "list",
              "usage" => {
                "prompt_tokens" => 8,
                "total_tokens" => 8
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end
      
      it "calls the OpenAI API with the correct parameters" do
        service.embed_batch(sample_texts)
        
        expect(WebMock).to have_requested(:post, %r{https://api.openai.com/v1/embeddings})
          .with(body: hash_including({
            "model" => "text-embedding-3-small",
            "input" => sample_texts
          }))
      end
      
      it "returns the embeddings from the API response" do
        result = service.embed_batch(sample_texts)
        
        expect(result).to eq(sample_embeddings)
      end
      
      it "logs debug information" do
        expect(Rails.logger).to receive(:debug).at_least(:once)
        
        service.embed_batch(sample_texts)
      end
    end
    
    context "when texts array is empty" do
      it "returns an empty array without calling the API" do
        result = service.embed_batch([])
        
        expect(WebMock).not_to have_requested(:post, %r{https://api.openai.com/v1/embeddings})
        expect(result).to eq([])
      end
    end
    
    context "when API call fails" do
      before do
        # Simulate a network error by raising an exception
        stub_request(:post, %r{https://api.openai.com/v1/embeddings})
          .with(body: hash_including({
            "model" => "text-embedding-3-small",
            "input" => sample_texts
          }))
          .to_raise(StandardError.new("API connection error"))
        
        allow(Rails.logger).to receive(:error)
      end
      
      it "logs the error and returns an empty array" do
        result = service.embed_batch(sample_texts)
        
        # Use a regex pattern to match the error message since the exact message may vary
        expect(Rails.logger).to have_received(:error) do |message|
          expect(message).to include("[OpenAI::EmbeddingService] Error generating batch embeddings")
        end
        expect(result).to eq([])
      end
    end
  end
  
  describe "with custom model" do
    let(:custom_model) { "text-embedding-3-large" }
    let(:custom_service) { described_class.new(model: custom_model) }
    
    before do
      # Create a custom stub for this specific test
      response_body = {
        data: [
          {
            embedding: sample_embedding,
            index: 0,
            object: "embedding"
          }
        ],
        model: custom_model,
        object: "list",
        usage: {
          prompt_tokens: 8,
          total_tokens: 8
        }
      }
      
      stub_request(:post, %r{https://api.openai.com/v1/embeddings})
        .with(body: hash_including({
          "model" => custom_model,
          "input" => sample_text
        }))
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end
    
    it "uses the specified model when generating embeddings" do
      custom_service.embed(sample_text)
      
      expect(WebMock).to have_requested(:post, %r{https://api.openai.com/v1/embeddings})
        .with(body: hash_including({
          "model" => custom_model,
          "input" => sample_text
        }))
    end
  end
end
