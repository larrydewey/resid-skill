# Compile-time reduction

> Compilation is maximal authorized reduction of first-class knowledge.

The compiler is an evaluator. Everything whose inputs are known at compile
time is computed during compilation; the binary contains only the
**residual**: the part that depends on run-time information (providers,
stdin, `rt` values) or that reduction chose not to finish. Reduced and
unreduced programs behave identically; reduction only moves work.

## Knowledge states

Every expression is one of:

| State | Meaning |
|---|---|
| KNOWN | value determined at compile time (literals, pure functions of known values) |
| EFFECT | performs an effect (printing, provider call); order preserved |
| RESIDUAL | depends on run-time values; lowered to code |
| INVALID | carries a diagnostic; program rejected |

Unknown information must enter explicitly: through a provider
(`args.get(1)`, `filesystem.read_all(p)`), stdin, or `rt`.

## What gets reduced

```resid
Int fib(Int n) { return if (n < 2) { n } else { fib(n - 1) + fib(n - 2) }; }
Int pow(Int b, Int e) { return if (e == 0) { 1 } else { b * pow(b, e - 1) }; }

@requires(args)
Int main() {
    Int f = fib(20);           // KNOWN: 6765 is computed by the compiler
    comptime_print(f);         // compiler prints "[comptime_print] 6765"
    Int n = args.count();      // RESIDUAL: provider call
    Int c = pow(n + 1, 3);     // specialized: pow with e = 3 unrolled
    println(f"{f} {c}");       //> 6765 8
    return 0;
}
```

With `--dump-reduced out.txt` the compiler writes the residual program;
for this one `main` becomes (abridged):

```text
@requires(args) Int main() {
Int f = 6765;
Int n = args.count();
Int c = pow__rs1(n + 1, 3);
println(f"6765 {c}");
return 0;
}
Int pow__rs1(Int b, Int rs#known1) {
return ((b * pow__rs2(b, 2)));
}
// pow__rs2, pow__rs3, then pow__rs4 returns 1: e = 3, 2, 1, 0 specialized
```

A known binding stays in the dump with its value (`Int f = 6765;`) and its
uses are replaced by that value. Unused source functions (`fib`) are also
printed; they cost nothing at run time.

Reduction covers: constant folding, inlining and evaluation of calls with
known arguments, specialization on partly known arguments (known record
fields count), dead-branch elimination (`if (false)`, known `match`
scrutinees), short-circuit folding, string interpolation of known parts,
strings and the string builtins, lists, `Map`/`Set`, records, sum types
(generic ones too), `Result`/`Option`, closures (`lambda`), `StrBuf` and
`ListBuf`, and integers up to 2^1023 in magnitude. Lowering then drops
bounds and overflow checks that range facts prove cannot fire
(`--no-facts` keeps them).

What stays residual by design: effects, provider calls, `rt` values,
integers of 2^1023 or more, `Float(16)`/`Float(32)`/`Float(128)`, `Dec`
(a function whose body binds a `Dec` is not reduced at all, and no note
says so; keep decimal arithmetic in small functions of its own), a
`while` whose body falls through, and the legacy `str_sb_*` builder
functions. A plain `Float` result is computed but its formatting in an
f-string hole is left to run time.

## Rules that keep reduction sound

- **Effects are never duplicated, dropped or reordered.** `Int a = noisy(1);`
  still prints once at run time; `Bool unused = println("x");` still prints.
  Only fully known, effect-free bindings are elided.
- **Overflow is never folded.** A known `Int(8) 100 + 100` is left residual
  and aborts at run time, exactly as the unreduced program would.
- **Budgets are deterministic**: they count work (steps, calls, value
  sizes, nesting, specializations), never time or native memory, so every
  build reduces a program the same way. Past a budget the call is simply
  left residual and runs at run time; behavior is identical either way. A
  call that keeps re-entering itself without progress is left residual too.
- Authority is part of knowledge: a provider result is not folded in unless
  the capability grants it at build time (the current compiler treats
  provider calls as residual).

```resid
//! exit 134
Int main() {
    Int(8) a = i8(100);
    Int(8) b = i8(100);
    Int(8) c = a + b;         // known operands, but overflow: aborts at run time
    return 0;
}
```

## Budgets

| Budget | Default | Raise it with |
|---|---|---|
| fuel: evaluation steps over the whole program | 16,000,000 | `--reduce-budget N` or `--reduce-budget unbounded`; `[reduce] budget = "N"` in `resid.toml` |
| steps: one top-level call's attempt | 65,536, doubled on each retry up to 1/8 of the fuel left | `@reduce(steps = N)` or `@reduce(steps = unbounded)` on the function (its own allowance, outside the fuel) |
| memory meter (abstract bytes per attempt) | a quarter of the compiler's memory budget (`RESID_MEM_LIMIT`, 4096 MB); half under `unbounded` | `RESID_MEM_LIMIT=<MB>` |
| depth: non-tail call nesting | 100,000 (none under `unbounded`) | `--reduce-budget unbounded` |
| specializations | 400 per program, 8 per function | not adjustable |

