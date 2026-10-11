# Capabilities, sandboxes, concurrency and handles

Resid has **no ambient authority**. External knowledge (files, environment,
arguments, processes, network, terminal, clock, display) enters only
through *providers* and a few effectful builtins, and every function that reaches one, directly or through
anything it calls, must be granted the capability. Authority can only be
narrowed (attenuated) on the way down, never amplified.

## @requires

```resid
@requires(filesystem(readonly))
Str first_line(Str path) {
    List(Str) lines = str_split(filesystem.read_all(path), "\n");
    return lines[0];
}

// main must grant what its callees use.
@requires(filesystem(readonly), args)
Int main() {
    Str host = first_line("/etc/hostname");
    println(f"{str_len(host) > 0} {args.count()}");   //> true 1
    return 0;
}
```

- Syntax: `@requires(family, family(mode), ...)` immediately before a function
  (or a `test` block). Modes: `readonly`, `readwrite` (default). An unknown
  family or mode is E0213; `display` and `native_<m>` take no mode.
  Provider arguments are type-checked.
- `network(readonly)` covers every TCP builtin except `resid_tcp_listen_at`:
  exposing a port to other machines is the one network write. A server binds
  in `main` under `network` and spawns workers with `network(readonly)`.
- A function "uses" what its provider calls and effectful builtins use, plus
  everything used by each function it calls, each lambda it writes, each
  method-sugar call, and each `sort` behavior it selects. Generics add
  nothing: each concrete copy needs what it and its instances use (E0219
  names the copy, e.g. `label(Task)`).
- Missing grants are **E0219**, with the path: ``function `main` uses
  (through `save`) capability `filesystem` but is not granted it: declare
  @requires(filesystem) on it``.
- A read-only grant does not cover a write, even one reached through a callee.
- Pure functions need nothing. Most of a program should be pure; keep
  capability use in a thin outer layer.

```resid
//! compile-error: E0219
@requires(process)
Int run_it() { return process.run("true"); }

Int main() { return run_it(); }      // main is not granted process
```

```resid
//! compile-error: E0219
@requires(filesystem)
Bool save(Str p) { return filesystem.write_all(p, "x"); }

@requires(filesystem(readonly))
Int main() {
    if (save("out.txt")) { return 1; }  // readonly grant cannot cover a write
    return 0;
}
```

The writes a read-only grant refuses: the filesystem write verbs,
`process.run`, `clock.sleep_ns`, `resid_term_raw`/`resid_term_restore` and
`resid_tcp_listen_at`.

```resid
//! compile-error: E0219
@requires(network(readonly))
Int main() {
    Int lfd = resid_tcp_listen_at("0.0.0.0", 0);   // a public bind is a network write
    return 0;
}
```

## Families and verbs

