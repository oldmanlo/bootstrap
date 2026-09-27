#!/usr/bin/env bash
# The front door. Typed from memory on a bare Mac:
#
#   curl -fsSL https://raw.githubusercontent.com/oldmanlo/bootstrap/main/mac.sh | bash
#
# A fresh Mac has no SSH key and oldmanlo/.claude is private, so nothing in the
# real harness is reachable yet. This script exists only to walk the chain of
# trust far enough to clone it:
#
#   xcode-select --install -> Homebrew -> 1Password + CLI -> (sign in, enable the
#   SSH agent) -> point ssh at that agent -> git clone -> claude-setup init
#
# It holds NO secrets and must stay that way: it lives in a PUBLIC repo. The root
# of trust is 1Password, which holds the age key that decrypts
# dotfiles/.env.secrets.sops. Everything sensitive comes from there, after a human
# signs in.
#
# Idempotent: every step checks before acting, so re-running is safe.
set -euo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:oldmanlo/.claude}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
OP_AGENT_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
die()  { printf '\n\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "this bootstrap is for macOS"

say "1/5  Xcode command line tools"
if xcode-select -p >/dev/null 2>&1; then
  info "already installed"
else
  info "requesting install — accept the GUI prompt, then re-run this script"
  xcode-select --install || true
  die "waiting on the Xcode CLI tools install"
fi

say "2/5  Homebrew"
if command -v brew >/dev/null 2>&1; then
  info "already installed"
else
  # NONINTERACTIVE makes the installer resolve sudo as `sudo -n -l mkdir`
  # (install.sh, have_sudo_access). A fresh administrator account has no cached
  # sudo timestamp, so that returns non-zero and the installer aborts with
  # "Need sudo access on macOS" before it downloads anything. Prime the timestamp
  # here — this is the one password prompt the bootstrap needs.
  info "Homebrew needs administrator rights; macOS will ask for your password"
  sudo -v || die "sudo is required to install Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Apple silicon and Intel put brew in different places, and this shell has not
# sourced any profile yet.
for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$p" ] && eval "$("$p" shellenv)" && break
done
command -v brew >/dev/null 2>&1 || die "brew is still not on PATH"

say "3/5  1Password and its CLI"
for c in 1password 1password-cli; do
  if brew list --cask "$c" >/dev/null 2>&1; then
    info "$c already installed"
  else
    brew install --cask "$c"
  fi
done

say "4/5  1Password SSH agent"
# Two interactive moments are unavoidable by nature; this is the first. The agent
# cannot be enabled non-interactively, and the account cannot be unlocked without
# a human.
if [ -S "$OP_AGENT_SOCK" ]; then
  info "agent socket is live"
else
  cat <<'MANUAL'
   Do this now, then re-run this script:
     1. Open 1Password and sign in.
     2. Settings -> Developer -> "Use the SSH agent".
     3. Make sure the key that can read the private repo is in your vault.
MANUAL
  die "1Password SSH agent is not running yet"
fi

# Enabling the agent creates its socket; it does NOT point ssh at it. On a bare
# Mac there is no ~/.ssh/config yet either — the harness's dotfiles are exactly
# what we have not cloned. Without this, git uses the default (empty) macOS agent
# and the clone dies with "Permission denied (publickey)".
export SSH_AUTH_SOCK="$OP_AGENT_SOCK"
info "SSH_AUTH_SOCK -> 1Password agent"

say "5/5  Clone the harness and hand off"
if [ -d "$CLAUDE_DIR/.git" ]; then
  info "$CLAUDE_DIR already cloned"
else
  git clone "$REPO_SSH" "$CLAUDE_DIR"
fi

info "handing off to claude-setup"
exec "$CLAUDE_DIR/scripts/claude-setup" init --yes
