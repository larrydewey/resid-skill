# Behaviors

A behavior is **compile-time knowledge attached to a type**: "how to order a
`T`", "how to show a `T`". It is not a trait or interface system (the spec
lists those as non-goals): there are no method tables, no generic bounds, no
dynamic dispatch. An instance names a behavior, a type and one ordinary
function that implements it:

```text
Name(Type) = impl_function;
```

The compiler checks the function's signature, inserts the behavior where it is
selected, and reduces it like any other known function.

## What exists today

| Behavior | Impl signature | Used by |
|---|---|---|
| `Ord(T)` | `Int f(T a, T b)` | `sort(xs)` (inserted when it is the unique order for `T`), `sort(xs, using = Ord(T))` |
| `Reverse(Ord(T))` | (combinator) | flips a comparator: `sort(xs, using = Reverse(Ord(T)))` |
| `Show(T)` | `Str f(T v)` | every f-string hole of type `T`, including inside records, lists and options |
| `Ord`/`Eq`/`Hash` for every numeric width, `Ord(Str)` | built in | `sort(xs)` on Int/Float/Str lists |
| any other name, e.g. `ByPay(T)` | `Int f(T a, T b)` | accepted, but **broken in code generation today** (see below) |

Comparator contract: negative if `a` sorts before `b`, 0 if equal, positive
if after. `sort` kept equal elements in order in tests, but the spec does not
promise stability.

## Ordering: Ord and Reverse

```resid
type Emp = { Str name; Int age; Int pay; };

Int by_age(Emp a, Emp b) { return a.age - b.age; }
Ord(Emp) = by_age;

Str show_emp(Emp e) { return e.name; }
Show(Emp) = show_emp;

Int main() {
    List(Emp) es = [
        Emp {.name = "ann", .age = 40, .pay = 50},
        Emp {.name = "bo", .age = 25, .pay = 70},
        Emp {.name = "cy", .age = 31, .pay = 60}
    ];
    println(f"{sort(es)}");                              //> [bo, cy, ann]
    println(f"{sort(es, using = Reverse(Ord(Emp)))}");   //> [ann, cy, bo]
    List(Int) xs = [3, 1, 2];
    println(f"{sort(xs)} {sort(xs, using = Reverse(Ord(Int)))}");   //> [1, 2, 3] [3, 2, 1]
    return 0;
}
```

Rules:

- One `Ord(T)` instance per type; `sort(xs)` inserts it, `using =` selects it
  explicitly. A duplicated instance declaration fails in clang (`invalid
  redefinition of function '__cmp_c'`); one impl function may serve several
  types' instances.
- Instance types may be any type: `Ord(Int(32)) = desc;`,
  `Ord(Emp) = ...`, `Show(Level) = ...`.
- A user instance for a builtin type is used when selected explicitly:
  after `Ord(Int) = desc;`, `sort(xs, using = Ord(Int))` sorts descending
  while plain `sort(xs)` keeps the builtin ascending order.
- Do not define `Show` for builtin types (`Show(Int)`): top-level holes keep
  the builtin text, but holes inside other `Show` impls start using yours.
- An impl that uses capabilities makes every `sort` that selects it need them
  too (E0219: "uses (through `by_run`) capability `process`").
- **Known issue (commit 79f9062):** a behavior with any name other than `Ord`
  (`ByPay(Emp) = by_pay; sort(es, using = ByPay(Emp))`, also under
  `Reverse`) fails in clang with `use of undefined value '@__cmp_by_pay'`
  unless the same impl is also some type's `Ord` instance. For a second
  order on a type, sort with a comparator closure (next section).

### Other orders: comparator closures

`sort` only takes behaviors, so for extra orders write a small stable merge
sort that takes a comparator closure (monomorphic: one per element type):

