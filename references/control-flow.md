# Control flow

Resid has no mutation, so there are no counters to bump and no accumulators
to update in a loop body. Repetition that carries state is a **tail-recursive
function**; `for` is for effects (printing, writing) over a range or list.

## if / else

`if` is both a statement and an expression. As an expression each branch is a
block whose last expression (no `;`) is the value; branches must have the same
type (no implicit widening between arms).

```resid
Str sign(Int n) {
    if (n < 0) { return "negative"; }
    else if (n == 0) { return "zero"; }
    return "positive";
}

Int main() {
    Int x = rt 7;
    Int y = if (x > 5) { x * 2 } else { 0 };
    Str s = if (x % 2 == 0) { "even" } else { "odd" };
    println(f"{sign(-3)} {sign(0)} {y} {s}");   //> negative zero 14 odd
    return 0;
}
```

- Arms must agree exactly: `if (c) { n } else { i64(0) }` is fine for `Int`,
  but mixing `Int(128)` and a bare literal needs `i128(0)`.
- An `if` used as a value needs an `else` (compile error otherwise).
- Ternary: `c ? a : b`.
- `&&`/`||` short-circuit (the right side is not evaluated, not even its
  aborts or effects).
- A `Void` function cannot `return;` early: use `if/else` around the rest.
- A non-Void function that can reach its end without `return` is a compile
  error (`function f can reach its end without a return`).

## match

`match` works on sum types (`Option`, `Result`, your own). It is an
expression; arms are separated by commas (trailing comma allowed). It must be
exhaustive, or end with `_ => ...`.

```resid
type Op = Add | Sub | Neg(Int);

Int apply(Op op, Int a, Int b) {
    return match op {
        Add => a + b,
        Sub => a - b,
        Neg(k) => 0 - k,
    };
}

Int main() {
    println(f"{apply(Add, 2, 3)} {apply(Sub, 2, 3)} {apply(Neg(9), 0, 0)}");  //> 5 -1 -9
    Option(Int) o = Some(4);
    match o { Some(v) => println(f"got {v}"), None => println("none") };       //> got 4
    return 0;
}
```

Arms may contain any expression, including `if`, `?:`, `&&`/`||`, a nested
`match` or an `else { }` default:

```resid
type Cmd = Inc(Int) | Reset;

Int step(Int acc, Cmd c, Option(Int) cap) {
    return match c {
        Inc(by) => match cap { Some(m) => if (acc + by > m) { m } else { acc + by }, None => acc + by },
        Reset => 0
    };
}

Int main() {
    println(f"{step(8, Inc(5), Some(10))} {step(3, Inc(2), None)} {step(9, Reset, None)}");   //> 10 5 0
    return 0;
}
```

A variant pattern binds one name per payload, in order (`Rect(w, h)`), or
none for a variant without payload; `_` discards a position (`Rect(_, h)`),
and a binding list is all-or-nothing (`Rect(w)` against a two-payload `Rect`
is an error).

```resid
type Shape = Circle(Int) | Rect(Int, Int) | Dot;

Int area(Shape s) {
    return match s { Circle(r) => 3 * r * r, Rect(w, h) => w * h, Dot => 0 };
}

Int height(Shape s) { return match s { Rect(_, h) => h, _ => 0 }; }

Int main() {
    println(f"{area(Rect(2, 5))} {area(Circle(1))} {height(Rect(2, 5))}");   //> 10 3 5
    return 0;
}
```

Patterns are flat: `Variant(names)`, `Variant`, `_`. There are no literal,
range, guard or nested patterns (`Some(Some(x))` and `1 => ...` are compile
errors). Dispatch on numbers/strings with `if` chains:

```resid
Str word(Int n) {
    if (n == 1) { return "one"; }
    if (n == 2) { return "two"; }
    return "many";
}

Int main() {
    println(word(1) + " " + word(5));   //> one many
    return 0;
}
```

```resid
//! compile-error: match is not exhaustive
type Rgb = R | G | B;
Str n(Rgb c) { return match c { R => "r", G => "g" }; }
```

```resid
//! compile-error: match arm pattern must be a variant name or _
Str name(Int n) { return match n { 1 => "one", _ => "many" }; }
```

## if-let, while-let, destructuring

