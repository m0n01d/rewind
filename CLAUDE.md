# rewind

An Elm-style time-travel debugger for ReScript React apps.
See DESIGN.md for the design. Run `npm test` to build and test it.

## Shared conventions

Workspace-wide conventions (language choice, ReScript rules, `resq`, sub-agent orchestration, PR rules) live in the private repo [`m0n01d/claude-conventions`](https://github.com/m0n01d/claude-conventions). On the Mac they auto-load via `~/code/CLAUDE.md`; **a cloud sandbox does not see them** — fetch before starting work:

```sh
gh repo clone m0n01d/claude-conventions /tmp/conventions 2>/dev/null || git clone https://github.com/m0n01d/claude-conventions /tmp/conventions
cat /tmp/conventions/CLAUDE.md
```

If the clone fails (sandbox credentials may be scoped to this repo only), continue with this file — the critical rules for this project are inlined below.

## Use `resq` when editing the `.res` files here

`resq` reads and edits ReScript structurally — prefer it over reading whole files and hand-splicing
text. Run `resq guide` for the full command reference.

```sh
resq list src/Main.res
resq get src/Greeting.res make      # decorators + doc comment included
resq refs src/Greeting.res tone     # project-wide references
resq rm decl src/Main.res farewell  # removes decorators + doc comment too
```

Writes fail closed: resq refuses a file that already has parse errors, re-parses its own output, and
leaves the file byte-identical on any failure.

## Bootstrapping resq in a fresh environment

**This section exists because a cloud sandbox starts with nothing installed.** When you open this
repo on claude.ai/code (or from the phone app), you get a Linux container with only this repo — the
workspace-level `code/CLAUDE.md` is *not* present, so the instructions have to live here.

```sh
curl -fsSL https://raw.githubusercontent.com/m0n01d/resq/main/scripts/install.sh | sh
export PATH="$HOME/.cargo/bin:$PATH"
```

[`m0n01d/resq`](https://github.com/m0n01d/resq) is **public**, so this needs no credentials. The
script is idempotent and installs rustup itself if `cargo` is missing.

Verified end to end from a clean directory with git credentials stripped — fetch, clone, compile,
install, run. Budget a few minutes on a cold sandbox; the dependency compile is the slow part.

If resq cannot be installed, nothing here breaks — just edit the `.res` files directly. resq is a
convenience, not a dependency.
