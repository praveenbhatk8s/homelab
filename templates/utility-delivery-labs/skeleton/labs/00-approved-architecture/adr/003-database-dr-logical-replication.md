# ADR-003: Database DR through logical replication to the datacentre

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

The customer accepts losing at most 15 minutes of readings already received (RPO). Production uses Azure Database for PostgreSQL Flexible Server, a managed service, so we cannot stream its physical WAL to a database we run elsewhere. The DR database runs on OpenShift in Talheim.

## Decision

1. Replicate the readings and reference tables from Azure to a PostgreSQL cluster on the DR OpenShift using PostgreSQL logical replication (publication in Azure, subscription in Talheim).
2. Alert when replication lag exceeds 5 minutes, page at 10 minutes, so the 15-minute RPO is protected with margin.
3. Keep Azure's own backups (35-day point-in-time restore, geo-redundant) for corruption and accidental deletion, which replication would copy.
4. Copy a nightly logical dump to the Talheim object store, so a full restore is possible even if Azure is unavailable for a long time.

## Alternatives considered

| Option | Why not chosen |
| --- | --- |
| Rely on Azure geo-redundant backup only | Restores into another Azure region, which fails ADR-001's independence requirement; restore time also eats into the RTO. |
| Run PostgreSQL ourselves on AKS with physical streaming replication | Gives better replication, but makes the delivery team responsible for database HA and patching, which the customer wants managed in production. |
| Application-level dual writes | Complex, and creates consistency problems on partial failure. |

## Consequences

- Logical replication does not replicate schema changes (DDL). Schema migrations must be applied to both sides, in order, as part of every release. This is a release-checklist item.
- Sequences are not replicated; failover includes a step to advance sequences on the DR side.
- Replication runs over the VPN, so VPN bandwidth must cover the peak write rate plus catch-up. At about 100 bytes per reading and 2,000 readings per second, that is roughly 200 KB/s before protocol overhead.
- Measured replication lag is the real RPO and must be part of the DR drill evidence (lab 05).
