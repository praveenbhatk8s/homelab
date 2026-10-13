# The answer framework: H-C-T-F-V

Use the same five beats for every technical answer. Repetition is the point: when the structure is automatic, your attention goes to the content, and nerves have less room.

| Beat | Question it answers | Length |
| --- | --- | --- |
| **H** Headline | What is the answer, in one sentence? | 1 sentence |
| **C** Concrete | How did I (or would I) do it, with one real detail? | 2–4 sentences |
| **T** Trade-off | What did I give up, and what did I consider instead? | 1–2 sentences |
| **F** Failure mode | How does it break, and how would I know? | 1–2 sentences |
| **V** Value | Why does the customer care? | 1 sentence, then stop |

Total: about 60 to 90 seconds. If they want more, they will ask, and a follow-up question is a good sign, not a failure.

## Why each beat matters

- **Headline** lets the interviewer relax: they know where you are going. It also forces you to commit to an answer instead of circling.
- **Concrete** is where seniority shows. One specific number, command, or design detail beats five tool names. Interviewers who said "we expected senior-level depth" were asking for this beat.
- **Trade-off** separates people who chose from people who copied. Name the alternative you rejected.
- **Failure mode** shows you have operated the thing, not just installed it. Say the symptom, the cause, and the signal that would warn you.
- **Value** turns an engineering answer into a delivery answer. For a customer-delivery role, this beat is half the evaluation.

## Worked example

**Question:** "How would you protect the database in the customer's production environment?"

> **H** — I'd make the database private, zone-redundant, and restorable to any point in the last 35 days, and I'd prove the restore before go-live.
>
> **C** — In Terraform that's a PostgreSQL Flexible Server on a delegated subnet with no public access, Entra ID authentication only so no password exists to leak, zone-redundant HA, and geo-redundant backups. Then I run a timed point-in-time restore into an isolated environment and record how long it took.
>
> **T** — Zone-redundant HA roughly doubles the database compute cost, so I'd only enable it in production and DR, not in dev or UAT. I'd also discuss with the customer whether 35 days of retention is a legal requirement or a default.
>
> **F** — HA does not protect against a bad migration or an accidental `DELETE`, because the standby replicates the damage. That's what PITR is for. The warning signal would be the restore test failing or taking longer than the RTO, which is why it's a go-live gate.
>
> **V** — For a utility, a lost hour of meter readings means estimated bills and complaints, so the restore evidence is what lets their security team sign off.

That is about 80 seconds spoken.

## Short version for quick questions

Not every question needs all five beats. For a factual question, use **H + C**, and add **F** if you can:

> "What's the difference between RTO and RPO?"
>
> "RTO is how long until the service is back; RPO is how much data you can lose, measured in time. RPO drives how often you back up or replicate; RTO drives how automated your recovery has to be. The classic mistake is treating replication as backup: it gives you a good RPO for hardware failure and none at all for corruption."

## Bad versus good openings

| Instead of | Say |
| --- | --- |
| "So, basically, at Actian we had, like, EKS and Terraform and..." | "I'd split it into three Terraform layers. Let me explain why." |
| "It depends." (and then silence) | "It depends on one thing: whether the customer allows public endpoints. If not, here's the design." |
| "I'm not sure, but maybe..." | "I haven't done that in production. Here's how I'd approach it, based on what I've done with X." |
| Listing six tools | Naming one tool and why you chose it over the obvious alternative |

## Closing lines that work

End on value, then stop. Useful endings:

- "...and that's what got the customer's security team to sign off."
- "...which turned a two-day manual build into a 40-minute pipeline run."
- "...so the next customer environment reused all of it."
- "Would you like me to go deeper on the network side or the restore test?"

The last one is especially useful: it hands control back and steers the next question toward something you know well.
