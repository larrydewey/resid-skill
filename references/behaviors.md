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
| `Ord(T)` | `Int f(T a, T b)` | `sort(xs, using = Ord(T))` |
| any name, e.g. `ByAge(T)` | `Int f(T a, T b)` | `sort(xs, using = ByAge(T))` |
| `Reverse(B(T))` | (combinator) | flips any comparator behavior |
| `Show(T)` | `Str f(T v)` | every f-string hole of type `T`, including a record field of type `T` |
| `Ord`/`Eq`/`Hash` for every numeric width, `Ord(Str)` | built in | `sort(xs)` on Int/Float/Str lists picks them automatically |

Comparator contract: negative if `a` sorts before `b`, 0 if equal, positive
if after. `sort` does not change equal elements' order in tests so far, but
the spec does not promise stability.

## Ordering: Ord, named orders, Reverse

```resid
type Emp = { Str name; Int age; Int pay; };

Int by_age(Emp a, Emp b) { return a.age - b.age; }
Int by_pay(Emp a, Emp b) { return a.pay - b.pay; }

Ord(Emp) = by_age;            // the "default" order, still selected explicitly
ByPay(Emp) = by_pay;          // a second, named order

Str names(List(Emp) xs, Int i, StrBuf b) {
    if (i >= xs.len()) { return b.finish(); }
    Str sep = if (i == 0) { "" } else { " " };
    return names(xs, i + 1, b.push(sep).push(xs[i].name));
}

Int main() {
    List(Emp) es = [
        Emp {.name = "ann", .age = 40, .pay = 50},
        Emp {.name = "bo", .age = 25, .pay = 70},
        Emp {.name = "cy", .age = 31, .pay = 60}
    ];
    println(names(sort(es, using = Ord(Emp)), 0, StrBuf()));             //> bo cy ann
    println(names(sort(es, using = Reverse(Ord(Emp))), 0, StrBuf()));    //> ann cy bo
    println(names(sort(es, using = ByPay(Emp)), 0, StrBuf()));           //> ann cy bo
    List(Int) xs = [3, 1, 2];
    println(f"{sort(xs)} {sort(xs, using = Reverse(Ord(Int)))}");        //> List(Int(64))(1, 2, 3) List(Int(64))(3, 2, 1)
    return 0;
}
```

Rules:

- For your own types, `sort(xs)` alone is an error even when exactly one
  instance exists; always pass `using = ...`.
- Each instance needs its **own** impl function. Two instances naming the same
  function (`Ord(T) = c; ByV(T) = c;`) or a repeated instance fails in
  code generation (`invalid redefinition of function '__cmp_c'`).
- The instance type must be a **single identifier**: a builtin like `Int`,
  `Str`, `Float`, `Bool`, or your own record/sum type. `Ord(Int(32))`,
  `Show(Option(Int))`, `Show(Box(Int))` do not parse or do not check, and an
  alias does not help. Wrap the value in a record ("newtype") instead.
- A user instance for a builtin type is used when selected explicitly:
  after `Ord(Int) = desc;`, `sort(xs, using = Ord(Int))` sorts descending
  while plain `sort(xs)` keeps the builtin ascending order. `Show(Int) = f`
  is ignored: builtin types keep their builtin text.
- An impl that uses capabilities makes every `sort` that selects it need them
  too (E0219: "uses (through `by_run`) capability `process`").

### Multi-key and derived orders

Compose in the impl function; there are no comparator combinators beyond
`Reverse`.

```resid
type Row = { Str team; Int score; };

Int str_cmp(Str a, Str b, Int i) {
    Int la = str_len(a);
    Int lb = str_len(b);
    if (i >= la || i >= lb) { return la - lb; }
    Int d = str_char_at(a, i) - str_char_at(b, i);
    return if (d != 0) { d } else { str_cmp(a, b, i + 1) };
}

// team ascending, then score descending
Int team_then_score(Row a, Row b) {
    Int t = str_cmp(a.team, b.team, 0);
    return if (t != 0) { t } else { b.score - a.score };
}
Standings(Row) = team_then_score;

Str show_row(Row r) { return f"{r.team}:{r.score}"; }
Show(Row) = show_row;

Int main() {
    List(Row) rs = [
        Row {.team = "red", .score = 3}, Row {.team = "blue", .score = 1},
        Row {.team = "red", .score = 9}, Row {.team = "blue", .score = 5}
    ];
    List(Row) s = sort(rs, using = Standings(Row));
    println(f"{s[0]} {s[1]} {s[2]} {s[3]}");     //> blue:5 blue:1 red:9 red:3
    return 0;
}
```

Beware `a - b` comparators on values near the Int limits: the subtraction is
checked and can abort. Use `if (a < b) { -1 } else { if (a > b) { 1 } else { 0 } }`
for full-range integers and for Floats.

## Built-in generic behaviors and verbs

The numeric family gets `Eq`, `Ord` and `Hash` generically: every width has
them without declarations, and the built-in instance may be named with a
parenthesized type (only *user* instance declarations are limited to single
identifiers). The list verbs and math helpers are generic in the same way.

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
    println(f"{it}");           //> Item(tea, $12.05)
    println(f"{High}");         //> HIGH
    return 0;
}
```

Without `Show`, a payload-less variant prints `null` and a variant with a
payload prints oddly; define `Show` for every sum type you print. `Show` is
not applied inside lists (`List(Money)` prints `…` for each element) or
inside `Option` (prints `Some<Option(T)>`): join lists yourself and match
options.

## "Behavioralizing" code

Behaviors in Resid are one tool among three for varying behavior. Pick by
when the choice is known:

| Choice known... | Use | Example |
|---|---|---|
| at compile time, per type | behavior instance | `sort(xs, using = ByPay(Emp))`, `Show(Money)` |
| at compile time, per call | a named comparator/formatter function, or a default parameter | `fmt(x, width = 8)` |
| at run time, open set | a closure value (strategy) | `Int closure(Int, Int) pick` in a record |
| at run time, closed set | a sum type + `match` | `type Mode = Fast | Safe;` |

### 1. Replace ad-hoc sort helpers with instances

Before (hand-written insertion sort per field) - after: one comparator per
order, an instance per comparator, `sort(..., using = ...)` at call sites.
The compiler inserts the comparator; the call sites say which order they mean.

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

### 5. Newtypes to attach behavior to a builtin

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
