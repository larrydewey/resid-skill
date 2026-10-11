# Types and values

All values are immutable and have no identity. Only handles (`File`) are
identity-bearing resources. Every block below is compiled by the checker.

## Integers

- `Int` = `Int(64)`, `UInt` = `UInt(64)`; widths 8, 16, 32, 64, 128, 256, 512
  for both. `ISize`/`USize` are pointer-sized. Every width is a distinct type.
- Literals: `42`, `0x2A`, `0b1010`, char `'a'` (an `Int` code point, `'\n'`
  works). No `_` digit separators, no suffixes.
- Literal typing: a literal takes the type of the other operand, or of the
  position it wholly fills (binding, argument, return, field). An operand
  pair of literals alone takes the smallest of `Int(64/128/256/512)` that
  fits, so `10000000000 * 10000000000` is `Int(64)` even when bound to an
  `Int(128)`, and overflows. Widen one operand first. A literal that does not
  fit its type (`UInt(8) x = 256;`) is a compile error.
- Mixed widths of one signedness: the result is the widest operand.
  Signed/unsigned mixing is a compile error; convert explicitly.
- `+ - * / %` are checked at every width: overflow, `/ 0`, `MIN / -1` abort
  (exit 134). `/` truncates toward zero; `%` takes the dividend's sign
  (`MIN % -1` is 0).
- Shifts and `& | ^ ~` are unchecked bit operations. `>>` is arithmetic for
  signed, logical for unsigned. Shift counts `>=` width give 0 (or -1 for `>>`
  of a negative).
- Widening is implicit at bindings, returns and fields (same signedness,
  or unsigned into a strictly wider signed type). Narrowing never is.
  Arguments should match the parameter type exactly; convert explicitly,
  because a signed argument to an unsigned parameter is not caught at
  present and wraps (`-1` arrives as `18446744073709551615`).
