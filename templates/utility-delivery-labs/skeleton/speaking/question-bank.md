# Question bank

Questions for customer-delivery platform roles in regulated industries, with answer outlines in the H-C-T-F-V shape. The outlines are bullets on purpose: memorising full sentences makes you sound scripted. Learn the beats; let the sentences come fresh each time.

Placeholders like **[your story]** are where your own experience goes. Fill them in your private copy.

## A. Opening and motivation

### A1. Tell me about yourself.
Aim for 60 seconds, three parts: who you are now, the two experiences most relevant to this role, why this role.
- **Now:** senior platform engineer, 17 years in infrastructure, last 8 on Kubernetes across AWS, Azure and GCP.
- **Relevant 1:** built and operated a multi-cloud data platform; Terraform and GitOps across 40+ clusters.
- **Relevant 2:** delivered on-prem Kubernetes end to end for a regulated bank: dev to prod, CI/CD, backup, DR.
- **Why this:** you like delivering complete environments to customers, and the energy sector work matters to you.
- **Close:** "That combination of repeatable cloud builds and customer-site delivery is exactly what this role describes."

### A2. Why delivery work rather than platform ownership?
- **H:** you like finishing things and seeing them go live.
- **C:** each customer is a new set of constraints: network, security, compliance.
- **T:** you give up long-term ownership of one system, but gain breadth and a faster feedback loop.
- **V:** your experience lowers the risk of a failed go-live.

### A3. You have far more experience than we asked for. Will you be bored?
- **H:** no; each customer environment is a different problem, and you want hands-on work.
- **C:** mention that you deliberately prefer an individual-contributor or tech-lead path over management.
- **V:** seniority means fewer surprises at go-live, and someone who can write the standards others reuse.

### A4. Why did you leave your last role?
- One sentence: the company restructured after a merger, and the role was eliminated; not performance.
- Then pivot: "Since then I've been deliberate about what I want next, which is customer delivery."

## B. Architecture and environments

### B1. How do you turn one approved architecture into dev, UAT, staging, prod and DR?
- **H:** one set of modules, one root per environment, differences only in variables.
- **C:** sizes, replica counts, HA flags as inputs; DR is the same code in another region or site. Show lab 01.
- **T:** directories over workspaces, because environments differ in more than size and need separate state.
- **F:** environment drift when someone hot-fixes prod by hand; caught by a scheduled `plan`.
- **V:** the tenth environment is a pull request, not a project.

### B2. Design the platform for a utility with production in Azure and DR in its own datacentre.
Use the whiteboard sequence in [freeze-recovery.md](freeze-recovery.md). Key points:
- Requirements first: meter count, reading interval, RTO and RPO, data residency, public endpoints.
- Data path: meter, APN, customer network, VPN or ExpressRoute, head-end, database.
- DR: asynchronous database replication to on-prem, GitOps to rebuild workloads, DNS switch.
- **F:** VPN as single point of failure; readings buffered at concentrators for how long?
- **V:** billing completeness, data in Germany.

### B3. The customer forbids any public endpoint. What changes?
- Private cluster API, private endpoints for PaaS, no public load balancer.
- Access through VPN, bastion, or private CI runners inside their network.
- Pull-based GitOps from inside their network.
- Image registry mirrored internally.
- **F:** DNS: private zones must resolve from on-prem; conditional forwarding both ways.

## C. Terraform

### C1. How do you structure Terraform so the next customer environment takes days, not weeks?
- Small composable modules with typed, validated inputs; versioned with tags; a thin root per customer environment.
- Tests with `terraform test`, policy checks, plan on every pull request.
- **[your story]:** custom Terraform providers at your last company; the Go provider at IBM.

### C2. A colleague's apply died halfway and the state is locked.
- Find who holds the lock and confirm nothing is running.
- `terraform force-unlock` with the lock ID.
- `plan` to see what was partially created; never hand-edit state first.
- **T:** importing orphans vs letting Terraform recreate them.

### C3. How do you change a module used by fifteen customer environments safely?
- New version tag; roll through dev, then one low-risk customer; read every plan.
- `moved` blocks for refactors so nothing is destroyed.
- **F:** a provider upgrade that changes defaults silently; pin versions and read the changelog.

