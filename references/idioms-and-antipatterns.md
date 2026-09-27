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
| `a == b` on records | declare `Eq(T) = eq_fn;` (then `==` calls it), or compare fields |
| generics `fn f<T>(x: T)` | `T f(T x)`; bounds `T: Ord` become `@needs(Ord(T))` |
| interface / trait | `behavior Name(T) { ... }` + an instance per type (no methods), a closure record, or a sum type |
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

**Readable output.** Define `Show` for your types (it applies inside lists,
options and records too); `sort(m.keys())` before printing map entries in
order.

**Make runtime values explicit in tests and benchmarks** with `rt`.

## Anti-patterns

- **Assuming C-style loops exist.** `for (Int i = 0; ...)`, `while (i < n)`
  with a counter, `i = i + 1`: none can work without assignment.
- **Prepending or re-reading an accumulator in a loop**: quadratic
  ([performance-and-memory.md](performance-and-memory.md)).
- **Reusing a builder** or pushing to a builder inside `for`: E0402/E0403.
- **Relying on map iteration order**: it is hash order.
- **Forgetting `@requires` up the call chain**: every caller needs the
  grant, not just the function that touches the provider.
- **Literal-only products that need headroom**: `Int(128) x = a_lit * b_lit;`
  computes in `Int(64)`. Widen one operand.
- **Constraint types as validation of user input**: a failing residual value
  aborts the process; validate with `if` and return a `Result` instead.
- **Defining `Show` for builtin types** (`Show(Int)`): rejected (numbers,
  Bool and Str have a fixed display). Wrap in a record instead.
- **Calling compiler internals** seen in `compiler/` or `runtime/rt/`
  (`resid_raw_*`, `resid_arena_*`, `resid_bulk_*`, `*_persist*`): E0220.
- **Scientific float literals, `_` digit separators, `{{` in f-strings,
  `try`, `orelse`, `unwrap()`, `x.first()`, `s[i]`**: none exist.

## Known issues in the current compiler (commit 21dd7ab; work around them)

| Issue | Workaround |
|---|---|
| Unknown string escapes (`"\x1f"`) silently drop the backslash | use only `\n \t \r \" \\`; build control characters with `str_from_code(n)` |
| `git` provider from the spec: `@requires(git)` accepted, `git.*` calls do not compile | `process.run("git ...")` (exit status only) |

Language limits (by design or not yet implemented; not bugs): no methods or
run-time dispatch (behaviors resolve at compile time), no generic lambdas,
flat match patterns only (no nested/literal/guard patterns), one
payload per variant, no `s[i]` on `Str`, no global constants, no
`try`/`orelse`/`unwrap`, no scientific float literals or `_` separators, no
`{{` escape, `else { }` blocks cannot `return`, `Void` functions cannot
`return;`, lambdas take untyped parameters, named functions are not values,
`for` cannot iterate a `Set`/`Map` directly, maps iterate in hash order.