| Family | Call | Returns | Kind |
|---|---|---|---|
| `filesystem` | `filesystem.read_all(path)` | `Str` ("" if unreadable) | read |
| | `filesystem.read_bytes(path)` | `List(Int)` | read |
| | `filesystem.exists(path)` / `is_dir(path)` | `Bool` | read |
| | `filesystem.list_dir(path)` | `List(Str)` | read |
| | `filesystem.sha256(path)` | `List(Int)` (32 bytes; empty if missing) | read |
| | `filesystem.open(path)` | `File` handle | read |
| | `filesystem.read_handle(h)` / `close(h)` | `Str` / `Bool` | read |
| | `filesystem.write_all(path, s)` / `write_bytes(path, List(Int))` | `Bool` | write |
| | `filesystem.append_bytes(path, List(Int))` | `Bool` | write |
| | `filesystem.write_hex(path, hex)` / `append_hex(path, hex)` | `Bool` | write |
| | `filesystem.write_secret(path, List(Int))` (mode 0600, no symlink follow) | `Bool` | write |
| | `filesystem.create_dir(path)` (creates parents) | `Bool` | write |
| `environment` | `environment.get(name)` | `Str` ("" if unset) | read |
| `args` | `args.count()` / `args.get(i)` | `Int` / `Str` ("" if absent); `get(0)` is the program path | read |
| `process` | `process.run(cmdline)` | `Int` exit status (127 if the command cannot run, -1 if killed by a signal); no shell, words split on spaces (no quoting), output goes to the terminal | write |
| | `resid_dbg_*` (the ptrace debugger builtins behind `resid-debug`) | | builtins |
| `terminal` | `resid_term_is_tty(fd)` → `Bool` (fd 0–2), `resid_term_cols()` / `resid_term_rows()` → `Int` (80 / 24 if unknown) | | read (builtins) |
| | `resid_term_raw()` / `resid_term_restore()` → `Bool` (stdin raw mode on/off; the runtime also restores at exit and on abort) | | write (builtins) |
| `network` | `resid_tcp_connect(host, port)` → fd (`-1` on failure), `resid_tcp_send(fd, Str)`, `resid_tcp_send_bin(fd, List(Int))` (≤ 1 MB), `resid_tcp_recv_all(fd)` → `Str` (until close), `resid_tcp_recv_bin(fd, n)` → exactly `n` bytes, `resid_tcp_recv_some(fd, max)` → what one receive returns (`[]` at EOF), `resid_tcp_send_some(fd, List(Int))` → bytes taken without waiting, `resid_tcp_poll(fds, wants, ms)` → readiness per fd, `resid_tcp_deadline(fd, ms)` → `Bool` (a per-socket deadline, no `clock` needed), `resid_tcp_shutdown(fd)`, `resid_tcp_close(fd)` | | read (builtins) |
| | `resid_tcp_listen(port)` → loopback listener (`0` = any port), `resid_tcp_bound_port(lfd)`, `resid_tcp_accept(lfd)` → fd, `resid_tcp_accept_now(lfd)` → fd, `-2` if none is waiting | | read (builtins) |
| | `resid_tcp_listen_at(host, port)` → listener on an interface address (`"0.0.0.0"`) | | write (builtin) |
| `clock` | `clock.now_ns()`, `clock.now_sec()`, `clock.monotonic_ns()` (use `lib/clock.resid`: `clock_now()` → `Instant`, `clock_now_seconds()`, `clock_monotonic_ns()`, `clock_now_utc()`) | `Int` | read |
| | `clock.sleep_ns(ns)` (`clock_sleep_ms`, `clock_sleep(Span)`) | `Int` | write |
| `display` | `resid_disp_*` builtins (window-server connection, shared-memory frames); no modes, `display(readonly)` is E0213; a `DISPLAY` naming another host is refused | | builtins |
| `native_<m>` | calling an `@link("m")` function (see Native modules below); no modes, bare `native` is not a family | | |
| `device` | `lib/dev/` wrappers (`snp_get_report`, `tpm_*`, `tsm_report_get`, ...) over descriptors; see devices-and-attestation.md | `Result(_, DeviceError)` | read (`device(readonly)`) / write |

Reading the clock is an effect: without `clock(readonly)` a call to
`clock_now_seconds()` is E0219. Date/time arithmetic and formatting on an
`Instant` you already hold (`lib/calendar`, `instant`, `duration`, `zone`,
`datetime`) needs no grant.

```resid
import "clock.resid";

@requires(clock(readonly))
Int main() {
    Int t = clock_now_seconds();
    println(f"{t > 0}");   //> true
    return 0;
}
```

Not capabilities (always allowed): `print`, `println`, `eprintln`,
`print_bytes`, `resid_read_line()` (stdin; keeps the trailing `\n`, `""` at
EOF), `resid_read_byte()` (one stdin byte, `-1` at EOF; shares one buffer
with `resid_read_line`), `resid_crypto_random_byte()` (OS randomness), allocation, aborts.

The known families are `filesystem`, `environment`, `args`, `process`,
`network`, `terminal`, `clock`, `display`, `device`, `declassify`,
`provision`, `assume` and `native_<module>`. `device` (with `readonly`) is
kernel devices through `lib/dev/` descriptors, `declassify` a program that
publishes a secret, `provision` a stated provisioned key, `assume` an
attestation assumption: see [secrets.md](secrets.md) and
[devices-and-attestation.md](devices-and-attestation.md). There is
no `git` provider: `@requires(git)` is E0213 (unknown capability family).

```resid
@requires(filesystem)
Int main() {
    Bool w = filesystem.write_all("notes.txt", "one\ntwo\n");
    Bool a = filesystem.append_bytes("notes.txt", [51, 10]);   // "3\n"
    Str body = filesystem.read_all("notes.txt");
    println(f"{w} {a} {str_count(body, "\n")}");              //> true true 3
    println(f"{filesystem.exists("notes.txt")} {filesystem.is_dir(".")}");  //> true true
    Bool d = filesystem.create_dir("out/sub");
    println(f"{d} {filesystem.list_dir("out").len()}");       //> true 1
    return 0;
}
```

## Sandboxes

A `sandbox (caps) { ... }` block puts a ceiling on every declaration inside
it and on everything those functions call. A function inside with no
`@requires` is granted by the sandbox itself (callers outside still need the
grant). Nested sandboxes **meet** (intersect); `sandbox ()` grants nothing.

