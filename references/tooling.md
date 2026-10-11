# Tooling

Everything is self-hosted Resid. In a Resid checkout the compiler is
`build/boot/stage2.bin`; `build/boot/residc` is a wrapper that sets
`RESID_HOME` (where the runtime `rt.ll` lives) and runs it. `./install.sh`
copies the compiler, runtime (`rt.ll`, plus `rt-aarch64.ll` when built),
stdlib and a signing key to `~/.resid` (`RESID_INSTALL` overrides) and
builds `resid-manifest`, `resid-pkg` and `resid-fetch` into
`~/.resid/bin` next to `residc`; `source ~/.resid/env` (or `env.fish`)
puts them on PATH. `./boot.sh` refreshes an existing install after every
build or reseed (`RESID_NO_INSTALL_REFRESH=1` skips); `./uninstall.sh`
removes it, keeping the key (`--purge` removes all). Examples below write
`residc`.

## Compiling and running

```sh
residc prog.resid                       # type-check + reduce + build ./a.out (release profile)
residc prog.resid -o prog --profile debug && ./prog arg1 arg2
residc prog.resid --profile check       # type-check only, writes the graph artifact, no binary
residc prog.resid -o prog -O3 -march=native   # release, clang -O3 (needs a signing key)
residc prog.resid -o prog --target aarch64    # cross-compile for AArch64 Linux/Android
```

There is no `run` subcommand (older docs mention one): build, then execute.

| Flag | Meaning |
|---|---|
| `-o PATH` | output binary (default `a.out`); sidecars are named `PATH.*` |
| `--profile debug` | `-O0`, DWARF, graph artifact; unsigned when no key is found (a note, not an error) |
| `--profile check` | stop after checking; write `PATH.resid-graph.cbor`; prints `check: ok` |
| `--profile release` (default) | `-O2` with LTO, signed provenance; **fails without a signing key** |
| `-O0 -O1 -O2 -O3 -Os -Oz` | clang optimization level (overrides the profile's) |
| `-march=CPU` | passed to clang (`-march=native`) |
| `--target T` | `x86_64` (default) or `aarch64` (also `arm64`, `aarch64-linux-android`); links with lld against compiler-rt's AArch64 builtins (`RESID_AARCH64_BUILTINS`, else `$RESID_HOME/aarch64/libclang_rt.builtins.a`) |
| `--reduce-budget N\|unbounded` | compile-time reduction fuel ([compile-time-reduction.md](compile-time-reduction.md)) |
| `--dump-reduced FILE` | write the residual program (after reduction) as source |
| `--no-reduce` | skip compile-time reduction |
| `--no-facts` | keep checks that range facts would drop |
| `-native m=PATH.ll` | link a native module's LLVM IR for `@link("m")` (repeatable; see [capabilities-and-security.md](capabilities-and-security.md)) |
| `-depmap FILE` | package dependency map (`name::root::caps` lines) from `resid-manifest depmap` |
| `-rt FILE.c`, `-rtr FILE.ll` | add a C file to the link; replace the runtime IR (default `$RESID_HOME/rt.ll`) |
| `--dump-graph FILE`, `--graph-check`, `--graph-lint`, `--graph-resolve`, `--graph-types [FILE]`, `--graph-where LINE` | compiler-debugging views of the knowledge graph |
| `--runtime-internals`, `--runtime-module` | compiler/runtime builds only; refused for user programs |

Other subcommands:

- `residc keygen [dir]`: Ed25519 key pair in `dir` (default `keys`), the
  secret written 0600.
- `residc verify BINARY [--pub HEX] [--anchored] [--sources DIR]`: checks
  the provenance signature, code hash and sidecars, then prints each line
  as `evidence:` (re-derived by the verifier) or `attestation:` (signed but
  only claimed: toolchain, profile, output, grant, and sources unless
  `--sources DIR` re-hashes them). `trust:` names where the key came from:
  `anchored` (`$RESID_HOME/keys`), `supplied` (`--pub`, `RESID_VERIFY_PUB`)
  or `local` (`keys/*.pub` in the cwd); `--anchored` refuses all but the
  install keyring. It ends `verify: ok (...)` or `verify: FAIL: <reason>`.
  Rebuilding the same source with the same key and output path gives the
  same bytes.
- `residc test FILE [--filter RE] [--format pretty|tap|json]` builds and
  runs one file's `test` blocks; `residc test [--root DIR] [--testbin-dir
  DIR]` with no file runs every `*_test.resid` under `--root` (default
  `.`). The flags win over `RESID_TEST_FORMAT`/`RESID_TEST_FILTER`, which
  only matter when running a built test binary directly. See
  [testing.md](testing.md).
- `residc lsp`: language server over stdio.

Environment:

| Variable | Use |
|---|---|
| `RESID_HOME` | directory holding `rt.ll`, the stdlib (`$RESID_HOME/lib` in an install, else two levels up) and the install's `keys/`; set by both `residc` wrappers, needed only when running `stage2.bin` directly outside the checkout root (`clang: error: no such file or directory: 'build/boot/rt.ll'` means it is unset) |
| `RESID_SIGNING_KEY` | secret key file for release builds (else `keys/resid-ed25519.key` relative to the cwd, else `$RESID_HOME/keys/resid-ed25519.key`) |
| `RESID_VERIFY_PUB` | public key (hex) for `residc verify`, like `--pub` |
| `RESID_PROV_ENCRYPT=1`, `RESID_PROV_KEY` | conceal the provenance payload (ChaCha20-Poly1305, key as 64 hex digits); `verify` then needs the same `RESID_PROV_KEY` |
| `RESID_AARCH64_BUILTINS` | compiler-rt builtins archive for `--target aarch64` (`tools/aarch64-builtins.sh` finds one in an Android NDK) |
| `RESID_INSTALL` | install directory for `install.sh` / `uninstall.sh` (default `~/.resid`) |
| `RESID_MEM_LIMIT` | heap budget in MB, for the compiler (default 4096; also scales the reduction memory meter) and for any program (default none) |
| `RESID_STACK_MB` | stack of the thread running `main`, in MB (default 1024) |
| `RESID_TEST_FORMAT`, `RESID_TEST_FILTER` | test binary output and filter |

Outputs of a build: the binary, `PATH.ll` (LLVM IR), and sidecars
`PATH.resid-notes.cbor` (residual notes), `PATH.resid-graph.cbor` (knowledge
graph; debug/check), `PATH.resid-prov.cbor` (detached provenance; signed
builds). Binaries are static PIEs with no C library.

## Reading compiler output

```text
OK func main                     # per-declaration progress (ignore)
typecheck OK
[comptime_print] 6765            # your comptime_print values
note: reduce: reduction budget (steps) exhausted evaluating f(...); the call stays residual
wrote prog
note: notes: 2 residual note(s) recorded
note: provenance: signed (kid e815aaa1920ec0ba)
```

Errors look like:

```text
error[E0001]: type error: binding s: expected Str, got Int
  --> prog.resid:3:11
