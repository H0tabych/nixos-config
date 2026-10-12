---
name: run-nixos-config
description: Validate, build, boot, and interrogate this NixOS flake config — run "just check", build the ci-vm NixOS VM, launch it headless under tmux, and run smoke commands on its serial console. Use when asked to run, check, build, test, boot, or screenshot this repo, or to verify a module change actually boots.
---

This repo is a NixOS flake configuration (infra-as-code), not an
application — there is no GUI/CLI/server to launch. "Running" it means
one of two things, in order of how often each is actually used:

1. **Validate** (fast, ~seconds): `nix fmt` + `nix flake check` +
   structural checks + secret scan. This is what every ROADMAP step and
   CI (`check.yml`) actually run. Start here for any module change.
2. **Boot and interrogate** (slow, ~1 minute): build the `ci-vm` NixOS
   host (`modules/hosts/ci-vm.nix`, class `vm` — exists specifically to
   prove the shared modules are portable, HOST-4) as a QEMU VM, launch it
   headless, and run commands on its serial console. This is the closest
   thing this repo has to "launch the app and click around."

Paths below are relative to the repo root (`<unit>` = repo root), not to
this skill directory.

## Hard rule this skill respects

Per `CLAUDE.md`, never run `sudo`, `nixos-rebuild`, `nixos-install`,
`disko`, or other destructive/host-mutating commands. Both paths below
use only `nix fmt`, `nix flake check`, and `nix build` — never
`nixos-rebuild` (not even `build-vm`), never `sudo`. `ci-vm` is a
synthetic VM-only host (`vm-layout.nix`); nothing here touches the real
machine.

## 1. Validate (primary path for almost all changes)

```
nix develop --command just check
```

Runs `nix fmt` then `nix flake check` (structure checks C1–C11, metadata
checks, treefmt, and eval of both `nixosConfigurations` — `ci-vm` fully
builds there per CI, `sgms-laptop` is eval-only). Also available split
up:

```
bash scripts/check-structure.sh   # C1–C11 structural rules
nix develop --command bash scripts/check-secrets.sh  # gitleaks scan
```

## 2. Boot and interrogate `ci-vm` (agent path)

```
./.claude/skills/run-nixos-config/driver.sh
```

What it does (verified working in this sandbox, ~55s end to end):

1. Builds `.claude/skills/run-nixos-config/debug-vm.nix` with
   `nix build --impure -f ... -o <workdir>/vm-result`. This is the exact
   same attribute CI builds (`nix build
   .#nixosConfigurations.ci-vm.config.system.build.vm`), just layered
   with one extra module via `.extendModules` (see Gotchas) — `ci-vm`
   itself is never edited.
2. Launches `<workdir>/vm-result/bin/run-nixos-vm` headless inside a
   detached tmux session (`QEMU_OPTS=-nographic`, `NIX_DISK_IMAGE` pinned
   into the workdir so no stray `nixos.qcow2` lands in the repo).
3. Polls the console (`tmux capture-pane`) until the autologin prompt
   appears (timeout 180s).
4. Runs `uname -a`, `systemctl is-system-running`, `hostnamectl` and
   saves the full console transcript to `<workdir>/transcript-*.log` —
   this is the "screenshot" for a text console; always look at it, don't
   just trust the exit code.
5. Sends `poweroff`, waits for the tmux session to end, kills it if it
   doesn't.

It prints the transcript path at the end. A real captured transcript
from this sandbox:

```
<<< Welcome to NixOS 26.05.20261008.7c8764b (x86_64) - ttyS0 >>>
nixos login: root (automatic login)
[root@nixos:~]# uname -a; echo ---; systemctl is-system-running; echo ---; hostnamectl; echo ---DRIVER_DONE---
Linux nixos 6.18.55 #1-NixOS SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux
---
running
---
     Static hostname: nixos
      Virtualization: kvm
    Operating System: NixOS 26.05 (Yarara)
---DRIVER_DONE---
```

Needs `tmux`; the driver fetches it ad hoc via
`nix shell nixpkgs#tmux` if it's not already on `PATH`, so no system
install is required.

To add more checks (e.g. after changing a specific module), edit the
`send-keys` line in `driver.sh` or run it manually against
`<workdir>/vm-result/bin/run-nixos-vm` under your own tmux session.

## Human path

