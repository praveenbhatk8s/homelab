# TALK: Terraform for repeatable customer environments

Terraform is the one tool most customer-delivery job ads name as a hard requirement, so expect the deepest questions here. This is where to show depth: one concrete detail per answer.

## The two-minute walkthrough

> **H** — Every environment for the customer comes from one set of modules, and the only difference between dev and prod is a profile table.
>
> **C** — There are four small modules: network, AKS, PostgreSQL and monitoring, plus a composition module that wires them into one customer environment. Each environment has its own root directory and its own state file. The profile table sets zones, node sizes, database HA and backup retention per environment, so the customer can see exactly why UAT costs less than production.
>
> The customer's requirements are guardrails in code. The region is restricted to Germany. The spoke's address range is checked against every customer range, so we can't create a network that breaks routing over the VPN. AKS and PostgreSQL are private and accept Entra ID only, so no database password exists anywhere. And each of those rules has a test that runs offline with mock providers, in seconds, on every pull request.
>
> **T** — I chose directories over workspaces, because environments differ in more than size and I want separate state and a visible difference in code. The cost is a bit of duplication in the environment roots.
>
> **F** — The failure I watch for is drift: someone fixes production by hand in the portal. A scheduled plan catches it, and the pipeline is the only identity with write access in production.
>
> **V** — The point is that the next customer environment is a pull request with a variables file, reviewed and tested, rather than a two-week project.

## Depth points to drop in when asked

Pick the one that fits the question. Each is a detail most candidates don't mention.

- **Overlap check.** "Terraform has no CIDR-overlap function, so the validation reads both ranges at the shorter prefix length and compares their network addresses with `cidrhost(x, 0)`. It catches a spoke that overlaps the customer's datacentre before anything is created."
- **HA zone swap.** "After a Flexible Server HA failover, Azure swaps the primary and standby zones. Without `ignore_changes` on those two attributes, the next plan tries to move them back and triggers another failover. That's the kind of thing you only learn from running it."
- **Autoscaler and node count.** "`ignore_changes` on node count, because the cluster autoscaler owns it; otherwise every plan shows a diff and people stop reading plans."
- **Preconditions over documentation.** "HA isn't available on Burstable SKUs. Instead of a comment, it's a precondition, so a wrong combination fails at plan with a clear message."
- **wal_level restarts the server.** "Turning on logical replication changes `wal_level`, which restarts the database. On a live customer that's a planned change in a maintenance window, not something to slip into a routine apply."
- **Geo-redundant backup is create-time only.** "You can't turn it on later without recreating the server, so it has to be right in the first prod apply."

## Questions you'll likely get

**"How do you handle state?"**
> One state file per environment in the customer's own storage account, with Entra ID auth and blob-lease locking. The state contains sensitive values, so access to the container is restricted to the pipeline identity and a break-glass group. I never commit state, and I never edit it by hand; I use `import` blocks, `moved` blocks and `terraform state mv` when I need to change it.

**"An apply failed halfway. What now?"**
> First, don't panic and don't re-run blindly. Check whether the state is still locked and who holds the lock; if nothing is running, `force-unlock`. Then run a plan, which shows what was created and what's left. Usually re-running the apply finishes the job. If a resource was created outside state, import it rather than letting Terraform create a duplicate.

**"How would you roll out a module change to fifteen customer environments?"**
> Tag a new version, update dev first, read the plan, then one low-risk customer, then the rest in batches. For refactors I use `moved` blocks so the plan shows zero destroys. I'd never point environments at a branch; every root pins a version.

**"Why Terraform and not Bicep?"**
> For a single Azure customer, Bicep is a reasonable choice and has day-zero support for new resource types. I'd choose Terraform when the same delivery team builds on Azure, AWS and on-prem, because one tool, one review process and one test approach across all of them is worth more than day-zero support. If the customer mandates Bicep, I'd use Bicep.

**"Terraform or OpenTofu?"**
> Terraform moved to the Business Source Licence in 2023, and OpenTofu is the open-source fork. For a delivery team using it internally the licence rarely matters, but some customers have policies on it. These labs run on both: `TF=tofu make test`.

**"How do you test infrastructure code?"**
> Three levels. `terraform test` with mock providers for logic and guardrails, which is fast and needs no cloud. Policy scanning with Checkov or similar for security baselines. And a real apply into a short-lived sandbox for integration, destroyed the same day. Most bugs are caught by the first level.

## Trade-offs to have ready

| Choice | Cost | Benefit |
| --- | --- | --- |
| Separate roots per environment | Small duplication in `envs/` | Separate state, visible differences, small blast radius |
| Profiles inside the composition module | Changing a size means a module change | One table to review; environments can't drift in shape |
| Entra ID only on PostgreSQL | Every app needs workload identity set up | No password exists to leak or rotate |
| Mock-provider tests | Don't catch Azure API errors | Run in seconds with no credentials, on every PR |

## Connect it to your real experience

- "At my last company I wrote custom Terraform providers, so I know the plan and apply lifecycle from the inside: how a provider decides a change needs replacement."
- "At IBM I wrote a Terraform provider in Go for the object storage project."
- "Across 40+ clusters on three clouds, the lesson was the same as here: the profile table and the guardrails are what keep environments consistent, not documentation."

## Practice

- Do the walkthrough with the profile table on screen. Record it; aim for two minutes.
- Answer "an apply failed halfway" and "roll out to fifteen environments" in 60 seconds each.
- Have someone ask "Why?" three times after your answer about directories versus workspaces.
