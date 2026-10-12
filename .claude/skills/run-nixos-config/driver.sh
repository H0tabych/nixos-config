#!/usr/bin/env bash
# Driver for the run-nixos-config skill: builds the ci-vm NixOS VM (debug
# variant, see debug-vm.nix), boots it headless under tmux, runs a few
# smoke commands on the serial console, saves a transcript, shuts down.
#
# Usage: ./driver.sh [workdir]
#   workdir defaults to a fresh mktemp -d. The build result (vm-result/)
#   and the transcript log live there — nothing is written into the repo.
#
# Requires: nix (with flakes), and tmux — fetched ad hoc via
# `nix shell nixpkgs#tmux` if not already on PATH, so no system install
# is needed.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${1:-$(mktemp -d /tmp/run-nixos-config.XXXXXX)}"
SESSION="ci-vm-debug-$$"
VM_RESULT="$WORKDIR/vm-result"
TRANSCRIPT="$WORKDIR/transcript-$(date +%s).log"

mkdir -p "$WORKDIR"
echo "workdir: $WORKDIR"

tmux_bin() {
  if command -v tmux >/dev/null 2>&1; then
    tmux "$@"
  else
    nix shell nixpkgs#tmux --command bash -lc "tmux $(printf '%q ' "$@")"
  fi
}

echo "== building debug VM (nix build --impure) =="
nix build --impure -f "$SKILL_DIR/debug-vm.nix" -o "$VM_RESULT" --print-build-logs

echo "== booting under tmux (session: $SESSION) =="
tmux_bin kill-session -t "$SESSION" 2>/dev/null || true
tmux_bin new-session -d -s "$SESSION" -x 200 -y 50 \
  "env QEMU_OPTS=-nographic NIX_DISK_IMAGE=$WORKDIR/nixos.qcow2 $VM_RESULT/bin/run-nixos-vm"

echo "== waiting for console login (timeout 180s) =="
booted=0
for _ in $(seq 1 60); do
  sleep 3
  pane="$(tmux_bin capture-pane -t "$SESSION" -p || true)"
  if grep -q "automatic login" <<<"$pane"; then
    booted=1
    sleep 2 # let the shell prompt settle
    break
  fi
done
if [ "$booted" -ne 1 ]; then
  echo "ERROR: VM did not reach a console login within timeout" >&2
  tmux_bin capture-pane -t "$SESSION" -p >"$TRANSCRIPT" || true
  echo "partial transcript: $TRANSCRIPT" >&2
  tmux_bin kill-session -t "$SESSION" 2>/dev/null || true
  exit 1
fi

echo "== running smoke commands =="
tmux_bin send-keys -t "$SESSION" \
  "uname -a; echo ---; systemctl is-system-running; echo ---; hostnamectl; echo ---DRIVER_DONE---" \
  Enter
for _ in $(seq 1 20); do
  sleep 2
  pane="$(tmux_bin capture-pane -t "$SESSION" -p || true)"
  if grep -q "DRIVER_DONE" <<<"$pane"; then
    break
  fi
done
tmux_bin capture-pane -t "$SESSION" -p -S -200 >"$TRANSCRIPT"
echo "transcript: $TRANSCRIPT"

echo "== shutting down =="
tmux_bin send-keys -t "$SESSION" "poweroff" Enter
for _ in $(seq 1 20); do
  sleep 2
  if ! tmux_bin has-session -t "$SESSION" 2>/dev/null; then
    break
  fi
done
tmux_bin kill-session -t "$SESSION" 2>/dev/null || true

echo "== done =="
echo "vm-result: $VM_RESULT"
echo "transcript: $TRANSCRIPT"
