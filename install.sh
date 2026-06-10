#!/usr/bin/env bash
# claude-deep-gate installer.
#
# Preferred install is via the Claude Code plugin marketplace (auto-wires the hook):
#
#   /plugin marketplace add EugenBoss/claude-deep-gate
#   /plugin install deep-gate@claude-deep-gate
#
# This script is for a MANUAL install (no marketplace) and optional extras:
#   ./install.sh                 # wire the Stop hook into ~/.claude/settings.json
#   ./install.sh --claude-md     # also append the proportional-depth snippet to ~/.claude/CLAUDE.md
#   ./install.sh --config        # also drop a starter ~/.claude/deep-gate.config.json
#
# Requires: bash, python3. Re-running is safe (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK="$ROOT/hooks/deep-refute-gate.sh"

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required."; exit 1; }
mkdir -p "$CLAUDE_DIR"
chmod +x "$HOOK" 2>/dev/null || true

# default mode file
[ -f "$CLAUDE_DIR/.deep-mode" ] || printf 'auto\n' > "$CLAUDE_DIR/.deep-mode"

# wire the Stop hook into settings.json (merge, don't clobber)
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
HOOK="$HOOK" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os
settings_path = os.environ["SETTINGS"]
hook_cmd = f'bash "{os.environ["HOOK"]}"'
try:
    with open(settings_path) as f: data = json.load(f)
except Exception:
    data = {}
hooks = data.setdefault("hooks", {})
stop = hooks.setdefault("Stop", [])
exists = any(
    h.get("command","") == hook_cmd
    for group in stop for h in group.get("hooks", [])
)
if not exists:
    stop.append({"hooks": [{"type": "command", "command": hook_cmd, "timeout": 15}]})
    with open(settings_path, "w") as f: json.dump(data, f, indent=2)
    print("  + wired Stop hook into", settings_path)
else:
    print("  = Stop hook already present, skipped")
PY

echo "deep-gate: hook installed. Mode file: $CLAUDE_DIR/.deep-mode (default: auto)"

if [ "${1:-}" = "--claude-md" ] || [ "${2:-}" = "--claude-md" ]; then
  CM="$CLAUDE_DIR/CLAUDE.md"
  if [ -f "$CM" ] && grep -q "Proportional depth (escalate on signal" "$CM" 2>/dev/null; then
    echo "  = proportional-depth snippet already in CLAUDE.md, skipped"
  else
    # extract the fenced markdown block from the doc and append it
    awk 'f&&/^```$/{exit} f{print} /^```markdown$/{f=1}' "$ROOT/docs/PROPORTIONAL-DEPTH.md" >> "$CM"
    echo "  + appended proportional-depth snippet to $CM"
  fi
fi

if [ "${1:-}" = "--config" ] || [ "${2:-}" = "--config" ]; then
  CFG="$CLAUDE_DIR/deep-gate.config.json"
  if [ -f "$CFG" ]; then
    echo "  = $CFG already exists, skipped"
  else
    cp "$ROOT/deep-gate.config.example.json" "$CFG"
    echo "  + wrote starter config $CFG"
  fi
fi

echo "Done. Set mode anytime:  echo auto|off|force > $CLAUDE_DIR/.deep-mode   (or /deepmode)"
