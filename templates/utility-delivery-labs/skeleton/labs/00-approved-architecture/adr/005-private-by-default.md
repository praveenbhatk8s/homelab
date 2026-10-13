# ADR-005: Private by default

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

The customer's security team does not allow public endpoints for operational systems, and meter traffic must never cross the public internet.

## Decision

- AKS uses a private API server. Access is from the customer network over the VPN, through Entra ID.
- PostgreSQL uses VNet integration (delegated subnet) with public network access disabled.
- Key Vault and the container registry use private endpoints and private DNS zones.
- No public load balancers. Meter and API traffic arrive through an internal load balancer.
- CI/CD that changes the cluster runs on private runners inside the customer network, and GitOps agents pull from inside the cluster.
- All internet egress passes Azure Firewall with an FQDN allow-list.

## Alternatives considered

| Option | Why not chosen |
| --- | --- |
| Public API server with IP allow-list | Simpler for the delivery team, but violates the customer's policy and depends on IP lists staying correct. |
| Public endpoints behind a WAF | Appropriate for customer-facing portals, not for meter ingestion or operations. |

## Consequences

- Delivery engineers need VPN access to the customer network from day one. Request it in week one; it is often the slowest dependency.
- Hybrid DNS must work in both directions before anything else can be tested.
- Debugging from outside is impossible by design. Runbooks and observability must be good enough for the customer's team to act on their own.
