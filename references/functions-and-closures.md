# Functions and closures

## Functions

```resid
// Ret name(Type param, Type param = default) { body }
Int area(Int w, Int h = 1) { return w * h; }

// A Void function has no return value (and cannot `return;` early).
Void banner(Str s) { println("== " + s + " =="); }

Int main() {
    banner("demo");                            //> == demo ==
    println(f"{area(3)} {area(3, 4)} {area(3, h = 5)}");   //> 3 12 15
    return 0;
}
```

- Parameters are immutable bindings; they may not be shadowed in the body.
- Defaults must be compile-time expressions; named arguments use `name = v`.
- Every path of a non-Void function must `return` a value.
- Argument types must match exactly after literal adoption (value-preserving
  integer widening of a variable is accepted; computed expressions of the
  wrong width are not). Convert explicitly when in doubt: `f(i32(x))`.
- One function per name: no overloading, no generic type parameters. For the
  same logic over several types, write one function per type (or wrap the
  varying part in a closure parameter).
- Method-call sugar: `x.f(a)` means `f(x, a)` for any function whose first
  parameter matches.
- `pub` exports a function from its module; see [stdlib.md](stdlib.md) for
  imports.
- The entry point is `Int main()`; its return value is the exit code.

```resid
Str shout(Str s, Int times) { return str_repeat(str_to_upper(s), times); }

Int main() {
    Str s = "ab";
    println(s.shout(2));      //> ABAB
    return 0;
}
```

## Closures

A closure type is written `Ret closure(Arg1, Arg2)`. A lambda is
`lambda(a, b) { statements; final_expression }`: parameters are untyped (the
expected closure type supplies them) and the last expression, without `;`, is
the result. Lambdas capture the variables they mention.

```resid
Int apply_twice(Int closure(Int) f, Int x) { return f(f(x)); }

Int main() {
    Int k = 10;
    Int closure(Int) add_k = lambda(x) { x + k };          // typed binding
    println(f"{apply_twice(add_k, 1)}");                    //> 21
    // the parameter type supplies the lambda type:
    println(f"{apply_twice(lambda(x) { x * 3 }, 1)}");      //> 9
    Str closure(Str, Int) rep = lambda(s, n) { str_repeat(s, n) };
    println(rep("ab", 3));                                  //> ababab
    Int closure(Int) poly = lambda(x) { Int sq = x * x; sq + 2 * x + 1 };
    println(f"{poly(4)}");                                  //> 25
    return 0;
}
```

Rules that bite (all observed with the current compiler):

| Situation | What to do |
|---|---|
| A lambda with no expected closure type (`return lambda...`, a record literal field, an untyped position) | bind it to a typed name first, then use the name |
| A named function passed as a value (`apply(inc, 1)`) | `undefined variable`: wrap it, `lambda(x) { inc(x) }` |
| Typed lambda parameters `lambda(Int x)` | not allowed; types come from the closure type |
| A lambda that captures another closure *variable* and calls it | codegen error `undefined variable`; inline the inner lambda or call a named function |
| `Void closure(...)` whose body ends in `println(...)` | `println` returns `Bool`: call a `Void` helper, or use a `Bool closure` |
| Two list literals inside lambdas of one function | may fail with a duplicate `@.lty` global in clang; move literals into helper functions |

```resid
// Returning a closure: bind it to a typed name first.
Int closure(Int) multiplier(Int m) {
    Int closure(Int) f = lambda(x) { x * m };
    return f;
}

type Op = { Str name; Int closure(Int, Int) run; };

Int main() {
    Int closure(Int) triple = multiplier(3);
    Int closure(Int, Int) plus = lambda(a, b) { a + b };
    Op add = Op {.name = "add", .run = plus};         // field set from a typed name
    List(Int closure(Int)) pipeline = [triple, multiplier(10)];
    Int closure(Int) second = pipeline[1];
    println(f"{triple(5)} {add.run(2, 3)} {second(4)}");   //> 15 5 40
    return 0;
}
```

```resid
//! compile-error: undefined variable inc
Int inc(Int x) { return x + 1; }
Int apply(Int closure(Int) f, Int x) { return f(x); }
Int main() { return apply(inc, 1); }
```

```resid
//! compile-error: closure literal needs a closure(..) expected type
Int closure(Int) adder(Int n) { return lambda(x) { x + n }; }
```

## Higher-order helpers you write yourself

There is no builtin `map`/`filter`/`fold`/`any`. These are the standard
shapes (monomorphic: one per element type you need):

```resid
List(Int) map_ints(List(Int) xs, Int closure(Int) f, Int i, ListBuf(Int) out) {
    if (i >= xs.len()) { return out.finish(); }
    return map_ints(xs, f, i + 1, out.push(f(xs[i])));
}

List(Int) filter_ints(List(Int) xs, Bool closure(Int) keep, Int i, ListBuf(Int) out) {
    if (i >= xs.len()) { return out.finish(); }
    if (keep(xs[i])) { return filter_ints(xs, keep, i + 1, out.push(xs[i])); }
    return filter_ints(xs, keep, i + 1, out);
}

Int fold_ints(List(Int) xs, Int closure(Int, Int) f, Int i, Int acc) {
    if (i >= xs.len()) { return acc; }
    return fold_ints(xs, f, i + 1, f(acc, xs[i]));
}

Bool any_ints(List(Int) xs, Bool closure(Int) p, Int i) {
    if (i >= xs.len()) { return false; }
    return p(xs[i]) || any_ints(xs, p, i + 1);
}

// Strings: map each element to text and join.
Str join_ints(List(Int) xs, Str sep, Int i, StrBuf out) {
    if (i >= xs.len()) { return out.finish(); }
    Str s = if (i == 0) { "" } else { sep };
    return join_ints(xs, sep, i + 1, out.push(s).push(f"{xs[i]}"));
}

Int main() {
    List(Int) xs = [1, 2, 3, 4, 5];
    List(Int) sq = map_ints(xs, lambda(x) { x * x }, 0, ListBuf());
    List(Int) odd = filter_ints(sq, lambda(x) { x % 2 == 1 }, 0, ListBuf());
    Int total = fold_ints(odd, lambda(a, b) { a + b }, 0, 0);
    println(join_ints(odd, "+", 0, StrBuf()) + f" = {total}");   //> 1+9+25 = 35
    println(f"{any_ints(xs, lambda(x) { x > 4 }, 0)}");          //> true
    return 0;
}
```

For a different element type, copy the helper with the types changed
(`map_strs(List(Str) xs, Str closure(Str) f, ...)`). This is normal Resid:
functions are monomorphic.

## Recursion patterns

- Loop with state: tail call with extra parameters ([control-flow.md](control-flow.md)).
- Index walk over a list: `f(xs, i + 1, ...)` with a base case `i >= xs.len()`.
- Tree walk: `match` on a recursive sum type and recurse into children.
- Two outputs: return a record (`type Pair = { Int lo; Int hi; };`).

```resid
type MinMax = { Int lo; Int hi; };

MinMax bounds(List(Int) xs, Int i, MinMax acc) {
    if (i >= xs.len()) { return acc; }
    Int v = xs[i];
    return bounds(xs, i + 1, MinMax {.lo = min(acc.lo, v), .hi = max(acc.hi, v)});
}

Int main() {
    List(Int) xs = [4, -2, 9, 3];
    MinMax m = bounds(xs, 1, MinMax {.lo = xs[0], .hi = xs[0]});
    println(f"{m.lo} {m.hi}");   //> -2 9
    return 0;
}
```
