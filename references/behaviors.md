# Behaviors and generics

A behavior is **compile-time knowledge about a type**, stated from outside
the type: "how to order a `T`", "how to show a `T`". It is not a trait
system (the spec lists those as non-goals): a type never declares what it
implements, verbs are plain functions (no methods), nothing dispatches at
run time, behaviors do not inherit, and a behavior holds no types of its
own. Every instance is chosen at compile time, before reduction.

## Declaring a behavior and instances

```resid
type Circle = { Float r; };
type Square = { Float side; };

behavior Area(T) {
    Float area(T shape);
}
behavior Shape(T) {
    Float surface(T s);
    Float perimeter(T s);
}

Float circle_area(Circle c) { return 3.0 * c.r * c.r; }
Float sq_area(Square s) { return s.side * s.side; }
Float sq_perimeter(Square s) { return 4.0 * s.side; }
Area(Circle) = circle_area;
Area(Square) = sq_area;
Shape(Square) = { .surface = sq_area, .perimeter = sq_perimeter };

Int main() {
    Square s = Square {.side = 3.0};
    println(f"{area(Circle {.r = 2.0})} {area(s)} {perimeter(s)}");   //> 12 9 12
    return 0;
}
```

- Behavior names start uppercase; parameters are single letters; each
  prototype (no body; there are no default bodies) declares a lowercase verb.
- An instance gives one function, or a record `{ .verb = f, ... }` naming
  every verb exactly once. The function must have the prototype's
  signature with the behavior's parameters replaced by the instance types.
- A verb call picks the instance from its argument types; a type that
  appears only in the result comes from where the result goes:

```resid
type Celsius = { Float deg; };
type Kelvin = { Float deg; };
behavior Convert(A, B) { B convert(A x); }
Kelvin c_to_k(Celsius c) { return Kelvin {.deg = c.deg + 273.15}; }
Convert(Celsius, Kelvin) = c_to_k;

Int main() {
    Kelvin k = convert(Celsius {.deg = 0.0});
    println(f"{k.deg}");   //> 273.15
    return 0;
}
```

## The core behaviors (declared in the prelude)

| Behavior | Verb | Instance signature | Used by |
|---|---|---|---|
| `Eq(T)` | `eq` | `Bool f(T a, T b)` | `==`, `!=` on types without built-in equality |
| `Ord(T)` | `compare` | `Int f(T a, T b)` | `sort`, `Reverse`, `<` `<=` `>` `>=` |
| `Hash(T)` | `hash` | `Int f(T x)` | the verb |
| `Show(T)` | `show` | `Str f(T x)` | f-string holes (also nested in records, lists, options) |
| `Serialize(T)` | `serialize` | `Str f(T x)` | the verb |
| `Allocator(T)` | `allocate` | `T f()` | the verb |

Numbers and `Str` have built-in instances (`"a" < "b"` works, `compare(1, 2)`
is `-1`). `Show` cannot be given for numbers, `Bool` or `Str`. A function of
your own named `show`, `hash`, ... wins over the verb.

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
    println(f"{es[1] < es[2]}");                         //> true
    List(Int) xs = [3, 1, 2];
    println(f"{sort(xs)} {sort(xs, using = Reverse(Ord(Int)))}");   //> [1, 2, 3] [3, 2, 1]
    return 0;
}
```

- One instance per behavior and type; `sort(xs)` inserts it, `using =`
  selects another: `sort(es, using = by_pay)` with a comparator function.
- Comparator contract: negative, zero or positive. Beware `a - b` near the
  Int limits (checked subtraction can abort).
- An impl that uses capabilities makes every user need them (E0219).

## Generic functions and records

A single uppercase letter in a signature or type declaration is a type
parameter. `Int(N)`/`UInt(N)`/`Float(N)` range over widths.

```resid
type Pair(T) = { T a; T b; };

T first(List(T) xs) { return xs[0]; }
Int(N) clamp_pos(Int(N) x) { return if (x < 0) { 0 } else { x }; }

@needs(Ord(T))
T biggest(List(T) xs) { return sort(xs)[xs.len() - 1]; }

List(U) map_all(List(T) xs, U closure(T) f, Int i, ListBuf(U) acc) {
    if (i >= xs.len()) { return acc.finish(); }
    return map_all(xs, f, i + 1, acc.push(f(xs[i])));
}

Int main() {
    Pair(Int) p = Pair {.a = 1, .b = 2};
    Int(8) s = -3;
    println(f"{p} {first(["x"])} {clamp_pos(s)} {biggest([3, 9, 4])}");   //> Pair { a: 1, b: 2 } x 0 9
    println(f"{map_all([1, 2], lambda(x) { x * 10 }, 0, ListBuf())}");     //> [10, 20]
    return 0;
}
```

- Inside a generic body a `T` is opaque: `sort` on `List(T)` needs
  `@needs(Ord(T))`, `f"{x}"` needs `Show(T)`, `==` needs `Eq(T)`, `<` needs
  `Ord(T)`, a verb call needs its behavior (E0226 otherwise).
- Calls infer parameters from arguments, then the expected type
  (`List(Int) xs = empty();`); otherwise E0227. Lambdas, `ListBuf()` and
  `[]` passed to generic calls get their types from the other arguments.
- Each concrete call calls a copy made before reduction; records get one
  layout per concrete type. Polymorphic recursion is E0228. Lambdas are not
  generic; named functions are still not values.
- Only single letters are parameters: an unknown multi-letter type name is
  an error ("unknown type `Pint` (did you mean `Point`?)").

### Instances for generic types, derivations, overrides

```resid
type Pair(T) = { T a; T b; };
type Task = { Str name; Int p; };

@needs(Show(T))
Str show_pair(Pair(T) p) { return f"<{p.a}|{p.b}>"; }
Show(Pair(T)) = show_pair;

Int by_p(Task a, Task b) { return a.p - b.p; }
Ord(Task) = by_p;
@needs(Ord(T))
Bool eq_from_ord(T a, T b) { return compare(a, b) == 0; }
Eq(Task) = eq_from_ord;

@needs(Ord(T))
T top(List(T) xs) { return sort(xs)[0]; }

Int main() {
    Pair(Int) p = Pair {.a = 1, .b = 2};
    Task a = Task {.name = "a", .p = 1};
    println(f"{p} {a == Task {.name = "z", .p = 1}} {top([3, 1, 2], using = Reverse(Ord(Int)))}");   //> <1|2> true 3
    return 0;
}
```

`using = f`, `using = B(T)` or `using = Reverse(..)` overrides a behavior at
one verb call, `sort`, or generic call (the copy uses the override).

## Coherence

- Overlapping instances at one level (`Show(Pair(T))` and
  `Show(Pair(Int))`) are E0225: no specialization.
- Levels: application > library > prelude. A higher-level instance
  replaces a lower one program-wide, library code included (`resid-why prog
  Show` shows "replaced by").
- A library may declare instances only of its own behaviors or types
  (E0224); the application may declare any.
- A generic function's authority is its own `@requires` plus what its
  instances need; the concrete caller holds it (E0219 names the copy, e.g.
  "through `label(Task)`"). A generic declared in a `sandbox` keeps that
  ceiling in every copy.

## Extra orders at run time: comparator closures

`sort` takes behaviors or named comparators known at compile time. For an
order chosen at run time, write a small merge sort that takes a comparator
closure (it can be generic over the element type):

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
