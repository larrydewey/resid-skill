# Error codes and messages

Compiler diagnostics print as `error[CODE]: message` followed by
`--> file:line:col` and a caret line. Most type and syntax problems share
`E0001`; the message text is what tells you the fix. Messages below are
quoted from the current compiler.

## Coded errors

Every code the compiler emits, in order. A code that a type error
carries still prints as `error[CODE]:` (for example `error[E0226]: sort of
T needs Ord(T) ...`).

| Code | Meaning | Typical fix |
|---|---|---|
| E0001 | type or syntax error (message says which; see next section) | read the message |
| E0211 | a function inside a sandbox calls one whose `@requires` exceeds the sandbox ceiling: ``call to `g` requires capability `process` which exceeds the caller's effective sandbox ceiling [filesystem:ro] (attenuation is transitive across the call closure)`` | move the callee out, narrow its needs, or widen the sandbox if you own it |
| E0212 | inside a sandbox: a function's `@requires` exceeds the ceiling (``function `f` requires capability `process` which exceeds the effective capability ceiling [filesystem:ro]``), a **write** under a read-only grant (``provider call `filesystem.write_all` is a write operation, but only a read-only grant ...``), or a `File` parameter or argument in a region without `filesystem` | grant the right mode; keep writes and handles out of narrower sandboxes |
| E0213 | unknown capability family or mode, or a mode on a mode-less family: ``unknown capability family `git` (filesystem, environment, args, process, network, terminal, clock, display, native_<module>)``, ``unknown capability mode `sometimes` on `filesystem`; supported modes are `readonly` and `readwrite` ``, `` `display` has no modes`` | spell it from that list; `display` and `native_<m>` take no mode. There is no `git` family |
| E0214 | a `spawn` list beyond the parent (``spawn declares capability `x` which exceeds the parent's capability ceiling``), or a body using what its list lacks (`spawn body uses capabilities its list [filesystem] does not grant: process (spec §19)`) | add it to the spawn list (and the parent's `@requires`) or move the call out |
| E0215 | inside a spawn or sandbox, a call to a function whose `@requires` is not granted there: ``call to `g` requires capability `process` which is not granted to this region's capability set [filesystem]`` | same as E0214 |
| E0216 | `import "m" @requires(...)` after `m` was already imported without the bound | import it attenuated first (or only) |
| E0218 | a provider call inside a sandbox or spawn whose family is not granted there: ``provider call family `filesystem` is not granted to this region's capability set [network] (spec §21.3)`` | grant it or move the call out |
| E0219 | no ambient authority: ``function `main` uses (through `save`) capability `filesystem` but is not granted it: declare @requires(filesystem) on it``; also a `test` block, and a write under a read-only `@requires` | add the named `@requires(...)` to that function, and to each caller up to `main` |
| E0220 | a runtime internal in user code: `` `resid_arena_push` is a runtime internal of the compiler, not part of the language`` | never use `resid_raw_*`, `resid_arena_*`, `resid_bulk_*`, `resid_fmt_*`, persist copies, `resid_mem_limit_set`, `resid_stack_left`, or `@export`/`@import`/`@inline`/`@noinline`/`@cold` |
| E0221 | ``cannot find module `x.resid` imported by ... (looked for ...)`` | fix the path; stdlib names like `crypto.resid` resolve through the install's `lib/` or `RESID_HOME/../../lib` |
| E0222 | naming case: ``value name `X` must start with a lowercase letter; uppercase names are types``, ``type name ... must start with an uppercase letter``, `` `P`: single uppercase letters are reserved for type parameters`` (also functions, variants, behaviors) | values and functions lowercase; types, variants and behaviors uppercase; types longer than one letter |
| E0223 | `` `f` is ambiguous: more than one imported module exports it`` | `import "m.resid" as m;` and write `m.f`, or import only one |
| E0224 | `a library may declare instances only of its own behaviors or types` | declare the instance in the application, or in the library owning the type/behavior |
| E0225 | `overlapping instances: B(X) and B(Y) both cover some type` | one instance per type; no specialization (use `using =` at the call) |
| E0226 | a behavior need not met: `sort of T needs Ord(T): add @needs(Ord(T)) to the function`, `no behavior instance B(X)` | add the need to the generic function, or declare the instance |
| E0227 | `cannot infer type parameter T of f` | give the result a declared type (`List(Int) xs = f();`) |
| E0228 | `instantiation does not terminate: f keeps calling itself at ever larger types` | recurse at one type |
| E0231 | `` `X` is a verb of behavior B; a name is either a verb or a function, not both`` | rename the function, or override the behavior with an instance or `using =`; this reserves `min`, `max`, `least`, `greatest`, `show`, `hash`, `eq`, `compare`, `serialize`, `allocate` program-wide |
| E0232 | `@link` in the standard library, the tools or the runtime | native modules belong to programs and packages only |
| E0233 | a parameter or result type that cannot cross to a native module | `Bool`, `Int`/`UInt` (8-64 bits), `Float`/`Float(32)`, `Str(N)`, `Bytes(N)` (N <= 16777216), `Void` as a result |
| E0234 | a malformed `@link`: module name not one lowercase string literal, combined with `@requires`/`@needs`/`@import`/`@export`, non-empty body, generic, or on something other than a function | top-level, non-generic, body `{}`; its capability is `native_<m>` |
| E0235 | the artifact does not define the `@link` function, cannot be read, or was not given (`pass -native m=<path.ll>`) | pass `-native m=path.ll`; define the function, externally visible, under the declared name |
| E0236 | the artifact's C signature differs from the binding | match the spec §47.2 type table |
| E0237 | a bad `-native` flag (module named twice, path not `.ll`) or a refused artifact: module asm, aliases, ifuncs, constructors, comdats, sections, quoted, external or thread-local globals, a triple other than the build target, foreign declarations | LLVM IR text for the target (x86-64 or AArch64 Linux) that references only itself, intrinsics and memcpy/memmove/memset |
| E0250-E0259 | secret values: see [secrets.md](secrets.md) | |
| E0260-E0294 | devices, keys and attestation: see [devices-and-attestation.md](devices-and-attestation.md) | |
| E0301 | constraint type violated by a known value: `constraint of Positive (value > 0) does not hold for p = (-1) at line 2` | fix the value or the constraint |
| E0401 | builder never consumed on some path (end of scope, a `return`, a `?`, one branch only) | finish/return/pass it on every path |
| E0402 | builder used more than once | use each builder value once; rebind the result of `push` |
| E0403 | builder bound outside a loop or lambda used inside it | thread builders through tail calls, not `for`/`while`/lambdas |
| E0404 | builder type inside another type (field, element, closure) | builders only as locals and parameters |
| E0410 | bad vector type: `Vec(Int) needs a lane count: Vec(T, N)`, a lane type other than 8-64-bit Int/UInt or Float/Float(32), a lane count other than 2-64 (powers of two) | `Vec(Int(32), 8)` |
| E0411 | a vector inside another type (list, option, field, variant payload) or captured by a lambda or spawn | keep vectors in locals, parameters and results |
| E0412 | a vector literal or `splat()`/`lanes()` with no vector type from its context | bind it to a `Vec` local, return it, or pass it as an argument first |
| E0413 | an f-string format flag the value's type cannot mean: `` `hex` needs an integer; Str has no radix to change`` | `hex`/`oct`/`bin` need an integer, `precision` a Float or Dec (ignored on a Dec at present), `trim` a Dec, a style a Float, `group` and the sign flags a number, `upper`/`lower` an integer or text; some pairs conflict (`hex` with `precision` or `group`, `trim` with `precision`) |
| E0901 | `known(x)`: the value is residual (not known at compile time) | make it known, or drop the assertion |
| E0902 | compile-time evaluation would nest past the compiler's stack | raise `RESID_STACK_MB`, or bound the reduction (`--reduce-budget N`) |
| E0903 | an `@fold` function's call did not reduce: `@fold function f: the call at line 3 must reduce at compile time, but its arguments are not all known` | pass known arguments, or drop `@fold` |
| E0904 | a malformed `@reduce`: not `@reduce(steps = N)` with N > 0 or `steps = unbounded`, combined with `@fold`, or on an `@link` function | fix the annotation |