```resid
type Row = { Str team; Int score; };

Int str_cmp(Str a, Str b, Int i) {
    Int la = str_len(a);
    Int lb = str_len(b);
    if (i >= la || i >= lb) { return la - lb; }
    Int d = str_char_at(a, i) - str_char_at(b, i);
    return if (d != 0) { d } else { str_cmp(a, b, i + 1) };
}

// team ascending, then score descending: compose inside one comparator
Int team_then_score(Row a, Row b) {
    Int t = str_cmp(a.team, b.team, 0);
    return if (t != 0) { t } else { b.score - a.score };
}

List(Row) merge(List(Row) a, List(Row) b, Int closure(Row, Row) cmp, Int i, Int j, ListBuf(Row) out) {
    if (i >= a.len() && j >= b.len()) { return out.finish(); }
    if (j >= b.len()) { return merge(a, b, cmp, i + 1, j, out.push(a[i])); }
    if (i >= a.len()) { return merge(a, b, cmp, i, j + 1, out.push(b[j])); }
    if (cmp(b[j], a[i]) < 0) { return merge(a, b, cmp, i, j + 1, out.push(b[j])); }
    return merge(a, b, cmp, i + 1, j, out.push(a[i]));
}

List(Row) sort_rows(List(Row) xs, Int closure(Row, Row) cmp) {
    if (xs.len() <= 1) { return xs; }
    Int mid = xs.len() / 2;
    return merge(sort_rows(xs[0..mid], cmp), sort_rows(xs[mid..], cmp), cmp, 0, 0, ListBuf());
}

Str show_row(Row r) { return f"{r.team}:{r.score}"; }
Show(Row) = show_row;

Int main() {
    List(Row) rs = [
        Row {.team = "red", .score = 3}, Row {.team = "blue", .score = 1},
        Row {.team = "red", .score = 9}, Row {.team = "blue", .score = 5}
    ];
    println(f"{sort_rows(rs, lambda(a, b) { team_then_score(a, b) })}");   //> [blue:5, blue:1, red:9, red:3]
    println(f"{sort_rows(rs, lambda(a, b) { a.score - b.score })}");       //> [blue:1, red:3, blue:5, red:9]
    return 0;
}
```

Beware `a - b` comparators on values near the Int limits: the subtraction is
checked and can abort. Use `if (a < b) { -1 } else { if (a > b) { 1 } else { 0 } }`
for full-range integers and for Floats.

## Built-in generic behaviors and verbs

The numeric family gets `Eq`, `Ord` and `Hash` generically: every width has
them without declarations, and the built-in instance may be named with a
parenthesized type (`Ord(UInt(16))`). The list verbs and math helpers are generic in the same way.

```resid
Int main() {
    List(UInt(16)) a = [u16(300), u16(100), u16(200)];
    List(UInt(16)) up = sort(a, using = Ord(UInt(16)));
    List(Float) f = [2.5, -1.0, 0.5];
    println(f"{up[0]} {sort(f)[0]} {sort(f, using = Reverse(Ord(Float)))[0]}");   //> 100 -1 2.5
    List(Int(8)) small = [i8(3), i8(-7)];
    println(f"{small.contains(i8(-7))} {f.contains(0.5)} {f.sum()}");            //> true true 2
    Int(32) x = i32(-9);
    println(f"{abs(x)} {min(u16(4), u16(2))} {clamp(1.5, 0.0, 1.0)}");            //> 9 2 1
    return 0;
}
```

- `sort(xs)` inserts the built-in `Ord` for integer, Float and Str elements.
- `xs.contains(v)` needs integer (up to 64-bit), Float or Str elements;
  `xs.sum()` needs `List(Int)` or `List(Float)`.
- `abs`/`min`/`max`/`clamp` accept any single numeric type except Dec.
- A user function with the same name as a verb (`Int reverse(List(Int) xs)`)
  takes precedence over the built-in method.

### Ordering a sum type

Map each variant to a rank in the comparator:

```resid
type Level = Low | Mid | High;

Int rank(Level l) { return match l { Low => 0, Mid => 1, High => 2 }; }
Int by_rank(Level a, Level b) { return rank(a) - rank(b); }
Ord(Level) = by_rank;

Str show_level(Level l) { return match l { Low => "low", Mid => "mid", High => "high" }; }
Show(Level) = show_level;

Int main() {
    List(Level) ls = [High, Low, Mid, Low];
    List(Level) s = sort(ls, using = Reverse(Ord(Level)));
    println(f"{s[0]} {s[1]} {s[2]} {s[3]}");   //> high mid low low
    return 0;
}
```

## Show: how a type is written

```resid
type Money = { Int cents; };
type Item = { Str name; Money price; };
type Level = Low | Mid | High;

Str show_money(Money m) {
    Int c = m.cents % 100;
    Str pad = if (c < 10) { "0" } else { "" };
    return f"${m.cents / 100}." + pad + f"{c}";
}
Show(Money) = show_money;

Str show_level(Level l) { return match l { Low => "low", Mid => "mid", High => "HIGH" }; }
Show(Level) = show_level;

Int main() {
    Money m = Money {.cents = 1205};
    Item it = Item {.name = "tea", .price = m};
    println(f"cost {m}");       //> cost $12.05
    println(f"{it}");           //> Item { name: "tea", price: $12.05 }
    println(f"{High}");         //> HIGH
    return 0;
}
```

