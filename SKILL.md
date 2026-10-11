---
name: resid
description: Write, read, review and debug programs in Resid, the eager compile-time-reducing language with immutable values, no shadowing, explicit capabilities (@requires) and a self-hosted LLVM compiler. Use for any .resid file, resid.toml manifest, Resid compiler error (error[E0xxx], E0219 authority, E0401-E0404 builders), residc/stage2.bin invocation, or questions about Resid syntax, types, behaviors, reduction, sandboxing or tooling (resid-why, resid-debug, resid-fmt).
---

# Resid

Resid is a C-syntax, expression-rich language where **the compiler evaluates
everything it can prove** and only the residual computation reaches the
binary. Values are immutable, bindings cannot be reassigned or shadowed,
loops that carry state are tail calls, errors are `Option`/`Result` values,
and **no function touches the outside world without a declared capability**.

This skill was verified against the self-hosted compiler (spec v3.6,
Resid commit 219dcd9, 2026-10-11). Every code block in it compiles;
`scripts/check-examples.sh` re-checks them. For security guarantees, the
Resid repo's `SECURITY.md` is the source of truth (each row names its tests).

## Mental model

1. **Everything is a value; nothing changes.** `Type name = expr;` binds once.
   "Updating" a list, map, string or record returns a new one. The compiler
   reuses storage in place when the old version is dead, so write code in the
   shapes it recognizes (see performance).
2. **State flows through parameters.** A loop is `return loop(i + 1, acc2);`
   (compiled to a jump). `for (T x in range_or_list)` is for effects.
3. **The compiler is an evaluator.** Pure code over known inputs is computed
   at build time. Unknowns enter only via providers, stdin, or `rt expr`.
4. **Authority is explicit and only narrows.** `@requires(filesystem(readonly))`
   on every function that reaches a provider, directly or transitively, up to
   `main`. Sandboxes and spawn lists can only take authority away.
5. **Failure is a value or an abort.** `Result`/`Option` with `?` and
   `else { default }`; bugs (overflow, bad index, failed assert) abort with
   exit 134, or become `Err(RegionError)` inside `spawn`.

## Minimal program

```resid
type Item = { Str name; Int cents; };

Int total(List(Item) xs, Int i, Int acc) {        // loop = tail recursion
    if (i >= xs.len()) { return acc; }
    return total(xs, i + 1, acc + xs[i].cents);
}

@requires(args)                                   // args is a provider
Int main() {
    List(Item) cart = [Item {.name = "tea", .cents = 350}, Item {.name = "cake", .cents = 425}];
    Int sum = total(cart, 0, 0);
    println(f"{cart.len()} items, {sum / 100}.{sum % 100:zero, width 2} total, argc={args.count()}");  //> 2 items, 7.75 total, argc=1
    return 0;                                     // exit code
}
```

## Rules that prevent most errors

- Declarations are C-like: `Int f(Str s, Int n = 3) { ... }`, `Int x = 1;`,
  records `type P = { Int x; Int y; };` built as `P {.x = 1, .y = 2}`.
- **No reassignment, no shadowing** (not even a parameter name in the body,
  not in nested blocks). Sibling blocks may reuse names. Discard with `_ = e;`.
- **Names have a case**: types, behaviors, variants start uppercase; values,
  functions, params, fields lowercase (E0222). One uppercase letter (`T`,
  `N`) is a type parameter, never a type name.
- **No globals**: constants are zero-arg functions. No overloading. A verb
  is a method on its receiver (`x.f(a)` = `f(x, a)`), but a type does not
  carry its own methods.
- **Generics**: `T first(List(T) xs)`, `type Pair(T) = { T a; T b; };`,
  `Int(N)` for any width. A body that sorts/shows/compares a `T` declares
  `@needs(Ord(T))` etc. **Behaviors**: `behavior Area(T) { Float area(T s); }`,
  `Area(Circle) = circle_area;`, call `area(c)` or `c.area()`. A zero-arg
  verb takes its type from the receiver: `x.max()` (Bounded). See
  references/behaviors.md.
- **A name is a verb or a function, never both** (E0231), program-wide:
  don't define a function called `min`, `max`, `least`, `greatest`,
  `show`, `hash`, `eq`, `compare`, `serialize` or `allocate`. Override a
  behavior with an instance or `using =`, not a function. A multi-verb instance is a complete record:
  `Ord(X) = { .compare = f, .least = g, .greatest = h };`.