```resid
type Pair = { Int a; Int b; };

Int main() {
    Option(Int) maybe = Some(5);
    if (Some(v) = maybe) {
        println(f"have {v}");         //> have 5
    } else {
        println("nothing");
    }
    Result(Int, Str) r = Err("bad");
    if (Ok(v) = r) { println(f"{v}"); } else if (Err(e) = r) { println(e); }  //> bad
    Pair p = Pair {.a = 1, .b = 2};
    Pair { a, b } = p;                // irrefutable record destructuring
    Some(n) = maybe;                  // refutable form: aborts if None
    println(f"{a + b + n}");          //> 8
    return 0;
}
```

if-let and destructuring take single-payload variants only (`Some(v)`,
`Ok(v)`, `Some(_)`); take a multi-payload variant apart with `match`.

`while (cond) { ... }` and `while (Some(x) = expr) { ... }` exist, but without
mutation the condition only changes if it reads something external, so a
`while` loop either exits through `break` or is rarely what you want.

## for-in

`for (Type name in iterable) statement` over a range or a `List`. The loop
variable's type is required. `break` and `continue` work. `for` cannot iterate
a `Set`/`Map` directly: use `s.to_list()`, `m.keys()`, `m.values()`.

```resid
Int main() {
    for (Int i in 0..5) {
        if (i == 1) { continue; }
        if (i == 4) { break; }
        print(f"{i},");
    }
    println("");                       //> 0,2,3,
    for (Int j in 1..=3) { print(f"{j * j} "); }
    println("|");                      //> 1 4 9 |
    List(Str) names = ["ann", "bo"];
    for (Str n in names) { println(n); }
    //> ann
    //> bo
    for (Int k in 5..0) { println("never"); }   // empty when start >= end
    return 0;
}
```

A range is a `Range(Int)` value (`0..n`, `0..=n`), not a list. There is no
C-style `for (init; cond; step)` because there is nothing to step.

## Loops that compute: tail recursion

State lives in parameters; each iteration is a call with the new state. A call
in tail position (`return f(...)`) compiles to a jump, so it never grows the
stack and can run billions of times.

```resid
// sum of i*i for i in [i, n)
Int sum_sq(Int i, Int n, Int acc) {
    if (i >= n) { return acc; }
    return sum_sq(i + 1, n, acc + i * i);
}

// Several state variables = several parameters.
Int collatz_steps(Int n, Int steps) {
    if (n == 1) { return steps; }
    Int next = if (n % 2 == 0) { n / 2 } else { 3 * n + 1 };
    return collatz_steps(next, steps + 1);
}

Int main() {
    println(f"{sum_sq(0, 10, 0)} {collatz_steps(27, 0)}");   //> 285 111
    println(f"{sum_sq(0, rt 3000000, 0)}");                  //> 8999995500000500000
    return 0;
}
```

Recipe for turning an imperative loop into Resid:

1. List every variable the loop body assigns: those become parameters.
2. The loop condition becomes the base case (`if (done) { return result; }`).
3. The body computes new values as fresh bindings and ends with
   `return loop(new_a, new_b, ...)`.
4. Seed it from the caller: `loop(initial_a, initial_b, ...)`.
5. Many state variables: group them into a record and pass one value.

Mutual recursion works (`is_even` calling `is_odd`). Non-tail recursion
(`return n + f(n - 1)`) uses stack per level; the main thread's stack is large
(10 million levels of a small function ran fine), but prefer an accumulator
for unbounded input.

Accumulating lists or strings in the loop: use a builder parameter
(`ListBuf(T)`, `StrBuf`) and `.finish()` at the end
([performance-and-memory.md](performance-and-memory.md)).

```resid
List(Int) evens_below(Int i, Int n, ListBuf(Int) acc) {
    if (i >= n) { return acc.finish(); }
    if (i % 2 == 0) { return evens_below(i + 1, n, acc.push(i)); }
    return evens_below(i + 1, n, acc);
}

Int main() {
    println(f"{evens_below(0, 10, ListBuf())}");   //> [0, 2, 4, 6, 8]
    return 0;
}
```

## Early exit

`return` anywhere in a function. `?` returns an `Err`/`None` early
([errors-and-results.md](errors-and-results.md)). `todo("msg")`,
`unimplemented("msg")` and failing `assert` abort.

## Blocks and scope

A `{ }` block opens a scope; names bound inside disappear at `}` and may be
reused by a sibling block, never by a nested one.

## Concurrency and resources

`spawn (caps) { ... }` runs a child region and yields `Result(T, RegionError)`;
`with (File h = ...) { ... }` scopes a handle. Both are in
[capabilities-and-security.md](capabilities-and-security.md).
