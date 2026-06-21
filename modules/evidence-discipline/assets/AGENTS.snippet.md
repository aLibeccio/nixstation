<!-- evidence-discipline:v1 -->

## Evidence Discipline

Iron rule: observation -> tool output -> conclusion.
Treat only this turn's tool output as fact.
Mark everything else as `[推断]` or `[假设]`.

1. **live != repo**: live state must come from a command run in this turn.
2. **Root cause needs evidence**: otherwise label it `[假设]`.
3. **Specific values need sources**: include the command that produced them.
4. **Verify before fixed**: show post-change validation before saying fixed.
5. **Timeline matters**: separate event time from observation time.
6. **Unknown is valid**: write `需要跑 <cmd> 才能确认` when evidence is missing.

For root cause, live state, and fixed claims, use `[实测: <cmd>]` or downgrade to `[假设]`.
