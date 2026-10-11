# Errors and results

Resid has no exceptions and no null. Expected failure is a value:
`Option(T)` (`Some(v)` / `None`) or `Result(T, E)` (`Ok(v)` / `Err(e)`).
Unexpected failure is an **abort**: the process prints `resid: abort: ...`
to stderr and exits with status 134 (inside `spawn`, the abort becomes an
`Err(RegionError)` for the parent instead).

The operators are exactly these four; `try`, `catch`, `orelse`, `!!`,
`unwrap()` do not exist:

| Form | Meaning |
|---|---|
| `T x = e?;` | if `e` is `Err`/`None`, return it from the current function; else bind the payload |
| `T x = e else { default_expr };` | payload, or the block's value when `Err`/`None` |
| `match e { Ok(v) => ..., Err(err) => ... }` | inspect both cases |
| `if (Some(v) = e) { ... } else { ... }` | branch on one case |

## `?` propagation

```resid
type Config = { Str host; Int port; };

Result(Int, Str) parse_port(Str s) {
    if (!str_is_int(s)) { return Err(f"port is not a number: {s}"); }
    Int p = str_parse_int(s);
    if (p < 1 || p > 65535) { return Err(f"port out of range: {p}"); }
    return Ok(p);
}

Result(Config, Str) parse_config(Str line) {
    List(Str) parts = str_split(line, ":");
    if (parts.len() != 2) { return Err("expected host:port"); }
    Int port = parse_port(parts[1])?;
    return Ok(Config {.host = parts[0], .port = port});
}

Str describe(Result(Config, Str) r) {
    return match r { Ok(c) => f"{c.host} on {c.port}", Err(e) => "error: " + e };
}

Int main() {
    println(describe(parse_config("example.org:443")));   //> example.org on 443
    println(describe(parse_config("example.org:http")));  //> error: port is not a number: http
    println(describe(parse_config("nope")));              //> error: expected host:port
    return 0;
}
```

- `?` works in functions returning `Option` or `Result`. Match the kinds:
  `Option` inside an `Option` function, `Result` inside a `Result` function
  with the same error type. The checker does not enforce this yet: a
  mismatch compiles, then returns an empty error (`Err("")`, `None`) or
  crashes. Convert first (`match`, or `else` plus an explicit `return Err(...)`).
- `?` in a function that returns neither (such as `Int main()`) is a compile
  error; handle the value there with `else` or `match`.

The same in an `Option` function, and `if` on one case of a `Result`:

```resid
Option(Int) first_even(List(Int) xs) {
    for (Int x in xs) { if (x % 2 == 0) { return Some(x); } }
    return None;
}

Option(Int) half_first_even(List(Int) xs) {
    Int e = first_even(xs)?;
    return Some(e / 2);
}

Int main() {
    println(f"{half_first_even([3, 8])} {half_first_even([1])}");   //> Some(4) None
    Result(Int, Str) r = Err("bad");
    if (Err(msg) = r) { println(msg); }                            //> bad
    return 0;
}
```

## `else` defaults

```resid
Int main() {
    Map(Str, Int) stock = {"apple": 3};
    Int apples = stock.get("apple") else { 0 };
    Int pears = stock.get("pear") else { 0 };
    Result(Int, Str) r = Err("boom");
    Int v = r else { Int fallback = 40; fallback + 2 };   // statements, then a value
    println(f"{apples} {pears} {v}");                     //> 3 0 42
    return 0;
}
```

The `else` block must produce a value of the payload type. It cannot
`return` or `break` (a parse error), and `todo()` there is `Void` (a type
error). For an early
exit, use `?`, `match` or `if (Some(v) = e) ... else { return ...; }`:

```resid
Int lookup_or_fail(Map(Str, Int) m, Str k) {
    if (Some(v) = m.get(k)) {
        return v;
    }
    println(f"missing key {k}");
    return -1;
}

Int main() {
    Map(Str, Int) m = {"a": 1};
    println(f"{lookup_or_fail(m, "a")} {lookup_or_fail(m, "z")}");
    //> missing key z
    //> 1 -1
    return 0;
}
```

