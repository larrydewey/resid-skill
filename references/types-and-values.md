# Types and values

All values are immutable and have no identity. Only handles (`File`) are
identity-bearing resources. Every block below is compiled by the checker.

## Integers

- `Int` = `Int(64)`, `UInt` = `UInt(64)`; widths 8, 16, 32, 64, 128, 256, 512
  for both. `ISize`/`USize` are pointer-sized. Every width is a distinct type.
- Literals: `42`, `0x2A`, `0b1010`, char `'a'` (an `Int` code point, `'\n'`
  works). No `_` digit separators, no suffixes.
- Literal typing: a literal takes the type of the other operand, or of the
  position it wholly fills (binding, argument, return, field). Two literals
  alone (`10000000000 * 10000000000`) are `Int(64)`, even when bound to an
  `Int(128)`, and then overflow at run time. Widen one operand first.
- Mixed widths of one signedness: the result is the widest operand.
  Signed/unsigned mixing is a compile error; convert explicitly.
- `+ - * / %` are checked at every width: overflow, `/ 0`, `MIN / -1` abort
  (exit 134). `/` truncates toward zero; `%` takes the dividend's sign.
- Shifts and `& | ^ ~` are unchecked bit operations. `>>` is arithmetic for
  signed, logical for unsigned. Shift counts `>=` width give 0 (or -1 for `>>`
  of a negative).
- Widening is implicit at bindings, returns and fields (same signedness,
  or unsigned into a strictly wider signed type). Narrowing never is.

```resid
Int main() {
    Int(8) a = 100;
    Int(16) sq = (Int(16))a * a;                 // widen BEFORE multiplying
    Int(128) big = (Int(128))10000000000 * 10000000000;
    UInt(16) w = u16(300);
    UInt(32) ww = w;                              // implicit widening
    Int back = (Int)sq;
    println(f"{sq} {big} {ww} {back}");           //> 10000 100000000000000000000 300 10000
    println(f"{-7 / 2} {-7 % 2} {1 << 4} {-8 >> 1} {8 >> 64}");  //> -3 -1 16 -4 0
    return 0;
}
```

```resid
//! compile-error: signed and unsigned
Int main() {
    Int a = 1;
    UInt b = u64(2);
    Int c = a + b;
    return 0;
}
```

```resid
//! compile-error: implicit narrowing
Int main() {
    Int(128) a = rt 3;
    Int b = a + 1;          // Int(128) result does not fit Int
    return 0;
}
```

```resid
//! exit 134
Int main() {
    Int(8) a = i8(rt 100);
    Int(8) b = a + a;        // 200 overflows Int(8): abort
    println(f"{b}");
    return 0;
}
```

### Conversions

