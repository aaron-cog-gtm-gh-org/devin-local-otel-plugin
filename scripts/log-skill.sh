#!/usr/bin/env bash
# Devin skill-usage telemetry hook (macOS / Linux / Devin Cloud).
# Reads the hook event JSON on stdin and, when it is a skill use, appends one
# JSON line (skill, user, time, ...) to a local file. Needs only bash + sed.
# Fails open: always exits 0 and prints nothing.
log_file="${SKILL_TELEMETRY_FILE:-$HOME/.devin/skill-telemetry/skill-usage.jsonl}"
log_dir="$(dirname "$log_file")"
BS="$(printf '\134')"

input="$(cat)"
# Value of the first "key":"value" pair in the hook JSON (kept JSON-escaped).
jstr() { printf '%s' "$input" | sed -nE "s/.*[^\\\\]\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -n1; }
# JSON-escape a raw string.
esc() { local v="$1"; v="${v//"$BS"/"$BS$BS"}"; v="${v//\"/"$BS"\"}"; printf '%s' "$v"; }

event="$(jstr hook_event_name)"
skill="" event_kind="" plugin="" skill_path=""
if [ "$event" = "PostToolUse" ]; then
  case "$(jstr tool_name)" in skill_invoke|skill) ;; *) exit 0 ;; esac
  success="$(printf '%s' "$input" | sed -nE 's/.*[^\\]"success"[[:space:]]*:[[:space:]]*true.*/success/p' | sed -n '1p')"
  [ "$success" = "success" ] || exit 0
  skill="$(jstr skill)"; event_kind="activated"
  skill_path="$(printf '%s' "$input" | grep -oE 'Source:[[:space:]]*[^\\]*\\n' | head -n1 | sed -E 's/^Source:[[:space:]]*//; s/\\n$//')"
  [ -n "$skill_path" ] || skill_path="$(jstr path)"
  if [ "${skill#*:}" != "$skill" ]; then
    plugin="${skill%%:*}"
  else
    plugin="$(jstr plugin)"
  fi
elif [ "$event" = "UserPromptSubmit" ]; then
  skill="$(printf '%s' "$input" | sed -nE 's/.*"prompt"[[:space:]]*:[[:space:]]*"[[:space:]]*\/([A-Za-z0-9][A-Za-z0-9_:.-]*).*/\1/p' | head -n1)"
  event_kind="user_invoked"
fi
[ -n "$skill" ] || exit 0
if [ -z "$plugin" ] && [ "${skill#*:}" != "$skill" ]; then plugin="${skill%%:*}"; fi

# Identity: explicit override > git author env > Devin git author file (cloud) > git config > OS user.
os_user="${USER:-$(id -un 2>/dev/null)}"
user="${SKILL_TELEMETRY_USER:-}"; source="override"
if [ -z "$user" ] && [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then user="$GIT_AUTHOR_EMAIL"; source="git_author_env"; fi
if [ -z "$user" ]; then
  for f in "${DEVIN_DIR:-/nonexistent}/git_author" /opt/.devin/git_author; do
    if [ -f "$f" ]; then
      user="$(sed -nE 's/.*GIT_AUTHOR_EMAIL="?([^"]+)"?.*/\1/p' "$f" | head -n1)"
      if [ -n "$user" ]; then source="devin_git_author"; break; fi
    fi
  done
fi
if [ -z "$user" ] && command -v git >/dev/null 2>&1; then
  user="$(git config --global user.email 2>/dev/null)"
  if [ -n "$user" ]; then source="git_config"; fi
fi
if [ -z "$user" ]; then user="$os_user"; source="os_user"; fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
host="$(hostname 2>/dev/null)"
line="{\"timestamp\":\"$ts\",\"event\":\"skill_used\",\"skill\":\"$skill\",\"event_kind\":\"$event_kind\",\"plugin\":\"$plugin\",\"user\":\"$(esc "$user")\",\"user_source\":\"$source\",\"os_user\":\"$(esc "$os_user")\",\"host\":\"$(esc "$host")\",\"session_id\":\"$(jstr session_id)\",\"prompt_id\":\"$(jstr prompt_id)\",\"hook_event\":\"$event\",\"tool_use_id\":\"$(jstr tool_use_id)\",\"skill_path\":\"$skill_path\",\"cwd\":\"$(esc "${DEVIN_PROJECT_DIR:-}")\"}"

if mkdir -p "$log_dir" 2>/dev/null && printf '%s\n' "$line" >>"$log_file" 2>/dev/null; then :; else
  printf '%s could not write %s\n' "$ts" "$log_file" >>"${TMPDIR:-/tmp}/devin-skill-telemetry-errors.log" 2>/dev/null
fi
exit 0
