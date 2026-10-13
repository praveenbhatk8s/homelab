# TALK: Presenting the architecture

Likely the first technical thing you'll be asked: "Walk me through how you'd design this," or "Tell me about an architecture you delivered." Use this design as your worked example, then connect it to your real experience.

## The three-minute walkthrough

Say this with the diagram in front of you. Point at each box as you mention it. Practise until you can do it without reading.

**Requirements first (30 seconds)**

> The customer is a utility with 250,000 meters reading every 15 minutes. That's 24 million readings a day, about 830 a second at peak, and I designed for 2,000 a second so the platform can catch up after an outage. They want production in Azure, DR independent of Azure, data in Germany, no public endpoints, RTO four hours, RPO fifteen minutes.

**Data path (45 seconds)**

> I always draw the data path first. Meters send readings over a private APN to concentrators, which forward them into the customer's datacentre. From there they cross a site-to-site VPN into an Azure hub with a firewall, and reach the head-end on AKS through an internal load balancer. The head-end stores them in a zone-redundant PostgreSQL, which replicates to the DR site.

**The key decisions (60 seconds)**

> Three decisions shape everything. First, DR runs on the customer's own OpenShift, because they already operate it and the APN already terminates there, so failover shortens the path instead of lengthening it. Second, because of that, the workload has to be portable: every container runs as an arbitrary non-root UID with a read-only filesystem, so the same chart runs on AKS and OpenShift. Third, the database replicates with logical replication, because it's a managed service and we can't ship physical WAL out of it. That gives us the 15-minute RPO, and we alert at five minutes of lag.

**Trade-offs and failure modes (30 seconds)**

> The trade-off I watch most is logical replication: it doesn't carry schema changes, so every release applies migrations to both sides in order. And HA doesn't protect against a bad migration, because the standby copies the damage. That's what point-in-time restore is for.

**Value close (15 seconds)**

> For the utility, the number that matters isn't uptime, it's reading completeness, because a lost reading becomes an estimated bill. So the primary SLO is 99.5% of expected readings stored within two hours, and every design choice protects that.

Then stop, and ask: "Would you like me to go deeper on the network, the DR failover, or the Terraform behind it?"

## Connecting it to your real experience

After the walkthrough, add one or two sentences that link the design to work you did in production:

- **Portable workloads and policy:** "At Actian I enforced admission policy across 40+ clusters with a tiered Kyverno chart, so this contract is something I've run, not just designed."
- **On-prem plus cloud:** "The DR side is close to what I delivered for a bank at IBM: on-prem Kubernetes with dev to prod clusters, backups, and DR tested through mock incidents."
- **Multi-cloud:** "I ran the same platform on EKS, AKS and GKE, so I'm used to keeping one design portable across providers."

## Trade-offs to have ready

| Decision | What it costs | What it buys |
| --- | --- | --- |
| DR on customer OpenShift | Two platforms to test; portability rules on every image | Independence from Azure; a team that knows the DR platform |
| Logical replication | Manual DDL handling; sequence fix-up at failover | RPO of minutes from a managed database |
| Zone-redundant database in prod only | Non-prod doesn't test HA failover | Roughly half the database cost outside prod |
| Private by default | Slower delivery start (VPN, DNS); harder debugging | Passes security review; nothing exposed |
| Design for 2,000/s | About 2.4× the peak capacity, at idle cost | Catch-up after a four-hour outage in about 35 minutes |

## Failure modes to have ready

| Failure | Symptom | Signal |
| --- | --- | --- |
| Both VPN tunnels down | Readings stop arriving; concentrators buffer | Completeness drops for the newest interval; VPN gateway metrics |
| Replication stalled | DR silently falls behind | Replication lag alert at 5 minutes |
| Schema migration not applied on DR | Replication errors, then stops | Subscription error in DR logs; lag climbing |
| Hybrid DNS one-way | Azure can't resolve customer names or vice versa | Billing integration timeouts; failover test fails at name resolution |
| Certificate expiry from customer CA | Meters or billing fail TLS | Certificate expiry alerts at 30 and 14 days |

## Likely questions

1. **"Why not put DR in a second Azure region?"** Customer wants independence from one provider; Germany North also lacks zones and needs an access request. See ADR-001.
2. **"What if the customer had wanted RTO 30 minutes?"** Warm standby instead of scaled-to-zero: head-end running at reduced size in DR, automated DNS or route switch, tested monthly. Higher cost; name roughly what changes.
3. **"How would this change for a second utility customer?"** Ask first whether they need dedicated infrastructure by contract. Usually a separate spoke and cluster per customer from the same modules; shared only if the contract allows and isolation is proven (lab 03).
4. **"Where is the weakest point?"** Honest answer: the VPN and hybrid DNS, because they are outside our control and fail in confusing ways. Mitigations: two tunnels with BGP, DNS tested in both directions as the first acceptance test, and DR receiving APN traffic locally.
5. **"How do you know the RPO is really 15 minutes?"** Replication lag is measured continuously and is part of the DR drill report; the drill also checks the last reading on the DR side against the last reading in production.
6. **"What would you do in week one?"** Request VPN access, send the connectivity matrix, confirm CA ownership and lead time, agree the environment list and budget, and set up the Terraform repository and pipeline.

## Practice

- Record the three-minute walkthrough. Score it with the scorecard in [speaking/drills.md](../../speaking/drills.md).
- Have someone ask the six questions above in random order. Answer each in under 90 seconds.
- Draw the data path from a blank page while narrating, using the whiteboard sequence in [speaking/freeze-recovery.md](../../speaking/freeze-recovery.md).
