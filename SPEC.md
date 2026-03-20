# commit-helper (`ch`) — Specification
```
   ____                          _ _     _   _      _
  / ___|___  _ __ ___  _ __ ___ (_) |_  | | | | ___| |_ __   ___ _ __
 | |   / _ \| '_ ` _ \| '_ ` _ \| | __| | |_| |/ _ \ | '_ \ / _ \ '__|
 | |__| (_) | | | | | | | | | | | | |_  |  _  |  __/ | |_) |  __/ |
  \____\___/|_| |_| |_|_| |_| |_|_|\__| |_| |_|\___|_| .__/ \___|_|
                                                     |_|
```

## Overview

`ch` is a CLI shell tool that uses AI (OpenAI or Anthropic) to analyze git diffs and generate meaningful commit messages, then commits automatically.

---

## Commands

| Command | Description |
|---------|-------------|
| `ch -s` | **Staged changes** — analyze already-staged files and commit |
| `ch -c` | **Current changes** — stage all modified/untracked files, then commit |
| `ch show -s` | **Preview staged** — generate and display the commit message only, no commit |
| `ch show -c` | **Preview current** — generate and display the commit message only, no commit |
| `ch` | **Default** — display the Commit Helper banner and all commands |
| `ch help` | **Help** — alias for `ch` with no arguments |

---

## Behavior

### `ch -s` (staged)

1. Run `git diff --cached` to get the staged diff
2. If nothing is staged, exit with an error: `No staged changes found.`
3. Send the diff to the AI model
4. Display the generated commit message to the user
5. Prompt for confirmation: `Commit with this message? [Y/n]`
6. On confirm: run `git commit -m "<generated message>"`

### `ch -c` (current)

1. Run `git status` to detect modified, untracked, or deleted files
2. If no changes exist, exit with an error: `No changes found.`
3. Run `git add .` to stage all current changes
4. Run `git diff --cached` to get the staged diff
5. Send the diff to the AI model
6. Display the generated commit message to the user
7. Prompt for confirmation: `Commit with this message? [Y/n]`
8. On confirm: run `git commit -m "<generated message>"`

### `ch` / `ch help` (banner + usage)

Running `ch` with no arguments (or `ch help`) prints the banner and usage, then exits. No git or AI calls are made.

**Example output:**
```
   ____                          _ _     _   _      _
  / ___|___  _ __ ___  _ __ ___ (_) |_  | | | | ___| |_ __   ___ _ __
 | |   / _ \| '_ ` _ \| '_ ` _ \| | __| | |_| |/ _ \ | '_ \ / _ \ '__|
 | |__| (_) | | | | | | | | | | | | |_  |  _  |  __/ | |_) |  __/ |
  \____\___/|_| |_| |_|_| |_| |_|_|\__| |_| |_|\___|_| .__/ \___|_|
                                                     |_|
  AI-powered git commit message generator              v1.0.0

Usage:
  ch -s              Commit staged changes
  ch -c              Stage all changes and commit
  ch show -s         Preview commit message for staged changes (no commit)
  ch show -c         Preview commit message for current changes (no commit)
  ch help            Show this help

Note:
  Reads config from ~/.config/ch/config
  Supports AI_PROVIDER=anthropic|openai
```

---

### `ch show -s` / `ch show -c` (preview only)

Same diff collection logic as `ch -s` / `ch -c` respectively, but instead of prompting to commit:

1. Generate the commit message via AI
2. Print it to the terminal in a styled box
3. Offer a **copy to clipboard** action:
   - If running in a terminal: show `Press C to copy` inline prompt, copy via `pbcopy` (macOS), `xclip`/`xsel` (Linux), or `clip` (Windows)
   - If output is piped (non-TTY): write the raw message to stdout only, no copy prompt
4. Exit without touching the git index or making any commit

No `git add` is run for `ch show -c` — it reads the unstaged diff (`git diff`) to preview what the message would look like without staging.

**Example terminal output:**
```
┌─ Generated commit message ──────────────────────────────┐
│ feat(auth): add JWT refresh token support               │
│                                                         │
│ - Add refresh endpoint                                  │
│ - Store refresh token in httpOnly cookie                │
│ - Rotate token on each use                              │
└─────────────────────────────────────────────────────────┘
  Press C to copy  |  Any other key to exit
```

