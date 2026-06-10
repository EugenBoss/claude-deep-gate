#!/usr/bin/env bash
# claude-deep-gate — TIERED adversarial refuter gate (Stop hook) for Claude Code.
#
# Philosophy: do NOT reduce WHEN Claude verifies a substantive completion — reduce
# HOW MUCH the verification costs. A missed prod/money/data bug dwarfs the cost of
# one agent, so anything substantive gets AT LEAST a cheap, scoped refuter. Depth
# escalates with stakes:
#
#   trivial pure (doc/style edit only, no data claim, no Bash/Agent)  -> SKIP
#   normal substantive (any real code/logic change)                  -> CHEAP refuter (small model, scoped, 1 pass)
#   high-stakes (money/prod/DB/migration/auth/irreversible/cost-number) -> FULL refuter (deep, independent)
#
# Mode override (runtime toggle) via ~/.claude/.deep-mode  (or $DEEP_GATE_MODE_FILE):
#   auto  (default) = tiered, as above
#   off             = never fire (max token save; you lose the auto net)
#   force           = FULL refuter on EVERY substantive completion (legacy max-safety)
#
# Optional config ~/.claude/deep-gate.config.json (or $DEEP_GATE_CONFIG):
#   { "cheap_model": "haiku",
#     "extra_stakes_keywords": ["usage_ledger","my_prod_table"],
#     "extra_claim_keywords":  ["gata","rezolvat"],
#     "safe_extensions":       ["md","mdx","txt","rst","css","scss","less"] }
#
# Fires (when allowed) ONLY when: the turn was substantive (Edit/Write/Bash/Agent/
# Task since the last genuine user message), the last assistant message claims
# completion, and NO refuter agent was already spawned this turn.
# stop_hook_active guards against loops (one nag max per stop-cycle).
#
# Requires: bash, python3. No network, no writes. Exit 0 always (never blocks hard).

input=$(cat)

active=$(printf '%s' "$input" | python3 -c "import sys,json
try: print(str(json.load(sys.stdin).get('stop_hook_active',False)).lower())
except Exception: print('false')" 2>/dev/null)
[ "$active" = "true" ] && exit 0

# --- mode --------------------------------------------------------------------
MODE=""
mf="${DEEP_GATE_MODE_FILE:-$HOME/.claude/.deep-mode}"
[ -f "$mf" ] && MODE=$(tr -d ' \t\n\r' < "$mf" 2>/dev/null | tr 'A-Z' 'a-z')
[ -z "$MODE" ] && MODE=auto
case "$MODE" in auto|off|force) ;; *) MODE=auto ;; esac
[ "$MODE" = "off" ] && exit 0

tpath=$(printf '%s' "$input" | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('transcript_path',''))
except Exception: print('')" 2>/dev/null)
[ -z "$tpath" ] && exit 0
[ ! -f "$tpath" ] && exit 0

read -r CLAIM SUBSTANTIVE REFUTED STAKES TRIVIAL CHEAPMODEL <<<"$(DEEP_GATE_CONFIG="${DEEP_GATE_CONFIG:-$HOME/.claude/deep-gate.config.json}" python3 - "$tpath" <<'PY'
import sys,json,re,os
path=sys.argv[1]

# ---- optional user config (extra keywords / cheap model) --------------------
cfg={}
cpath=os.environ.get('DEEP_GATE_CONFIG','')
if cpath and os.path.isfile(cpath):
    try: cfg=json.load(open(cpath))
    except Exception: cfg={}
extra_stakes=[str(x).lower() for x in cfg.get('extra_stakes_keywords',[]) if str(x).strip()]
extra_claims=[str(x).lower() for x in cfg.get('extra_claim_keywords',[]) if str(x).strip()]
safe_ext=[str(x).lower().lstrip('.') for x in cfg.get('safe_extensions',
          ['md','mdx','markdown','txt','rst','css','scss','less']) if str(x).strip()]
cheap_model=str(cfg.get('cheap_model','haiku')).lower()
if cheap_model not in ('haiku','sonnet','opus','fable'): cheap_model='haiku'

rows=[]
try:
    for line in open(path):
        line=line.strip()
        if not line: continue
        try: rows.append(json.loads(line))
        except Exception: pass
except Exception:
    print(f"0 0 0 0 0 {cheap_model}"); sys.exit(0)

def blocks(o):
    m=o.get('message',{}) if isinstance(o,dict) else {}
    c=m.get('content')
    if isinstance(c,str): return [{'type':'text','text':c}]
    return c if isinstance(c,list) else []

# Index of the LAST genuine user prompt (not a tool_result echo).
last_user=-1
for i,o in enumerate(rows):
    if o.get('type')!='user': continue
    bs=blocks(o)
    if any(isinstance(b,dict) and b.get('type')=='tool_result' for b in bs): continue
    if any(isinstance(b,dict) and b.get('type')=='text' and b.get('text','').strip() for b in bs):
        last_user=i
seg=rows[last_user+1:] if last_user>=0 else rows

user_text=''
if last_user>=0:
    for b in blocks(rows[last_user]):
        if isinstance(b,dict) and b.get('type')=='text':
            user_text+=' '+b.get('text','')

