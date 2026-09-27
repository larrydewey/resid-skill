# Capabilities, sandboxes, concurrency and handles

Resid has **no ambient authority**. External knowledge (files, environment,
arguments, processes, network) enters only through *providers* and a few
effectful builtins, and every function that reaches one, directly or through
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
  (or a `test` block). Modes: `readonly`, `readwrite` (default).
- A function "uses" what its provider calls and effectful builtins use, plus
  everything used by each function it calls, each lambda it writes, each
  method-sugar call, and each `sort` behavior it selects.
- Missing grants are **E0219**, with the path: `function main uses (through
  save) capability filesystem`.
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
| | `filesystem.write_secret(path, s)` (mode 0600) | `Bool` | write |
| | `filesystem.create_dir(path)` (creates parents) | `Bool` | write |
| `environment` | `environment.get(name)` | `Str` ("" if unset) | read |
| `args` | `args.count()` / `args.get(i)` | `Int` / `Str` ("" if absent); `get(0)` is the program path | read |
| `process` | `process.run(cmdline)` | `Int` exit status; no shell, words split on spaces, output goes to the terminal | write |
| `network` | `resid_tcp_connect(host, port)` → fd (`-1` on failure), `resid_tcp_send(fd, Str)`, `resid_tcp_send_bin(fd, List(Int))`, `resid_tcp_recv_all(fd)` → `Str`, `resid_tcp_recv_bin(fd, n)` → `List(Int)`, `resid_tcp_close(fd)` | | builtins |

Not capabilities (always allowed): `print`, `println`, `eprintln`,
`print_bytes`, `resid_read_line()` (stdin; keeps the trailing `\n`, `""` at
EOF), `resid_crypto_random_byte()` (OS randomness), allocation, aborts.

The spec also lists a `git` provider; the current compiler does not accept
`git.*` calls.

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
- A package manifest (`resid.toml`) gives each dependency a ceiling:
  `[dependencies.http] path = "vendor/http" capabilities = ["network"]`.
  The package tools pass it to the compiler as a depmap line
  `name::root::caps` (`-depmap FILE`). Code can narrow further, never widen.
- Violations are compile errors (E0211/E0212/E0218) when visible statically;
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
- The body captures outer bindings by value and returns a pure value.
- An abort inside the child (overflow, index, assert) is delivered as
  `Err(RegionError { message })`; the parent keeps running.
- Nested spawns are allowed. Scheduling is implementation-defined: do not
  count on parallel speedup.

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

## Handles and `with`

`File` is an identity-bearing handle (the only mutable-state kind of value).
`with (T h = expr) { ... }` scopes it; several handles may be opened in one
`with`. Handles need the capability they came from.

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
`resid_mem_*`, `resid_internals*`, `@export`/`@import` belong to the
compiler and `runtime/rt/` only. User code calling them is rejected with
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

## Security caveats worth knowing

- The TLS client in `lib/tls*.resid`/`lib/h2.resid` does **not** authenticate
  servers (no trust store). Do not rely on it against an active attacker.
- DER/X.509/HPACK parsers abort on malformed input instead of returning an
  error; run untrusted parsing inside `spawn` if the process must survive.
- Constant-time behavior of compiled code is not verified.
- Release binaries carry signed provenance; `residc verify <binary>` checks
  it (see [tooling.md](tooling.md)).
