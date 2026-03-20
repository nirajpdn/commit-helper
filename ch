#!/usr/bin/env python3
"""ch — AI-powered git commit message generator"""

import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

# ── ANSI colors ───────────────────────────────────────────────────────────────
CYAN  = "\033[1;36m"
GREEN = "\033[1;32m"
DIM   = "\033[2;37m"
BOLD  = "\033[1m"
RED   = "\033[0;31m"
RESET = "\033[0m"

VERSION = "1.0.0"

BANNER = (
    r"   ____                          _ _     _   _      _"           + "\n"
    r"  / ___|___  _ __ ___  _ __ ___ (_) |_  | | | | ___| |_ __   ___ _ __" + "\n"
    r" | |   / _ \| '_ ` _ \| '_ ` _ \| | __| | |_| |/ _ \ | '_ \ / _ \ '__|" + "\n"
    r" | |__| (_) | | | | | | | | | | | | |_  |  _  |  __/ | |_) |  __/ |"  + "\n"
    r"  \____\___/|_| |_| |_|_| |_| |_|_|\__| |_| |_|\___|_| .__/ \___|_|"  + "\n"
    r"                                                     |_|"
)

SYSTEM_PROMPT = """\
You are a git commit message generator. Analyze the provided git diff and write \
a concise, meaningful commit message.

Rules:
- Use Conventional Commits format: <type>(<scope>): <subject>
- Types: feat, fix, chore, refactor, docs, test, style, perf
- Subject must be ≤72 characters, imperative mood
- Optionally include a short bullet-point body if the change is complex
- Return ONLY the commit message — no explanation, no markdown fencing\
"""


# ── Config ────────────────────────────────────────────────────────────────────

def load_config():
    config = {}
    for path in [
        os.path.expanduser("~/.config/ch/config"),
        os.path.expanduser("~/.chrc"),
    ]:
        if os.path.exists(path):
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, _, v = line.partition("=")
                        config[k.strip()] = v.strip()
            break
    for key in ("AI_PROVIDER", "AI_MODEL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"):
        if key in os.environ:
            config[key] = os.environ[key]
    return config


def resolve_provider(config):
    """Return the provider to use, auto-detecting claude-cli if available."""
    provider = config.get("AI_PROVIDER", "").lower()
    if provider:
        return provider
    if shutil.which("claude"):
        return "claude-cli"
    if config.get("ANTHROPIC_API_KEY"):
        return "anthropic"
    if config.get("OPENAI_API_KEY"):
        return "openai"
    die("No AI provider configured. Install Claude Code or set an API key.")


def get_api_credentials(config):
    provider = resolve_provider(config)
    if provider == "claude-cli":
        return provider, None, None
    if provider == "anthropic":
        key = config.get("ANTHROPIC_API_KEY")
        model = config.get("AI_MODEL", "claude-sonnet-4-6")
    elif provider == "openai":
        key = config.get("OPENAI_API_KEY")
        model = config.get("AI_MODEL", "gpt-4o")
    else:
        die(f"Unknown AI_PROVIDER: {provider}")
    if not key:
        die("API key not configured. Set ANTHROPIC_API_KEY or OPENAI_API_KEY.")
    return provider, key, model


# ── Helpers ───────────────────────────────────────────────────────────────────

def die(msg, code=1):
    print(f"{RED}{msg}{RESET}", file=sys.stderr)
    sys.exit(code)


def run_git(*args, check=False):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        die(result.stderr.strip() or f"git {args[0]} failed.")
    return result


def is_git_repo():
    r = run_git("rev-parse", "--is-inside-work-tree")
    return r.returncode == 0


# ── AI calls ──────────────────────────────────────────────────────────────────

def generate_commit_message(diff, config):
    print(f"{DIM}Generating commit message…{RESET}", file=sys.stderr)
    provider, key, model = get_api_credentials(config)
    prompt = f"Generate a commit message for this diff:\n\n{diff}"
    try:
        if provider == "claude-cli":
            return _call_claude_cli(prompt)
        elif provider == "anthropic":
            return _call_anthropic(prompt, key, model)
        else:
            return _call_openai(prompt, key, model)
    except urllib.error.HTTPError as e:
        die(f"AI request failed: {e.read().decode()}")


