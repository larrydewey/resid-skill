# Error codes and messages

Compiler diagnostics print as `error[CODE]: message` followed by
`--> file:line:col` and a caret line. Most type and syntax problems share
`E0001`; the message text is what tells you the fix. Messages below are
quoted from the current compiler.

## Coded errors

| Code | Meaning | Typical fix |
|---|---|---|
| E0001 | type or syntax error (message says which; see next section) | read the message |
| E0211 | a function inside a sandbox calls one whose `@requires` exceeds the sandbox ceiling ("attenuation is transitive across the call closure") | move the callee out, narrow its needs, or widen the sandbox if you own it |
| E0212 | a function's needs exceed its ceiling: `function f requires capability c which exceeds the effective capability ceiling [...]`, or a **write** under a read-only grant (`provider call filesystem.write_all is a write operation, but only a read-only grant ...`), or a `File` handle entering a region without `filesystem` | grant the right mode; keep writes out of read-only sandboxes |
| E0213 | unknown capability mode in a sandbox/ceiling: `supported modes are readonly and readwrite` | use `family(readonly)` or `family(readwrite)` |
| E0214 | `spawn (caps)` lists a capability beyond the parent's, or its body uses one not listed: `spawn body uses capabilities its list [..] does not grant: process` | add it to the spawn list (and the parent's `@requires`) or move the call out |
| E0215 | inside a spawn/restricted region, a call to a function whose `@requires` is not granted there | same as E0214 |
| E0216 | `import "m" @requires(...)` after `m` was already imported without the bound | import it attenuated first (or only) |
| E0218 | a provider call in a restricted region whose family is not granted: `provider call family filesystem is not granted to this region's capability set [network]` | grant it or remove the call |
| E0219 | no ambient authority: `function main uses (through save) capability filesystem but is not granted it: declare @requires(filesystem) on it`; also for `test` blocks | add the named `@requires(...)` to that function, and to each caller up to `main` |
| E0220 | runtime internal used: `resid_arena_push is a runtime internal of the compiler, not part of the language` | never use `resid_raw_*`, `resid_arena_*`, `resid_bulk_*`, persist copies, `@export`/`@import` |
| E0301 | constraint type violated by a known value: `constraint of Positive (value > 0) does not hold for p = -1` | fix the value or the constraint |
| E0401 | builder never consumed on some path | finish/return/pass it on every path |
| E0402 | builder used twice | use each builder value once; rebind the result of `push` |
| E0403 | builder from outside a loop used inside it, or captured by a lambda | thread builders through tail calls, not `for`/`while`/lambdas |
| E0404 | builder type inside another type | builders only as locals and parameters |
| E0901 | `known(x)`: the value is residual | make it known, or drop the assertion |

Driver-level errors without a code:

- `error: release builds require a signing key: set RESID_SIGNING_KEY or run residc keygen (or build with --profile debug)`
- `error: --runtime-internals is only for building the compiler ...`
- `clang: error: no such file or directory: 'build/boot/rt.ll'`: set
  `RESID_HOME` to the checkout's `build/boot` or run from the checkout root.
- `test error: no test "..." { ... } blocks found` / `defines main()`.

## Common E0001 messages