(The output order shows argument evaluation: both calls run before the outer
`println`.)

## Error types

`Str` messages are the common error type. For errors callers must
distinguish, use a sum type and give it a `Show`:

```resid
type ParseError = Empty | BadChar(Int) | TooLong(Int);

Str show_err(ParseError e) {
    return match e {
        Empty => "empty input",
        BadChar(pos) => f"bad character at {pos}",
        TooLong(n) => f"too long ({n} chars)"
    };
}
Show(ParseError) = show_err;

Result(Int, ParseError) digits_value(Str s, Int i, Int acc) {
    if (i >= str_len(s)) { return Ok(acc); }
    Int c = str_char_at(s, i);
    if (c < '0' || c > '9') { return Err(BadChar(i)); }
    return digits_value(s, i + 1, acc * 10 + (c - '0'));
}

Result(Int, ParseError) parse(Str s) {
    if (str_len(s) == 0) { return Err(Empty); }
    if (str_len(s) > 18) { return Err(TooLong(str_len(s))); }
    return digits_value(s, 0, 0);
}

Str report(Str s) {
    return match parse(s) { Ok(v) => f"ok {v}", Err(e) => f"{e}" };
}

Int main() {
    println(report("1234"));   //> ok 1234
    println(report("12x4"));   //> bad character at 2
    println(report(""));       //> empty input
    return 0;
}
```

`f"{r}"` prints a `Result` as `Ok(42)` / `Err("msg")`; match it when you
want your own wording.

## Aborts

| Cause | Message |
|---|---|
| checked arithmetic overflow, `MIN / -1` | `integer overflow in checked arithmetic` |
| integer `/ 0` or `% 0` | `integer division by zero` |
| checked conversion out of range (`u8(300)`) | `numeric conversion out of range` |
| `xs[i]` out of range | `list index out of bounds: index 3, length 1` |
| `assert(c, msg)` / `rt_assert(c, msg)` false | `assertion failed: msg` |
| `todo(msg)` / `unimplemented(msg)` reached | `not yet implemented: msg` / `not implemented: msg` |
| refutable binding `Some(v) = none_value;` | `irrefutable pattern did not match` |
| run-time value bound to a constraint type that fails it | `constraint of Positive (value > 0) does not hold` |
| Dec division by zero / non-integral Dec to Int | `dec: division by zero` / `dec: non-integer to Int` |
| memory budget exceeded | `memory budget exceeded (N MB); set RESID_MEM_LIMIT (MB) to raise it` |

`assert` and `rt_assert` both check at run time (an `assert` whose condition
is known false still aborts at run time rather than failing the build).
`todo()`/`unimplemented()` take an optional `Str` and are fine in code that
never runs.

```resid
//! exit 134
Int main() {
    List(Int) xs = [1, 2, 3];
    Int i = rt 7;
    println(f"{xs[i]}");
    return 0;
}
```

To survive a possible abort, run the work in a `spawn` region:

```resid
Int risky(Int i) { List(Int) xs = [1]; return xs[i]; }

Int main() {
    Int n = rt 5;
    Result(Int, RegionError) r = spawn () { return risky(n); };
    Str s = match r { Ok(v) => f"ok {v}", Err(e) => "failed: " + e.message };
    println(s);          //> failed: list index out of bounds: index 5, length 1
    return 0;
}
```

`RegionError` has one field, `message`: the abort text. A failed native
call inside the region arrives the same way (spec §47).

## Checked vs. explicit arithmetic

Overflow is an error, not wrap-around. Where wrap-around or clamping is the
intent, say so: `wrapping_add`, `wrapping_u8(x)`, `saturating_mul`. Widen
before an operation that needs headroom: `(Int(128))a * b`.

## Validating input

Use `str_is_int`/`str_is_float` before `str_parse_int`/`str_parse_float`
(`str_parse_int("abc")` returns 0, not an error), and check lengths
before indexing. Constraint types (`Int[value > 0]`) check known values at
compile time and residual values at run time (an abort); for recoverable
validation use `if` and return a `Result`.
