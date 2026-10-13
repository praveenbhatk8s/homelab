# ADR-004: One Terraform codebase, a directory per environment

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

Four Azure environments (dev, uat, staging, prod) must share one design, differ in size and resilience, and be changed safely. The same patterns will be reused for the next utility customer.

## Decision

- Reusable modules in `modules/` (network, AKS, PostgreSQL, monitoring), each with typed and validated inputs, its own tests, and semantic version tags.
- One composition module (`modules/meter-platform`) that wires them together for a customer environment.
- One root directory per environment in `envs/`, each with its own remote state and a small variables file. Differences between environments live only in those variables.
- Changes reach an environment only through a pipeline: plan on pull request, review of the plan, apply of the saved plan on merge, in the order dev, uat, staging, prod.

## Alternatives considered

| Option | Why not chosen |
| --- | --- |
| Terraform workspaces | One backend configuration for all environments and no visible per-environment difference in code; risk of applying to the wrong workspace. |
| One root for all environments | One state file means one failed apply can block every environment, and every plan touches production. |
| Terragrunt | Useful at larger scale; adds a tool the customer's operations team would also need to learn. Revisit beyond about ten environments. |

## Consequences

- A new environment is a new directory and a variables file, reviewed like any other change.
- State is split per environment, which limits the blast radius of a mistake.
- Module upgrades roll through environments one at a time, which takes longer but surfaces problems in dev first.
