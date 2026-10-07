#!/usr/bin/env bash
# Feeds sample hook payloads to the hook script(s) and checks the log file.
# Usage: bash test/run-tests.sh   (needs python3/python for the assertions)
here="$(cd "$(dirname "$0")" && pwd)"; root="$(dirname "$here")"
py="$(command -v python3 || command -v python)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PLUGIN_ROOT="$root"
runners=("$BASH $root/scripts/log-skill.sh")
if command -v pwsh >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1; then
  ps="$(command -v pwsh || command -v powershell)"
  w() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
  runners+=("$ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $(w "$root/scripts/log-skill.ps1")")
fi
fail=0; i=0
for r in "${runners[@]}"; do
  i=$((i+1)); export SKILL_TELEMETRY_FILE="$tmp/run$i/skill-usage.jsonl"
  for f in sample-agent-skill sample-agent-skill-failed sample-agent-skill-pre sample-user-slash sample-non-skill; do $r <"$here/$f.json" || { echo "FAIL: non-zero exit"; fail=1; }; done
  echo 'not json' | $r || { echo "FAIL: non-zero exit on garbage"; fail=1; }
  "$py" - "$SKILL_TELEMETRY_FILE" "$r" "$here" <<'PY' || fail=1
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
fixtures = [json.load(open(f"{sys.argv[3]}/{name}.json", encoding="utf-8")) for name in ("sample-agent-skill", "sample-user-slash")]
ok = [(r["skill"], r["event_kind"]) for r in rows] == [("rbc-plugin:deploy", "activated"), ("code-review", "user_invoked")]
ok = ok and rows[0]["plugin"] == "rbc-plugin" and rows[0]["skill_path"] == "/x/rbc-plugin/skills/deploy/SKILL.md"
ok = ok and all(r["prompt_id"] == fixture["prompt_id"] for r, fixture in zip(rows, fixtures))
ok = ok and all(r["user"] and r["timestamp"].endswith("Z") for r in rows)
print(("PASS" if ok else "FAIL"), sys.argv[2].split()[0].rsplit("/", 1)[-1])
for r in rows: print("   ", json.dumps(r))
sys.exit(0 if ok else 1)
PY
done

"$py" - "$root" "$here" "$tmp" <<'PY' || fail=1
import json, os, subprocess, sys, tempfile
root, fixtures, tmp = sys.argv[1:]
with open(os.path.join(root, "hooks.json"), encoding="utf-8") as stream:
    hooks = json.load(stream)

def run_hook(hook_name, fixture_name, plugin_env, expected_skill, expected_kind):
    command = hooks[hook_name][0]["hooks"][0]["command"]
    payload = open(os.path.join(fixtures, fixture_name), encoding="utf-8").read()
    with tempfile.TemporaryDirectory(dir=tmp) as cwd:
        log_file = os.path.join(cwd, "skill-usage.jsonl")
        env = os.environ.copy()
        env.pop("DEVIN_PLUGIN_ROOT", None)
        env.pop("CLAUDE_PLUGIN_ROOT", None)
        env.pop("PLUGIN_ROOT", None)
        env[plugin_env] = root
        env["SKILL_TELEMETRY_FILE"] = log_file
        result = subprocess.run(["bash", "-c", command], input=payload, text=True, cwd=cwd, env=env, capture_output=True)
        if result.returncode or result.stdout or result.stderr:
            raise AssertionError(f"{hook_name} command failed: {result.returncode} {result.stdout!r} {result.stderr!r}")
        rows = [json.loads(line) for line in open(log_file, encoding="utf-8")]
        assert len(rows) == 1 and rows[0]["skill"] == expected_skill and rows[0]["event_kind"] == expected_kind, rows

run_hook("PostToolUse", "sample-agent-skill.json", "DEVIN_PLUGIN_ROOT", "rbc-plugin:deploy", "activated")
print("PASS hooks.json PostToolUse command with DEVIN_PLUGIN_ROOT from external cwd")
run_hook("UserPromptSubmit", "sample-user-slash.json", "DEVIN_PLUGIN_ROOT", "code-review", "user_invoked")
print("PASS hooks.json UserPromptSubmit command with DEVIN_PLUGIN_ROOT from external cwd")
run_hook("PostToolUse", "sample-agent-skill.json", "CLAUDE_PLUGIN_ROOT", "rbc-plugin:deploy", "activated")
print("PASS hooks.json PostToolUse command with CLAUDE_PLUGIN_ROOT fallback")
PY
exit $fail
