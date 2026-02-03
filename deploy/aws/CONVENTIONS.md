# Seqr Clickhouse AWS Deployment

This project contains infrastructure to deploy seqr in a standard AWS infrastructure setup.

Details of the architecture are contained in `INFRA_ARCHITECTURE.md`.

Ensure to read this document and understand the architecture.

## Project Configuration

- **AWS Region**: ap-southeast-2 (Sydney)
- **Prefix**: mcri
- **IaC Tool**: OpenTofu (all commands use `tofu` not `terraform`)

## Guidelines

- Always create a plan for steps to complete
- ASSUME that the session may be interrupted, so record progress in the plan,
  and note any important corrections, clarifications or changes that occur along the way
- Where critical decisions impact the outcome, STOP and confirm and ASK the correct choice
  - Always note the outcomes of questions in the plan
- Always approach implementation **step by step**

## Implementation Strategy

- **Incremental Development**: Build and test each component independently before moving to the next
- **Staged Deployment**: Follow a logical dependency order - foundational components first, then dependent services
- **Test Each Stage**: Validate each component works correctly before proceeding
- **Minimal Viable Increments**: Each step should produce a testable, working piece of infrastructure
- **Document Progress**: Mark completion status and any issues/decisions in the PLAN.md file

