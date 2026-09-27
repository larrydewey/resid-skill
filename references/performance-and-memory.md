# Performance and memory

Resid exposes no storage control: no pointers, no `free`, no allocation API,
no mutable arrays. The compiler decides storage, and it *does* update values
in place when it can prove nobody can observe the old version. Writing code
in the shapes it recognizes is the whole performance game.

## The mental model

1. Values are immutable. `m.insert(k, v)`, `xs.concat([x])`, `s + t` are
   specified to return new values.
2. The compiler's ownership analysis makes an update **in place** when the
   old value is dead: e.g. a `Map` parameter that a tail call consumes
   (`return loop(i + 1, m.insert(k, v))`) and that nothing else reads
   afterwards.
3. Loops are tail calls; the compiler reclaims each iteration's garbage
   (loop regions, scalar scopes) when what the loop carries is scalars,
   maps/sets of scalars/strings, or lists.
4. Where the analysis cannot prove linearity, you get a copy (correct, but
   possibly O(n) per step, so O(n^2) overall).
5. Linear builders (`StrBuf`, `ListBuf(T)`) make the in-place guarantee
   explicit and checked.

## Strings: StrBuf

```resid
StrBuf csv_row(List(Int) xs, Int i, StrBuf b) {
    if (i >= xs.len()) { return b; }
    StrBuf b2 = if (i == 0) { b } else { b.push_char(',') };
    return csv_row(xs, i + 1, b2.push(f"{xs[i]}"));
}

Int main() {
    StrBuf b0 = StrBuf();
    StrBuf b1 = b0.push("row: ");
    Str s = csv_row([1, 22, 333], 0, b1).finish();
    println(s);                                  //> row: 1,22,333
    return 0;
}
```

`StrBuf()` makes an empty builder; `b.push(Str)` and `b.push_char(Int)`
return the builder to use next; `b.finish()` returns the `Str`. Push is
amortized O(1).

## Lists: ListBuf(T)

```resid
ListBuf(Int) squares(Int i, Int n, ListBuf(Int) acc) {
    if (i >= n) { return acc; }
    return squares(i + 1, n, acc.push(i * i));
}

Int main() {
    ListBuf(Int) empty = ListBuf();              // T comes from the binding
    List(Int) sq = squares(0, 100000, empty).finish();
    ListBuf(Str) w = ListBuf();
    List(Str) words = w.push("a").push("b").finish();
    println(f"{sq.len()} {sq[99999]} {words.len()}");   //> 100000 9999800001 2
    return 0;
}
```

## Linearity rules for builders (E0401-E0404)

Every builder value must be used **exactly once** on every path:

| Code | Violation |
|---|---|
| E0401 | a builder is never consumed on some path (end of scope, or a `return` that does not consume it) |
| E0402 | a builder is used twice (same expression, same path, or after it was consumed) |
| E0403 | a builder bound outside a loop is used inside the loop body, or captured by a lambda |
| E0404 | a builder type inside another type (struct field, List/Map/Set/Option/Result element, closure type) |

Branches (`if`/`else`, `match` arms, `?:`, `else { }`) must consume the same
builders, except a branch that leaves by `return`/`break`/`continue`.
Passing a builder to a function or returning it counts as one use. The right
operand of `&&`/`||` must not consume an outer builder.

```resid
//! compile-error: E0402
Int main() {
    StrBuf b = StrBuf();
    StrBuf c = b.push("a");
    StrBuf d = b.push("b");       // b already consumed
    println(c.finish());
    println(d.finish());
    return 0;
}
```

```resid
//! compile-error: E0401
Int main() {
    StrBuf b = StrBuf();
    if (true) { println(b.finish()); }   // not consumed on the else path
    return 0;
}
```

```resid
//! compile-error: E0404
type Holder = { StrBuf b; };
```

So builders flow through **tail-recursive functions as parameters**, not
through `for` loops.

## String accumulators without StrBuf

A self tail call that only ever does `acc + piece` with its `Str` parameter
is rewritten to append in place. It stops being in place, silently, when the
accumulator is read in any other way:

| Shape | Cost for n steps (measured) |
|---|---|
| `return loop(i + 1, acc + "x");` | linear: 1,000,000 steps in 3 ms |
| `if (str_len(acc) >= n) ...` then `acc + "x"` (acc read elsewhere) | quadratic: 80,000 steps 0.93 s |
| `return loop(i + 1, "x" + acc);` (prepend) | quadratic: 80,000 steps 0.77 s |
| `return "x" + rec(i + 1);` (non-tail) | quadratic: 80,000 steps 0.79 s |
| `StrBuf` push | linear: 1,000,000 steps in 4 ms |