---

## AI Prompt

The diff is sent to the AI with a system prompt instructing it to:

- Write a concise, imperative commit message (≤72 characters for the subject)
- Follow the Conventional Commits format: `<type>(<scope>): <subject>`
  - Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`, `perf`
- Optionally include a short body (bullet points) if the change is complex
- Return **only** the commit message — no explanation, no markdown fencing

**Example output:**
```
feat(auth): add JWT refresh token support

- Add refresh endpoint
- Store refresh token in httpOnly cookie
- Rotate token on each use
```

---

## Configuration

Configuration is read from `~/.config/ch/config` (or `~/.chrc`):

```ini
AI_PROVIDER=claude-cli       # default — uses installed `claude` CLI (no API key needed)
                             # or: anthropic | openai
AI_MODEL=claude-sonnet-4-6   # only used when provider is anthropic or openai
ANTHROPIC_API_KEY=sk-ant-... # only needed when AI_PROVIDER=anthropic
OPENAI_API_KEY=sk-...        # only needed when AI_PROVIDER=openai
```

Environment variables override config file values.

---

## AI Provider Support

### `claude-cli` (default — recommended)

Uses the `claude` CLI that ships with Claude Code, which is already authenticated.
No API key or account setup required.

```bash
claude -p "<system prompt>\n\n<diff>"
```

- Requires `claude` to be installed and logged in (`claude auth login`)
- Uses whatever model Claude Code is currently configured with
- Zero configuration for existing Claude Code users

### Anthropic API (direct)
- API: Messages API (`/v1/messages`)
- Requires `ANTHROPIC_API_KEY` with active credits
- Default model: `claude-sonnet-4-6`

### OpenAI
- API: Chat Completions (`/v1/chat/completions`)
- Requires `OPENAI_API_KEY`
- Default model: `gpt-4o`

---

## Provider Resolution Order

1. `AI_PROVIDER` env var or config file value
2. If `claude` binary is found in PATH → default to `claude-cli`
3. If `ANTHROPIC_API_KEY` is set → fall back to `anthropic`
4. If `OPENAI_API_KEY` is set → fall back to `openai`
5. Exit with: `No AI provider configured. Install Claude Code or set an API key.`

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Not inside a git repo | Exit with: `Not a git repository.` |
| No changes / nothing staged | Exit with appropriate message |
| `claude` CLI not found (claude-cli provider) | Exit with: `` `claude` CLI not found. Install Claude Code or set AI_PROVIDER=anthropic. `` |
| API key missing (anthropic/openai provider) | Exit with: `API key not configured. Set ANTHROPIC_API_KEY or OPENAI_API_KEY.` |
| API call fails | Exit with: `AI request failed: <error>` |
| User declines confirmation | Exit without committing: `Aborted.` |

---

## Implementation Options

The tool can be implemented as:

1. **Shell script** (`bash`/`zsh`) — zero dependencies, easiest to install via PATH, works well with `claude -p`
2. **Python script** — cleaner API handling, easier to test
3. **Node.js script** — good if Anthropic/OpenAI JS SDKs are preferred

Recommended: **Shell script** — since the default provider (`claude-cli`) is just a subprocess call, a shell script has zero dependencies and is trivially installable.

---

## Installation

```bash
# Install to user-local bin (no sudo required)
mkdir -p ~/.local/bin
cp ch ~/.local/bin/ch
chmod +x ~/.local/bin/ch

# Add to PATH if not already (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"

# Configure
mkdir -p ~/.config/ch
echo "AI_PROVIDER=anthropic" >> ~/.config/ch/config
echo "ANTHROPIC_API_KEY=your-key-here" >> ~/.config/ch/config
```

---

## Example Usage

```bash
# Stage specific files manually, then let AI commit
git add src/auth.py
ch -s

# Stage everything and commit in one step
ch -c

# Preview what the commit message would be for staged changes (no commit)
ch show -s

# Preview what the commit message would be for all current changes (no commit, no staging)
ch show -c
```

---

## Out of Scope (v1)

- Branch awareness or PR description generation
- Multi-repo support
- Interactive diff selection (like `git add -p`)
- Commit signing
- GUI or TUI interface