### C4. Where do Terraform, Ansible and Helm each stop?
- Terraform: infrastructure and the cluster itself.
- Ansible: operating systems and software on VMs and on-prem hosts.
- Helm and GitOps: workloads inside the cluster.
- **T:** you could do more with Terraform, but its state model is poor at in-cluster lifecycle.

## D. Kubernetes and OpenShift

### D1. A vendor image runs on EKS but crash-loops on OpenShift. Why?
- **H:** almost always security context constraints: OpenShift runs pods as a random UID.
- **C:** the image writes to a directory owned by root, or binds a port below 1024. Fix the image: group 0 ownership with group write, or use writable volumes; listen on a high port.
- **T:** granting `anyuid` makes it work today and fails the security review tomorrow.
- **[lab]:** lab 02 builds an image that runs under the restricted profile; lab 09 drill 1 reproduces the failure.

### D2. Walk me through an OpenShift minor upgrade for a production customer.
- Check the upgrade graph and channel, operator compatibility, deprecated APIs.
- Back up etcd. Confirm PodDisruptionBudgets allow drains.
- Control plane first via the Cluster Version Operator; then worker MachineConfigPools roll.
- Pause a worker pool to control the blast radius.
- **F:** a PDB with `maxUnavailable: 0` stalls the drain forever.

### D3. How do you isolate two customers on one cluster?
- Namespaces, RBAC, NetworkPolicy default-deny, quotas, restricted pod security, separate node pools with taints.
- Stronger: a virtual cluster per tenant, or a dedicated cluster.
- **T:** the stronger the isolation, the higher the cost and operational load. Ask what the customer contract requires.
- **F:** shared control plane means one tenant's CRD or webhook can affect another.
- Lab 03 builds the isolation matrix.

### D4. How do you manage certificates when the customer insists on their own CA?
- cert-manager with a CA issuer using a customer-issued intermediate, or an ACME/Vault issuer they run.
- Replace default ingress and API certificates.
- **F:** expiry. Alert at 30 and 14 days; one inventory of every certificate in the handover pack.

## E. Security, DR, migration

### E1. The customer wants RPO 15 minutes and RTO 4 hours on a limited budget.
- **H:** a pilot-light DR: data replicated continuously, compute off until needed.
- **C:** database geo-replication or log shipping; infrastructure as code to stand up compute; GitOps for workloads.
- **T:** cheaper than warm standby, but recovery depends on automation working when needed, so it must be drilled.
- **F:** replication lag silently exceeding 15 minutes; alert on lag.
- **V:** meets the contract at a fraction of active-active cost.

### E2. Tell me about a restore that failed.
- **[your story]:** the Velero restore gap found during a mock drill on the banking engagement.
- What exactly failed, what you changed, how you proved it in the next drill.
- **V:** found in a drill, not during an outage.

### E3. How do you validate that no data was lost in a migration?
- Row counts and checksums per partition (per meter per day for readings).
- Application-level reconciliation: totals the business recognises.
- Parallel run where possible.
- **[your story]:** 2,000-server migration with zero data loss.

### E4. The security questionnaire arrives two weeks before go-live.
- Build evidence from day one so the questionnaire is a matter of pointing at documents.
- Answer the easy ones fast; schedule a call for the ambiguous ones.
- **V:** go-live doesn't slip on paperwork.

## F. Escalation and customers

### F1. Production is down and you're escalated. Your first 15 minutes?
- Impact and scope; what changed recently.
- Stabilise first: roll back, fail over, scale.
- One hypothesis at a time, cheapest check first.
- Update the customer on a fixed rhythm, even without news.

### F2. You disagree with the architect's approved design after you've found a problem during the build.
- Bring evidence, not opinion: a failing test, a cost figure, a limit.
- Propose an alternative and its cost.
- Accept the final decision and record it in an ADR.

### F3. The customer's network team is slow to open firewall rules.
- Send a complete connectivity matrix early, in their format.
- Agree a date; escalate through the project manager if it slips; never work around their controls.

### F4. How do you use AI tools responsibly in infrastructure work?
- Drafting modules, pipelines, runbooks; explaining errors.
- Review every line, `plan` and policy-scan generated IaC, test in non-production.
- Never paste customer names, IPs, credentials, state or logs with personal data.

## G. Questions to add after each interview

Write any question that surprised you here, with a better answer, within an hour of the interview.

| Date | Company | Question | Better answer outline |
| --- | --- | --- | --- |
| | | | |