Three of the less obvious ones:

```resid
//! compile-error: E0213
@requires(display(readonly))       // display has no modes
Int main() { return 0; }
```

```resid
//! compile-error: E0904
@reduce(steps = 0)                 // N must be > 0, or `unbounded`
Int f() { return 1; }
```

```resid
//! compile-error: E0412
Int main() {
    println(f"{splat(1)}");        // splat() has no Vec type to take
    return 0;
}
```

Driver-level errors without a code:

- ``error: release builds require a signing key: set RESID_SIGNING_KEY or run `residc keygen` (or build with --profile debug)``
- `error: --runtime-internals is only for building the compiler (compiler/driver.resid) or the runtime (runtime/rt/)`
- `clang: error: no such file or directory: 'build/boot/rt.ll'`: use an
  installed `residc` (`./install.sh`), the checkout's `build/boot/residc`, or
  set `RESID_HOME` to the checkout's `build/boot`.
- ``test error: no `test "..." { ... }` blocks found in FILE`` /
  `test error: FILE defines main(); a test file's entry point is generated`.

## Common E0001 messages

| Message | Cause | Fix |
|---|---|---|
| `undefined variable X` | name not bound; a named function used as a value | bind it; wrap functions `lambda(x) { f(x) }` |
| `unknown function f` | no such function or builtin | check spelling / `pub` / import |
| `binding x: expected A, got B` | initializer type differs | convert (`i64(..)`, `(Float)..`, `f"{..}"`) |
| `call f expects (A), got (B)` | argument type mismatch (also constraint-typed params given `Int`) | convert the argument |
| ``shadowing: `x` is already bound in this scope`` | reused name in a nested scope or a parameter name | pick a new name (`x2`, `next_x`) |
| `cannot assign: bindings are immutable ...` | `x = ...;` | bind a new name or recurse |
| `binding y: implicit narrowing from Int to Int(8) requires an explicit cast` | wider value into narrower slot | explicit checked conversion `i8(..)` or `wrapping_i8(..)` |
| `cannot mix signed and unsigned operands in one operation: Int + UInt` | mixing `Int` and `UInt` | convert one side |
| ``match is not exhaustive: not every variant is covered (add the missing arm(s) or a trailing `_ => ...`)`` | missing arm | add arms or `_ => ...` |
| `match arm pattern must be a variant name or _` | literal pattern (`1 =>`, `"a" =>`) | use `if` chains |
| `expected , or ) in match arm pattern` | nested pattern `Some(Some(x))` | match twice |
| `malformed type declaration` | a type alias without its `;`, or variants without `\|` between them | `type Meters = Int;`, `type Shape = Circle(Float) \| Rect(Float, Float);` |
| `cannot index Str` | `s[i]` on a `Str` | `str_char_at(s, i)` / `str_slice` |
| ``expected `in` in for statement`` | `for (x in xs)` | `for (Int x in xs)` |
| `for-in over non-iterable Set(Int)` / `Map(Str, Int)` | iterating Set/Map | `s.to_list()`, `m.keys()` |
| `unsupported method m` | no such method on that type | see stdlib.md for the method list |
| `unknown provider method environment.has` | verb does not exist | see capabilities-and-security.md |
| `closure literal needs a closure(..) expected type` | lambda where no closure type is expected (e.g. an f-string hole) | bind to `Ret closure(..) name = lambda...` first |
| `function f can reach its end without a return (it returns Int)` | a path with no `return` | return on every path |
| `` `?` returns early, so it needs a function that returns an Option or Result `` | `?` in `main` or another plain function | `else { }` or `match` |
| `an if expression needs an else branch (it yields Int)` | value-producing `if` without `else` | add `else` |
| `operator == compares numbers, Bool and Str; compare the parts of a Px (...), or declare Eq(Px) = f` | `==` on records/lists/options/sums | compare fields, `match`, or declare `Eq(Px)` |
| `filesystem.write_secret expects (Str,List(Int)), got (Str,Str)` | provider argument types | pass the declared types |
| `expected , or ) in lambda parameters` | typed lambda params `lambda(Int x)` | `lambda(x)` |
| `return without a value in a Void function` | `return;` | restructure with `if/else` |
| `` `else` block yields Void, need payload Int `` | `x else { todo() }` | give a value; use `match` for early exit |
| `expected }, found 1` | `x else { return 1; }`: an `else` block holds no `return` | `if (Some(v) = x) { ... }`, `match`, or `?` |
| `f-string hole is not one expression` | `{1e10}` or other unparsable hole | fix the expression (no scientific literals) |
| `expected a function declaration` | top-level `Int X = 5;`, or a bad annotation | constants are zero-arg functions |
| ``unknown type `Elem`; a type parameter is a single uppercase letter (T, K, V)`` | a multi-letter name used as a type parameter, or a typo | use `T`, `K`, `V`; fix the name |
| `sort(xs) of T needs a behavior: sort(xs, using = Ord(T))` | sorting records/sums with no `Ord(T)` instance | declare `Ord(T) = { .compare = cmp, .least = lo, .greatest = hi };` |
| `behavior Show(Px): impl must have signature (Px) -> Str` | wrong impl signature | fix the signature |
| `behavior Show(Int): numbers, Bool and Str have a fixed display` | an instance for a built-in type | wrap the value in a record |
| `expected ;, found orelse` / `found !` / `found 1` after `try` | non-existent operators (`orelse`, `!!`, `try`) | use `else { }`, `?`, `match` |
| `.sum() needs List(Int) or List(Float), got List(Str)` | wrong element type | fold manually |
| `expected , or ] in list literal, found 2` | missing comma | add it |

## Runtime aborts (exit 134)

`resid: abort: <message>` on stderr: `integer overflow in checked
arithmetic`, `integer division by zero`, `numeric conversion out of range`,
`list index out of bounds: index I, length N`, `assertion failed: MSG`,
`not yet implemented: MSG` (`todo`), `not implemented: MSG`
(`unimplemented`), `irrefutable pattern did not match`, `constraint of T
(...) does not hold`, `dec: division by zero`, `dec: non-integer to Int`,
`memory budget exceeded (N MB); set RESID_MEM_LIMIT (MB) to raise it`.
Inside `spawn` these become `Err(RegionError)`; see
[errors-and-results.md](errors-and-results.md).
