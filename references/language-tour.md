# Language tour

A fast pass over the whole surface. Every block here compiles with the current
self-hosted compiler (`scripts/check-examples.sh` checks them); `//>` lines are
the program's exact output.

## Program shape

```resid
// Top level: imports, type declarations, behavior instances, functions,
// sandbox blocks. No global variables or constants: use zero-arg functions.
type Point = { Int x; Int y; };

Int limit() { return 10; }            // a "constant"; folded at compile time

Int dist2(Point p) { return p.x * p.x + p.y * p.y; }

Int main() {                          // entry point; return value = exit code
    Point p = Point {.x = 3, .y = 4};
    println(f"{dist2(p)} {limit()}"); //> 25 10
    return 0;
}
```

- Declaration order does not matter (use before define is fine).
- Statements end with `;`. Blocks use `{ }`. Comments: `//`, `/* */`, doc `///`, `/** */`.
- Declarations are C-like: `Type name = expr;`, `Ret f(Type a, Type b) { ... }`.

## Bindings: immutable, no shadowing

```resid
Int main() {
    Int a = 1;
    Int b = a + 1;            // new name for every new value
    _ = b * 100;              // discard a value explicitly
    if (true) { Int t = 5; println(f"{t}"); }  //> 5
    if (true) { Int t = 6; println(f"{t}"); }  //> 6
    return a + b - 3;
}
```

Sibling scopes may reuse a name; nested scopes may not (`shadowing` error).
There is no assignment: `x = 5;` is `cannot assign`.

```resid
//! compile-error: shadowing
Int f(Int x) {
    Int x = 2;                // parameter x is already bound
    return x;
}
```

## Types at a glance

| Kind | Syntax |
|---|---|
| Integers | `Int`=`Int(64)`, `Int(N)`/`UInt(N)` for N in 8, 16, 32, 64, 128, 256, 512, `UInt`=`UInt(64)`, `ISize`, `USize` |
| Floats | `Float`=`Float(64)`, `Float(16/32/128)` |
| Decimal | `Dec`=`Dec(34)`, `Dec(N)` any N >= 1; literal `1.5m` |
| Text | `Str` (UTF-8, indexed by code point via builtins), char literal `'a'` is an `Int` |
| Collections | `List(T)`, `Map(K, V)`, `Set(T)` (persistent, immutable) |
| Absence / failure | `Option(T)` = `Some(v)`/`None`, `Result(T, E)` = `Ok(v)`/`Err(e)` |
| Records | `type P = { Int x; Int y; };` (also `{ x: Int, y: Int }`) |
| Sums | `type S = A(T) \| B \| C(U, V);` (any number of payloads per variant) |
| Generic sums | `type Box(T) = Full(T) \| Empty;` |
| Aliases / constraints | `type Word = Int(32);`  `type Pos = Int[value > 0];` |
| Fixed capacity | `Str(N)`, `Bytes(N)`, `List(T, N)` |
| Bytes | `b"..."` is a heap `Bytes` (no indexing, ends at its first zero byte); `Bytes(N)` keeps zeros |
| Vectors | `Vec(T, N)` (SIMD lanes; see types-and-values.md) |
| Closures | `Ret closure(A, B)` |
| Builders | `StrBuf`, `ListBuf(T)` (linear: use each value exactly once) |

Details: [types-and-values.md](types-and-values.md).

## Expressions and control flow

```resid
type Color = Red | Green | Blue;

Str name(Color c) {
    return match c { Red => "red", Green => "green", Blue => "blue" };
}

Int main() {
    Int n = 7;
    Str size = if (n > 5) { "big" } else { "small" };   // if is an expression
    Int half = n > 5 ? n / 2 : n;                       // ternary
    println(f"{size} {half} {name(Green)}");            //> big 3 green
    for (Int i in 0..3) { print(f"{i};"); }             // half-open range
    println("");                                        //> 0;1;2;
    return 0;
}
```

Loops that carry state are tail-recursive functions (compiled to jumps);
`while (cond) { ... }` exists but, with no mutation, is only useful with
`break` or an external condition.
See [control-flow.md](control-flow.md).

## Functions

```resid
Str greet(Str name, Str greeting = "hello", Str end = "!") {
    return greeting + ", " + name + end;
}

Int main() {
    println(greet("ada"));                    //> hello, ada!
    println(greet("ada", "hi"));              //> hi, ada!
    println(greet("ada", end = "?"));         //> hello, ada?
    return 0;
}
```

- Defaults must be compile-time constants. Named arguments: `f(x, name = v)`.
- `x.f(args)` is sugar for `f(x, args)` (works for any function, and for
  builtin list/map/set/builder methods).
- Generic functions and records: one uppercase letter is a type parameter
  (`T id(T x)`, `type Box(T) = { T v; };`, `Int(N)` for widths); a body that
  sorts/shows/compares a `T` declares `@needs(Ord(T))`. See
  [behaviors.md](behaviors.md).
- No overloading (one function per name).
- Functions are not values; lambdas are: [functions-and-closures.md](functions-and-closures.md).

## Errors

```resid
Result(Int, Str) parse(Str s) {
    if (str_is_int(s)) { return Ok(str_parse_int(s)); }
    return Err(f"bad int {s}");
}

Result(Int, Str) sum2(Str a, Str b) {
    Int x = parse(a)?;          // propagate Err
    Int y = parse(b)?;
    return Ok(x + y);
}

Int main() {
    Int ok = sum2("2", "3") else { -1 };     // default on Err/None
    Int bad = sum2("2", "x") else { -1 };
    println(f"{ok} {bad}");                   //> 5 -1
    return 0;
}
```

No exceptions. Aborts (overflow, index out of range, failed assert, `todo`)
end the process with exit 134, except inside `spawn`, where they become
`Err(RegionError)`. See [errors-and-results.md](errors-and-results.md).

## Effects need authority

```resid
@requires(filesystem(readonly))
Bool has_etc() { return filesystem.is_dir("/etc"); }

@requires(filesystem(readonly))
Int main() {
    println(f"{has_etc()}");   //> true
    return 0;
}
```

Every function that reaches a provider (`filesystem`, `environment`, `args`,
`process`, `clock`) or an effectful builtin (TCP = `network`, TTY queries and
raw mode = `terminal`, the window server = `display`, a `@link` native
call = `native_<m>`) directly *or
through any callee* must declare `@requires(...)`, all the way up to `main`
(E0219). Printing, stdin and randomness need nothing; reading the time does
(`clock(readonly)`). See
[capabilities-and-security.md](capabilities-and-security.md).

## Compile-time reduction

```resid
Int fib(Int n) { return if (n < 2) { n } else { fib(n - 1) + fib(n - 2) }; }

Int main() {
    Int f = fib(20);       // computed by the compiler
    known(f);              // compile error if it were not
    Int r = rt 20;         // rt: explicitly a runtime value
    println(f"{f} {fib(r)}");   //> 6765 6765
    return 0;
}
```

The compiler evaluates everything it can prove; only the residual reaches the
binary. See [compile-time-reduction.md](compile-time-reduction.md).

## Modules

```resid
//! skip -- needs a second file; see the text below
import "geometry.resid";                 // everything pub
import "geometry.resid" (area, perim);   // selected names
import "geometry.resid" as G;            // G.area(...), G.Shape
```

Paths are relative to the importing file, falling back to the stdlib
directory (so `import "crypto.resid";` works anywhere). A module that cannot
be found is E0221. Only `pub` functions are exported (types are visible
without `pub`). A name two imports both export must be qualified through an
alias; an ambiguous unqualified use is E0223.
