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
Resid commit 79f9062). Every code block in it compiles; `scripts/check-examples.sh`
re-checks them.

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
    println(f"{cart.len()} items, {sum / 100}.{sum % 100} total, argc={args.count()}");  //> 2 items, 7.75 total, argc=1
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
- **No globals**: constants are zero-arg functions. No overloading, no
  methods on types (but `x.f(a)` = `f(x, a)`).
- **Generics**: `T first(List(T) xs)`, `type Pair(T) = { T a; T b; };`,
  `Int(N)` for any width. A body that sorts/shows/compares a `T` declares
  `@needs(Ord(T))` etc. **Behaviors**: `behavior Area(T) { Float area(T s); }`,
  `Area(Circle) = circle_area;`, call `area(c)`. See references/behaviors.md.
- `if` is an expression (`Int y = if (c) { 1 } else { 2 };`) and then needs
  its `else`. Branches must have identical types.
- `match` only on sum types (`Option`, `Result`, yours); patterns are flat
  (`V(x)`, `V`, `_`), must be exhaustive. Use `if` chains for numbers/strings.
- Sum variants carry at most one payload: `Rect(Dims)`, not `Rect(Float, Float)`.
- `for` needs the element type: `for (Int i in 0..n)`, `for (Str s in xs)`.
  Sets/maps: iterate `s.to_list()` / `m.keys()`.
- Every numeric width is a distinct type; **no implicit narrowing**, no
  signed/unsigned mixing; `+ - * / %` are **checked** (overflow aborts).
  Widen before multiplying: `(Int(128))a * b`. Use `wrapping_*`/`saturating_*`
  when wrap/clamp is intended.
- Strings: `+`, `==`, f-strings `f"{any_value}"`; no `s[i]` (use
  `str_char_at`), `<` on `Str` works (Ord(Str)), no `{{` escape, no
  scientific float literals.
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

- [ ] Every function using `filesystem`/`environment`/`args`/`process`/TCP,
      *or calling one that does*, has `@requires(...)`; `main` covers all.
- [ ] Writes are not under a `readonly` grant.
- [ ] No name bound twice on a nesting path (parameters included).
- [ ] Every sum type in a `match` has an arm or `_`; no literal patterns.
- [ ] `?` only inside functions returning Option/Result.
- [ ] Literal-only arithmetic that needs >64 bits has a widened operand.
- [ ] Loops accumulate via tail calls with builders; no prepending in loops.
- [ ] Map output that must be ordered goes through `sort(m.keys())`.
- [ ] One `Ord(T)` per type (then `sort(xs)` and `<` work); other orders via
      `sort(xs, using = cmp)` or `using = Reverse(Ord(T))`.
- [ ] Generic bodies list what they sort/show/compare in `@needs(...)`.

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
   error about the generated `.ll` means a construct the compiler mishandles;
   see the known-issues table in
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
| [references/performance-and-memory.md](references/performance-and-memory.md) | builders, in-place updates, quadratic traps, memory |
| [references/compile-time-reduction.md](references/compile-time-reduction.md) | what folds, rt/known/comptime_print, specialization, notes |
| [references/tooling.md](references/tooling.md) | compiler flags/profiles/env, resid-fmt/why/graph/debug, packages |
| [references/error-codes.md](references/error-codes.md) | every E-code, common messages, post-check failures |
| [references/idioms-and-antipatterns.md](references/idioms-and-antipatterns.md) | translating habits, idioms, anti-patterns, **known compiler issues** |

`examples/` holds 21 complete programs with their exact expected output
(`NAME.out`): hello, fizzbuzz, word count, shapes, results, behaviors,
closures, files, numbers, fixed capacity, spawn, sandbox, reduction, testing,
args/env, tokenizer, BFS, crypto, records, stdin filter, readline REPL.