Tail calls and loops are evaluated iteratively, so a long tail loop
spends steps, not depth. A budget that runs out prints a note and leaves
the call residual:

```text
note: reduce: reduction budget (steps) exhausted evaluating sumto(...); the call stays residual
```

`@fold` turns "should fold" into a requirement: every call of the
function must reduce at compile time, with no step limit, or the build
fails with E0903 (calls from inside another `@fold` function are exempt).
A malformed `@reduce` is E0904. If evaluation would overflow the
compiler's own stack the build fails with E0902 (raise `RESID_STACK_MB`)
rather than silently leaving the call residual. A non-default budget is
recorded in the release provenance (`reduce` key).

```resid
@reduce(steps = unbounded)
Int sumto(Int i, Int n, Int acc) { return if (i > n) { acc } else { sumto(i + 1, n, acc + i) }; }

@fold
Int sq(Int x) { return x * x; }

Int main() {
    println(f"{sumto(0, 3000000, 0)} {sq(12)}");   //> 4500001500000 144
    return 0;
}
```

```resid
//! compile-error: E0903
@fold
Int sq(Int x) { return x * x; }

@requires(args)
Int main() {
    println(f"{sq(args.count())}");   // argument not known at compile time
    return 0;
}
```

## Controlling knowledge

| Form | Effect |
|---|---|
| `rt expr` | make a value residual on purpose (`Int n = rt 5;`) |
| `@residual Type x = expr;` | same, as a binding annotation |
| `known(x);` | compile error `E0901` unless `x` is KNOWN |
| `rt_known(x);` | the run-time counterpart (accepted; no effect on a residual value) |
| `comptime_print(x);` | the compiler prints `[comptime_print] <value>` (`<residual>` when not known); removed from the binary |
| `assert(c, msg)` / `rt_assert(c, msg)` | run-time checks (a known-false `assert` still aborts at run time) |

```resid
Int main() {
    Int a = 5;
    known(a);
    @residual Int b = a * 7;      // kept as run-time computation
    Int c = rt 9;
    println(f"{b} {c}");          //> 35 9
    return 0;
}
```

```resid
//! compile-error: E0901
Int main() {
    Int b = rt 7;
    known(b);
    return 0;
}
```

`rt` applies to a primary expression: `rt 5`, `rt "text"`, `rt (a + b)`,
`rt None`, `rt 1.5m`.

## Designing for reduction

- Write the pure part as ordinary functions over values; do not
  hand-optimize for known inputs. Table builders, parsers of constant text,
  configuration arithmetic, lookup tables: all fold away when their inputs
  are known.
- Keep the residual boundary narrow: read input once in `main`, pass values
  down. Everything upstream of a provider call is residual; everything that
  does not depend on it can fold.
- Constant "globals" are zero-argument functions (`Int limit() { return 10; }`);
  they fold to their value.
- Use `rt` in tests and benchmarks so the compiler does not compute the
  answer at build time (the conformance suite does this everywhere).
- Use `known(x)` to assert that something you expect to be free really is.

## Seeing what happened

- Compiler notes: `note: notes: N residual note(s) recorded`, and
  `note: reduce: ...` when a budget left work residual.
- `--dump-reduced FILE`: the residual program as source.
- `--no-reduce`: build without reduction (for comparing behavior).
- Every build writes `<out>.resid-notes.cbor` (actionable notes, kinds
  `rt-binding`, `provider-call`, `budget`, `loop`, `whistle`). Debug and
  check builds also write `<out>.resid-graph.cbor`: every node's state,
  value, facts, derive edges (`fold`, `beta`, `eval`, `specialize`,
  `select`, `interpolate`, `known`, `rebuild`) and the reason a node stayed
  residual.
- `resid-why <out>` explains the notes; `resid-why <out> SYMBOL`,
  `--node ID` or `--at FILE:LINE` walk the graph; `resid-debug` shows folded
  values next to live variables. See [tooling.md](tooling.md).

`resid-why prog` for the program above:

```text
residual notes for prog (1 of 1):

prog.resid
8:13  args.count();  [provider-call]
    queries an external provider (filesystem/env/git/...); grant the capability at build time with a concrete value to discharge it
```

A `budget` note names the ways to raise the budget (`--reduce-budget`,
`[reduce] budget`, `@reduce(steps = N)`, `@fold`).
