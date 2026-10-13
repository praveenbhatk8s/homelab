# Customer brief: Stadtwerke Talheim

*Fictional customer. All figures are invented for the lab.*

## Context

Stadtwerke Talheim is a municipal utility serving about 250,000 electricity customers. It is replacing legacy meters with smart meters over two years and has bought the MeterFlow head-end software. The delivery team's job is to build the environments MeterFlow runs in, migrate readings from the pilot system, and hand the platform to the operations team.

## What the customer said

1. "Production should run in Azure. Our IT strategy is cloud-first, and our group already has an Azure enterprise agreement."
2. "We already run OpenShift in our own datacentre for other systems. We want disaster recovery there, not dependent on the same cloud provider."
3. "All meter data must stay in Germany."
4. "Meters connect over a private cellular APN that terminates in our datacentre. No meter traffic over the public internet."
5. "Our security team does not allow public endpoints for operational systems."
6. "All TLS certificates must chain to our corporate CA."
7. "We can tolerate four hours of head-end downtime, because the concentrators buffer readings. We cannot lose more than fifteen minutes of readings that were already received."
8. "Our operations team knows OpenShift and Linux well, Azure less so. The runbooks must be written for them."
9. "Budget is fixed. Non-production environments should not cost the same as production."
10. "The pilot system holds 14 months of readings for 12,000 meters in a PostgreSQL database on a VM. Those readings must be migrated without gaps; they are used for billing disputes."

## Requirements as numbers

| Requirement | Value | Derived from |
| --- | --- | --- |
| Meters at full rollout | 250,000 | Brief |
| Reading interval | 15 minutes, so 96 readings per meter per day | Brief |
| Daily readings | 250,000 × 96 = **24 million** | Calculation |
| Average rate | 24,000,000 ÷ 86,400 s ≈ **278 readings/s** | Calculation |
| Peak rate | Meters report within a 5-minute window after each interval: 250,000 ÷ 300 s ≈ **833 readings/s** | Calculation |
| Design capacity | **2,000 readings/s** (about 2.4× peak, for catch-up after an outage) | Decision |
| Catch-up after 4 h outage | 16 intervals × 250,000 = 4 million readings; at 2,000/s spare capacity, about **35 minutes** | Calculation |
| Storage per reading | About 100 bytes in the database including index overhead (assumption to verify in lab 08) | Assumption |
| Storage per year | 24 M × 365 × 100 B ≈ **876 GB/year** before compression | Calculation |
| RTO | **4 hours** | Brief, item 7 |
| RPO | **15 minutes** for received readings | Brief, item 7 |
| Data residency | Germany only | Brief, item 3 |
| Public endpoints | None | Brief, item 5 |

The catch-up figure matters: after a four-hour outage, the platform must absorb the buffered backlog while new readings keep arriving. Designing for average load would turn a four-hour outage into a much longer one.

## Out of scope

- The meters, concentrators and APN (owned by the customer and their telecom provider).
- The billing system (consumes readings through an API; owned by another vendor).
- Day-to-day operation after handover (owned by the customer's operations team, with escalation to the delivery team).

## Open questions to raise with the customer

- How long can the concentrators actually buffer? The four-hour RTO assumes at least four hours plus margin.
- Who owns the corporate CA intermediate we will use, and what is the issuance lead time?
- Is the fixed budget per year or per month, and does it include the DR site's hardware?
