# devin-skill-telemetry

Devin plugin that logs every **skill use** (**which skill, which user, when**) to a local file,
one JSON object per line. It also records the session, trigger, plugin and host for
correlation. Works in Devin CLI, Devin Local in Desktop, and Devin Cloud. Fails open: the hook
always exits 0 and prints nothing, so it never blocks or changes the agent.

## What fires

| Hook | Catches | `trigger` |
|---|---|---|
| `PreToolUse` matcher `^(skill_invoke\|skill)$` | the agent invoking a skill (`skill_invoke` tool) | `agent` |
| `UserPromptSubmit` (prompt starts with `/name`) | a user typing `/skill-name ...` | `user` |

Windows runs `scripts/log-skill.ps1` (Windows PowerShell 5.1+ or pwsh, no extra installs).
macOS/Linux/Cloud runs `scripts/log-skill.sh` (bash + sed only).

## Output

The default file is `~/.devin/skill-telemetry/skill-usage.jsonl`
(`%USERPROFILE%\.devin\skill-telemetry\skill-usage.jsonl` on Windows).
Override it with the `SKILL_TELEMETRY_FILE` env var.

```json
{"timestamp":"2026-10-07T20:22:19.265Z","event":"skill_used","skill":"rbc-tools:code-review","trigger":"agent","plugin":"rbc-tools","user":"jane.doe@rbc.com","user_source":"git_config","os_user":"RBC\jdoe","host":"RBC-LAPTOP-123","session_id":"...","hook_event":"PreToolUse","tool_use_id":"...","skill_path":"...SKILL.md","cwd":"..."}
```

`timestamp` is UTC. `user` uses the first of these that is set:
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
   `pre_tool (tool_name ~ ^(skill_invoke|skill)$)`.
2. Start `devin` and use a skill both ways: type `/<skill-name>`, then ask "use the <skill-name> skill to ...".
3. Look at the file:
   - macOS/Linux: `tail -f ~/.devin/skill-telemetry/skill-usage.jsonl`
   - Windows: `Get-Content -Wait $HOME\.devin\skill-telemetry\skill-usage.jsonl`

   You should see one line with `"trigger":"user"` and one with `"trigger":"agent"`.

Offline script test: `bash test/run-tests.sh` feeds sample hook payloads (agent skill, user
`/skill`, non-skill tool, garbage input) through the script(s) and checks the file. On Windows it
tests both the bash and PowerShell versions.

## Rolling it out as an enterprise-managed plugin

1. Push this folder to an internal git repo and tag it.
2. Enterprise/Org settings → Plugins → add it under **required plugins**, pinned to the tag or sha.

## Known limitations
- `UserPromptSubmit` logs any prompt that starts with `/<name>`. The REPL handles built-in commands
  (`/model`, `/help`, ...) and unknown commands client-side, so in practice these should be skills.
  This is not yet verified against a live session.
- The user is self-reported by the endpoint (git email or OS user), not the Devin account ID.
  Set `SKILL_TELEMETRY_USER` if you need a corporate ID.
- Sending to Datadog (or any central sink) was removed for now. To add it back, ship this file
  with the Datadog Agent's file tailing, or restore the HTTP intake post.
