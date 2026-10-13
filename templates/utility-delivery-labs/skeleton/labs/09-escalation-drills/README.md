# Lab 09: Escalation drills

Six faults injected into the lab 02 platform, each arriving as a customer escalation. You diagnose from the symptoms, fix it, and explain it out loud as if the customer's engineer were on the call.

Delivery engineers are the escalation point for critical problems during go-live and after handover. Interviewers test this with "production is down, walk me through it". These drills give you real incidents to talk about, and practise the habit that matters most under pressure: narrating calmly, one hypothesis at a time.

## Before you start

- Lab 02 running and its acceptance script passing.
- Read the method below once.
- Don't read `drill.sh` or any `SOLUTION.md` before the drill.

## The method: say every step out loud

Record yourself, or have someone listen. Narrate like this:

1. **Impact.** "Who is affected, since when, and how badly?" Read the ticket for this.
2. **What changed?** "What was deployed, edited or scaled recently?" `helm history`, `kubectl rollout history`, events.
3. **Stabilise if you can.** "Can I roll back or restore service before I understand it fully?"
4. **One hypothesis at a time.** "My first hypothesis is X, because of Y. The cheapest check is Z." Run it, say what it ruled in or out.
5. **Fix, then verify with data.** Use the same signal that showed the problem.
6. **Close.** Root cause in one sentence, how to stop it happening again, and a short update for the customer.

When stuck: say "Let me step back. What do I know for certain?" and list the facts. This is the freeze-recovery move from [speaking/freeze-recovery.md](../../speaking/freeze-recovery.md).

## Run a drill

```bash
cd labs/09-escalation-drills
./drill.sh list
./drill.sh start 1        # then open drills/01-*/TICKET.md
# ... diagnose and fix ...
./drill.sh reset          # always reset before the next drill
```

Useful views while you work:

```bash
kubectl -n meterflow get pods,deploy,rs -o wide
kubectl -n meterflow get events --sort-by=.lastTimestamp | tail -20
kubectl -n concentrators logs deploy/meter-sim --tail=20
kubectl -n concentrators port-forward deploy/meter-sim 9091:9091   # then curl localhost:9091/metrics
kubectl -n meterflow port-forward svc/meterflow 9090:9090          # then curl localhost:9090/metrics
```

## The drills

| # | Ticket | What it teaches |
| --- | --- | --- |
| 1 | [Vendor exporter never starts](drills/01-vendor-exporter/TICKET.md) | Pod security admission; the OpenShift SCC failure in Kubernetes form |
| 2 | [Readings stopped arriving](drills/02-readings-stopped/TICKET.md) | Label-based NetworkPolicy trust; buffering hides outages |
| 3 | [TLS errors since this morning](drills/03-tls-errors/TICKET.md) | Certificate SANs; drift from manual edits |
| 4 | [Release pipeline stuck](drills/04-stuck-release/TICKET.md) | Readiness probes; why `maxUnavailable: 0` saved production |
| 5 | [Scaled up, nothing changed](drills/05-pending-pods/TICKET.md) | Scheduling, requests and capacity |
| 6 | [Estimated readings, green dashboards](drills/06-silent-rejections/TICKET.md) | Why completeness is the SLI, not uptime |

Each drill folder has `TICKET.md` (the escalation), `HINTS.md` (three hints, read one at a time), and `SOLUTION.md` (diagnosis, fix, prevention, and a model narration).

## Scoring yourself

| | Target |
| --- | --- |
| Time to first correct hypothesis | Under 5 minutes |
| Hints used | 0 or 1 |
| Stabilised before diagnosing, where possible | Yes |
| Customer update written | Under 5 sentences, no jargon |
| Narration | No silence longer than 10 seconds |

Repeat any drill where you used two or more hints, a week later, without notes.

## Done when

- All six drills done, each in under 15 minutes.
- For two of them, you've recorded a full narration and scored it with [speaking/drills.md](../../speaking/drills.md).
- You can tell the story of drill 6 as an interview answer to "Tell me about a time monitoring didn't catch a problem."
