# claude-deep-gate

**Verify smarter, not more expensively.**

A Claude Code [Stop hook](https://docs.claude.com/en/docs/claude-code/hooks) that forces an
adversarial **refuter agent** before Claude declares a substantive task "done" — but
**tiers the depth by stakes** instead of running a heavyweight check on everything.

If you've added a "double-check your work / spawn a refuter / dig to the bottom" rule to
your `CLAUDE.md`, you've probably noticed it fires on *everything* — including one-line
typo fixes — and burns tokens for no reason. The fix isn't to verify less. It's to make
the common case cheap and reserve the expensive pass for when it matters.

## The tiers

| Turn | What it gets | Cost |
|------|--------------|------|
| **Trivial** — doc/style edit only, no data claim, no shell/agent | **skip** | 0 |
| **Normal** — any real code/logic change | **cheap** scoped refuter (small model, 1 pass on the claim+diff) | ~1/10 |
| **High-stakes** — money / prod / DB / migration / auth / irreversible / a cost-number | **full** deep refuter (independent, per-claim verdicts) | full |

Nothing substantive ships with **zero** scrutiny — it just drops from a heavyweight model
to a cheap, scoped one on the everyday case. High-stakes still gets the full treatment.

## Why this design

Two layers, and they are **not** symmetric:

- **The hook decides at the END of a turn**, with full evidence: which tools ran, what was
  claimed, which files were touched. So it classifies *accurately* — the turn already happened.
- A `CLAUDE.md` rule decides at the **START**, from the prompt alone. That's blind: "fix the
  color" can hide a real trap; "quick question" can uncover a prod bug.

So the gate keys off **what actually happened**, not a guess. A keyword match only sets the
*cost ceiling* (skip / cheap / full); the **verdict** (CONFIRMED / REFUTED / UNCERTAIN) is
produced by an agent that looks at the real diff and data.

## Install (plugin — recommended)

```text
/plugin marketplace add EugenBoss/claude-deep-gate
/plugin install deep-gate@claude-deep-gate
```

The plugin auto-wires the Stop hook — no `settings.json` editing. Requires `python3`.

### Manual install (no marketplace)

```bash
git clone https://github.com/EugenBoss/claude-deep-gate
cd claude-deep-gate
./install.sh                 # wire the hook into ~/.claude/settings.json
./install.sh --claude-md     # also append the optional "proportional depth" guidance
./install.sh --config        # also drop a starter config you can edit
```

## Control the mode

Runtime toggle lives in `~/.claude/.deep-mode`. Use the slash command or just write the file:

```text
/deepmode auto      # default — tiered (recommended)
/deepmode off       # never fire a refuter (max token save; you lose the net)
/deepmode force     # full deep refuter on every substantive completion
```

```bash
echo auto > ~/.claude/.deep-mode
```

## Configure (optional)

Drop `~/.claude/deep-gate.config.json` (or point `$DEEP_GATE_CONFIG` at one). All fields
optional; zero-config defaults work out of the box.

```json
{
  "cheap_model": "haiku",
  "extra_stakes_keywords": ["usage_ledger", "checkout"],
  "extra_claim_keywords": ["gata", "fertig", "listo"],
  "safe_extensions": ["md", "txt", "css"]
}
```

- `cheap_model` — model for the cheap tier (`haiku` | `sonnet` | `opus` | `fable`).
- `extra_stakes_keywords` — your own high-stakes terms (table names, service names…).
- `extra_claim_keywords` — completion words in your language (English is built in).
- `safe_extensions` — file types that count as "trivial" when edited alone.

## How a turn is classified

The hook fires only when **all** hold, evaluated since the last genuine user message:

1. the turn was **substantive** (used `Edit` / `Write` / `NotebookEdit` / `Bash` / `Agent` / `Task`);
2. the last assistant message **claims completion** (done/shipped/fixed/merged/… + your extras);
3. **no refuter** agent was already spawned this turn (it detects `refut`/`adversar` in agent prompts).

Then the tier is chosen: `force` mode or a high-stakes signal → **full**; clearly-trivial → **skip**;
everything else → **cheap**. `off` mode and `stop_hook_active` short-circuit immediately.

> Note: a cost **number** in a "done" message (e.g. "total is $1,240") escalates a
> doc-only edit to **full** — a measured figure is exactly the kind of claim worth refuting.

## What it does NOT do

- No network. No file writes. Reads the transcript, prints a decision, exits 0.
- It never *hard*-blocks: worst case it asks Claude to run one verification, then the turn ends.
- It is **not** a response-style compressor (use [caveman](https://github.com/JuliusBrussee) for that)
  and **not** extended-thinking control — those are separate levers.

## Requirements

`bash` + `python3`. macOS / Linux. (Windows: run under Git Bash / WSL.)

## License

MIT © Eugen Popa