```resid
sandbox (filesystem(readonly)) {
    Bool root_is_dir() { return filesystem.is_dir("/"); }
}

@requires(filesystem(readonly))
Int main() {
    println(f"{root_is_dir()}");   //> true
    return 0;
}
```

```resid
//! compile-error: read-only grant
sandbox (filesystem(readonly)) {
    Bool sneaky() { return filesystem.write_all("x.txt", "x"); }
}

@requires(filesystem)
Int main() { println(f"{sneaky()}"); return 0; }
```

```resid
//! compile-error: E0212
sandbox () {
    @requires(filesystem(readonly))
    Str peek() { return filesystem.read_all("/etc/hostname"); }
}

@requires(filesystem(readonly))
Int main() { println(peek()); return 0; }
```

### Attenuated imports and manifest ceilings

- `import "lib.resid" @requires(network);` compiles that module (and its
  imports) inside `sandbox (network)`. A module already imported without the
  bound cannot be re-imported with one (E0216): import it attenuated first.
- A package manifest (`resid.toml`) gives each dependency a ceiling, which
  must be grantable under the package's own `[capabilities] grant` (modes
  included); a dependency declared twice gets the meet of both ceilings.
  The package tools pass it to the compiler as a depmap line
  `name::root::caps` (`-depmap FILE`). Code can narrow further, never widen.

  ```toml
  [capabilities]
  grant = ["filesystem", "network"]

  [dependencies.http]
  path = "vendor/http"
  capabilities = ["network(readonly)"]
  ```
- Violations are compile errors (E0211, E0212, E0215, E0218) when visible statically;
  every provider call is also checked at run time against the thread's
  sandbox frames before it runs.

## Concurrency: spawn

```resid
Int work(Int n) { return n * n; }

@requires(filesystem(readonly))
Int main() {
    Int n = rt 12;                                  // captured by value
    Result(Int, RegionError) a = spawn () { return work(n); };
    Result(Bool, RegionError) b = spawn (filesystem(readonly)) {
        return filesystem.is_dir("/");
    };
    Int av = match a { Ok(v) => v, Err(e) => -1 };
    Bool bv = match b { Ok(v) => v, Err(e) => false };
    println(f"{av} {bv}");                          //> 144 true
    return 0;
}
```

- `spawn (caps) { ... return value; }` has type `Result(T, RegionError)`.
- The child gets a fresh capability environment with only the listed
  capabilities; the list must be within the parent's grant (E0214), and
  functions it calls must fit (E0215).
- The body captures outer bindings by value and returns a value, never a
  handle. A captured `File` is **moved**: the parent may not use it after
  the spawn. The `Result` needs a declared type
  (`Result(T, RegionError) r = spawn ...`).
- An abort inside the child (overflow, index, assert) is delivered as
  `Err(RegionError { message })`; the parent keeps running.
- Nested spawns are allowed. Regions may run in parallel; each is joined
  before the scope that started it ends.

```resid
//! compile-error: E0214
@requires(filesystem, process)
Int main() {
    Result(Int, RegionError) r = spawn (filesystem) {
        return process.run("true");   // process not in the spawn list
    };
    return 0;
}
```

```resid
//! compile-error: was moved into a spawn region
@requires(filesystem)
Int main() {
    File h = filesystem.open("h.txt");
    Result(Str, RegionError) r = spawn (filesystem(readonly)) {
        return filesystem.read_handle(h);
    };
    Bool c = filesystem.close(h);    // h now belongs to the region
    return 0;
}
```

## Handles and `with`

`File` is an identity-bearing handle (the only mutable-state kind of value).
`with (T h = expr) { ... }` scopes it and releases it when the block ends;
`with (T a = e1, U b = e2)` opens several. Handles need the capability they
came from: a `File` parameter in a sandbox without `filesystem` is E0212.

```resid
@requires(filesystem)
Int main() {
    Bool w = filesystem.write_all("h.txt", "hello handle\n");
    with (File h = filesystem.open("h.txt")) {
        print(filesystem.read_handle(h));      //> hello handle
    }
    File g = filesystem.open("h.txt");
    Bool closed = filesystem.close(g);
    println(f"{closed}");                      //> true
    return 0;
}
```

## Runtime internals are not part of the language (E0220)

`resid_raw_*` (raw memory, syscalls, atomics), `resid_arena_*`,
`resid_bulk_*`, `resid_list_str_persist_copy`, `resid_dec_persist`,
`resid_mem_limit_set`, `resid_stack_left`, `resid_internals_set`,
`resid_fmt_*` (f-string specs reach these) and the annotations
`@export`/`@import`/`@inline`/`@noinline`/`@cold` belong to the compiler
and `runtime/rt/` only. User code calling them is rejected with
E0220, and `--runtime-internals` is refused for any other entry file. Never
use them, even if you see them in `compiler/` or `runtime/rt/` sources.

