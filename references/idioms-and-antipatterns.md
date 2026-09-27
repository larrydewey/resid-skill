# Idioms, anti-patterns and known issues

## Translating habits from other languages

| You would write | Write in Resid |
|---|---|
| `x = x + 1` in a loop | a tail-recursive function with `x` as a parameter |
| `for i in ...: total += f(i)` | `Int sum(Int i, Int n, Int acc)` with `return sum(i + 1, n, acc + f(i));` |
| `list.append(x)` in a loop | `ListBuf(T)` parameter: `acc.push(x)`, `.finish()` at the end |
| `s += piece` in a loop | `StrBuf` parameter, or a pure `acc + piece` tail accumulator |
| `const LIMIT = 10` | `Int limit() { return 10; }` |
| `null` / `nil` | `Option(T)`: `None` / `Some(v)` |
| exceptions | `Result(T, E)` + `?`; aborts only for bugs |
| `obj.field = v` | build a new record with every field |
| `switch (n) { case 1: ... }` | `if` chains (match only takes variants) |
| `s[i]` on a string | `str_char_at(s, i)` (a code point `Int`) |
| `a < b` on strings | a code-point comparison function, or `sort` of a list |
| `a == b` on records/lists | an `eq` function comparing fields/elements |
| generics `fn f<T>(x: T)` | one function per concrete type, or a closure parameter |
| interface / trait | a behavior instance (orderings, Show), a closure record, or a sum type |
| `map(f, xs)` / `filter` | write `map_ints`/`filter_ints` once (see functions-and-closures.md) |
| global mutable state | pass state explicitly; return new state |
| `printf("%5.2f")` | f-strings plus your own padding/rounding helpers; `Dec(N)` for fixed decimals |
| reading a file anywhere | read in `main` (with `@requires`), pass the text to pure code |

## Idioms

**Index walk with base case first.**

```resid
Int count_if_neg(List(Int) xs, Int i, Int acc) {
    if (i >= xs.len()) { return acc; }
    Int add = if (xs[i] < 0) { 1 } else { 0 };
    return count_if_neg(xs, i + 1, acc + add);
}

Int main() {
    println(f"{count_if_neg([1, -2, -3, 4], 0, 0)}");   //> 2
    return 0;
}
```

**State record for loops with many variables.**

```resid
type Stats = { Int n; Int sum; Int max; };

Stats step(Stats s, Int v) {
    return Stats {.n = s.n + 1, .sum = s.sum + v, .max = max(s.max, v)};
}

Stats run(List(Int) xs, Int i, Stats s) {
    if (i >= xs.len()) { return s; }
    return run(xs, i + 1, step(s, xs[i]));
}

Int main() {
    Stats s = run([4, 9, 2], 0, Stats {.n = 0, .sum = 0, .max = 0});
    println(f"{s.n} {s.sum} {s.max}");   //> 3 15 9
    return 0;
}
```

**Parse, don't validate: turn text into typed values at the edge.**

```resid
type Cmd = Push(Int) | Pop | Bad(Str);

Cmd parse_cmd(Str line) {
    List(Str) w = str_split(str_trim(line), " ");
    if (w[0] == "pop") { return Pop; }
    if (w[0] == "push" && w.len() == 2 && str_is_int(w[1])) { return Push(str_parse_int(w[1])); }
    return Bad(line);
}

List(Int) pop(List(Int) stack) {
    return if (stack.len() > 0) { stack[0..stack.len() - 1] } else { stack };
}

List(Int) exec(List(Str) lines, Int i, List(Int) stack) {
    if (i >= lines.len()) { return stack; }
    // Arms stay branch-free (see known issues): the `if` lives in pop().
    List(Int) next = match parse_cmd(lines[i]) {
        Push(v) => stack.concat([v]),
        Pop => pop(stack),
        Bad(s) => stack
    };
    return exec(lines, i + 1, next);
}

Int main() {
    List(Int) empty = [];
    List(Int) st = exec(["push 3", "push 4", "pop", "push 10", "oops"], 0, empty);
    println(f"{st.len()}: {st[0]} {st[1]}");   //> 2: 3 10
    return 0;
}
```

**Thin effectful shell, pure core.** `main` gathers inputs (args, files,
env) under `@requires`, calls pure functions, prints. Pure functions need
no grants, fold at compile time when their inputs are known, and are easy
to test.

