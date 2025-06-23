# Feature: Extract Entities from Content Using OpenAI

## User Story
As a user, I want the system to analyze each uploaded document and extract key entities, so that information can be structured and searched.

## Acceptance Criteria
- On content creation, the system uses OpenAI to analyze uploaded files and text
- Entities (e.g., people, places, topics) are extracted and saved to a new `Entity` model
- Each entity is related to its parent Content
- Entity extraction runs asynchronously (background job)
- Users can view extracted entities on the Content show page
- Debug logging is present for OpenAI calls and entity creation
- All new code passes Rubocop and RSpec

## Implementation Steps

1. **Integrate OpenAI API with ruby-openai** ✅
   - Add the `ruby-openai` gem and configure API credentials securely.
   - Create an `OpenAI::ClientService` class to provide reusable functions for interacting with OpenAI (e.g., chat completion, error handling, logging).
   - _Complete as of 2025-06-22: Service tested via RSpec and rails runner, API key loaded from .env, acronym inflection set._

2. **Build Content Analysis Service**
   - Implement a `ContentAnalysisService` that takes a Content's note and uploaded files.
   - Compose a detailed prompt for OpenAI, describing how to extract entities from both text and file content.
   - Ensure the service is modular and testable.

3. **Set File Size Limit**
   - Enforce a maximum file size for analysis (configurable, e.g., 2MB per file).
   - Validate and skip or warn on files that exceed the limit before sending to OpenAI.

4. **Entity Extraction and Storage**
   - Use the OpenAI response to create related `Entity` records for the Content.
   - Classify entities (e.g., person, place, topic) and store them with their type and value.
   - Store the full OpenAI response body with the Content or Entity for future review/audit.

5. **Background Processing**
   - Run the content analysis and entity extraction in a background job (e.g., Sidekiq or ActiveJob).
   - Ensure robust error handling and debug logging for all OpenAI calls and entity creation.

6. **Display and Test**
   - Display extracted entities on the Content show page, grouped by type.
   - Add/expand RSpec tests for all new code and ensure Rubocop compliance.