- `x.min()` / `x.max()` (behavior `Bounded`) give the bounds of `x`'s type.

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
| `dN(x)` (any N: `d2`, `d10`, `d1000`) | to `Dec(N)` from Int, Dec or Str (decimal text; bad text aborts), rounded to N significant digits (`d2(12345)` is `12000`); not from Float |
| `(Type)expr` | C-style cast, also checked (Float to Int truncates; NaN/inf aborts) |
| `wrapping_i8 ... wrapping_u512` | keep the low bits (two's complement) |

Arithmetic helpers: `wrapping_add/sub/mul/div`, `saturating_add/sub/mul`,
with a `u` form for unsigned (`wrapping_uadd`, `saturating_umul`); both
operands of the variant's signedness; result is the widest operand. Plain
operators are already the checked form (`checked_*` names exist but wrap at
run time; do not use them). `abs`, `min`, `max`, `clamp` take one numeric
type; `sqrt` takes a Float.

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
the shortest text that round-trips (`Float(32)` at its own width): `2.0`
prints `2`, `3.14` prints `3.14`, `f32(0.1)` prints `0.1`, `0.1 + 0.2`
prints `0.30000000000000004`. `Float(16)` prints as a `Float(32)` would
(`f16(0.1)` is `0.099975586`); `Float(128)` prints all its digits. Special
values print `inf`, `-inf`, `nan`. For fixed decimals use `{x:precision 2}`
or compute in `Dec(N)`. No scientific literals (`1e10` is rejected).
`sqrt(x)` is builtin (correctly rounded; `nan` for a negative); there is no
`sin`/`pow`/`exp` ([stdlib.md](stdlib.md)). NaN != NaN.

```resid
Int main() {
    Float a = 7.0 / 2;
    Float b = (Float)7 / 2.0;
    Int t = (Int)3.99;              // truncates
    Float(32) s = f32(0.1);
    println(f"{0.1} {3.14}");                    //> 0.1 3.14
    println(f"{a} {b} {t} {2.0} {0.1 + 0.2} {s}");  //> 3.5 3.5 3 2 0.30000000000000004 0.1
    println(f"{sqrt(2.0)} {1.0 / 0.0} {a:precision 2}");  //> 1.4142135623730951 inf 3.50
    return 0;
}
```

## Decimals

`Dec(N)`: exact decimal with N significant digits (any N >= 1; `Dec` = 34).
Literal `1.5m` (no exponent form). `Dec(N) op Dec(M)` is `Dec(max(N, M))`;
arithmetic rounds once, half away from zero. Dec never mixes with Int/Float
(compile error); convert with `dN(...)`, `i64(...)`, `f64(...)`. Display
keeps all N digits; `{x:trim}` (or `{x:.}`) drops trailing zeros. Division
by zero aborts; Dec to Int aborts unless the value is integral.

```resid
Int main() {
    Dec(4) a = 1.5m;
    Dec(4) b = 2.25m;
    println(f"{a} {a + b} {a / b} {a:trim}"); //> 1.500 3.750 0.6667 1.5
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

`Str` is immutable UTF-8. Indices are **code points**. Length is
`str_len(s)`: `s.len()` on a `Str` compiles but returns garbage at present.
There is no `s[i]` indexing (use `str_char_at`); `==`, `!=` and `<` `<=` `>` `>=` (through `Ord(Str)`) work. `+` concatenates.
Escapes (in `"..."`, `f"..."`, `b"..."` and `'.'`): `\n \t \r \0 \\ \" \'`
and `\xHH`; any other is a compile error. Text takes `\x00`-`\x7f` only
(above that, write the character itself) and refuses NUL (`\0`, `\x00`):
a Str ends at NUL. Character literals reject `\xHH` at present
(write the number). Raw strings `r"C:\x"` have no escapes. f-strings: `f"{expr}"`; a
hole holds one expression of any type. `{{` and `}}` are a literal brace
(a single `}` is an error).

A hole may carry a **format spec** after `:` — a comma-separated list of
flags, **in any order**, each naming one thing:

```resid
Int main() {
    Int n = 1234567;
    Float pi = 3.14159265;
    Dec price = 12.50m;
    println(f"{n:group}");                  //> 1,234,567
    println(f"{n:12}|{n:12, left}|");       //>      1234567|1234567     |
    println(f"{n:hex, width 8, fill '.'}"); //> ..12d687
    println(f"{-42:zero, width 6}");        //> -00042
    println(f"{pi:precision 2}");           //> 3.14
    println(f"{price:trim}");               //> 12.5
    return 0;
}
```

Flags: `width N` (or a bare `8`), `left` / `right` / `center`, `fill 'x'`
(or `zero` for `0` after a sign), `plus` / `space` / `minus`, `hex` / `oct`
/ `bin`, `upper` / `lower`, `group`, `precision N` (or `.N`), `auto` /
`decimal` / `scientific` / `percent`, `trim`.

Alignment defaults to `right` for a number and `left` for anything else, so
a spec says only what differs. A flag the value's type cannot mean is a
**compile error** (E0413), not a silent no-op: `hex` needs an integer,
`precision` a Float (a Dec accepts it but ignores it at present: round
with `dN`), `trim` a Dec, `group` and the sign flags a number.
A spec only changes how text is written, so when the value is known it
reduces at compile time (`f"{n:group}"` is a literal).

```resid
Int main() {
    Str s = "héllo";
    println(f"{str_len(s)} {str_char_at(s, 1)} {str_slice(s, 1, 3)}");  //> 5 233 él
    println(str_from_code(97) + str_to_upper(s));                         //> aHÉLLO
    println(f"{str_index_of(s, "l", 0)} {str_contains(s, "ll")}");       //> 2 true
    List(Str) parts = str_split("a,b,,c", ",");
    println(f"{parts.len()} " + str_join(parts, "|"));                   //> 4 a|b||c
    println("{{" + f"{1 + 1}" + "}}");                                   //> {{2}}
    println(r"C:\path");                                                 //> C:\path
    println(f"{str_len("a\tb\x41")} {'\''} {'\t'}");                     //> 4 39 9
    return 0;
}
```

```resid
//! compile-error: unknown escape
Int main() { Str s = "C:\dir"; return 0; }
```

Full builtin list: [stdlib.md](stdlib.md).

## List(T)

Persistent immutable list. Literal `[1, 2, 3]`; empty `[]` takes its element
type from the declared type. Index `xs[i]` is bounds-checked (abort on miss).

| Operation | Result |
|---|---|
| `xs.len()` | `Int` |
| `xs[i]` | element, abort if out of range |
| `xs[a..b]`, `xs[a..]`, `xs[..b]`, `xs[a..=b]` | new `List(T)` (`..` half-open, `..=` closed) |
| `xs.with(i, v)` | new list with element i replaced (checked) |
| `xs.concat(ys)` | new list; `acc.concat([x])` is the append idiom |
| `xs.contains(v)` | integer, Float or Str elements only |
| `xs.reverse()` | new list |
| `xs.sum()` | `List(Int)` or `List(Float)` |
| `sort(xs)` | Int/Float/Str elements; others need `using = Ord(T)` |

No `map`/`filter`/`fold` builtins; write them with closures
([functions-and-closures.md](functions-and-closures.md)) or recursion.
`==` on lists is a compile error unless you declare `Eq(List(T)) = f`
([behaviors.md](behaviors.md)).

```resid
Int main() {
    List(Int) xs = [5, 3, 9];
    List(Int) more = xs.concat([1]);
    List(Int) none = [];
    println(f"{more} {more[1..3]} {xs.contains(9)} {xs.sum()}");  //> [5, 3, 9, 1] [3, 9] true 17
    println(f"{sort(xs)} {xs.reverse()} {none.len()}");           //> [3, 5, 9] [9, 3, 5] 0
    println(f"{xs.with(1, 7)} {xs[0..=1]}");                       //> [5, 7, 9] [5, 3]
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
form). Generic records: `type Pair(T) = { T a; T b; };`, with `Pair {.a = 1,
.b = 2}` inferring `Pair(Int)`. Single uppercase letters are type
parameters, so `type P = ...` is E0222: use a longer name. Built-in `==`
covers numbers, Bool and Str; on a record, list, Option or sum it is a
compile error until you declare an `Eq` instance:

```resid
type Pt = { Int x; Int y; };
Bool pt_eq(Pt a, Pt b) { return a.x == b.x && a.y == b.y; }
Eq(Pt) = pt_eq;

Int main() {
    Pt a = Pt {.x = 1, .y = 2};
    println(f"{a == Pt {.x = 1, .y = 2}} {a != a}");   //> true false
    return 0;
}
```

## Sum types

```resid
type Shape = Circle(Float) | Rect(Float, Float) | Nothing;
type Tree = Node(Branch) | Leaf;          // recursion goes through a variant
type Branch = { Tree l; Tree r; Int v; };

Float area(Shape s) {
    return match s {
        Circle(r) => 3.0 * r * r,
        Rect(w, h) => w * h,
        Nothing => 0.0
    };
}

Int sum(Tree t) {
    return match t { Node(b) => b.v + sum(b.l) + sum(b.r), Leaf => 0 };
}

Int main() {
    Tree t = Node(Branch {.l = Leaf, .r = Node(Branch {.l = Leaf, .r = Leaf, .v = 2}), .v = 1});
    println(f"{area(Rect(3.0, 2.0))} {area(Nothing)} {sum(t)}");   //> 6 0 3
    println(f"{Rect(1.5, 2.0)}");                                  //> Rect(1.5, 2)
    return 0;
}
```

- A variant carries zero or more payloads, built and matched by position:
  `Rect(3.0, 4.0)`, `Rect(w, h) =>`. A pattern binds all of them or none
  (`Rect(w)` is an error); `_` discards one (`Rect(_, h)`).
- Patterns are flat: `Name(a, b)`, `Name`, `_`. No nested patterns
  (`Some(Some(x))`), no literal patterns (`0 =>`, `"a" =>`): use `if`.
  `if (Some(x) = opt) { ... }` tests one variant.
- Variants print by name (`Circle(1)`, `Nothing`); define a `Show` instance
  for custom text ([behaviors.md](behaviors.md)).
- Generic sums: `type Box(T) = Full(T) | Empty;` then `Box(Int) b = Full(3);`;
  payload positions are independent (`Cell(T, Int)`).

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
Positive (value > 0) does not hold`. Float constraints work the same
(`type Percent = Float[value >= 0.0 && value <= 1.0];`). Use constraint
types on bindings, not in signatures: a `Positive` parameter rejects every
`Int` argument (a `Positive` binding included), and a function returning a
constraint type is miscompiled at present.

## Fixed-capacity types

`Str(N)` (N UTF-8 bytes), `Bytes(N)`, `List(T, N)`: stored inline, never on
the heap. A literal must fit (compile error otherwise). Capacity changes only
by cast; a narrowing cast keeps a prefix of whole code points. Builtins
(`println`, `str_len`) accept `Str(N)`; your own functions need an exact type,
so cast `(Str)s`. `List(T, N).len()` and `Bytes(N).len()` are N; unset slots
are zero. `s[i]` (a code point of a `Str(N)`), `b[i]` (a byte) and `xs[i]`
are bounds-checked; `xs.with(i, v)` replaces an element; `.capacity()` is N.
`Eq`/`Ord`/`Hash` do not cover them: cast to the heap form to compare.

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
    Bytes(4) b = b"ab";
    println(f"{s[1]} {b[0]} {b} {xs.with(3, 7)} {s.capacity()}");  //> 98 97 b"ab\x00\x00" [10, 20, 0, 7] 8
    return 0;
}
```

`StrBuf(N)`, `BytesBuf(N)` and `ListBuf(T, N)` fill a fixed value in place;
a push past capacity is recorded, `finish()` then aborts and `try_finish()`
returns `Err(length asked for)`:

```resid
Int main() {
    BytesBuf(3) bb = BytesBuf();
    Bytes(3) out = bb.push(1).push(255).finish();
    StrBuf(3) sb = StrBuf();
    Result(Str(3), Int) r = sb.push("abcd").try_finish();
    println(f"{out} {r}");                        //> b"\x01\xff\x00" Err(4)
    return 0;
}
```

```resid
//! compile-error: exceeds Str(2)
Int main() { Str(2) w = "éé"; return 0; }
```

A heap `Bytes` (`b"abc"`, `.len()`) has no indexing and ends at its first
zero byte (`b"a\x00b".len()` is 1); `Bytes(N)` keeps zeros. The stdlib and
the filesystem provider use `List(Int)` for byte data; prefer it.

## Vector types

`Vec(T, N)`: N lanes (2 to 64, a power of two) of `Int(8/16/32/64)`, the same
`UInt` widths, `Float(32)` or `Float`, held in registers. Built from a list
literal of exactly N elements, `splat(x)` or `lanes()` (0, 1, ...) in a typed
slot. Operators work lanewise (integer lanes checked; `v.wrapping_add(w)`
wraps; no integer `/`), a scalar operand broadcasts, comparisons give a mask
`Vec(Bool, N)`. Also `v[i]`, `v.with(i, x)`, `v.sum()`, `v.shuffle(idx)`,
`m.any()`, `m.all()`, `m.bits()`, `select(m, a, b)`, `sqrt`/`min`/`max`
lanewise, `v.to_list()`, and `(Vec(U, N))v` for widening and int-to-float.
A vector cannot sit inside another type or be captured by a lambda (E0411),
and an f-string shows it only through `v.to_list()`.

```resid
Int main() {
    Vec(Float, 4) v = [1.0, 2.0, 3.0, 4.0];
    Vec(Float, 4) h = splat(0.5);
    Vec(Float, 4) w = v * 2.0 + h;
    Vec(Bool, 4) m = w > 4.0;
    Vec(Int(32), 4) k = lanes();
    println(f"{select(m, w, h).sum()} {w.to_list()} {m.bits()} {k.to_list()}");  //> 20 [2.5, 4.5, 6.5, 8.5] 14 [0, 1, 2, 3]
    return 0;
}
```

## Closure and builder types

`Ret closure(A, B)` is a closure type ([functions-and-closures.md](functions-and-closures.md)).
`StrBuf` and `ListBuf(T)` are linear builders ([performance-and-memory.md](performance-and-memory.md)).

## Printing values

`f"{v}"` renders any value. At top level: numbers, Bool, Str as is, Dec at
its precision. Containers: lists `[1, 2, 3]`, records
`Point { x: 1, y: 2 }`, maps `{"a": 1}`, sets `{1, 2}`, variants by name
(`Some(3)`, `None`, `Ok(3)`, `Err("x")`, `Rect(1.5, 2)`, `Nothing`), bytes as
a literal (`b"ab\x00"`); strings
inside containers are quoted (`["a", "b"]`). A `Show(T)` instance is used
wherever a `T` appears, including inside lists, options and records
([behaviors.md](behaviors.md)).
