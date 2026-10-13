# ADR-002: A portable workload contract for AKS and OpenShift

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

ADR-001 puts production on AKS and DR on OpenShift. A workload that runs on one and fails on the other turns a disaster into a debugging session. OpenShift's default `restricted-v2` security context constraint runs containers with a random UID from the namespace's range, forbids privilege escalation, and drops all capabilities. Many images built for vanilla Kubernetes assume root or a fixed UID.

## Decision

Every workload in this platform must satisfy this contract, enforced in CI and at admission:

1. Runs as a non-root, arbitrary UID. Files the process writes belong to group 0 with group write permission, or live on mounted volumes.
2. `allowPrivilegeEscalation: false`, all capabilities dropped, `seccompProfile: RuntimeDefault`.
3. Read-only root filesystem; temporary files go to an `emptyDir`.
4. Listens on unprivileged ports (above 1024).
5. No cloud-specific APIs in application code. Cloud integrations (identity, secrets) are injected by the platform.
6. Ingress is defined once in the Helm chart, with a value that switches between a Kubernetes Gateway/Ingress and an OpenShift Route.

On AKS, every namespace enforces the Kubernetes Pod Security Standard `restricted`. This is close enough to `restricted-v2` that passing one predicts passing the other, with one gap: PSA does not assign random UIDs. CI therefore also runs the image with a random UID (lab 02 does this).

## Alternatives considered

| Option | Why not chosen |
| --- | --- |
| Grant `anyuid` on OpenShift | Works immediately and fails the customer's security review. Also differs from production behaviour. |
| Separate charts for AKS and OpenShift | Two things to keep in sync; the DR chart would drift and fail when needed. |

## Consequences

- Third-party images (for example databases) must be checked against the contract, and some replaced with OpenShift-certified equivalents.
- Lab 09 drill 1 reproduces the most common violation so the failure is recognisable.
