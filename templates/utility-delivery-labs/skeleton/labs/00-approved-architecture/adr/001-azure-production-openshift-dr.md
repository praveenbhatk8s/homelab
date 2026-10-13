# ADR-001: Production in Azure, disaster recovery on the customer's OpenShift

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

The customer requires production in Azure (cloud-first strategy, existing enterprise agreement), disaster recovery independent of that cloud provider, all data in Germany, and an RTO of four hours. Their operations team already runs OpenShift in their Talheim datacentre, and the meter APN terminates there.

## Decision

Run production on AKS in Azure Germany West Central across three availability zones. Run disaster recovery on the customer's existing OpenShift cluster in Talheim, with the database replicating continuously and the head-end scaled to zero until failover.

## Alternatives considered

| Option | Why not chosen |
| --- | --- |
| DR in a second Azure region (Germany North) | Fails the "independent of the cloud provider" requirement. Germany North also has no availability zones and requires an access request. |
| Active-active across Azure and Talheim | Far higher cost and complexity (write conflicts, global load balancing) for an RTO the customer says can be four hours. |
| Production on-prem, DR in Azure | Contradicts the cloud-first strategy the customer stated. |

## Consequences

- MeterFlow must run identically on AKS and OpenShift (see ADR-002).
- Failover routes meter traffic to a site the APN already reaches, which shortens the path during a disaster.
- The operations team gets a DR environment on a platform they know, which lowers the risk of a failed failover.
- The delivery team must test failover across two platforms, which is drilled in lab 05.
- Cost: the DR site uses existing customer hardware; the main extra cost is PostgreSQL capacity and replication bandwidth.
