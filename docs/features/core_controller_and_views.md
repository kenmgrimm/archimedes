# Feature: Core Content and User Stories

This document breaks out the core MVP features into focused, sequential stories. Each story includes its own user story, acceptance criteria, and implementation tasks. All stories follow mobile-first, Turbo/Hotwire, TailwindCSS, debug logging, and test/lint best practices.

---

## Story 1: Upload Content (Files and Text) ✅

> **Status:** ✔️ Complete — All acceptance criteria and tasks have been implemented and tested as of 2025-06-22.

### User Story
As a user, I want to upload files and enter text through a simple form, so I can create and view content in the system.

### Acceptance Criteria
- A `Content` model exists with:
  - File attachment support via ActiveStorage (multi-file upload)
  - A text area for entering additional information
- Users can create new content via a mobile-first form
- An index page lists all content items with summary info and links to show pages
- A show page displays the uploaded files and text for a single content item
- Turbo/Hotwire is used for dynamic updates (e.g., instant feedback on upload)
- All forms and views are styled with TailwindCSS
- Debug logging is present for all content actions
- All new code passes Rubocop and RSpec

### Tasks
1. Scaffold `Content` model, controller, and views (index, show, new, create)
2. Add file attachment (ActiveStorage) and text area to the form
3. Implement index and show pages for Content
4. Style all views mobile-first with TailwindCSS
5. Add Turbo/Hotwire for dynamic form/feedback
6. Add debug logging to controller actions
7. Add/expand RSpec tests and ensure Rubocop compliance

---

## Story 2: Extract Entities from Content Using OpenAI

### User Story
As a user, I want the system to analyze each uploaded document and extract key entities, so that information can be structured and searched.

### Acceptance Criteria
- On content creation, the system uses OpenAI to analyze uploaded files and text
- Entities (e.g., people, places, topics) are extracted and saved to a new `Entity` model
- Each entity is related to its parent Content
- Entity extraction runs asynchronously (background job)
- Users can view extracted entities on the Content show page
- Debug logging is present for OpenAI calls and entity creation
- All new code passes Rubocop and RSpec

### Tasks
1. Create `Entity` model related to Content
2. Integrate OpenAI API for entity extraction
3. Implement background job for analysis
4. Display extracted entities on Content show page
5. Add debug logging and tests for all new code

---

## Story 3: User Login and Registration

### User Story
As a user, I want to register for an account and log in, so my content is private and secure.

### Acceptance Criteria
- Users can register and log in via Devise
- Only authenticated users can create or view content
- Registration and login forms are mobile-first and styled with TailwindCSS
- Debug logging is present for authentication events
- All new code passes Rubocop and RSpec

### Tasks
1. Ensure Devise is configured and working
2. Style registration and login forms with TailwindCSS
3. Restrict Content actions to authenticated users
4. Add debug logging for authentication
5. Add/expand RSpec tests and ensure Rubocop compliance

---

## Notes
- All stories prioritize mobile-first, responsive design
- Use Turbo/Hotwire for interactive elements wherever possible
- Commit code in small, logical increments with detailed messages

## References
- [ActiveStorage Documentation](https://edgeguides.rubyonrails.org/active_storage_overview.html)
- [Hotwire Turbo](https://turbo.hotwired.dev/)
- [StimulusJS](https://stimulus.hotwired.dev/)
- [TailwindCSS Rails Guide](https://tailwindcss.com/docs/guides/ruby-on-rails)
- [Devise](https://github.com/heartcombo/devise)
- [OpenAI API Docs](https://platform.openai.com/docs/api-reference)