| Message | Cause | Fix |
|---|---|---|
| `undefined variable X` | name not bound; a named function used as a value; a failed (silently skipped) import | bind it; wrap functions `lambda(x) { f(x) }`; check the import path |
| `unknown function f` | no such function or builtin | check spelling / `pub` / import |
| `binding x: expected A, got B` | initializer type differs | convert (`i64(..)`, `(Float)..`, `f"{..}"`) |
| `call f expects (A), got (B)` | argument type mismatch (also constraint-typed params given `Int`) | convert the argument |
| `shadowing: x is already bound in this scope` | reused name in a nested scope or a parameter name | pick a new name (`x2`, `next_x`) |
| `cannot assign: bindings are immutable ...` | `x = ...;` | bind a new name or recurse |
| `implicit narrowing from Int(64) to Int(8)` | wider value into narrower slot | explicit checked conversion `i8(..)` or `wrapping_i8(..)` |
| `... signed and unsigned ...` | mixing `Int` and `UInt` | convert one side |
| `match is not exhaustive: not every variant is covered` | missing arm | add arms or `_ => ...` |
| `match arm pattern must be a variant name or _` | literal pattern (`1 =>`, `"a" =>`) | use `if` chains |
| `expected ) in match arm pattern` | nested pattern `Some(Some(x))` | match twice |
| `malformed type declaration` | variant with two payloads `A(Int, Int)` | one payload: `A(Pair)` |
| `cannot index Str` | `s[i]` on a `Str` | `str_char_at(s, i)` / `str_slice` |
| `operator < between Str and Str` | ordering strings | compare code points (see behaviors.md) or `sort` a list |
| `expected in in for statement` | `for (x in xs)` | `for (Int x in xs)` |
| `for-in over non-iterable Set(Int)` | iterating Set/Map | `s.to_list()`, `m.keys()` |
| `unsupported method m` | no such method on that type | see stdlib.md for the method list |
| `unknown provider method environment.has` | verb does not exist | see capabilities-and-security.md |
| `closure literal needs a closure(..) expected type` | lambda without a typed context | bind to `Ret closure(..) name = lambda...` first |
| `closure body returns Bool, expected Void` | `Void closure` whose body ends in `println(..)` | call a `Void` helper, or use `Bool closure` |
| `expected , or ) in lambda parameters` | typed lambda params `lambda(Int x)` | `lambda(x)` |
| `return without a value in a Void function` | `return;` | restructure with `if/else` |
| ``else` block yields Void, need payload Int`` | `x else { todo() }` or `return` in `else` | give a value; use `match` for early exit |
| `f-string hole is not one expression` | `{1e10}` or other unparsable hole | fix the expression (no scientific literals) |
| `expected a function declaration` | top-level `Int X = 5;`, or a bad annotation | constants are zero-arg functions |
| `call ident expects (T), got (Int)` | generic function `T f(T x)` | write concrete functions |
| `sort(xs) of T needs a behavior: sort(xs, using = Ord(T))` | sorting records/sums | define a comparator instance and pass `using =` |
| `behavior Show(T): impl must have signature (T) -> Str` | wrong impl signature, or `T` not a single identifier | fix the signature; wrap non-identifier types in a record |
| `expected ;, found orelse` / `found f` after `try` | non-existent operators | use `else { }`, `?`, `match` |
| `.sum() needs List(Int) or List(Float)` | wrong element type | fold manually |
| `expected , or ] in list literal` | missing comma | add it |

## Failures after type checking

These have no E-code. They mean the checker accepted a construct that a
later stage cannot handle; rewrite the construct.

| Symptom | Usual cause | Rewrite |
|---|---|---|
| clang: `'%tN' defined with type 'ptr' but expected 'i64'` near `icmp eq` | `==`/`!=` on records, lists, options or sums | compare fields / write an `eq_*` function / `match` |
| LLVM: `PHI node entries do not match predecessors!` / `Instruction does not dominate all uses!` | control flow (`if` expr, `?:`, `&&`, `||`, nested `match`, `else { }` default) inside a `match` arm | move the arm's logic into a helper function |
| clang: `value doesn't match function result type 'i32'` | `?` used in `main` | handle the error in main with `else`/`match` |
| clang: `invalid redefinition of function '__cmp_f'` | two behavior instances share one impl, or a duplicated instance | one impl function per instance |
| clang: `redefinition of global '@.ltyN'` | list literals inside several lambdas of one function | move literals into helper functions |
| `codegen error: undefined variable f` | a lambda capturing and calling another closure variable | inline the inner lambda or call a named function |
| `codegen error: closure literal needs a closure(..) expected type` | returning or storing an untyped lambda | bind it to a typed name first |
| `ld.lld: warning: cannot find entry symbol _start` from `residc test` | current test-runner link bug | use explicit registration (lib/testing.resid) |

## Runtime aborts (exit 134)

`resid: abort: <message>` on stderr: `integer overflow in checked
arithmetic`, `integer division by zero`, `numeric conversion out of range`,
`list index out of bounds: index I, length N`, `assertion failed: MSG`,
`not yet implemented: MSG`, `irrefutable pattern did not match`,
`dec: division by zero`, `dec: non-integer to Int`, `memory budget exceeded
(N MB); set RESID_MEM_LIMIT (MB) to raise it`. Inside `spawn` these become
`Err(RegionError)`.
