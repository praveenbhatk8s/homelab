# Lab 00: Approved architecture

Every delivery starts from an architecture the customer has approved. This lab is that starting point: the customer brief, the target architecture, the connectivity matrix the customer's network team needs, and the decisions behind it, recorded as ADRs.

The other labs implement this design. When an interviewer asks "why did you build it this way?", the answer is in this folder.

## What you'll practise

- Turning customer requirements into numbers you can design against.
- Drawing the data path before the infrastructure.
- Writing decisions down with their trade-offs, so the next engineer (or the customer's auditor) understands them.
- Presenting a design in three minutes, then defending it.

## Files

| File | Purpose |
| --- | --- |
| [customer-brief.md](customer-brief.md) | What Stadtwerke Talheim asked for, and the numbers derived from it |
| [architecture.md](architecture.md) | Target architecture, data path, environments, failure behaviour |
| [connectivity-matrix.md](connectivity-matrix.md) | Every network flow, for the customer's firewall team |
| [adr/](adr/) | Six architecture decision records |
| [TALK.md](TALK.md) | How to present and defend this design |

## Exercises

1. **Re-derive the numbers.** Read the brief, close it, and calculate the reading rate, daily volume and storage per year yourself. Compare with the brief.
2. **Draw it from memory.** On paper or Excalidraw, draw the data path from meter to database, then add the DR site. Time yourself; aim for under five minutes while narrating.
3. **Change one requirement.** The customer now wants RTO 30 minutes instead of 4 hours. Which ADR changes, and what does it cost? Write a new ADR (`adr/007-...md`) that supersedes the old one.
4. **Present it.** Follow [TALK.md](TALK.md) with a timer and a recording. Score it with the scorecard in [speaking/drills.md](../../speaking/drills.md).

## Done when

- You can present the architecture in three minutes without notes.
- You can answer every question in the "Likely questions" section of TALK.md in under 90 seconds.
- Exercise 3's ADR exists and names its cost.
