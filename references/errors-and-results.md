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

Str show(Result(Config, Str) r) {
    return match r { Ok(c) => f"{c.host} on {c.port}", Err(e) => "error: " + e };
}

Int main() {
    println(show(parse_config("example.org:443")));   //> example.org on 443
    println(show(parse_config("example.org:http")));  //> error: port is not a number: http
    println(show(parse_config("nope")));              //> error: expected host:port
    return 0;
}
```

- `?` works in functions returning `Option` or `Result`. Match the kinds:
  `Option` inside an `Option` function, `Result` inside a `Result` function
  with the same error type.
- Do not use `?` in `Int main()` (it fails in code generation). Handle the
  error in main with `else` or `match`.

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
`return`, `break` or abort with `todo()` (those are `Void`). For an early
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

Note: `f"{result}"` on a `Result` prints `Some(...)`/`None` today. Always
`match` a `Result` before printing it.

## Aborts

| Cause | Message |
|---|---|
| checked arithmetic overflow, `MIN / -1` | `integer overflow in checked arithmetic` |
| integer `/ 0` or `% 0` | `integer division by zero` |
| checked conversion out of range (`u8(300)`) | `numeric conversion out of range` |
| `xs[i]` out of range | `list index out of bounds: index 3, length 1` |
| `assert(c, msg)` / `rt_assert(c, msg)` false | `assertion failed: msg` |
| `todo(msg)` / `unimplemented(msg)` reached | `not yet implemented: msg` |
| refutable binding `Some(v) = none_value;` | `irrefutable pattern did not match` |
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
    Str s = match r { Ok(v) => f"ok {v}", Err(e) => "region failed" };
    println(s);          //> region failed
    return 0;
}
```

`RegionError` has one field, `message: Str`.

## Checked vs. explicit arithmetic

Overflow is an error, not wrap-around. Where wrap-around or clamping is the
intent, say so: `wrapping_add`, `wrapping_u8(x)`, `saturating_mul`. Widen
before an operation that needs headroom: `(Int(128))a * b`.

## Validating input

Use `str_is_int`/`str_is_float` before `str_parse_int`/`str_parse_float`
(`str_parse_int("abc")` returns 0, not an error), and check lengths
before indexing. Constraint types (`Int[value > 0]`) only check known values
at compile time; validate residual input with `if` or `rt_assert`.