**Readable output.** Define `Show` for your types; join lists yourself;
`sort(m.keys())` before printing a map.

**Make runtime values explicit in tests and benchmarks** with `rt`.

## Anti-patterns

- **Assuming C-style loops exist.** `for (Int i = 0; ...)`, `while (i < n)`
  with a counter, `i = i + 1`: none can work without assignment.
- **Prepending or re-reading an accumulator in a loop**: quadratic
  ([performance-and-memory.md](performance-and-memory.md)).
- **Reusing a builder** or pushing to a builder inside `for`: E0402/E0403.
- **Printing a `Result`, an `Option` of records, a list of records or a
  payload-less variant without `Show`**: gives `Some(..)`, `Some<Option(T)>`,
  `…`, `null`. Match and format explicitly.
- **Relying on map iteration order**: it is hash order.
- **Forgetting `@requires` up the call chain**: every caller needs the
  grant, not just the function that touches the provider.
- **Using `?` in `main`**: handle errors there with `else`/`match`.
- **Literal-only products that need headroom**: `Int(128) x = a_lit * b_lit;`
  computes in `Int(64)`. Widen one operand.
- **Constraint types as validation**: they do not check run-time values.
- **Missing return path**: a non-Void function whose last path has no
  `return` still compiles and returns garbage; end every function with a
  `return` (or an if/else where both branches return).
- **Calling compiler internals** seen in `compiler/` or `runtime/rt/`
  (`resid_raw_*`, `resid_arena_*`, `resid_bulk_*`, `*_persist*`): E0220.
- **Scientific float literals, `_` digit separators, `{{` in f-strings,
  `try`, `orelse`, `unwrap()`, `x.first()`, `s[i]`**: none exist.

## Known issues in the current compiler (observed; work around them)

| Issue | Workaround |
|---|---|
| A `match` arm containing control flow (`if` expression, `?:`, `&&`/`||`, a nested `match`, `x else { }`) produces broken LLVM IR (`PHI node entries do not match predecessors!`) | keep arms branch-free: move the logic into a helper function called from the arm, or use `if (V(x) = e)` |
| `==`/`!=` on records, lists, `Option`, sums fails in clang | compare fields or `match` |
| A missing return path is not diagnosed (returns garbage) | always end with `return` |
| Missing `import` file is silently ignored | double-check paths when names are `undefined` |
| `residc test` binaries fail to link (`_start` missing) | explicit registration with `lib/testing.resid` |
| `f"{result}"` prints `Some(..)`/`None` for `Ok`/`Err` | match first |
| Lists from `keys()`/`to_list()` print as `list(..)`; list prefix depends on type spelling | join elements yourself |
| `Show(Int)` etc. are ignored; `Show` not applied inside lists/options | format explicitly |
| Behavior instance types must be single identifiers | wrap in a record |
| Two instances sharing one impl function → clang redefinition | one impl per instance |
| `sort(xs)` of a user type needs `using =` even with one instance | pass `using = Ord(T)` |
| Lambda without a typed context (`return lambda..`, record field) fails | bind to a typed name first |
| Lambda capturing and calling another closure variable fails in codegen | inline or call a named function |
| Several list literals in lambdas of one function → duplicate `@.lty` global | move literals into helpers |
| `Void closure` body ending in `println` is `Bool` | call a `Void` helper |
| `?` in `main` fails in clang | handle in main |
| Constraint types unchecked for residual values | `rt_assert` / `if` |
| `@requires(fs(badmode))` is accepted silently (E0213 only fires in sandboxes) | spell modes `readonly`/`readwrite` |
| `filesystem.write_secret` aborts with `out of memory` (it still creates the 0600 file) | avoid until fixed |
| `Bytes.len()` returns garbage | use `List(Int)` for bytes |
| `lib/crypto.resid` `base64_encode` mis-pads (`aGk==` for "hi") | check library output against test vectors |
| `rt 1.5m` does not parse | `d4(rt 1)` style |
| `git` provider from the spec is not implemented | use `process.run("git ...")` (exit status only) |
| `toBeCloseTo(x, tol)` takes an Int absolute tolerance | `expect(abs(a - b) < 0.000001).toBeTrue()` |
| `if` expression without `else` yields a zero value | always write `else` |

When you hit a clang error about the generated `.ll`, the construct on the
reported source line is almost always one of the above.