Rule: in a loop, build text with `StrBuf` (or the pure `acc + piece`
accumulator). Never prepend in a loop; build forward and reverse, or collect
pieces in a `ListBuf(Str)` and `str_join`.

## Lists without ListBuf

`return loop(i + 1, acc.concat([x]));` is amortized O(1) per append in a tail
loop (1,000,000 appends in about 22 ms vs 4 ms with `ListBuf`). Indexing
`xs[i]` is fast; the compiler drops the bounds check when it can prove
`0 <= i < xs.len()` (for example inside `for (Int i in 0..xs.len())` or
after `if (i < xs.len())` with `i >= 0`).

Avoid rebuilding a list to change one element (`xs[0..i].concat([v]).concat(xs[i + 1..])`
is O(n)). If you need random updates, use a `Map(Int, T)` keyed by index.

## Maps and sets

Thread the map through a tail call and update it exactly once per path; the
first update copies (if shared), the rest are in place:

```resid
Map(Int, Int) histogram(List(Int) xs, Int i, Map(Int, Int) m) {
    if (i >= xs.len()) { return m; }
    Int c = m.get(xs[i]) else { 0 };             // reads are fine
    return histogram(xs, i + 1, m.insert(xs[i], c + 1));
}

Int main() {
    Map(Int, Int) empty = {};
    Map(Int, Int) h = histogram([3, 1, 3, 3, 2], 0, empty);
    println(f"{h.get(3) else { 0 }} {h.len()} {empty.len()}");   //> 3 3 0
    return 0;
}
```

What keeps it linear: each map value is consumed once per path (returned,
passed to a consuming parameter, `insert`/`remove`d, or stored in a struct
field that is itself threaded). What forces a copy: reading the old map after
updating it (`after(m.insert(k, 1), m.len())`), keeping an older version
alive, or storing it in a list. Older versions stay correct either way.

Maps of lists get a fused in-place append when written exactly like this:

```resid
Map(Str, List(Int)) add(Map(Str, List(Int)) m, Str k, Int v) {
    List(Int) nil = [];
    List(Int) cur = m.get(k) else { nil };
    return m.insert(k, cur.concat([v]));        // cur used only here
}

Int main() {
    Map(Str, List(Int)) e = {};
    Map(Str, List(Int)) m = add(add(add(e, "a", 1), "b", 2), "a", 3);
    List(Int) nil = [];
    println(f"{m.get("a") else { nil }}");      //> [1, 3]
    return 0;
}
```

## Records

A function that returns a record literal of the same type as a dead
parameter can reuse its storage (`return P {.x = p.x + 1, .y = p.y};`). Many
state variables in a hot loop: prefer several scalar parameters over a
record per step (the n-body benchmark carries 35 Float parameters).

## Memory reclamation

There is no garbage collector. Memory is reclaimed through compiler-inferred
regions: a scalar binding whose initializer allocates (`Int n = count(parse(s));`)
releases the temporaries, and a tail-call loop releases each iteration's
garbage when what it carries is scalars, Map/Set of scalars or strings, or
lists. Long-running loops should carry their state in those forms; state
kept in other shapes can grow for the life of the loop.

`RESID_MEM_LIMIT=<MB>` sets a memory budget: exceeding it aborts with
`memory budget exceeded`. User programs have no budget by default.

## Numeric performance

- Checked arithmetic costs a branch; the compiler removes checks it can
  prove unnecessary from ranges (`i` in `0..n`, `x != 0` before `/ x`).
  `wrapping_*` removes the check where wrap-around is intended.
- `Int` and `Float` are unboxed in locals and immediates in collections.
  Wide integers (`Int(256)`, `Int(512)`) are native LLVM integers but slow.
- Compile-time reduction removes whole computations over known data
  ([compile-time-reduction.md](compile-time-reduction.md)).
- Build optimized binaries with `-O2`/`-O3` (release profile, needs a
  signing key); debug profile compiles at `-O0`.

## Things that do not exist

No SIMD types, no raw intrinsics, no FFI, no mutable arrays, no manual
allocation, no arenas for user code (`resid_arena_*` etc. are compiler-only,
E0220). Structured `spawn` exists but do not plan on parallel speedups.
