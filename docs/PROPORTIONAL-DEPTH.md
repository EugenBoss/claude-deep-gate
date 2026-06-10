# Optional: "Proportional depth" guidance for your CLAUDE.md

The Stop hook is the **hard** layer — the harness enforces it after the turn, with
full evidence of what actually happened. This snippet is the **soft** layer: it
shapes how deeply Claude works *during* the turn. Paste it into your
`~/.claude/CLAUDE.md` (or a project `CLAUDE.md`) if you also want effort to scale
with stakes, not just verification.

You don't need it for the hook to work. It's a complement. `install.sh --claude-md`
will append it for you.

```markdown
## Proportional depth (escalate on signal, don't guess up front)

Go deep ON SIGNAL, not max-depth on everything. Don't decide depth from the prompt
(at the start you can't know yet) — start at NORMAL and ESCALATE to full (measure the
whole population, multi-angle check, adversarial refuter) the moment a signal appears:
- you touch money / billing / prod / DB / migration / auth / secrets / anything irreversible
- a number derived from data becomes a reported conclusion
- the user contradicts a result ("but I spent more than that")
- a symptom that "has persisted for days" / keeps coming back
- a fix on a path with no tests / no reproduction
Carve down to LITE (proportional verification, skip the full multi-angle pass) ONLY when
the task is closed-form trivial: cosmetic, docs, mechanical rename/format, a single line,
or a read-only answer — AND none of the signals above are in sight.

Safety net: if you misjudged at the start, the deep-gate Stop hook catches you at the
end with real evidence and forces the refuter. Lite up front is safe because it's
backstopped — no conclusion ships un-refuted.
```
