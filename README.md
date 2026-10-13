# devin-skill-telemetry

This plugin uses two hooks, `PostToolUse` and `UserPromptSubmit`, to append raw event JSON to
`~/devin-hooks.jsonl`, one line per event. On Windows, the file is
`%USERPROFILE%\devin-hooks.jsonl`.

## How it runs

On macOS and Linux, the `command` field runs through bash. On Windows, the `powershell` field
runs in PowerShell; Git Bash is not needed. The plugin has no scripts.

The hooks log every tool call and user prompt; events are not filtered to skill use. This plugin
is for local surfaces only (`platforms: ["local"]`).

## Test it

1. Install the plugin.
2. Start a new Devin Local session and send a prompt that makes Devin run a command.
3. Watch the log:
   - macOS/Linux: `tail -f ~/devin-hooks.jsonl`
   - Windows: `Get-Content -Wait $HOME\devin-hooks.jsonl`

## Rolling it out as an enterprise-managed plugin

1. Push this folder to an internal git repo and tag it.
2. Enterprise/Org settings → Plugins → add it under **required plugins**, pinned to the tag.
