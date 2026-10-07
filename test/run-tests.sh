#!/usr/bin/env bash
# Feeds sample hook payloads to the hook script(s) and checks the log file.
# Usage: bash test/run-tests.sh   (needs python3/python for the assertions)
here="$(cd "$(dirname "$0")" && pwd)"; root="$(dirname "$here")"
py="$(command -v python3 || command -v python)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PLUGIN_ROOT="$root"
runners=("$BASH $root/scripts/log-skill.sh")
if command -v powershell >/dev/null 2>&1; then
  w() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
  runners+=("powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $(w "$root/scripts/log-skill.ps1")")
fi
fail=0; i=0
for r in "${runners[@]}"; do
  i=$((i+1)); export SKILL_TELEMETRY_FILE="$tmp/run$i/skill-usage.jsonl"
  for f in sample-agent-skill sample-user-slash sample-non-skill; do $r <"$here/$f.json" || { echo "FAIL: non-zero exit"; fail=1; }; done
  echo 'not json' | $r || { echo "FAIL: non-zero exit on garbage"; fail=1; }
  "$py" - "$SKILL_TELEMETRY_FILE" "$r" <<'PY' || fail=1
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
ok = [(r["skill"], r["trigger"]) for r in rows] == [("rbc-plugin:deploy", "agent"), ("code-review", "user")]
ok = ok and rows[0]["plugin"] == "rbc-plugin" and all(r["user"] and r["timestamp"].endswith("Z") for r in rows)
print(("PASS" if ok else "FAIL"), sys.argv[2].split()[0].rsplit("/", 1)[-1])
for r in rows: print("   ", json.dumps(r))
sys.exit(0 if ok else 1)
PY
done
exit $fail