```resid
//! compile-error: E0220
Int main() {
    Int a = resid_arena_push();
    Int b = resid_arena_pop();
    return 0;
}
```

## Native modules (`@link`, spec §47)

There is no `extern` and no in-process FFI. Code from another language comes
in as a native module: LLVM IR text for the build's target (x86-64 or
AArch64 Linux), freestanding (no C library), given with `-native m=<path.ll>` (or `[native.m]` in the
manifest, where the artifact's SHA-256 is pinned).

```resid
//! compile-error: E0219
@link("zlib")
Int adler32(Int len) {}           // body is empty: the module supplies it

Int main() { return adler32(3); } // needs @requires(native_zlib)
```

- `@link("m")` goes on a top-level, non-generic function with an empty body
  and no `@requires`/`@needs`/`@import`/`@export` (E0234). Its use is the
  family `native_m`, carried to callers (E0219) and bounded by spawn lists,
  sandboxes and manifest ceilings like any family. Not allowed in the
  stdlib, the tools or the runtime (E0232).
- Only fixed-form values cross (E0233): `Bool`, sized `Int`/`UInt`/`Float`,
  `Str(N)`, `Bytes(N)` (N ≤ 16777216), and `Void` as a result. The
  artifact must define the function (E0235) with matching C types (E0236).
  A missing `-native m=...` for a used module is E0235.
- The artifact is checked and rewritten (E0237): it may reference only its
  own symbols, LLVM intrinsics and memcpy/memmove/memset; no module asm,
  aliases, ifuncs, constructors, comdats, sections, external or
  thread-local globals, personality functions, or a
  triple other than the target; every symbol is renamed `native.m.*`.
- **Each call runs in a fresh process**: the program re-executed with an
  empty environment and only the call's socket, with the TSC disabled, the
  vDSO clock unmapped, seccomp allowing only socket read/write,
  non-executable mmap and exit, and 60 s of CPU. A call costs about 2 ms. No
  state survives between calls, and it is never evaluated at compile time.
- The reply is checked as untrusted input (type and range, never meaning).
  A crash or a malformed reply aborts the caller, or becomes
  `Err(RegionError)` inside `spawn`.
- Native code that needs the OS (a file, a device, a GPU) can't be a native
  module. Do that work through providers.

## Security caveats worth knowing

`SECURITY.md` in the Resid repo lists every guarantee with its tests; check
it before relying on anything here.

- The TLS client (`lib/tlsclient.resid`) **does** authenticate servers:
  host name, validity window, chain to a `TrustStore` (PEM bundle or DER
  directory), CertificateVerify, and CRL/OCSP revocation when the store holds
  them (`revocation_required` turns "no information" into a refusal). No
  store means nothing is trusted, and there is no skip flag. Not implemented:
  stapled OCSP, client certificates, resumption, ECH, 0-RTT, and RSA
  signing on the server (it signs with Ed25519 or ECDSA P-256/P-384).
- Parsers of untrusted bytes (X.509, CRL, OCSP, keys, signatures,
  CBOR/COSE, TLS messages, PEM, HTTP/2 frames, HPACK) are total: they return
  an error rather than abort or hang, and are mutation-fuzzed.
- Verified signatures: ECDSA P-256/P-384 with SHA-256/384/512, RSA PKCS#1
  v1.5 and PSS (2048-16384 bits) with SHA-256/384/512, and Ed25519. Not
  verified: P-521, SHA-1, SHA-3, DSA, RSA below 2048 bits. Such a
  certificate is refused.
- Constant time is checked on the optimized binary with valgrind
  (`tests/ct/run.sh`, x86-64 only) for the listed primitives (ECDSA
  signing, ECDH, X25519, Ed25519, AES, AES-GCM, ChaCha20-Poly1305, SHA-512,
  HMAC, HKDF, HPKE open, `ct_equal`). The TLS record layer and handshake
  around them are not separately checked, and variable-latency
  instructions are out of the check's reach.
- Timing side channels beyond that and denial of service are out of
  scope (a malformed input may still abort a program at a checked
  operation). So is an attacker who can write the build tree (`-rt FILE`
  hands whatever it names to the linker unchecked).
- The bootstrap is a self-compile fixed point (`./boot.sh`). SECURITY.md
  does not count an independent second compiler, so a "trusting trust"
  seed isn't ruled out by the repo's own checks.
- Release binaries carry signed, reproducible provenance (COSE_Sign1,
  Ed25519). `residc verify <binary>` checks it and separates evidence from
  attestation (see [tooling.md](tooling.md)).