- `if` is an expression (`Int y = if (c) { 1 } else { 2 };`) and then needs
  its `else`. Branches must have identical types.
- `match` only on sum types (`Option`, `Result`, yours); patterns are flat
  (`V(x)`, `V`, `_`), must be exhaustive. Use `if` chains for numbers/strings.
- Sum variants take any number of payloads: `type Shape = Rect(Float, Float) | Dot;`,
  built `Rect(2.0, 3.0)`, matched `Rect(w, h) =>` (one name per payload).
- `for` needs the element type: `for (Int i in 0..n)`, `for (Str s in xs)`.
  Sets/maps: iterate `s.to_list()` / `m.keys()`.
- Every numeric width is a distinct type; **no implicit narrowing**, no
  signed/unsigned mixing; `+ - * / %` are **checked** (overflow aborts).
  Widen before multiplying: `(Int(128))a * b`. Use `wrapping_*`/`saturating_*`
  when wrap/clamp is intended. Avoid `checked_*` (they wrap) and convert
  signed to unsigned explicitly (an `Int` argument to a `UInt` parameter
  wraps silently).
- Strings: `+`, `==`, f-strings `f"{any_value}"`; length is `str_len(s)`
  (`s.len()` compiles but returns garbage: a compiler bug); no `s[i]` (use
  `str_char_at`), `<` on `Str` works (Ord(Str)), no scientific float
  literals. A hole takes a format spec after `:`, a list of flags **in any
  order**: `{n:8}` (width), `{n:width 8, left}`, `{n:zero, width 6}`,
  `{n:group, hex}`, `{f:precision 2}`, `{s:fill '.', center}`, `{d:trim}`.
  `{{` / `}}` are a literal brace. A flag the value's type cannot mean is a
  compile error, so a typo never reads as "it didn't apply".
- `==` works on numbers, Bool and `Str`, and on types with an `Eq` instance
  (`<` with `Ord`); compare other records/lists by parts.
- Lambdas take their type from context (typed binding, parameter, return
  type, field): `Int closure(Int) f = lambda(x) { x + 1 };`. Named functions
  are not values: wrap them (`lambda(x) { g(x) }`).
- Build strings/lists in loops with `StrBuf` / `ListBuf(T)` threaded through
  tail calls; each builder value is used exactly once.
- `println` takes one `Str`. `print`, `eprintln` likewise.
- Imports are file paths relative to the importing file, falling back to the
  stdlib (`import "crypto.resid";` works anywhere); missing module = E0221.
  Only `pub` functions are visible. Each module has its own names: when two
  imports export one, `import "a.resid" as a;` and write `a.f()` (plain `f()`
  is E0223); your own declarations win.
- Never call `resid_raw_*`, `resid_arena_*`, `resid_bulk_*`, persist copies:
  compiler internals, rejected with E0220.

## Gotchas checklist (review before compiling)

- [ ] Every function using `filesystem`/`environment`/`args`/`process`/
      `network`/`clock`/`terminal`/`display`/`device`/a `@link` native module,
      *or calling one that does*, has `@requires(...)`; `main` covers all.
- [ ] Writes are not under a `readonly` grant.
- [ ] No name bound twice on a nesting path (parameters included).
- [ ] Every sum type in a `match` has an arm or `_`; no literal patterns.
- [ ] `?` only inside functions returning Option/Result, and of the same
      kind (an `Option` inside an `Option` function, a `Result` with the
      same error type inside a `Result` one): a mismatch is not caught.
- [ ] Literal-only arithmetic that needs >64 bits has a widened operand.
- [ ] Loops accumulate via tail calls with builders; no prepending in loops.
- [ ] Map output that must be ordered goes through `sort(m.keys())`.
- [ ] One `Ord(T)` per type (then `sort(xs)` and `<` work); other orders via
      `sort(xs, using = cmp)` or `using = Reverse(Ord(T))`. It is a record
      naming all three verbs: `{ .compare = f, .least = g, .greatest = h }`;
      a bare function is rejected.