| Helper | Meaning |
|---|---|
| `i8 i16 i32 i64 i128 i256 i512`, `u8 ... u512`, `isize`, `usize` | checked conversion; aborts if the value does not fit |
| `f16 f32 f64 f128` | to float |
| `dN(x)` (any N: `d2`, `d10`, `d1000`) | to `Dec(N)` from Int (exact), Dec (rounded) or Str (decimal text) |
| `(Type)expr` | C-style cast, also checked |
| `wrapping_i8 ... wrapping_u512` | keep the low bits (two's complement) |

Arithmetic helpers: `wrapping_add/sub/mul/div`, `saturating_add/sub/mul`,
`checked_*`, with a `u` form for unsigned (`wrapping_uadd`,
`saturating_umul`); both operands of the variant's signedness; result is the
widest operand. `abs`, `min`, `max`, `clamp` take one numeric type.

```resid
Int main() {
    Int x = 300;
    println(f"{wrapping_u8(x)} {wrapping_u64(-1)}");      //> 44 18446744073709551615
    UInt(8) a = 250;
    UInt(8) b = 20;
    println(f"{wrapping_uadd(a, b)} {saturating_uadd(a, b)}");  //> 14 255
    Int big = 9223372036854775807;
    println(f"{saturating_add(big, 1)} {wrapping_add(big, 1)}");  //> 9223372036854775807 -9223372036854775808
    println(f"{abs(-3)} {min(4, 2)} {max(1.5, 2.5)} {clamp(99, 0, 10)}");  //> 3 2 2.5 10
    return 0;
}
```

```resid
//! exit 134
Int main() {
    Int y = rt 300;
    UInt(8) a = u8(y);      // 300 does not fit UInt(8): abort
    return 0;
}
```

## Floats

`Float` = `Float(64)`; also `Float(16)`, `Float(32)`, `Float(128)`. Int op
Float gives the Float type; Float op Float gives the wider. f-strings print
the shortest text that round-trips at the value's own width: `2.0` prints
`2`, `3.14` prints `3.14`, `f32(0.1)` prints `0.1`, `0.1 + 0.2` prints
`0.30000000000000004`. For fixed decimals in output, format yourself or
compute in `Dec(N)`. No scientific
literals (`1e10` is rejected); no `sqrt`/`sin`/`pow` builtins (write them;
see [stdlib.md](stdlib.md)). NaN != NaN.

```resid
Int main() {
    Float a = 7.0 / 2;
    Float b = (Float)7 / 2.0;
    Int t = (Int)3.99;              // truncates
    Float(32) s = f32(0.1);
    println(f"{0.1} {3.14}");                    //> 0.1 3.14
    println(f"{a} {b} {t} {2.0} {0.1 + 0.2} {s}");  //> 3.5 3.5 3 2 0.30000000000000004 0.1
    return 0;
}
```

## Decimals

`Dec(N)`: exact decimal with N significant digits (any N >= 1; `Dec` = 34).
Literal `1.5m`. Arithmetic rounds once, half away from zero. Dec never mixes
with Int/Float (compile error); convert with `dN(...)`, `i64(...)`, `f64(...)`.
Display keeps all N digits; `{x:.}` trims trailing zeros. Division by zero
aborts; Dec to Int requires an integral value.

```resid
Int main() {
    Dec(4) a = 1.5m;
    Dec(4) b = 2.25m;
    println(f"{a} {a + b} {a / b} {a:.}");    //> 1.500 3.750 0.6667 1.5
    Dec(2) r = d2(0.255m);
    println(f"{r}");                           //> 0.26
    Dec(10) price = d10("19.99");
    Dec(10) total = price * d10(3);
    println(f"{total:.} {i64(d10(12))}");      //> 59.97 12
    return 0;
}
```

```resid
//! compile-error: Dec
Int main() {
    Dec(4) a = 1.5m;
    Dec(4) c = a + 2;        // no Dec/Int mixing
    return 0;
}
```

## Bool

`true`, `false`, `!`, `&&`, `||` (short-circuit). Comparison yields `Bool`.

## Strings

`Str` is immutable UTF-8. Indices are **code points**. There is no `s[i]`
indexing; `==`, `!=` and `<` `<=` `>` `>=` (through `Ord(Str)`) work. `+` concatenates.
Escapes: `\n \t \" \\`. Raw strings `r"C:\x"`. f-strings: `f"{expr}"`; a
hole holds one expression of any type. No `{{` escape: concatenate a
`"{"` literal instead.

```resid
Int main() {
    Str s = "héllo";
    println(f"{str_len(s)} {str_char_at(s, 1)} {str_slice(s, 1, 3)}");  //> 5 233 él
    println(str_from_code(97) + str_to_upper(s));                         //> aHÉLLO
    println(f"{str_index_of(s, "l", 0)} {str_contains(s, "ll")}");       //> 2 true
    List(Str) parts = str_split("a,b,,c", ",");
    println(f"{parts.len()} " + str_join(parts, "|"));                   //> 4 a|b||c
    println("{" + f"{1 + 1}" + "}");                                     //> {2}
    println(r"C:\path");                                                 //> C:\path
    return 0;
}
```

Full builtin list: [stdlib.md](stdlib.md).

## List(T)

Persistent immutable list. Literal `[1, 2, 3]`; empty `[]` takes its element
type from the declared type. Index `xs[i]` is bounds-checked (abort on miss).

| Operation | Result |
|---|---|
| `xs.len()` | `Int` |
| `xs[i]` | element, abort if out of range |
| `xs[a..b]`, `xs[a..]`, `xs[..b]` | new `List(T)` (half-open) |
| `xs.concat(ys)` | new list; `acc.concat([x])` is the append idiom |
| `xs.contains(v)` | integer, Float or Str elements |
| `xs.reverse()` | new list |
| `xs.sum()` | `List(Int)` or `List(Float)` |
| `sort(xs)` | Int/Float/Str elements; others need `using = Ord(T)` |

No `map`/`filter`/`fold` builtins; write them with closures
([functions-and-closures.md](functions-and-closures.md)) or recursion.
`==` does not work on lists (write a comparison).

```resid
Int main() {
    List(Int) xs = [5, 3, 9];
    List(Int) more = xs.concat([1]);
    List(Int) none = [];
    println(f"{more} {more[1..3]} {xs.contains(9)} {xs.sum()}");  //> [5, 3, 9, 1] [3, 9] true 17
    println(f"{sort(xs)} {xs.reverse()} {none.len()}");           //> [3, 5, 9] [9, 3, 5] 0
    List(List(Int)) grid = [[1, 2], [3, 4]];
    println(f"{grid[1][0]}");                                      //> 3
    return 0;
}
```

## Map(K, V) and Set(T)

Persistent hash maps/sets. Literals `{"a": 1}`, `{1, 2}`; empty `{}` takes its
type from the binding (Map or Set). Iteration order is a canonical hash order,
**not** insertion or sorted order: `sort(m.keys())` when order matters.

| Map | | Set | |
|---|---|---|---|
| `m.get(k)` / `m[k]` | `Option(V)` | `s.contains(x)` | `Bool` |
| `m.insert(k, v)` | new map | `s.insert(x)` / `s.remove(x)` | new set |
| `m.remove(k)` | new map | `s.union(t)` / `s.intersection(t)` / `s.difference(t)` | new set |
| `m.contains(k)` | `Bool` | `s.to_list()` | `List(T)` |
| `m.keys()` / `m.values()` | `List` | `s.len()` | `Int` |
| `m.len()` | `Int` | | |

```resid
Int main() {
    Map(Str, Int) m = {"a": 1, "b": 2};
    Map(Str, Int) m2 = m.insert("c", 3).remove("a");
    Int b = m2.get("b") else { 0 };
    Int z = m2["z"] else { -1 };
    println(f"{m.len()} {m2.len()} {b} {z} {sort(m2.keys())}");  //> 2 2 2 -1 ["b", "c"]
    Set(Int) s = {1, 2, 3};
    Set(Int) t = {2, 3, 4};
    Set(Int) empty = {};
    println(f"{s.union(t).len()} {sort(s.intersection(t).to_list())} {empty.insert(7).contains(7)}");  //> 4 [2, 3] true
    return 0;
}
```

`for` does not iterate a Set or Map directly: use `s.to_list()` / `m.keys()`.

## Option and Result

```resid
Option(Int) find(List(Int) xs, Int want, Int i) {
    if (i >= xs.len()) { return None; }
    if (xs[i] == want) { return Some(i); }
    return find(xs, want, i + 1);
}

Int main() {
    Option(Int) hit = find([4, 7, 9], 7, 0);
    Int idx = hit else { -1 };
    Str msg = match find([4], 1, 0) { Some(i) => f"at {i}", None => "absent" };
    Result(Int, Str) r = Err("nope");
    println(f"{idx} {msg} {r else { 0 }}");   //> 1 absent 0
    return 0;
}
```

`RegionError` is `{ Str message; }`; `SourceLoc` is `{ Str file; Int line; Int col; }`
(`SourceLoc here = #location;`). More in [errors-and-results.md](errors-and-results.md).

## Records (product types)

```resid
type Point = { Int x; Int y; };          // or: type Point = { x: Int, y: Int };
type Line = { Point a; Point b; Str label; };

Point shift(Point p, Int dx) {
    return Point {.x = p.x + dx, .y = p.y};   // no update syntax: list every field
}

Int main() {
    Point p = Point {.x = 1, .y = 2};
    Point q = shift(p, 10);
    Line l = Line {.a = p, .b = q, .label = "L"};
    Point { x, y } = q;                        // destructuring binding
    println(f"{x} {y} {l.b.x} {p.x}");         //> 11 2 11 1
    println(f"{p}");                            //> Point { x: 1, y: 2 }
    return 0;
}
```

Record literal fields use `.name = value` (or `name = value` with the colon
form). `==` works only on numbers, Bool and Str: on records it is a compile
error ("compare the parts of a P"), so compare fields or write an `eq_p`
function.

## Sum types

```resid
type Shape = Circle(Float) | Square(Float) | Nothing;
type Tree = Node(Branch) | Leaf;          // recursion goes through a variant
type Branch = { Tree l; Tree r; Int v; };

Float area(Shape s) {
    return match s {
        Circle(r) => 3.0 * r * r,
        Square(w) => w * w,
        Nothing => 0.0
    };
}

Int sum(Tree t) {
    return match t { Node(b) => b.v + sum(b.l) + sum(b.r), Leaf => 0 };
}

Int main() {
    Tree t = Node(Branch {.l = Leaf, .r = Node(Branch {.l = Leaf, .r = Leaf, .v = 2}), .v = 1});
    println(f"{area(Square(3.0))} {area(Nothing)} {sum(t)}");   //> 9 0 3
    return 0;
}
```

- A variant carries **zero or one** payload. `Rect(Float, Float)` is a parse
  error: use `Rect(Dims)` with a record.
- Patterns are flat: `Name(x)`, `Name`, `_`. No nested patterns
  (`Some(Some(x))`), no literal patterns (`0 =>`, `"a" =>`): use `if`.
- Variants print by name (`Circle(1)`, `Nothing`); define a `Show` instance
  for custom text ([behaviors.md](behaviors.md)).
- Generic sums: `type Box(T) = Full(T) | Empty;` then `Box(Int) b = Full(3);`.

## Type aliases and constraint types

```resid
type Word = Int(32);
type Positive = Int[value > 0];
type Natural = Int where value >= 0;

Int main() {
    Word w = i32(4);
    Positive p = 5;           // checked at compile time on known values
    Natural n = 0;
    println(f"{w} {p * 2} {n}");   //> 4 10 0
    return 0;
}
```

```resid
//! compile-error: E0301
type Positive = Int[value > 0];
Int main() {
    Positive p = -1;
    return 0;
}
```

Known values are checked at compile time (E0301); a residual value bound to
a constraint type is checked at run time and aborts with `constraint of
Positive (value > 0) does not hold`. A plain `Int` argument does not match a
`Positive` parameter: bind it to a `Positive` first.

## Fixed-capacity types

`Str(N)` (N UTF-8 bytes), `Bytes(N)`, `List(T, N)`: stored inline, never on
the heap. A literal must fit (compile error otherwise). Capacity changes only
by cast; a narrowing cast keeps a prefix of whole code points. Builtins
(`println`, `str_len`) accept `Str(N)`; your own functions need an exact type,
so cast `(Str)s`. `List(T, N).len()` is N; unset slots are zero.

```resid
Int main() {
    Str(8) s = "abc";
    List(Int, 4) xs = [10, 20];
    Str(3) cut = (Str(3))"abcdef";
    println(s);                                   //> abc
    println(f"{xs[1]} {xs[3]} {xs.len()}");       //> 20 0 4
    println((Str)cut + "!");                      //> abc!
    List(Int) heap = (List(Int))xs;
    println(f"{heap.len()}");                     //> 4
    return 0;
}
```

```resid
//! compile-error: exceeds Str(2)
Int main() { Str(2) w = "éé"; return 0; }
```

`Bytes` (`b"abc"`, `.len()`) and `Bytes(N)` exist, but the stdlib and the
filesystem provider use `List(Int)` for byte data; prefer it.

## Closure and builder types

`Ret closure(A, B)` is a closure type ([functions-and-closures.md](functions-and-closures.md)).
`StrBuf` and `ListBuf(T)` are linear builders ([performance-and-memory.md](performance-and-memory.md)).

## Printing values

`f"{v}"` renders any value. At top level: numbers, Bool, Str as is, Dec at
its precision. Containers: lists `[1, 2, 3]`, records
`Point { x: 1, y: 2 }`, maps `{"a": 1}`, sets `{1, 2}`, variants by name
(`Some(3)`, `None`, `Ok(3)`, `Err("x")`, `Circle(1)`, `Nothing`); strings
inside containers are quoted (`["a", "b"]`). A `Show(T)` instance is used
wherever a `T` appears, including inside lists, options and records
([behaviors.md](behaviors.md)).
