# TALK: A hardened platform that runs on Kubernetes and OpenShift

Questions this lab prepares you for: "How do you secure a Kubernetes platform for a customer?", "What's different on OpenShift?", "How do you handle certificates?", "How do you prove an environment is ready?"

## The two-minute walkthrough

> **H** — The platform is built so the customer's security team can approve it once, and so the same workload runs on AKS in production and OpenShift in DR.
>
> **C** — Every namespace enforces the restricted Pod Security Standard, which is the closest built-in match to OpenShift's restricted-v2. The image has no shell and runs under any non-root UID, so OpenShift can assign a random one. The platform owns a default-deny network policy per namespace; the application chart only adds the allows that match the connectivity matrix. Certificates come from cert-manager using the customer's CA, and the service re-reads its certificate when it changes, so rotation needs no restart. Access is bound to the customer's groups: operations can read logs and restart, but can't read secrets.
>
> Then an acceptance script runs ten checks, from "a root pod is rejected" to "99.5% of readings acknowledged", and writes a report that goes into the handover pack.
>
> **T** — The strict contract means some third-party images need replacing or rebuilding. I'd rather find that during delivery than during a DR failover.
>
> **F** — The quiet failure is a CNI that doesn't enforce NetworkPolicy. The policies apply cleanly and do nothing. That's why the setup script tests enforcement before anything else.
>
> **V** — The customer gets evidence, not assurances: a report their security team can file.

## Depth points

- **PSA versus SCC.** "PSA checks what a pod asks for; an SCC can also change it, for example by assigning a UID from the namespace range. So passing PSA restricted predicts passing restricted-v2, except for images that need a specific UID. That's why the acceptance script also runs the image as UID 1000680000 with group 0."
- **Group 0.** "OpenShift's random UID always belongs to group 0. Files an image must write to should be owned by group 0 and group-writable. This image writes nothing, so it doesn't matter, but it's the first thing I check in a vendor image."
- **Graceful shutdown.** "On SIGTERM the service fails readiness and keeps serving for five seconds while endpoints update, then drains. Without that, a rolling update drops in-flight batches. The concentrators would retry, but you'd see errors in the dashboards at every deploy."
- **No CPU limit.** "Memory limit to protect the node, CPU request for scheduling, no CPU limit. CPU limits cause throttling on a bursty ingest path even when the node has idle CPU."
- **Platform-owned default-deny.** "If the app chart owned its own default-deny, a chart change could delete it. Separating ownership means the security baseline survives application changes."
- **DNS on OpenShift.** "A NetworkPolicy that allows DNS to kube-dns on port 53 breaks on OpenShift, where DNS pods are in `openshift-dns` on port 5353. Small difference, total outage. It's a value in the chart, tested on both platforms."

## Questions you'll likely get

**"A vendor image runs on EKS but crash-loops on OpenShift."**
> First suspect is the SCC. The image probably expects root or a fixed UID and tries to write to a root-owned directory, or bind a port below 1024. I'd check the events and logs, then fix the image: group 0 ownership with group write, or writable volumes for those paths, and a high port. I wouldn't grant `anyuid`, because it would fail the security review and the DR platform would behave differently from production.

**"How do you manage certificates when the customer insists on their own CA?"**
> cert-manager with a CA issuer backed by an intermediate the customer issues for the platform. Certificates are short-lived, 90 days here, and renew 30 days before expiry. Workloads reload them without restarting. I expose the expiry as a metric and alert at 30 and 14 days, and the handover pack lists every certificate and who owns renewal of the intermediate itself, because that one is manual and usually forgotten.

**"How do you know NetworkPolicy is actually working?"**
> Test it. The setup script creates a pod, denies ingress, and confirms a client times out. The acceptance script repeats that against the real service from an unlabelled namespace. A connection that's refused for another reason doesn't count as a pass; only a timeout does.

**"How do you give the customer's operations team access?"**
> By directory group, never by person. Operations get a role to read, see logs, restart and scale, but not read secrets or delete deployments. Auditors get view. The delivery team gets edit during the project, and that binding is removed at handover. I check it with `kubectl auth can-i` as each group, and the results are in the acceptance report.

**"What's in your acceptance evidence?"**
> Ten checks mapped to requirements: availability, zone spread, container hardening, admission rejecting a root pod, the arbitrary-UID test, network isolation, TLS chain to the customer CA, certificate lifetime, reading completeness, and the RBAC matrix. Each row says which requirement it proves.

## Connect it to your real experience

- "At my last company I ran a tiered Kyverno policy chart across 40+ clusters; this is the same principle with built-in admission."
- "I scanned images with Trivy and posture with Kubescape in production. In a customer delivery I'd add those to the pipeline and include the results in the evidence pack."
- "I hold the Red Hat OpenShift Specialist certification. The SCC behaviour in this lab is exactly what that exam tests, and here I've built an image and a chart that handle it."

Be honest about OpenShift if asked directly: say where your production experience is (Kubernetes at scale on EKS, AKS, GKE and on-prem) and that this lab is how you've made the OpenShift differences concrete.

## Practice

- Record the walkthrough with the acceptance report on screen.
- Answer the vendor-image question in under 60 seconds.
- Explain exercise 2's result (drain delay) to a non-technical project manager in 30 seconds.