`just vm <host>` / `just build|test|boot <host>` exist in the `justfile`
for a person to run on real or VM hosts — they wrap `nixos-rebuild`,
which this skill (and the assistant generally) never invokes. If you're
a human and want the VM with a window instead of headless: `just vm
ci-vm` then run the resulting `./result/bin/run-nixos-vm` directly (no
`QEMU_OPTS` needed — a window opens).

## Gotchas

- **`ci-vm` boots under hostname `nixos`, not `ci-vm`.** `my.host.name =
  "ci-vm"` (`modules/hosts/ci-vm.nix`) is this repo's own fact option
  (`host-facts`), not `networking.hostName` — nothing in the module
  graph sets the latter. The generated script is `run-nixos-vm`, and the
  console banner says `nixos login:`, not `ci-vm login:`.
- **No SSH, no network reachability into the VM.** `ci-vm` imports
  `base` (which enables `sshd`) but `modules/security/ssh.nix` sets
  `openFirewall = false`, `PermitRootLogin = "no"`,
  `PasswordAuthentication = false`, and `my.host.users = []` — there are
  no accounts and no keys. The firewall is default-deny. The **only**
  interaction channel is the QEMU serial console (`console=ttyS0` is
  already in the kernel params the generated script uses).
- **No password means no normal console login either.** With zero users
  and no root password set, a stock `ci-vm` VM boots to a login prompt
  you cannot pass. `debug-vm.nix` adds `services.getty.autologinUser =
  "root"` via `.extendModules` specifically to get a shell — this is a
  throwaway VM never deployed anywhere, not a credential or a change to
  the real host config.
- **`virtualisation.graphics` is not reachable through
  `.extendModules`.** It looks like a normal top-level option, but on
  this nixpkgs (26.05) `config.system.build.vm` is actually built from
  a separately-evaluated `virtualisation.vmVariant` submodule, and a
  plain `.extendModules { modules = [ { virtualisation.graphics =
  false; } ]; }` on the outer `nixosSystem` result fails with "The
  option `virtualisation.graphics' does not exist" (verified — same
  failure for *any* option under that submodule, even on an otherwise
  empty `extendModules { modules = []; }`). Workaround used here:
  disable graphics at the QEMU invocation instead
  (`QEMU_OPTS=-nographic`), since the generated `run-nixos-vm` script
  appends `"$QEMU_OPTS" "$@"` to the end of its `qemu-system-x86_64`
  command line.
- **`NIX_DISK_IMAGE` must be set explicitly.** The generated run script
  defaults to `./nixos.qcow2` *relative to the caller's cwd* — if you
  launch it from the repo root without overriding this, a disk image
  lands in the working tree. `driver.sh` always pins it into the
  workdir.
- **`--impure` is required** for the `nix build -f debug-vm.nix` step:
  `debug-vm.nix` uses `builtins.getFlake (toString flakeDir)` to pull in
  the flake's own `nixosConfigurations.ci-vm`, and this repo's working
  tree is essentially always "dirty" relative to the last commit during
  normal iteration. Fine for local/agent tooling; not used by CI.
- **tmux output capture via `nix shell ... --command tmux <args>`
  directly was unreliable** (silently empty output in this sandbox);
  wrapping in `bash -lc 'tmux ...'` was reliable every time. `driver.sh`
  does the latter.

## Troubleshooting

- `error: The option 'virtualisation.graphics' does not exist` — you
  added an override under `virtualisation.*` in `debug-vm.nix`'s
  `extendModules` list. See Gotchas above; use a QEMU runtime flag
  instead (`QEMU_OPTS`), not a Nix option, for anything under
  `virtualisation.vmVariant`'s territory.
- Driver prints `VM did not reach a console login within timeout` — read
  the partial transcript it still writes to `<workdir>/transcript-*.log`.
  In this sandbox the boot took ~10–15s after KVM acceleration kicked in
  (`Virtualization: kvm` in `hostnamectl` output confirms `/dev/kvm` was
  used); a container without `/dev/kvm` falls back to TCG software
  emulation and will be much slower — raise the timeout loop count in
  `driver.sh` rather than assuming something is broken.
- A `nixos.qcow2` file appears in the repo root after a manual run —
  you launched `run-nixos-vm` directly without `NIX_DISK_IMAGE` set; see
  Gotchas. Delete it (`rm nixos.qcow2`), it's disposable VM disk state,
  never tracked.
