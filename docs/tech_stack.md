# Tech Stack Overview: Personal Assistant RAG System

This document outlines the foundational technology stack for the Personal Assistant RAG system, supporting rapid development and a clear migration path toward a robust, self-contained architecture.

---

## 1. Server/API Layer

- **Framework:** Ruby on Rails
- **Language:** Ruby
- **Testing:** RSpec (unit/integration), FactoryBot (test data)
- **API:** RESTful and Hotwire/Turbo Streams for real-time features
- **Best Practices:**
  - Use Rails conventions for maintainability
  - Comprehensive test coverage with RSpec and FactoryBot
  - Modular, service-oriented business logic

---

## 2. Database & Vector Store

- **Primary Database:** PostgreSQL
- **Vector Search:** pg_vector extension for semantic search and embedding storage
- **Best Practices:**
  - Use strong data modeling and migrations
  - Store vector embeddings in pg_vector for efficient hybrid retrieval
  - Encrypt sensitive data at rest

---

## 3. Web Client

- **Framework:** Rails (server-rendered), Stimulus (JS), Hotwire (Turbo/Streams)
- **Features:**
  - Responsive, mobile-first design (TailwindCSS recommended)
  - Turbo/Hotwire for interactive, real-time UI without heavy JS
  - Secure authentication (Devise)
- **Best Practices:**
  - Keep JS minimal, use Stimulus for progressive enhancement
  - Leverage Rails partials and Turbo Frames for UI updates

---

## 4. Mobile Client

- **Framework:** React Native (Expo recommended for rapid iteration)
- **Features:**
  - Cross-platform (iOS/Android)
  - Native-feeling UI, fast reload, and OTA updates
  - Secure storage and authentication
- **Best Practices:**
  - Use TypeScript for type safety
  - Modularize components
  - Integrate with Rails API via REST or GraphQL

---

## 5. AI/LLM, OCR, and Voice

- **LLM/Text Inference:** OpenAI API (GPT-4/3.5)
- **Image Detection/OCR:** OpenAI Vision API (or similar), with future migration to local OCR (Tesseract)
- **Voice to Text:** OpenAI Whisper API (or similar)
- **Best Practices:**
  - Abstract all AI calls behind service objects for future migration
  - Log and monitor API usage/costs
  - Plan for future on-device or self-hosted models

---

## 6. Integration Patterns & Security

- **Authentication:** Devise (web), JWT or OAuth (mobile)
- **File Storage:** ActiveStorage (Rails, with local or S3 backend)
- **Notifications:** Turbo Streams (web), Push Notifications (mobile)
- **Security:**
  - Use HTTPS everywhere
  - Apply strong parameter validation and authorization (Pundit/CanCanCan)
  - Audit and log sensitive actions

---

## 7. Development & Tooling

- **Local Dev:** Docker Compose for consistent environment
- **CI/CD:** GitHub Actions or similar
- **Linting/Formatting:** RuboCop (Ruby), ESLint/Prettier (JS/TS)
- **Testing:** RSpec (Rails), Jest/React Native Testing Library (mobile)

---

## 8. Migration & Extensibility

- **LLM/OCR/Voice:** Start with OpenAI for rapid progress, but design interfaces to allow swapping for local/self-hosted models as tech matures
- **Vector DB:** pg_vector for now, with option to migrate to Qdrant, Chroma, or Weaviate if scale demands
- **Frontend:** Web and mobile clients share as much business logic as possible (API-first design)

---

## 9. Deployed / Production Environment (AWS)

- **Cloud Provider:** AWS (Amazon Web Services)
- **Compute:** EC2 (virtual machines), or ECS (containers) for scalable app hosting
- **Database:** Amazon RDS (managed PostgreSQL with pg_vector extension)
- **Object Storage:** S3 for file uploads, media, and backups
- **Container Orchestration:** ECS (Fargate) or EKS (Kubernetes) for containerized deployments (optional)
- **CI/CD:** GitHub Actions or AWS CodePipeline for automated deployments
- **Secrets Management:** AWS Secrets Manager or SSM Parameter Store
- **Monitoring & Logging:** CloudWatch (metrics/logs), AWS X-Ray (tracing)
- **Networking:** VPC, Application Load Balancer (ALB), Route 53 for DNS
- **Security:**
  - IAM roles and least-privilege policies
  - Enforce HTTPS with ACM (AWS Certificate Manager)
  - Automated backups and multi-AZ deployments for high availability
  - Security groups, WAF, and audit logging
- **Scaling:**
  - Auto Scaling Groups for EC2
  - RDS read replicas and scaling
  - S3 for elastic storage
- **Integration:**
  - Rails API backend connects to RDS/Postgres and S3
  - Web and mobile clients interact via secure API endpoints (ALB)
  - Push notifications via SNS or third-party services

---

This stack provides a balance of rapid development, strong community support, and a clear path to privacy-first, self-contained operation as the project matures.
