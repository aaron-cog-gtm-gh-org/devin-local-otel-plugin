# devin-skill-telemetry

Devin plugin that logs every **skill use** (**which skill, which user, when**) to a local file (can be swapped for logging to a service),
one JSON object per line. It also records the session_id, event kind, plugin and host for
correlation. 

This works on Devin Local surfaces (Devin Desktop and CLI) and is disabled for Devin Cloud.

It fails open: the hook always exits 0 and prints nothing, so it never blocks or changes the agent.

## What fires

| Hook | Catches | `event_kind` |
|---|---|---|
| `PostToolUse` matcher `^(skill_invoke\|skill)$` | a successfully activated skill (`skill` tool; `skill_invoke` in Cloud) | `activated` |
| `UserPromptSubmit` (prompt starts with `/name`) | a user typing `/skill-name ...` | `user_invoked` |

Windows runs `scripts/log-skill.ps1` (Windows PowerShell 5.1+ or pwsh, no extra installs).
macOS/Linux runs `scripts/log-skill.sh` (bash + sed only).
Hooks resolve the script path from `DEVIN_PLUGIN_ROOT` (falling back to `CLAUDE_PLUGIN_ROOT`
and then `PLUGIN_ROOT`).

## Output

For testing, this writes logs to a default file `~/.devin/skill-telemetry/skill-usage.jsonl`
(`%USERPROFILE%\.devin\skill-telemetry\skill-usage.jsonl` on Windows).
Override it with the `SKILL_TELEMETRY_FILE` env var.

```json
{"timestamp":"2026-10-07T20:22:19.265Z","event":"skill_used","skill":"rbc-tools:code-review","event_kind":"activated","plugin":"rbc-tools","user":"jane.doe@rbc.com","user_source":"git_config","os_user":"RBC\jdoe","host":"RBC-LAPTOP-123","session_id":"...","prompt_id":"...","hook_event":"PostToolUse","tool_use_id":"...","skill_path":"...SKILL.md","cwd":"..."}
```

`event_kind` is `activated` for successful skill calls and `user_invoked` for slash commands.
`prompt_id` correlates records from the same prompt. `timestamp` is UTC. `user` uses the first of these that is set:
1. `SKILL_TELEMETRY_USER` env var
2. `GIT_AUTHOR_EMAIL` env var
3. the Devin git author file (Devin Cloud VMs)
4. `git config --global user.email`
5. the OS user

`user_source` says which one was used, and `os_user` is always included. If the hook can't write
the file, it records why in `errors.log` next to the file (on Windows) or in
`$TMPDIR/devin-skill-telemetry-errors.log` (on macOS/Linux).

## Test it

1. Install: `devin plugins install <path-to-this-folder>`. Then run
   `devin plugins info devin-skill-telemetry`: it should list the hooks `user_prompt` and
   `post_tool (tool_name ~ ^(skill_invoke|skill)$)`.
2. Start `devin` and use a skill both ways: type `/<skill-name>`, then ask "use the <skill-name> skill to ...".
3. Look at the file:
   - macOS/Linux: `tail -f ~/.devin/skill-telemetry/skill-usage.jsonl`
   - Windows: `Get-Content -Wait $HOME\.devin\skill-telemetry\skill-usage.jsonl`

   You should see one line with `"event_kind":"user_invoked"` and one with `"event_kind":"activated"`.

Offline script test: `bash test/run-tests.sh` feeds sample hook payloads (successful/failed skill,
pre-tool skill, user `/skill`, non-skill tool, and garbage input) through the script(s) and checks
the file. It also verifies hook root resolution from outside the repo. On Windows it tests both the
bash and PowerShell versions.

## Rolling it out as an enterprise-managed plugin

1. Push this folder to an internal git repo and tag it.
2. Enterprise/Org settings → Plugins → add it under **required plugins**, pinned to the tag or sha.
