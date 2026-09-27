# Tooling

Everything is self-hosted Resid. In a Resid checkout the compiler is
`build/boot/stage2.bin`; `build/boot/residc` is a wrapper that sets
`RESID_HOME` (where the runtime `rt.ll` lives) and runs it. Examples below
write `residc`; substitute `/path/to/resid/build/boot/residc` (or run
`build/boot/stage2.bin` from the checkout root).

## Compiling and running

```sh
residc prog.resid                       # type-check + reduce + build ./a.out (release profile)
residc prog.resid -o prog --profile debug && ./prog arg1 arg2
residc prog.resid --profile check       # type-check only, writes the graph artifact, no binary
residc prog.resid -o prog -O3           # release with clang -O3 (needs a signing key)
```

There is no `run` subcommand (older docs mention one): build, then execute.

| Flag | Meaning |
|---|---|
| `-o PATH` | output binary (default `a.out`); sidecars are named `PATH.*` |
| `--profile debug` | `-O0`, DWARF, graph artifact; unsigned when no key is found (a note, not an error) |
| `--profile check` | stop after checking; write `PATH.resid-graph.cbor`; prints `check: ok` |
| `--profile release` (default) | `-O2`, signed provenance; **fails without a signing key** |
| `-O0 -O1 -O2 -O3 -Os -Oz` | clang optimization level |
| `--dump-reduced FILE` | write the residual program (after reduction) as source |
| `--no-reduce` | skip compile-time reduction |
| `--no-facts` | do not use range facts to drop checks |
| `-depmap FILE` | package dependency map (`name::root::caps` lines) from the manifest tool |
| `--dump-graph FILE`, `--graph-check`, `--graph-lint`, `--graph-resolve`, `--graph-types [FILE]` | compiler-debugging views of the knowledge graph |
| `--runtime-internals`, `--runtime-module`, `-rt`, `-rtr` | compiler/runtime builds only; refused for user programs |

Other subcommands: `residc keygen [dir]` (Ed25519 key pair, secret written
0600), `residc verify BINARY [--pub HEX]` (checks the provenance
signature, code hash and sidecars), `residc test FILE [--filter RE]
[--format pretty|tap|json]` (see [testing.md](testing.md)), `residc lsp`
(language server over stdio).

Environment:

| Variable | Use |
|---|---|
| `RESID_HOME` | directory holding `rt.ll` (and, two levels up, the stdlib `lib/` used as the import fallback); needed when running `stage2.bin` outside the checkout root (`clang: error: no such file or directory: 'build/boot/rt.ll'` means it is unset) |
| `RESID_SIGNING_KEY` | secret key file for release builds (else `keys/resid-ed25519.key` relative to the cwd) |
| `RESID_MEM_LIMIT` | memory budget in MB for a program (compiler default 4096) |
| `RESID_TEST_FORMAT`, `RESID_TEST_FILTER` | test runner output and filter |

Outputs of a build: the binary, `PATH.ll` (LLVM IR), and sidecars
`PATH.resid-notes.cbor` (residual notes), `PATH.resid-graph.cbor` (knowledge
graph; debug/check), `PATH.resid-prov.cbor` (detached provenance). Binaries
are static PIEs with no C library.

## Reading compiler output

```text
OK func main                     # per-declaration progress (ignore)
typecheck OK
[comptime_print] 55              # your comptime_print values
wrote ./prog
note: notes: 2 residual note(s) recorded
note: provenance: signed (kid e815aaa1920ec0ba)
```

Errors look like:

```text
error[E0001]: type error: binding s: expected Str, got Int
  --> prog.resid:3:13
3 |     Str s = x;
                ^^^
```

Some failures come from later stages without an E-code: `codegen error: ...`
(lowering) or a clang message about the generated `.ll` (`use of undefined
value '@__cmp_by_pay'`). Those are compiler
limitations triggered by a construct; see
[idioms-and-antipatterns.md](idioms-and-antipatterns.md) (known issues) for
the usual causes, then rewrite the construct. [error-codes.md](error-codes.md)
lists the codes.

## Tools (build them once)

Each tool is a Resid program in the checkout's `tools/`; build it like any
program (debug profile needs no key):

```sh
cd /path/to/resid
for t in resid-why resid-graph resid-debug resid-fmt; do
  build/boot/stage2.bin tools/$t.resid -o ~/bin/$t --profile debug
done
```

### resid-fmt: canonical formatter

```sh
resid-fmt prog.resid           # print formatted source
resid-fmt prog.resid -w        # rewrite in place
resid-fmt prog.resid --check   # exit 1 if not formatted
```

Four-space indentation, one declaration per line group, spaces around
binary operators. It leaves f-string hole contents as written.

### resid-why: why is this residual?

```sh
resid-why prog                         # every residual note, with reason and hint
resid-why prog --summary | --json | --kind provider-call | --max N
resid-why prog SYMBOL                  # a declaration and all its uses in the graph
resid-why prog --node 64               # one graph node and its derive chain
resid-why prog --at prog.resid:9       # every node on a source line
```

Needs a debug or check build (for the graph artifact). Output shows each
node's state, value (`known = 6765`), facts (`range [..]`, `check overflow
lacking #60`), and derive edges (`<- specialize #64`).

### resid-graph: call graph and graph artifact

```sh
resid-graph prog.resid [--dot]            # per function: which functions it calls
resid-graph prog --node ID [--depth N]    # DOT of the artifact around a node
resid-graph prog --check                  # verify the artifact's invariants
```

### resid-debug: graph-aware debugger

```sh
resid-debug prog -ex info -ex "break prog.resid:11" -ex run -ex quit
```

Commands: `info`, `node ID`, `at FILE:LINE`, `sym NAME`, `kids ID`,
`lowered [FN]`, `pc ADDR`, `check`, `break FILE:LINE|FN`, `run [ARGS]`,
`stops N`, `step N`, `backend native|gdb`, `quit` (no `-ex`: read from
stdin). At a stop it prints live variables with their graph nodes and the
KNOWN values that were folded into the code there:

```text
stop 1 at resid_user_main+0x37 (0x12b7)
  c = 8   #218 bind c: Int residual, unknown on #210 <- rebuild #65 @ prog.resid:9:5
  folded #211 lit: Int known = 6765 <- known #71 @ prog.resid:11:16
```

Build the program with `--profile debug` first. Live mode uses ptrace.

### Packages: resid-manifest, resid-pkg, resid-cose

`resid.toml`:

```toml
[package]
name = "myapp"
version = "0.1.0"

[capabilities]
grant = ["filesystem", "network"]

[dependencies.http]
path = "vendor/http"
capabilities = ["network"]      # ceiling for this dependency's code

[signing]
keyring = "keys/"
```

- `resid-manifest resid.toml` (show), `deps` (resolve transitively,
  checking cycles, capability ceilings and pinned keys), `depmap resid.toml
  OUT` (write the `-depmap` file), `build resid.toml DRIVER` (resolve and
  compile), `lock resid.lock`.
- `resid-pkg pack|sign|sign-dir|checksig|extract|publish|keygen`: content
  hashed `RESIDPKG1` archives and Ed25519 signatures. Unsigned registry
  packages are rejected unless `[signing] allow_unsigned = true`.
- `resid-cose sign1|verify1|encrypt0|decrypt0`: COSE tools.

### Editor support

`residc lsp` is a language server on stdio (diagnostics and more); the
checkout's `editors/vscode` extension launches it.