3 |     Str s = x;
              ^^^
```

Some failures come from later stages without an E-code: `codegen error: ...`
(lowering) or a clang message about the generated `.ll`. Those are compiler
limitations triggered by a construct; see
[idioms-and-antipatterns.md](idioms-and-antipatterns.md) (known issues) for
the usual causes, then rewrite the construct. [error-codes.md](error-codes.md)
lists the codes.

## Tools (build them once)

Each tool is a Resid program in the checkout's `tools/` (an install
already has the three package tools); build the rest like any program
(the debug profile needs no key):

```sh
cd /path/to/resid
for t in resid-why resid-graph resid-debug resid-fmt resid-cose; do
  build/boot/residc tools/$t.resid -o ~/bin/$t --profile debug
done
```

### resid-fmt: canonical formatter

```sh
resid-fmt prog.resid           # print formatted source
resid-fmt prog.resid -w        # rewrite in place
resid-fmt prog.resid --check   # exit 1 if not formatted
```

Four-space indentation, one statement per line, spaces around binary
operators. It leaves f-string hole contents as written.

### resid-why: why is this residual?

```sh
resid-why prog                         # every residual note, with reason and hint
resid-why prog --summary | --json | --kind provider-call | --file F | --max N
resid-why prog SYMBOL                  # a declaration and all its uses in the graph
resid-why prog --node 61               # one graph node and its derive chain
resid-why prog --at prog.resid:9       # every node on a source line
```

The argument is the binary path: notes come from `prog.resid-notes.cbor`,
and `SYMBOL`, `--node` and `--at` need the graph artifact of a debug or
check build. Output shows each node's state, value (`known = 6765`), facts
(`range [..]`, `check overflow lacking #57`) and derive edges
(`reduced to #701 call pow__rs1 ... <- specialize #61`).

