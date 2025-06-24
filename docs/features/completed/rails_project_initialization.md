# Feature: Rails Project Initialization

## Overview
This feature covers the initialization of the Rails backend for the Archimedes MVP. The goal is to establish a robust, modern Rails API application with all core stack components required for authentication, file storage, background processing, styling, and testing.

---

## User Story
- **As a developer, I want to initialize a new Rails project with the required stack so I can build and run the backend API.**

---

## Acceptance Criteria
- Rails project is created in standard (full-stack) mode, not API mode
- PostgreSQL is set up as the database
- pgvector extension is installed and configured for vector search
- Devise is installed and configured for authentication
- ActiveStorage is set up for file uploads
- Sidekiq (or similar) is configured for background jobs
- TailwindCSS is integrated for styling
- RSpec is set up for testing
- All stack components are included in version control and documented

---

## Tasks
1. **Create Standard Rails Project**
   - Run `rails new archimedes`
   - Commit initial project structure
   - Ensure Hotwire (Turbo + Stimulus) is enabled for interactive, real-time UI
   - Confirm view rendering and asset pipeline are available
2. **Add Core Gems and Database Extensions**
   - Add and configure PostgreSQL as the database
   - Install and configure the pgvector extension for vector search
   - Add and configure Devise for authentication
   - Add and configure ActiveStorage for file attachments
   - Add and configure Sidekiq for background jobs
   - Add and configure TailwindCSS for styling
   - Add and configure RSpec for testing
3. **Initial Configuration**
   - Set up environment variables and credentials
   - Configure database.yml for PostgreSQL
   - Set up binstubs and Procfile for local development
4. **Documentation**
   - Document setup steps and stack choices in README
   - Add references to MVP setup doc

---

## Notes
- Use standard Rails mode (not API mode) because the project will use Hotwire, Stimulus, and server-rendered Rails views for a rich, interactive UI.
- API mode omits view rendering, asset pipeline, and Hotwire/Stimulus integration, which are essential for this project's requirements.
- Follow best practices for full-stack Rails projects
- Ensure all code is committed in small, logical increments
- Use debug logging throughout configuration for easier troubleshooting
- Ensure all stack components are compatible and tested together

---

## References
- [MVP Setup: Initial Stories for Project Archimedes](./mvp_setup.md)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [ActiveStorage Documentation](https://edgeguides.rubyonrails.org/active_storage_overview.html)
- [Sidekiq Documentation](https://sidekiq.org/)
- [TailwindCSS Rails Guide](https://tailwindcss.com/docs/guides/ruby-on-rails)
- [RSpec Rails Guide](https://relishapp.com/rspec/rspec-rails/docs)
