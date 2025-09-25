# Events API — Context & Standards (Stages)

## Core Objective
Define the quality bar and operating standards for a production‑ready `/v1/events` REST endpoint. The canonical,
execution‑ready checklist is `Phase-2A-Tasks/events_api_subtasks.md` — implement from that file.

## Context Documents
You have been provided with:
1. **Signal Agent Guide (Production Build Spec)** - The authoritative specification
2. **Events API Subtasks Breakdown** - Your implementation roadmap

## Implementation Order & Dependencies
Use the checklist and dependency graph in `events_api_subtasks.md`. The “Phases” below are renamed to “Stages” to
avoid confusion with roadmap phases.

### Stage 1: Schema Foundation (Tasks 1a → 1b → 1c)
**Task 1a: Event Envelope Schema Definition**
- Implement `/services/api/events/schema/envelope.js`
- Use the exact envelope structure from Section 3.3 of the Agent Guide
- Validate required fields: `device_id`, `session_id`, `ts`, `events` array
- Set batch size limits (suggest 50-100 events per batch)
- Enforce envelope-level validation rules

**Task 1b: Individual Event Type Schemas** 
- Implement `/services/api/events/schema/eventTypes.js`
- Define schemas for each event type from Section 3.3:
  - `view_start`, `view_end`, `tap_play_pause`, `preview_scrub_start`, `preview_scrub_commit`
  - `playback_error`, `time_to_first_frame`, `rebuffer`, `selected_bitrate`
- Validate event names against this exact list
- Define required/optional properties for each event type

**Task 1c: Schema Validation Utilities**
- Implement `/services/api/events/schema/validator.js`
- Orchestrate envelope + individual event validation
- Return structured error responses for 400 status codes
- Provide clear, actionable error messages

### Stage 2: API Endpoint (Tasks 2a → 2b → 2c)
**Task 2a: Route Setup & Configuration**
- Implement `/services/api/events/routes.js`
- Define POST `/v1/events` route (note the versioned path requirement)
- Set up middleware chain for request processing
- Configure basic HTTP method handling

**Task 2b: Request Parsing & Validation**
- Implement `/services/api/events/handlers/requestParser.js`
- Parse incoming JSON with proper error handling
- Integrate with Phase 1 schema validation
- Handle malformed JSON gracefully (return 400)

**Task 2c: Response Formatting & Error Handling**
- Implement `/services/api/events/handlers/responseFormatter.js`
- Return 200/202 for successful ingestion
- Return 400 for validation failures with specific error details
- Maintain consistent JSON response structure

### Stage 3: Data Protection (Tasks 3a, 3b → 3c)
**Task 3a: PII Detection Rules**
- Implement `/services/api/events/sanitization/piiDetector.js`
- Focus on telemetry-specific PII patterns
- Note: `device_id`, `session_id` are acceptable per spec
- Flag potential email/phone patterns in error messages or custom props

**Task 3b: Field Truncation Logic**
- Implement `/services/api/events/sanitization/fieldTruncator.js`
- Truncate oversize fields while preserving data types
- Log truncation events for monitoring
- Maintain event structure integrity

**Task 3c: Data Sanitization Middleware**
- Implement `/services/api/events/sanitization/middleware.js`
- Orchestrate PII detection and field truncation
- Apply sanitization before downstream processing
- Log sanitization actions

### Stage 4 & 5: Infrastructure (Parallel with Stage 3)
**Task 4: Rate Limiting Implementation**
- Basic rate limiting per client (use `device_id` or IP)
- Return 429 when limits exceeded
- Suggest: 1000 requests/hour per device_id

**Task 5: Queue Integration Setup**
- Integrate with Firehose→S3 (MVP) for downstream lake; Redis optional for online features
- Handle queue service outages gracefully
- Implement retry logic for failed queue operations

### Stage 6: Testing (After corresponding implementations)
**Tasks 6a-6d: Comprehensive Testing**
- Unit tests for each component
- Integration tests for complete request lifecycle
- Rate limiting and PII redaction test scenarios
- Mock queue services for isolated testing

### Stage 7: Operations (Parallel with testing)
**Task 7: Error Handling & Monitoring**
- Structured logging and metrics
- Health check endpoints
- Operational monitoring setup

## Critical Requirements

### Data Validation Rules
- Accept ONLY the event types listed in Section 3.3 of the Agent Guide
- Reject any events not in the specification
- Validate all required properties per event type
- Enforce reasonable batch sizes and field lengths

### PII Protection Guidelines
- `device_id` and `session_id` are acceptable identifiers
- Redact email addresses, phone numbers in any field
- Truncate error messages that might contain file paths
- Be conservative - when in doubt, redact

### Performance Requirements
- Target <100ms response time for validation
- Handle batch sizes up to 100 events efficiently
- Minimize memory usage during processing

### Error Handling Standards
- Return 400 for all validation failures
- Provide specific error messages indicating which field/event failed
- Return 429 for rate limit violations
- Return 500 for internal errors (queue failures, etc.)
- Log all errors for debugging

## Code Standards
- Use strongly typed code (TypeScript preferred if applicable)
- Include proper error handling and logging
- Write unit tests for all validation logic
- Follow RESTful API conventions
- Use environment variables for configuration

## Technology Stack Specifications

### Backend Framework
- **AWS Lambda + API Gateway** (serverless architecture)
- **Node.js** runtime for Lambda functions
- **No traditional web framework** (Express.js, etc.) - pure serverless functions
- Structure: `/services/api/events/` for Lambda handlers

### Queue Services Integration
**Primary Sink (MVP):**
1. **Amazon Kinesis Firehose → S3** — Durable ingestion to the data lake (matches AGENTS.md and current code)
2. **Redis (ElastiCache)** — Optional for online aggregations / hot paths
3. **Amazon EventBridge** — Optional for pipeline triggers

### Rate Limiting Storage
- **Redis (ElastiCache)** - Primary choice for scalability
- Token bucket algorithm with keys: `user:{user_id}:rate_limit`, `ip:{ip}:rate_limit`
- 60-second TTL sliding windows
- Fallback to DynamoDB if Redis unavailable

### Testing Framework
- **Jest** for backend unit and integration tests
- Structure: `/tests/unit/`, `/tests/integration/`, `/tests/performance/`
- Mock external services (Kinesis, Redis) for isolated testing
- Coverage requirement: >90% for all business logic

### Environment & Deployment
- **AWS Lambda** deployment (serverless)
- **API Gateway** for REST endpoint routing
- Environment variables for configuration
- **CloudFormation/CDK** for infrastructure (if needed)

## Implementation Ready
Proceed with `events_api_subtasks.md` to implement; this document defines standards and acceptance bars only.
