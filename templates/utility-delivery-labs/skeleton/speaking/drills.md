# Drills: four weeks, 15 minutes a day

Confidence in speaking comes from repetition with feedback, the same way it does in operations. These drills are short on purpose: fifteen minutes every day beats two hours once a week.

## Setup

- Your phone's voice recorder, or QuickTime on the Mac for video.
- A timer.
- A file `speaking/log.md` (keep it private or gitignored) for the scorecard below.

Record every drill. Listening back is uncomfortable for the first few days and then becomes the most useful part.

## Scorecard

After each recording, score yourself 1 to 3 on each line and note the total.

| Item | 1 | 2 | 3 |
| --- | --- | --- | --- |
| Headline in first sentence | No | Second or third sentence | First sentence |
| One concrete detail | None | Vague | Specific number, command or design detail |
| Trade-off named | No | Implied | Explicit, with the alternative |
| Failure mode named | No | Mentioned | Symptom and signal |
| Value close | No | Generic | Specific to the customer |
| Fillers ("um", "basically", "like") | 6+ per minute | 3–5 | 0–2 |
| Length | Over 2 min or under 30 s | 1.5–2 min | 60–90 s |

Target: 18 of 21 by the end of week 3.

## Week 1: structure

Goal: make H-C-T-F-V automatic.

| Day | Drill (15 min) |
| --- | --- |
| 1 | Read [answer-framework.md](answer-framework.md). Record yourself answering "Tell me about yourself" in 60 seconds. Don't judge it yet; this is your baseline. |
| 2 | Write the five beats for "How do you structure Terraform for many customers?" as bullet points only, no sentences. Record from the bullets. |
| 3 | Same question, no bullets. Record twice. Score both. |
| 4 | Pick two questions from the question bank, section A. Bullets, then record. |
| 5 | Re-record day 1's introduction. Compare with the baseline. |
| 6 | Filler hunt: answer one question while consciously replacing every "um" with a silent pause. Record and count. |
| 7 | Rest, or listen back to the week's best recording once. |

## Week 2: depth and pressure

Goal: handle follow-ups without losing structure.

| Day | Drill (15 min) |
| --- | --- |
| 8 | Answer a question, then ask yourself "Why?" three times, answering each aloud. This simulates a probing interviewer. |
| 9 | "I don't know" practice: pick a topic you have not done in production (OpenShift disconnected install, for example). Answer using the bridge sentence from [freeze-recovery.md](freeze-recovery.md). |
| 10 | Present lab 00's architecture aloud in 3 minutes with the timer visible. |
| 11 | Same, but stop at a random point, wait 5 seconds, and restart with "Let me step back, the core point is...". |
| 12 | Two STAR stories (Velero restore gap, 2,000-server migration) in 90 seconds each. |
| 13 | Ask someone, a friend or your partner, to interrupt you with "why?" during one answer. |
| 14 | Rest. |

## Week 3: whiteboard and customer voice

Goal: think out loud while drawing; speak like a delivery engineer.

| Day | Drill (15 min) |
| --- | --- |
| 15 | Whiteboard (paper or Excalidraw): design lab 00's architecture from a blank page while narrating. Record audio. Use the S-A-D-S-I-C-O list. |
| 16 | Same, but start with the isolation question: "One utility or several?" |
| 17 | Customer role-play: explain to a non-technical project manager why go-live slips by one week. 60 seconds, no jargon. |
| 18 | Customer pushback: "Our security team won't allow your egress list." Respond calmly, find their real constraint, offer two options. |
| 19 | Escalation narration: pick a lab 09 drill and narrate the diagnosis as if on a call with the customer's engineer. |
| 20 | Full mock: introduction, one technical question, one story, one design question. 15 minutes. Score it. |
| 21 | Rest. |

## Week 4: the real interview

Goal: rehearse the actual interview conditions.

| Day | Drill (15 min) |
| --- | --- |
| 22 | Video-record (camera on) your introduction and "Why this company?" Check posture, eye contact with the lens, and pace. |
| 23 | Screen-share lab 01 or 02 and walk through it in 3 minutes as if demoing to the interviewer. |
| 24 | Five random questions from the bank, 90 seconds each, no preparation. |
| 25 | Re-answer the three lowest-scoring questions from your log. |
| 26 | Full mock with a friend, 30 minutes. |
| 27 | Light review only. Listen to your best recordings. |
| 28 | Interview day: see the checklist below. |

## Day-of checklist

- Ten minutes before: say your introduction out loud once, standing up.
- Water within reach. Sipping is a natural pause.
- Have the requirement letters S-A-D-S-I-C-O on a sticky note.
- First answer: speak slightly slower than feels natural. Nerves speed you up.
- If you stumble, correct and continue. Nobody remembers a stumble; they remember the recovery.
