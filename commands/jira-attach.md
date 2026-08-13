---
description: Attach one or more local files to a Jira issue via the REST API (the Atlassian MCP has no attachment endpoint).
argument-hint: <ISSUE-KEY> <file-path> [more-file-paths...]
allowed-tools: Bash(curl:*), Bash(jq:*), Bash(test:*), Read
---

Attach local file(s) to a Jira issue. The Atlassian MCP servers expose no file-attachment endpoint, so this uses the Jira Cloud REST API directly with the API token stored in `~/.claude/credentials.json`.

## Arguments

`$ARGUMENTS` = the issue key followed by one or more file paths. Example: `/jira-attach INTG-1191 ./planning/QA-PLAN.md ./planning/response-contract.md`

- First token: the Jira issue key (e.g. `INTG-1191`).
- Remaining tokens: absolute or relative paths to the files to attach.

If no arguments were given, ask the user for the issue key and file path(s) and stop.

## How to perform the attachment

1. Confirm each file path exists (`test -f`). If any is missing, report which and stop before uploading.
2. Run the upload via the **Bash tool** (the PowerShell tool returns exit 1 with no output in this environment). Read the token inside the command — never echo it. Use one `-F "file=@<path>"` per file to attach several at once:

```
jira=$(jq -r '[.credentials[]|select(.label|startswith("Jira API"))][0]' ~/.claude/credentials.json)
site=$(jq -r '.hosts[0]' <<<"$jira")
user=$(jq -r '.username' <<<"$jira")
tok=$(jq -r '.password' <<<"$jira")
curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST \
  -H "X-Atlassian-Token: no-check" \
  -u "$user:$tok" \
  -F "file=@<path-1>" \
  -F "file=@<path-2>" \
  "https://$site/rest/api/3/issue/<ISSUE-KEY>/attachments"
```

3. Success = `HTTP_STATUS:200` and a JSON array of attachment objects. Report the attached filenames + attachment ids.
4. On `HTTP_STATUS:401`: the token is likely rotated — tell the user to regenerate it at id.atlassian.com/manage-profile/security/api-tokens and update the Jira entry's (label prefix `"Jira API"`) `password` in `~/.claude/credentials.json`. Do not retry blindly.
5. On `HTTP_STATUS:404`: the issue key is wrong or not visible to this account — re-check the key.

## Notes

- Auth host is the site URL (the Jira entry's `hosts[0]`), NOT `api.atlassian.com/ex/jira/<cloudId>`. Basic auth = `email:api-token`.
- The `X-Atlassian-Token: no-check` header is REQUIRED (XSRF protection).
- The token in `credentials.json` is Jira-scoped; the separate Bitbucket entry (label prefix `"Bitbucket API"`) in the same file returns 401 against Jira — do not use it here.
