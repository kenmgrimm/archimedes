# frozen_string_literal: true

require "amazing_print"

require_relative "../app/services/content_analysis_service"
require_relative "../config/environment"

prompt = "License plate from my truck"
# Use a file from tmp as a fallback
file_path = File.expand_path("license plate.jpeg", __dir__)
file = File.open(file_path, "rb")
files = [{
  filename: "license plate.jpeg",
  data: file.read
}]

service = ContentAnalysisService.new
ap service.analyze(prompt, files:)
