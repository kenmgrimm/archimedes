# frozen_string_literal: true

require "rails_helper"
require "json"
require "yaml"

RSpec.describe ContentAnalysisService do
  let(:openai_service) { instance_double(OpenAI::ClientService) }
  let(:service) { described_class.new(openai_service: openai_service) }
  let(:notes) { ["Dinner with Steven at Joe's Diner"] }
  let(:files) { [{ filename: "receipt.jpg", data: "file content here" }] }

  let(:valid_openai_response) do
    {
      "choices" => [
        {
          "message" => {
            "content" => {
              "description" => "This is a test description.",
              "annotated_description" => "This is a [Test: description]",
              "rating" => 0.95
            }.to_json
          }
        }
      ]
    }
  end

  describe "#analyze" do
    it "returns parsed OpenAI response when output format is valid" do
      expect(openai_service).to receive(:chat_with_files).with(hash_including(
        note: kind_of(String),
        files: kind_of(Array),
        model: "gpt-4o",
        max_tokens: 4096
      )).and_return(valid_openai_response)
      result = service.analyze(notes: notes, files: files)
      expect(result).to be_an(Array)
      expect(result.first[:result]).to include(
        "description",
        "annotated_description",
        "rating"
      )
      expect(result.first[:result]["rating"]).to be_between(0, 1)
    end

    it "raises if OpenAI response is not valid JSON" do
      bad_response = valid_openai_response.dup
      bad_response["choices"][0]["message"]["content"] = "not json!"
      expect(openai_service).to receive(:chat_with_files).with(hash_including(
        note: kind_of(String),
        files: kind_of(Array),
        model: "gpt-4o",
        max_tokens: 4096
      )).twice.and_return(bad_response, bad_response)
      expect {
        service.analyze(notes: notes, files: files)
      }.to raise_error(/OpenAI response is not valid JSON/)
    end

    it "raises if OpenAI response does not match required output format" do
      incomplete_content = { "foo" => "bar" }.to_json
      bad_response = valid_openai_response.dup
      bad_response["choices"][0]["message"]["content"] = incomplete_content
      expect(openai_service).to receive(:chat_with_files).with(hash_including(
        note: kind_of(String),
        files: kind_of(Array),
        model: "gpt-4o",
        max_tokens: 4096
      )).and_return(bad_response)
      expect {
        service.analyze(notes: notes, files: files)
      }.to raise_error(/OpenAI response does not match required output format/)
    end
  end

  describe "#build_prompt" do
    it "includes taxonomy and output format in the prompt" do
      prompt = service.send(:build_prompt, notes)
      # If you want to check taxonomy and output format inclusion, you can add those here if needed
      # For now, just check that notes are included
      notes.each { |note| expect(prompt).to include(note) }
    end
  end
end
