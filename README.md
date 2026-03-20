# commit-helper (`ch`)

```
   ____                          _ _     _   _      _
  / ___|___  _ __ ___  _ __ ___ (_) |_  | | | | ___| |_ __   ___ _ __
 | |   / _ \| '_ ` _ \| '_ ` _ \| | __| | |_| |/ _ \ | '_ \ / _ \ '__|
 | |__| (_) | | | | | | | | | | | | |_  |  _  |  __/ | |_) |  __/ |
  \____\___/|_| |_| |_|_| |_| |_|_|\__| |_| |_|\___|_| .__/ \___|_|
                                                     |_|
```

AI-powered git commit message generator — analyzes your diff and writes a [Conventional Commits](https://www.conventionalcommits.org/) message for you.

## Requirements

- Python 3.6+
- One of:
  - [Claude Code](https://claude.ai/code) installed and logged in (zero-config default)
  - An `ANTHROPIC_API_KEY`
  - An `OPENAI_API_KEY`

## Installation

```bash
# Copy to user-local bin (no sudo required)
mkdir -p ~/.local/bin
cp ch ~/.local/bin/ch
chmod +x ~/.local/bin/ch

# Add to PATH if not already (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```
ch -s              Commit staged changes
ch -c              Stage all changes and commit
ch show -s         Preview commit message for staged changes (no commit)
ch show -c         Preview commit message for current changes (no commit)
ch help            Show this help
```

### Examples

```bash
# Stage specific files, then let AI write the commit message
git add src/auth.py
ch -s

# Stage everything and commit in one step
ch -c

# Preview what the commit message would look like (no commit)
ch show -s
ch show -c
```

Preview output:
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

## Configuration

Config is read from `~/.config/ch/config` (or `~/.chrc`). Environment variables override config file values.

```ini
AI_PROVIDER=claude-cli       # default — uses installed `claude` CLI (no API key needed)
                             # or: anthropic | openai
AI_MODEL=claude-sonnet-4-6   # only used when AI_PROVIDER=anthropic or openai
ANTHROPIC_API_KEY=sk-ant-... # only needed when AI_PROVIDER=anthropic
OPENAI_API_KEY=sk-...        # only needed when AI_PROVIDER=openai
```

### Provider auto-detection order

1. `AI_PROVIDER` from env or config file
2. `claude` binary found in PATH → use `claude-cli`
3. `ANTHROPIC_API_KEY` set → use `anthropic`
4. `OPENAI_API_KEY` set → use `openai`
5. Exit with an error

The `claude-cli` provider (default) calls `claude -p` under the hood — no API key or extra setup needed for existing Claude Code users.

## Commit message format

Messages follow Conventional Commits: `<type>(<scope>): <subject>`

| Type | Meaning |
|------|---------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `chore` | Maintenance tasks (deps, build config) with no behavior change |
| `refactor` | Code restructuring with no behavior change and no bug fix |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `style` | Formatting or whitespace — no logic change |
| `perf` | Performance improvement |

Subject is ≤72 characters, imperative mood. A short bullet-point body is included when the change is complex.