def _call_claude_cli(prompt):
    full_prompt = f"{SYSTEM_PROMPT}\n\n{prompt}"
    result = subprocess.run(
        ["claude", "-p", full_prompt],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        die(f"AI request failed: {result.stderr.strip()}")
    return result.stdout.strip()


def _http_post(url, headers, payload):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def _call_anthropic(prompt, key, model):
    data = _http_post(
        "https://api.anthropic.com/v1/messages",
        {
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        {
            "model": model,
            "max_tokens": 1024,
            "system": SYSTEM_PROMPT,
            "messages": [{"role": "user", "content": prompt}],
        },
    )
    return data["content"][0]["text"].strip()


def _call_openai(prompt, key, model):
    data = _http_post(
        "https://api.openai.com/v1/chat/completions",
        {
            "Authorization": f"Bearer {key}",
            "content-type": "application/json",
        },
        {
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        },
    )
    return data["choices"][0]["message"]["content"].strip()


# ── UI ────────────────────────────────────────────────────────────────────────

def confirm(message):
    print(f"\n{BOLD}Generated commit message:{RESET}")
    print(f"  {message}\n")
    try:
        answer = input("Commit with this message? [Y/n] ").strip().lower()
        return answer in ("", "y", "yes")
    except (EOFError, KeyboardInterrupt):
        print()
        return False


def print_box(message):
    lines = message.split("\n")
    inner_width = max(max(len(l) for l in lines), 50)
    title = "Generated commit message"
    top    = f"┌─ {title} " + "─" * (inner_width - len(title) - 1) + "┐"
    bottom = "└" + "─" * (inner_width + 3) + "┘"
    print(f"\n{CYAN}{top}{RESET}")
    for line in lines:
        print(f"{CYAN}│{RESET} {line:<{inner_width + 1}} {CYAN}│{RESET}")
    print(f"{CYAN}{bottom}{RESET}")


def copy_to_clipboard(text):
    for cmd in (["pbcopy"], ["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"], ["clip"]):
        if shutil.which(cmd[0]):
            subprocess.run(cmd, input=text, text=True)
            return True
    return False


def read_single_key():
    import termios, tty
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def show_preview(message):
    if not sys.stdout.isatty():
        print(message)
        return
    print_box(message)
    print(f"  {DIM}Press C to copy  |  Any other key to exit{RESET}", end="", flush=True)
    try:
        key = read_single_key()
        print()
        if key.lower() == "c":
            if copy_to_clipboard(message):
                print(f"  {GREEN}Copied to clipboard.{RESET}")
            else:
                print(f"  {RED}No clipboard tool found.{RESET}")
    except Exception:
        print()


def show_banner_and_usage():
    print(f"{CYAN}{BANNER}{RESET}")
    print(f"  {DIM}AI-powered git commit message generator{RESET}              v{VERSION}\n")
    print(f"{BOLD}Usage:{RESET}")
    print("  ch -s              Commit staged changes")
    print("  ch -c              Stage all changes and commit")
    print("  ch show -s         Preview commit message for staged changes (no commit)")
    print("  ch show -c         Preview commit message for current changes (no commit)")
    print("  ch help            Show this help\n")
    print(f"{DIM}Note:{RESET}")
    print("  Reads config from ~/.config/ch/config")
    print("  Supports AI_PROVIDER=claude-cli (default)|anthropic|openai")


# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_staged():
    if not is_git_repo():
        die("Not a git repository.")
    diff = run_git("diff", "--cached").stdout
    if not diff.strip():
        die("No staged changes found.")
    config = load_config()
    message = generate_commit_message(diff, config)
    if confirm(message):
        subprocess.run(["git", "commit", "-m", message], check=True)
    else:
        print("Aborted.")


def cmd_current():
    if not is_git_repo():
        die("Not a git repository.")
    status = run_git("status", "--porcelain").stdout
    if not status.strip():
        die("No changes found.")
    subprocess.run(["git", "add", "."], check=True)
    diff = run_git("diff", "--cached").stdout
    config = load_config()
    message = generate_commit_message(diff, config)
    if confirm(message):
        subprocess.run(["git", "commit", "-m", message], check=True)
    else:
        print("Aborted.")


def cmd_show_staged():
    if not is_git_repo():
        die("Not a git repository.")
    diff = run_git("diff", "--cached").stdout
    if not diff.strip():
        die("No staged changes found.")
    config = load_config()
    show_preview(generate_commit_message(diff, config))


def cmd_show_current():
    if not is_git_repo():
        die("Not a git repository.")
    diff = run_git("diff").stdout
    if not diff.strip():
        die("No unstaged changes found.")
    config = load_config()
    show_preview(generate_commit_message(diff, config))


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    if not args or args == ["help"]:
        show_banner_and_usage()
    elif args == ["-s"]:
        cmd_staged()
    elif args == ["-c"]:
        cmd_current()
    elif args == ["show", "-s"]:
        cmd_show_staged()
    elif args == ["show", "-c"]:
        cmd_show_current()
    else:
        print(f"{RED}Unknown command: {' '.join(args)}{RESET}", file=sys.stderr)
        print("Run 'ch help' for usage.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
