---
name: evidence-discipline
description: Evidence rules for debugging, fact-checking, live-state claims, and fix verification.
---

# Evidence Discipline

Use this with `systematic-debugging`, `diagnose`, or `diagnose-eks-pod`.
It controls what you may claim, not how to investigate.

Iron rule: observation -> tool output -> conclusion.
Treat only this turn's tool output as fact.
Mark everything else as `[推断]`, `[假设]`, or `[未知→查: <cmd>]`.

## Rules

1. **live != repo.**
   Live state must come from a command run in this turn.
   Repo files only prove configured intent.

2. **Root cause needs evidence.**
   Cite the log, query, metric, or command output before naming root cause.
   Without evidence, label it `[假设]` and show how to confirm it.

3. **Specific values need sources.**
   Any number, ID, timestamp, column, timeout, or byte count needs the command that produced it.

4. **Verify before fixed.**
   Before saying fixed, deployed, restarted, or rolled back, show post-change validation output.

5. **Keep the timeline clear.**
   Separate event time from observation time.

6. **Unknown is valid.**
   When evidence is missing, say `需要跑 <cmd> 才能确认`.

## Required Labels

- `[实测: <cmd>]`: proven by a command in this turn.
- `[推断]`: reasoned from evidence but not directly measured.
- `[假设]`: plausible, unproven, and needs confirmation.
- `[未知→查: <cmd>]`: unknown until a command is run.

Root cause, live state, and fixed claims require `[实测: <cmd>]`.
Without it, downgrade the claim to `[假设]`.

## When Challenged

Do not restate the claim.
Run the confirming command or mark the statement as unproven.
