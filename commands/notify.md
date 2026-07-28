---
description: Send a Pushover push notification (phone/desktop) via the machine-level wrapper.
argument-hint: <message text>
allowed-tools: Bash(pwsh:*), Bash(jq:*), Bash(test:*)
---

Send a **Pushover** push notification. This is separate from Claude Code's built-in `PushNotification` tool (which only fires when the terminal is unfocused and needs Remote Control for phone delivery). Pushover delivers to the user's phone/desktop unconditionally, so use it when the user has explicitly asked to be notified or for long-running-task completion while they're away.

The wrapper is machine-level at `~/.claude/tools/notify.ps1` and reads the Pushover credentials from `~/.claude/credentials.json` (entry label `"Pushover"`, fields `token` = application API token, `userKey` = user/group key).

## Arguments

`$ARGUMENTS` = the notification message text. Example: `/notify build finished, 0 errors`

If no arguments were given, ask the user what message to send and stop.

## How to send

Run via the **Bash tool** (the PowerShell tool returns exit 1 with no output in this environment). Do not echo secrets — the script reads them itself:

```
pwsh -NoProfile -File "$HOME/.claude/tools/notify.ps1" -Message "<message text>"
```

Optional flags the script accepts: `-Title "..."`, `-Priority <-2..1>`, `-Sound "<name>"`.

Success prints `SENT status=1 request=<id>`. Report that back.

## If it fails

- **"No 'Pushover' entry in credentials.json"** (or missing `token`/`userKey`): the credentials aren't set up. Tell the user to add them WITHOUT exposing secrets in chat — they run this themselves with the `!` prefix, substituting their values:

  ```
  jq '.credentials += [{"label":"Pushover","token":"YOUR_APP_TOKEN","userKey":"YOUR_USER_KEY"}]' ~/.claude/credentials.json > ~/.claude/credentials.json.tmp && mv ~/.claude/credentials.json.tmp ~/.claude/credentials.json && echo "added Pushover entry"
  ```

  (App token: create an application at pushover.net/apps. User key: on the pushover.net dashboard.)
- **Pushover API error** (e.g. invalid token/user): the script surfaces the message. A 4xx usually means a bad/rotated token or user key — have the user verify the `"Pushover"` entry in `~/.claude/credentials.json`.

## Notes

- The wrapper is cross-session/machine-level — any project session can call it.
- Credentials live only in `~/.claude/credentials.json` (never in any repo).
