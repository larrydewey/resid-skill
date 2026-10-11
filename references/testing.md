# Testing

Three layers, from cheapest to most complete:

1. `assert(cond, "msg")` / `rt_assert(...)` inside code: abort on violation.
2. `expect(value).matcher(...)` in **test blocks** or **registered cases**.
3. Golden tests: build the program, run it, diff stdout and the exit code
   (how the Resid repo's conformance suite and this skill's
   `scripts/check-examples.sh` work).

## Test blocks

```resid
Int add(Int a, Int b) { return a + b; }

test "add: identity" {
    expect(add(0, 5)).toEqual(5);
    expect(add(5, 0)).toEqual(5);
}

test "strings and lists" {
    expect("resid").toHaveLength(5);
    expect("resid").toMatch("^re[a-z]+d$");
    expect([1, 2, 3]).toContain(3);
}

@requires(filesystem(readonly))
test "needs a grant like any function" {
    expect(filesystem.is_dir("/")).toBeTrue();
}
```

- `test "name" { statements }` at top level. Matchers are type-checked
  against the value's type (`expect(1).toEqual("x")` is a compile error).
- A test block is granted only what its own `@requires` lists (E0219).
- In a normal build, test blocks are checked but not run.
- `residc test file.resid [--filter REGEX] [--format pretty|tap|json]`
  discovers the blocks, generates the entry point, runs it and returns 0 (all
  passed), 1 (failures) or 2 (compile error, no test blocks, or the file
  defines `main`). Filtered-out tests show as `- name (skipped)` in pretty
  output (with `Skipped: N` in the summary) and `# SKIP filtered` in TAP.
- `residc test [--root DIR] [--filter REGEX] [--format F]` with no file runs
  every `*_test.resid` under `DIR` (default `.`), one binary per file, and
  exits 2 if any file failed to compile, else 1 on any failure.
- Known discovery bug at HEAD: a `test` block that directly follows a record
  declaration (`type Point = { Int x; Int y; };`) is not found ("no `test`
  blocks found"). Put the tests first, or a function between.

```text
$ residc test math_test.resid
math_test
  ✓ add: identity (0ms)
  ✓ add: commutativity (0ms)
  ✓ mul: zero annihilates (0ms)
  ✓ strings and lists (0ms)

Failures: 0 | Passed: 4 | Duration: 0ms
```

## Explicit registration (lib/testing.resid)

Use this when cases are generated from data or the file needs its own
`main`. Cases are data: a name and a zero-argument closure. `run_tests` prints the
report and returns the exit code.

```resid
import "testing.resid";

Int gcd(Int a, Int b) { return if (b == 0) { a } else { gcd(b, a % b) }; }
Int at(List(Int) xs, Int i) { return xs[i]; }

Int main() {
    List(TestCase) cases = [
        test_case("gcd", lambda() { expect(gcd(12, 18)).toEqual(6) }),
        test_case("aborts", lambda() { Int closure() f = lambda() { at([1], 5) }; expect(f).toThrow() }),
        test_case("close", lambda() { expect(0.1 + 0.2).toBeCloseTo(0.3, 9) })
    ];
    return run_tests("math", cases);
}
```

Output (pretty format; durations vary):

```text
math
  ✓ gcd (0ms)
  ✓ aborts (0ms)
  ✓ close (0ms)

Failures: 0 | Passed: 3 | Duration: 0ms
```

A failing case prints `✗ name`, then `expectation failed: toEqual` and the
actual and expected values, and the run exits 1. The program reads
`RESID_TEST_FORMAT=pretty|tap|json` and `RESID_TEST_FILTER=<regex>` (a
search over the case name); `residc test` sets both from its own `--format`
and `--filter`, so set them only when running a binary directly.
`property_case(name, body)` registers a case the same way; it runs `body`
once (no generators yet).

`import "testing.resid";` resolves from anywhere: imports fall back to the
compiler's stdlib directory (`$RESID_HOME/lib` in an install, else
`RESID_HOME/../../lib`, or `./lib`).

## Matchers

| Matcher | Receiver | Checks |
|---|---|---|
| `toEqual(v)` / `toBe(v)` | any | equality (see the bug below) |
| `toNotEqual(v)` | any | inequality |
| `toBeTrue()` / `toBeFalse()` | `Bool` | |
| `toHaveLength(n)` | `List(T)` or `Str` | length (code points for Str) |
| `toContain(x)` | `List(T)` or `Set(T)` | membership (not `Str` or `Map`) |
| `toMatch(re)` | `Str` | regex search anywhere in the string, `lib/regex.resid` syntax: classes, `\d \w \s`, anchors, groups, `\|`, counted repeats, flags `(?i)` (ASCII folding), `(?m)`, `(?s)`, `(?x)`; a pattern that does not compile matches nothing |
| `toBeCloseTo(x, digits)` | `Float` | equal to `digits` decimal places: `abs(actual - x) < 0.5 * 10^-digits` (`expect(2.44).toBeCloseTo(2.4, 1)` passes, `2.46` fails); `digits` is required |
| `toBeNull()` | `Option(T)` | is `None` |
| `toSatisfy(pred)` | any `T` | `Bool closure(T)` returns true |
| `toThrow()` | `Ret closure()` | calling it aborts |

**Bug at HEAD:** on a `List`, `Set`, `Map` or record (also inside an `Option`), `toEqual` always
passes and `toNotEqual` always fails, whatever the values. It works on
scalars, `Str`, and `Option` or sum values of those. Until it is fixed, compare the
printed form or the parts:

```resid
test "lists by their text" {
    List(Int) xs = [3, 1, 2];
    expect(f"{sort(xs)}").toEqual("[1, 2, 3]");
    expect(xs).toHaveLength(3);
    expect(xs[0]).toEqual(3);
}
```

```resid
test "all matchers" {
    expect(5).toBe(5);
    expect(5).toNotEqual(6);
    expect(false).toBeFalse();
    expect([1, 2]).toHaveLength(2);
    Set(Int) s = {1};
    expect(s).toContain(1);
    expect(9).toSatisfy(lambda(v) { v > 3 });
    Option(Int) none = None;
    expect(none).toBeNull();
}
```

There is no property-based testing (`forall`, generators), snapshots,
custom matchers, parallel runs or per-test timeouts yet (SPEC-testing.md lists them as not implemented).

## Golden tests

For whole programs, compare stdout and exit status. A minimal harness:

```sh
residc prog.resid -o /tmp/prog --profile debug && /tmp/prog > got.txt; echo $? > got.exit
diff -u want.txt got.txt && diff want.exit got.exit
```

Useful exit statuses: 0 normal, the value `main` returned, 134 abort.
Use `rt` to keep inputs residual when you want to test the runtime path
rather than the compile-time folded result (`Int n = rt 5;`).

## Testing tips specific to Resid

- Most logic is pure: test it without capabilities; keep I/O in `main`.
- Force runtime behavior with `rt` (overflow checks, bounds checks and
  arithmetic on known values are folded or proven at compile time).
- Check compile errors in a harness by grepping the compiler output for the
  error code (`E0219`, `E0301`, ...), as the conformance suite's `.compile`
  files do.
- Golden output: remember maps print in hash order and floats in shortest
  round-trip form; sort keys before printing.