### resid-graph: call graph and graph artifact

```sh
resid-graph prog.resid [--dot]            # per function: which functions it calls
resid-graph prog --node ID [--depth N]    # DOT of the artifact around a node (depth 2)
resid-graph prog --check                  # verify the artifact's invariants
```

### resid-debug: graph-aware debugger

```sh
resid-debug prog -ex info -ex "break prog.resid:10" -ex run -ex quit
```

Commands: `info`, `node ID`, `kids ID`, `at FILE:LINE`, `sym NAME`,
`lowered [FN]`, `pc ADDR`, `check`, `break FILE:LINE|FN`, `run [ARGS]`,
`stops N`, `step N`, `backend native|gdb`, `help`, `quit` (no `-ex`: read
from stdin). At a stop it prints live variables with their graph nodes and
the KNOWN values that were folded into the code there:

```text
stop 1 at resid_user_main+0x3e (0x12be)
  c = 8   #708 bind c: Int residual, unknown on #701 <- rebuild #62 @ prog.resid:9:5
  folded #702 lit: Int known = 6765 <- known #64 @ prog.resid:10:16
```

Build the program with `--profile debug` first. The native backend uses
ptrace; resid-debug is x86-64 only.

### Packages: resid-manifest, resid-pkg, resid-fetch, resid-cose

`resid.toml` is a TOML subset: string, bool and string-array values, and
comments only on lines of their own.

```toml
[package]
name = "myapp"
version = "0.1.0"
# root = "src/main.resid" is the default

[capabilities]
grant = ["filesystem", "network"]

# capabilities is the ceiling for this dependency's code
[dependencies.http]
path = "vendor/http"
capabilities = ["network"]

[dependencies.mathx]
version = "0.2.0"

[registry]
path = "../registry"
pubkey = "<hex>"

[signing]
keyring = "keys/"

[reduce]
budget = "64000000"
```

A dependency names `path` or `version` (fetched from the registry) and may
pin `pubkey`. The registry is `path` (a directory) or `url` (`http://` or
`https://`, the latter needing `ca`, a PEM bundle or a directory of DER
certificates), never both; `[registry] pubkey` checks its signed index.
`[signing] require_signatures = true` demands a pinned or keyring key on
each archive; `allow_unsigned = true` admits unsigned registry packages.
`[native.m] path, sha256` declares a native module.

- `resid-manifest resid.toml` (show), `deps resid.toml` (resolve
  transitively, checking cycles, capability ceilings, pinned keys and
  `resid.lock`; registry packages are extracted to
  `target/resid/deps/`), `depmap resid.toml OUT` (write the `-depmap`
  file), `build resid.toml COMPILER` (resolve, then compile the root to
  `target/resid/<name>` as a release build, passing the depmap, native
  modules and `[reduce] budget`), `test resid.toml COMPILER` (`residc
  test` over the package's sources), `lock resid.lock` (show). A
  dependency marks its exports `pub`; the importer writes
  `import "mathx";`.
- `resid-pkg`: `keygen SECRET PUB`, `pack DIR OUT` (writes
  `OUT.resid-pkg`, a content-hashed archive), `sign ARCHIVE KEY`,
  `sign-dir DIR KEY`, `checksig ARCHIVE PUBHEX`, `extract ARCHIVE DIR`,
  `publish DIR REGISTRY [KEY]` (archive, signature, sha256 and re-signed
  index under `REGISTRY/pkg/`), `index list|add|remove|verify`,
  `serve REGISTRY [--port N] [--port-file F] [--requests N] [--cert F --key
  F] [--upload KEYRING --index-key F]` (loopback HTTP, or TLS 1.3 with the
  cert and key; read-only unless `--upload`), and `upload DIR URL KEY [--ca
  F]`.
- `resid-fetch [--timeout S] BASE_URL TRUST_STORE ARTIFACT OUT`: mirror one
  artifact over https and print its SHA-256.
- `resid-cose sign1|verify1|encrypt0|decrypt0`: COSE tools.

### Editor support

`residc lsp` is a language server on stdio (diagnostics, hover,
completion, go to definition, document symbols); the checkout's
`editors/vscode` extension launches it.
