# Utility Platform Delivery Labs

Hands-on labs that deliver a smart-metering platform for a utility customer, end to end: from an approved architecture, through Infrastructure as Code and a hardened Kubernetes/OpenShift-compatible platform, to migration, disaster-recovery validation and formal handover.

Every lab is built around one fictional customer, **Stadtwerke Talheim**, a municipal utility rolling out 250,000 smart electricity meters. The workload is **MeterFlow**, a small head-end service written in Go that receives 15-minute interval readings from meters and tracks data completeness.

> Stadtwerke Talheim and MeterFlow are invented for these labs. Any resemblance to a real utility or product is coincidental.

## Why this repo exists

Most platform demos stop at "the cluster is up". Customer delivery work does not. A utility needs every reading for billing, wants its data to stay in Germany, has its own corporate CA, forbids public endpoints, and expects a tested disaster-recovery plan and a handover package before it signs off.

These labs practise exactly that work, with numbers you can measure: provisioning time, restore time (RTO), data loss window (RPO), reading completeness, and cost per environment.

## The labs

| # | Lab | What you deliver | Status |
| --- | --- | --- | --- |
| 00 | [Approved architecture](labs/00-approved-architecture/) | Customer brief, architecture, connectivity matrix, ADRs | Ready |
| 01 | [Terraform environments](labs/01-terraform-environments/) | Reusable Azure modules; dev, UAT, staging and prod from one codebase; guardrails as offline tests | Ready |
| 02 | [Hardened platform](labs/02-hardened-platform/) | MeterFlow on Kubernetes: restricted pod security, arbitrary-UID image, RBAC, default-deny network, private-CA TLS | Ready |
| 03 | Tenant isolation | Two utilities on shared vs dedicated platforms; isolation matrix and failure modes | Next |
| 04 | GitOps and progressive delivery | Argo CD per environment; migrating a Deployment to Argo Rollouts with automated analysis | Next |
| 05 | Backup and DR drill | Velero and PostgreSQL PITR; a script that measures RTO and RPO; drill report | Next |
| 06 | Migration cutover | Legacy VM database to platform with replication, reading reconciliation, buffered replay and rollback | Next |
| 07 | On-prem automation | Ansible roles for customer-datacentre hosts: hardening, prerequisites, check mode | Next |
| 08 | SLOs, monitoring and cost | Completeness SLO, burn-rate alerts, runbook-linked alerts, cost per environment | Next |
| 09 | [Escalation drills](labs/09-escalation-drills/) | Six injected faults, written as customer escalations, with narrated diagnosis | Ready |
| 10 | Readiness and handover | Production-readiness checklist, acceptance evidence, handover pack | Next |

## Speaking track

Each lab has a `TALK.md`: a two-minute walkthrough, the trade-offs, the failure modes, and how the work serves the customer. The [speaking](speaking/) folder holds the method and the drills behind it.

## Prerequisites

| Tool | Used in | Notes |
| --- | --- | --- |
| Terraform 1.9+ or OpenTofu 1.9+ | 01 | `terraform test` runs offline with mock providers; no Azure account needed |
| Docker or OrbStack | 02, 09 | Builds the MeterFlow image |
| kind 0.24+ or k3s | 02, 09 | Any conformant cluster with NetworkPolicy support |
| kubectl, Helm 3 | 02, 09 | |
| Go 1.23+ | 02 | Only to build MeterFlow outside Docker |

An Azure subscription is optional. Lab 01 is designed to be planned and tested without one; applying it is a separate, opt-in step.

## Suggested order

1. Lab 00, and present it aloud.
2. Lab 02, then lab 09 on top of it. These two give you the most to talk about.
3. Lab 01, offline tests first.
4. The remaining labs as they arrive.

## Repository layout

```
labs/                each lab is self-contained, with README.md and TALK.md
apps/meterflow/      Go head-end service and meter simulator used from lab 02 onward
speaking/            answer framework, freeze recovery, drills
```

## Licence

MIT