Without `Show`, values print structurally (`Money { cents: 1205 }`,
variants by name: `High`). With it, the instance is used everywhere a
`T` appears: `[$1.00, $2.50]` for a `List(Money)`, `Some($3.00)` for an
option.

## "Behavioralizing" code

Behaviors in Resid are one tool among three for varying behavior. Pick by
when the choice is known:

| Choice known... | Use | Example |
|---|---|---|
| at compile time, per type | behavior instance | `Ord(Emp)` + `sort(xs)`, `Show(Money)` |
| at compile time, per call | a named comparator/formatter function, or a default parameter | `fmt(x, width = 8)` |
| at run time, open set | a closure value (strategy) | `Int closure(Int, Int) pick` in a record |
| at run time, closed set | a sum type + `match` | `type Mode = Fast | Safe;` |

### 1. Replace ad-hoc sort helpers with instances

Before: a hand-written sort per call site. After: the type's natural order
as `Ord(T)`, so `sort(xs)` and `sort(xs, using = Reverse(Ord(T)))` just
work; secondary orders go through one shared comparator-closure sort.

### 2. Put display logic in Show

Every `f"..."` that formats a type by hand (`f"{m.cents / 100}.{...}"`) turns
into one `Show(T)` function; records containing that type print through it
automatically.

### 3. Strategies as closure records

```resid
type Pricing = { Str name; Int closure(Int) apply; };

Int total(List(Int) items, Pricing p, Int i, Int acc) {
    if (i >= items.len()) { return acc; }
    return total(items, p, i + 1, acc + p.apply(items[i]));
}

Pricing make(Str name, Int percent_off) {
    Int closure(Int) f = lambda(c) { c - c * percent_off / 100 };
    return Pricing {.name = name, .apply = f};
}

Int main() {
    List(Int) cart = [1000, 2500];
    Pricing full = make("full", 0);
    Pricing sale = make("sale", 20);
    println(f"{full.name} {total(cart, full, 0, 0)}");   //> full 3500
    println(f"{sale.name} {total(cart, sale, 0, 0)}");   //> sale 2800
    return 0;
}
```

### 4. Closed sets of behavior as sum types

```resid
type Shape = Circle(Float) | Square(Float);

Float area(Shape s) { return match s { Circle(r) => 3.0 * r * r, Square(w) => w * w }; }
Str label(Shape s) { return match s { Circle(r) => "circle", Square(w) => "square" }; }
Show(Shape) = label;

Int main() {
    List(Shape) xs = [Circle(1.0), Square(2.0)];
    for (Shape s in xs) { println(f"{s}: {area(s)}"); }
    //> circle: 3
    //> square: 4
    return 0;
}
```

Adding a variant makes every non-exhaustive `match` a compile error, which
is the point: the compiler lists every place that needs the new behavior.

### 5. Newtypes: a unit-specific order and text

A record around a builtin gives it its own `Ord`/`Show` without changing
how plain `Float`s sort or print:

```resid
type Celsius = { Float deg; };

Int cmp_c(Celsius a, Celsius b) {
    return if (a.deg < b.deg) { -1 } else { if (a.deg > b.deg) { 1 } else { 0 } };
}
Ord(Celsius) = cmp_c;

Str show_c(Celsius c) { return f"{c.deg}°C"; }
Show(Celsius) = show_c;

Int main() {
    List(Celsius) ts = [Celsius {.deg = 21.5}, Celsius {.deg = -3.0}];
    List(Celsius) s = sort(ts, using = Reverse(Ord(Celsius)));
    println(f"{s[0]} then {s[1]}");     //> 21.5°C then -3°C
    return 0;
}
```

## Things behaviors are not

- Not operator overloading: `==`, `+`, `<` keep their builtin meaning and do
  not look at instances. `Eq(T)`/`Hash(T)` instances are accepted if their
  impl is `(T, T) -> Int`, but `==` on records still does not compile and
  map keys hash structurally.
- Not generic constraints: there is no `T: Ord`. A function that sorts must
  name a concrete element type.
- Not runtime values: `using = Ord(T)` must be written at the call; you
  cannot store a behavior in a variable. Store a closure if you need that.