substantive=False; refuted=False; last_text=''; tool_blob=''
edit_paths=[]; used_bash_or_agent=False
SUB_TOOLS={'Edit','Write','NotebookEdit','Bash','Agent','Task'}
EDIT_TOOLS={'Edit','Write','NotebookEdit'}
for o in seg:
    if o.get('type')!='assistant': continue
    for b in blocks(o):
        if not isinstance(b,dict): continue
        if b.get('type')=='tool_use':
            name=b.get('name','')
            if name in SUB_TOOLS: substantive=True
            inp_obj=b.get('input',{}) if isinstance(b.get('input'),dict) else {}
            inp=json.dumps(inp_obj).lower()
            tool_blob+=' '+inp
            if name in EDIT_TOOLS:
                fp=str(inp_obj.get('file_path',''))
                if fp: edit_paths.append(fp)
            if name in ('Bash','Agent','Task'): used_bash_or_agent=True
            if name in ('Agent','Task') and re.search(r'refut|adversar',inp): refuted=True
        elif b.get('type')=='text' and b.get('text','').strip():
            last_text=b['text']

# completion-claim words (English defaults + user extras)
claim_words=['done','shipped','merged','deployed','fixed','resolved','complete','completed',
             'finished','it works','all set','good to go']+extra_claims
cw='|'.join(re.escape(w) for w in claim_words)
claim=bool(re.search(r'(^|[^a-z])(' + cw + r')([^a-z]|$)', last_text.lower()))

# high-stakes signals (money / prod / data / irreversible / explicit deep trigger)
hay=(user_text+' '+last_text+' '+tool_blob).lower()
HS=(r'(\bmoney\b|\bcost\b|\$[0-9]|\beuro|\busd\b|\bbilling\b|\bcharge\b|\binvoice\b|\brefund\b'
    r'|\bpayment\b|\bstripe\b|\bprod\b|\bproduction\b|\bdeploy|\bmigrat|\bschema\b|drop\s+table'
    r'|\bdelete\b|\btruncate\b|\bdatabase\b|\bdb\b|\bledger\b|\bwebhook\b|\birrevers|irreversib'
    r'|force[- ]?push|reset\s+--hard|\brevoke\b|\bsecret\b|api[_ ]?key|\bpassword\b|\btoken\b|\bauth\b)')
TRIG=r'(deep mode|red ?team|/redteam|/deep|dig deeper|to the bottom)'
stakes=bool(re.search(HS,hay) or re.search(TRIG,hay))
if not stakes and extra_stakes:
    stakes=any(k in hay for k in extra_stakes)

# trivial: edits ONLY, every path a safe doc/style ext, no Bash/Agent, no numeric/data claim
ext_re=re.compile(r'\.(' + '|'.join(re.escape(e) for e in safe_ext) + r')$', re.I) if safe_ext else None
has_number=bool(re.search(r'(\$\s*\d|\d+\s*%|\b\d{3,}\b)', last_text))
edits_only_safe=(len(edit_paths)>0 and not used_bash_or_agent and ext_re is not None
                 and all(ext_re.search(p) for p in edit_paths))
trivial=bool(edits_only_safe and not has_number)

print(f"{int(claim)} {int(substantive)} {int(refuted)} {int(stakes)} {int(trivial)} {cheap_model}")
PY
)"

[ -z "$CHEAPMODEL" ] && CHEAPMODEL=haiku

# --- decide tier -------------------------------------------------------------
TIER=none
if [ "$CLAIM" = "1" ] && [ "$SUBSTANTIVE" = "1" ] && [ "$REFUTED" = "0" ]; then
  if [ "$MODE" = "force" ]; then TIER=full
  elif [ "$STAKES" = "1" ]; then TIER=full
  elif [ "$TRIVIAL" = "1" ]; then TIER=none
  else TIER=cheap
  fi
fi

if [ "$TIER" = "full" ]; then
  printf '%s\n' '{"decision":"block","reason":"DEEP-REFUTE-GATE [FULL / high-stakes]: you signalled completion on a substantive AND high-stakes turn (money/prod/data/migration/auth/irreversible or an explicit deep trigger) WITHOUT running an adversarial critic. Before ending: spawn a SEPARATE agent (Agent tool, subagent_type general-purpose) instructed EXPLICITLY to REFUTE your main conclusions — independent access to the same code/data, each claim with its exact figure, how to verify it independently, and a per-claim verdict CONFIRMED / REFUTED / UNCERTAIN. Integrate what it finds (correct your numbers if it caught you). If the turn genuinely has no conclusion to refute, say so explicitly in one line and you may end."}'
elif [ "$TIER" = "cheap" ]; then
  printf '{"decision":"block","reason":"DEEP-REFUTE-GATE [CHEAP / scoped]: you signalled completion on a substantive turn with no critic. Run a CHEAP, SCOPED refuter: spawn an agent (Agent tool, subagent_type general-purpose, model: %s) with a tight prompt — refute ONLY the main claim plus THIS turn diff, a single pass, do NOT re-investigate the whole codebase. List each claim with: how to check it in one step + verdict CONFIRMED / REFUTED / UNCERTAIN. Integrate what it catches. If nothing real to refute (pure cosmetic/doc), say so in one line and end. (High stakes? escalate to a stronger model.)"}\n' "$CHEAPMODEL"
fi
exit 0
