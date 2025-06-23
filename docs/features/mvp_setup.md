# MVP Setup: Initial Stories for Project Archimedes

This document outlines the initial set of user stories and technical tasks required to establish the MVP for the Archimedes project. These stories will serve as the foundation for breaking out individual features and tracking early progress.

## 1. Database Setup
- **Story:** As a developer, I want to stand up the PostgreSQL database so that the application has a robust, scalable data store.
- **Tasks:**
  - Initialize PostgreSQL instance
  - Install and configure the `pgvector` extension for vector search capabilities
  - Define initial schema for core entities (users, uploads, categories, etc.)

## 2. Rails Project Initialization
- **Story:** As a developer, I want to initialize a new Rails project with the required stack so I can build and run the backend API.
- **Tasks:**
  - Create new Rails app (API mode)
  - Set up gems for authentication (Devise), file storage (ActiveStorage), and background jobs (Sidekiq or similar)
  - Configure TailwindCSS for styling
  - Set up RSpec for testing

## 3. Core Controller and Views
- **Story:** As a user, I want to upload files and interact with the system via a basic web interface.
- **Tasks:**
  - Scaffold initial controllers for uploads, categories, and users
  - Create minimal views for file upload and category selection (mobile-first, responsive, Turbo/Hotwire enabled)
  - Integrate ActiveStorage for handling uploads

## 4. Backend Services Integration
- **Story:** As a developer, I want backend services to handle input processing, communicate with OpenAI, and manage storage/retrieval.
- **Tasks:**
  - Implement service objects for:
    - Parsing and validating user input
    - Communicating with OpenAI API (for semantic analysis, etc.)
    - Storing and retrieving data using pgvector
    - Managing background jobs for async processing

## 5. API Endpoints
- **Story:** As a frontend developer, I want RESTful API endpoints for uploads, categories, and search so the frontend can interact with the backend.
- **Tasks:**
  - Design and implement endpoints for:
    - Upload creation and retrieval
    - Category search/filter (with real-time filtering)
    - Search and retrieval of stored content

---

These stories provide a roadmap for the MVP setup. Each can be broken down into granular tasks and tracked individually as development progresses.
