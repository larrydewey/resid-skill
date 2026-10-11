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
| `x ?? d`, `getOrElse(d)` | `opt else { d }` |
| `if let Some(x) = opt` | `if (Some(x) = opt) { ... }` |
| exceptions | `Result(T, E)` + `?`; aborts only for bugs |
| `obj.field = v` | build a new record with every field |
| `switch (n) { case 1: ... }` | `if` chains (`match` patterns are variants or `_`) |
| `s[i]` on a string | `str_char_at(s, i)` (a code point `Int`) |
| `a == b` on records | declare `Eq(T) = eq_fn;` (then `==` calls it), or compare fields |
| generics `fn f<T>(x: T)` | `T f(T x)`; bounds `T: Ord` become `@needs(Ord(T))` |
| interface / trait | `behavior Name(T) { ... }` + an instance per type (a verb is a plain function, writable as `x.f(a)`), a closure record, or a sum type |
| `map(f, xs)` / `filter` | write generic `map_all`/`keep_if` once (see functions-and-closures.md) |
| global mutable state | pass state explicitly; return new state |
| `printf("%5.2f")` | `f"{x:precision 2, width 8}"`; a hole's spec is a list of flags in any order (see types-and-values.md) |
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
- **`==` on records or sum types** without an `Eq(T)` instance: a type
  error; an `Ord` instance does not supply it.
- **Defining `Show` for builtin types** (`Show(Int)`): rejected (numbers,
  Bool and Str have a fixed display). Wrap in a record instead.
- **Calling compiler internals** seen in `compiler/` or `runtime/rt/`
  (`resid_raw_*`, `resid_arena_*`, `resid_bulk_*`, `*_persist*`): E0220.
- **Scientific float literals, `_` digit separators, `try`, `orelse`,
  `unwrap()`, `x.first()`, `s[i]`**: none exist.
- **`s.len()` on a `Str`**: use `str_len(s)` (see the known issues).

## Known issues in the current compiler (commit 5060def; work around them)

| Issue | Workaround |
|---|---|
| `s.len()` on a `Str` compiles and returns garbage (the string's bytes read as a number) | `str_len(s)` |
| A signed argument to an unsigned parameter passes silently: `Int(32)` `-5` given to a `UInt` parameter arrives as 18446744073709551611 | convert explicitly, and check the sign first |
| A behavior of your own that declares a prelude verb's name (`behavior Mine(T) { Str show(T x); }`) compiles, but `show(x)` goes to the prelude's `Show`, with no diagnostic | give your verbs names the prelude does not use |
| A function returning a constraint type (`type Positive = Int where value > 0;` `Positive mk(Int x)`): binding its result is "expected Positive, got Positive", and printing `f"{mk(rt(5))}"` crashes | return the base type (`Int mk(Int x)`) and bind it to a `Positive` at the call site |
| `'\x41'` is refused as a character literal (`\x takes two hex digits`) | the code point as a number (`65`) |
| `'\0'` inside an f-string hole is refused (a Str cannot hold NUL) | bind it first: `Int nul = '\0';` then `f"{nul}"` |
| `wrapping_div(MIN, -1)`: with literal `Int` arguments it folds to 9223372036854775808 (out of range; at run time it is MIN); at `Int(8)` (`wrapping_div(i8(-128), i8(-1))`) the program dies with SIGFPE | test for a `-1` divisor and negate with `wrapping_sub(0, x)` |
| `{d:precision 2}` on a `Dec` is accepted but ignored: all N digits print | round with `dN(...)` to fewer significant digits, or `{d:trim}` |
| `checked_add`/`checked_sub`/`checked_mul` wrap (`checked_add(MAX, 1)` is MIN) | plain `+ - *`, which are checked and abort on overflow, or compare against `x.max()` first |
| `min(x)`/`max(x)` for `Bounded` is refused ("expects (), got (Int(8))") although the spec allows it | `x.min()`, or `Int(8) lo = min();` |
| An instance record naming a verb twice (`{ .surface = a, .perimeter = a, .surface = b }`) is accepted; the first entry wins | name each verb once |
| `expect(x).toEqual(y)` on a List, Set, Map or record always passes (`toNotEqual` always fails) | compare `f"{x}"` text or the parts ([testing.md](testing.md)) |
| `residc test` finds no `test` block that directly follows a record declaration | put a function (or the tests) between them |
| `using = f` on a generic call reaches the copy's verb calls, operators and `sort`, but not its f-string holes: `f"{x}"` still uses the type's own `Show` | call `show(x)` in the generic body instead of a bare hole |

```resid
type Task = { Str name; };
Str plain(Task t) { return "plain"; }
Str fancy(Task t) { return "fancy"; }
Show(Task) = plain;

@needs(Show(T))
Str by_verb(T x) { return "[" + show(x) + "]"; }
@needs(Show(T))
Str by_hole(T x) { return f"[{x}]"; }

Int main() {
    Task t = Task {.name = "a"};
    println(f"{by_verb(t, using = fancy)} {by_hole(t, using = fancy)}");   //> [fancy] [plain]
    return 0;
}
```

Language limits (by design or not yet implemented; not bugs): no
run-time dispatch (behaviors resolve at compile time, and a verb is a plain
function that may be *written* as `x.f(a)`), no generic lambdas,
flat match patterns only (a variant with one binding per payload, or `_`;
no nested, literal or guard patterns), no `s[i]` on `Str`, no global
constants, no `try`/`orelse`/`unwrap`, no scientific float literals or `_`
separators, `Void` functions cannot `return;`, lambdas take untyped
parameters, named functions are not values, `for` cannot iterate a
`Set`/`Map` directly (iterate `m.keys()`), maps iterate in hash order.