- [ ] No function reuses a behavior verb's name (E0231).
- [ ] Generic bodies list what they sort/show/compare in `@needs(...)`.
- [ ] Tests compare lists, maps, sets and records by parts: `toEqual` on
      them always passes (compiler bug, see references/testing.md).

## Workflow

1. **Write** pure functions first; keep providers in a thin `main` layer.
2. **Check** fast: `residc prog.resid --profile check` (type/authority
   errors, no binary).
3. **Build and run**: `residc prog.resid -o prog --profile debug && ./prog`.
   After `./install.sh` in a Resid checkout, `residc` is `~/.resid/bin/residc`
   and works from any directory (no `RESID_HOME`; it also has a signing key).
   Without an install, use the checkout's `build/boot/residc`. Release
   (default profile, `-O2`) needs a signing key (the install's, `residc
   keygen`, or `RESID_SIGNING_KEY`).
4. **Read errors**: `error[E0001]: type error: <message>` with a caret; the
   message says what to change ([references/error-codes.md](references/error-codes.md)).
   `residc test prog.resid` runs its `test "..." { }` blocks. A clang/LLVM
   error about the generated `.ll`, or a result that contradicts these rules,
   may be a compiler bug; see the known-issues table in
   [references/idioms-and-antipatterns.md](references/idioms-and-antipatterns.md).
5. **Runtime abort** (exit 134, `resid: abort: ...` on stderr): overflow,
   index, conversion, assert, `todo`. Use `rt` to reproduce runtime paths;
   `resid-debug` for live inspection.
6. **Understand reduction**: `--dump-reduced out.txt`, `comptime_print(x)`,
   `known(x)`, `resid-why prog` ([references/compile-time-reduction.md](references/compile-time-reduction.md)).

## References

| File | Read when |
|---|---|
| [references/language-tour.md](references/language-tour.md) | first contact; whole surface in one page |
| [references/types-and-values.md](references/types-and-values.md) | numbers, Dec, Str, List/Map/Set, Option/Result, records, sums, fixed-capacity types, printing |
| [references/control-flow.md](references/control-flow.md) | if/match/for, loops as tail recursion, early exit |
| [references/functions-and-closures.md](references/functions-and-closures.md) | defaults, named args, closures, map/filter/fold helpers |
| [references/behaviors.md](references/behaviors.md) | Ord/Show/custom orders, Reverse, strategies, behavioralizing code |
| [references/errors-and-results.md](references/errors-and-results.md) | `?`, `else`, error types, aborts, spawn isolation |
| [references/capabilities-and-security.md](references/capabilities-and-security.md) | @requires, provider verbs, sandbox, spawn, handles, E0219/E0220 |
| [references/testing.md](references/testing.md) | test blocks, lib/testing.resid, matchers, golden tests |
| [references/stdlib.md](references/stdlib.md) | builtin functions, missing math, lib/ modules |
| [references/secrets.md](references/secrets.md) | `Secret(T)`, `declassify`, constant-time rules, secret crypto/TLS APIs |
| [references/devices-and-attestation.md](references/devices-and-attestation.md) | the `device` provider and `lib/dev/`, integrity labels (E0270, E0286, E0291), attestation: `lib/verify/`, `@anchor`, `@policy`, `@decides`, CoRIM, SPDM sessions |
| [references/performance-and-memory.md](references/performance-and-memory.md) | builders, in-place updates, quadratic traps, memory |
| [references/compile-time-reduction.md](references/compile-time-reduction.md) | what folds, rt/known/comptime_print, specialization, notes |
| [references/tooling.md](references/tooling.md) | compiler flags/profiles/env, resid-fmt/why/graph/debug, packages |
| [references/error-codes.md](references/error-codes.md) | every E-code, common messages, post-check failures |
| [references/idioms-and-antipatterns.md](references/idioms-and-antipatterns.md) | translating habits, idioms, anti-patterns, **known compiler issues** |

`examples/` holds 25 complete programs with their exact expected output
(`NAME.out`): hello, fizzbuzz, word count, shapes, results, behaviors,
closures, files, numbers, fixed capacity, spawn, sandbox, reduction, testing,
args/env, tokenizer, BFS, crypto, records, stdin filter, readline REPL,
HTTP server and client, generics, user-defined behaviors, regex.
