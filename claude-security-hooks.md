# Claude Code — Security Hooks for Git Commits

Drop `.claude/settings.json` into any project root to get automatic sensitive-data scanning before commits, plus any project-specific reminders you need.

---

## Quick Setup

Create `.claude/settings.json` in your project root:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "cmd=$(jq -r '.tool_input.command // empty'); echo \"$cmd\" | grep -qE 'git (commit|push)' || exit 0; hits=$(git diff --cached -U0 2>/dev/null | grep -E '^\\+[^+]' | grep -iE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}|[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}' | head -3 || true); [ -n \"$hits\" ] && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Sensitive data pattern detected in staged changes (possible email or app-specific password). Review before committing.\"}}' || true"
          }
        ]
      }
    ]
  }
}
```

That's it. Claude Code loads `.claude/settings.json` automatically when you open the project.

---

## What It Catches

| Pattern | Example | Why |
|---------|---------|-----|
| Email addresses | `user@example.com` | API credentials, Apple IDs, account emails |
| App-specific passwords | `xxxx-xxxx-xxxx-xxxx` | Apple notarization, app passwords |

The scan only runs on **staged content** (`git diff --cached`) — lines being added in the current commit, not the entire file history.

---

## Adding Project-Specific Patterns

Extend the `grep -iE` pattern with `|your-pattern`:

```
... | grep -iE '[email pattern]|[app-password pattern]|sk-[a-zA-Z0-9]{32,}|ghp_[a-zA-Z0-9]+'
```

Common additions:

| Secret type | Pattern to add |
|-------------|---------------|
| OpenAI API key | `sk-[a-zA-Z0-9]{32,}` |
| GitHub personal token | `ghp_[a-zA-Z0-9]+` |
| AWS access key | `AKIA[A-Z0-9]{16}` |
| Stripe secret key | `sk_live_[a-zA-Z0-9]+` |
| Slack token | `xox[baprs]-[a-zA-Z0-9-]+` |
| Private key header | `-----BEGIN (RSA\|EC\|OPENSSH) PRIVATE KEY-----` |
| Specific known value | `your-literal-string-here` |

---

## Adding File-Edit Reminders

Add a `PostToolUse` block to remind yourself of anything that needs a follow-up when specific files change:

```json
{
  "hooks": {
    "PreToolUse": [ ...commit scanner above... ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path // empty' | grep -q 'YourFile' && echo '{\"systemMessage\":\"⚠️ YourFile changed — remember to do X.\"}' || true"
          }
        ]
      }
    ]
  }
}
```

Replace `YourFile` with any filename or path fragment, and the message with whatever reminder makes sense.

---

## How It Works

- **PreToolUse on Bash** — fires before Claude Code runs any shell command
- Extracts the command from stdin JSON and checks if it contains `git commit` or `git push`
- If yes: scans staged diff for sensitive patterns
- If a match is found: outputs a `permissionDecision: deny` response, which blocks the commit and shows the reason
- If no match (or not a commit command): exits silently, commit proceeds normally

---

## Notes

- `jq` must be installed (`brew install jq` on macOS)
- The hook only runs when Claude Code is driving the commit — it does not replace a git pre-commit hook for commits made directly in terminal
- For broader coverage (all commits regardless of tool), also add a `.git/hooks/pre-commit` script using the same grep patterns
- Commit `.claude/settings.json` to your repo so the hooks apply to all Claude Code sessions on that project
