# Freeze recovery

Going blank is a stress response, not a knowledge gap. The fix is to have words ready that buy time honestly and restart your thinking, so silence never gets long enough to feel like failure.

## The 3-second reset

When you feel the freeze:

1. **Breathe out slowly** through your mouth, one long exhale. It takes about three seconds and slows your heart rate.
2. **Say a bridge sentence** (below). It fills the silence and tells the interviewer you are working, not stuck.
3. **Go back to the headline beat.** Ask yourself: "What is the one-sentence answer?" Say that, even if rough. Detail will follow.

## Bridge sentences

These are honest. They describe what you are actually doing.

| Situation | Say |
| --- | --- |
| Need a moment | "Let me think about that for a second." (then actually take it) |
| Question is broad | "That's a big one. Let me start with the part that matters most, which is..." |
| Question is unclear | "Do you mean X or Y? I'd answer them differently." |
| You don't know | "I haven't done that directly. The closest I've done is X. Here's how I'd reason about it." |
| You lost your thread | "Let me step back. The core point is..." |
| You realise you said something wrong | "Actually, let me correct that." (interviewers respect this a lot) |
| Long design question | "Before I draw anything, can I check a few requirements?" |

Asking a clarifying question is never weak. In customer delivery it is the job.

## Thinking out loud on a whiteboard

Whiteboard rounds test how you reason, not whether you produce the perfect diagram. Silence while drawing is the most common way to lose them. Use this sequence and narrate every step.

1. **Restate the problem** in your words. "So we have a utility with 250,000 meters, data must stay in Germany, and they want production in Azure with DR on-prem. Is that right?"
2. **Ask about requirements before drawing.** Scale, availability target, RTO and RPO, compliance, who operates it after handover, budget. Write them in a corner of the board. You will point back to them later.
3. **Draw the simplest thing that works**, and say so: "Let me start simple and then harden it." Boxes and arrows for the data path first.
4. **Walk the data path out loud:** "A reading leaves the meter, goes through the APN into the customer's network, over the VPN, into the head-end."
5. **Harden it against the requirements**, one at a time, pointing at the list: HA, DR, security, isolation, cost.
6. **Name the trade-offs and failure modes** as you go: "If the VPN drops, readings buffer at the concentrators. How long can they buffer? That sets our tolerance."
7. **Close with value and a question:** "This meets their RPO with one region and keeps data in Germany. Where would you like me to go deeper?"

If you freeze during step 3 or 4, go back to the requirements list and pick the next one. The list is your map.

## Requirements checklist for any design question

Write the letters in the corner of the board: **S A D S I C O**.

- **S**cale: how many devices, users, requests, GB per day?
- **A**vailability: what uptime, what RTO and RPO?
- **D**ata: residency, retention, personal data?
- **S**ecurity: public endpoints allowed? customer CA? key ownership?
- **I**solation: one customer or many? shared or dedicated?
- **C**ost: budget, or a target per environment?
- **O**perations: who runs it after handover, and with which skills?

Missing **I** cost a previous final round. Ask about it every time, even if the answer is "just one customer".

## After the interview

Write down, within an hour, any question where you froze and what the good answer would have been. Add it to [question-bank.md](question-bank.md). Rehearsing the exact question that tripped you is the fastest way to stop it happening again.
