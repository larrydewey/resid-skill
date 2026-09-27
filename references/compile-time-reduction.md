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
Int n = args.count();
Int c = pow__rs1(n + 1);
println(f"6765 {c}");
return 0;
}
Int pow__rs1(Int b) { return ((b * pow__rs2(b))); }   // e = 3, 2, 1, 0 specialized
```

Reduction covers: constant folding, beta reduction (inlining known calls),
evaluation of fully known calls, specialization on partly known arguments
(known record fields count), dead-branch elimination (`if (false)`, known
`match` scrutinees), short-circuit folding, string interpolation of known
parts, dead-binding elision, and check discharge from facts (a bounds or
overflow check that provably cannot fire is dropped).

## Rules that keep reduction sound

- **Effects are never duplicated, dropped or reordered.** `Int a = noisy(1);`
  still prints once at run time; `Bool unused = println("x");` still prints.
  Only fully known, effect-free bindings are elided.
- **Overflow is never folded.** A known `Int(8) 100 + 100` is left residual
  and aborts at run time, exactly as the unreduced program would.
- **Budgets are deterministic** (steps, depth, specializations; never time).
  Past a budget the call is simply left residual: `count(5000)` of a
  non-tail recursion may fold while `count(100000)` runs at run time. A pure
  call that re-enters itself with identical arguments is left residual.
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

## Controlling knowledge

| Form | Effect |
|---|---|
| `rt expr` | make a value residual on purpose (`Int n = rt 5;`) |
| `@residual Type x = expr;` | same, as a binding annotation |
| `known(x);` | compile error `E0901` unless `x` is KNOWN |
| `rt_known(x);` | the run-time counterpart (accepted; no effect on a residual value) |
| `comptime_print(x);` | the compiler prints the reduced value; removed from the binary |
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
`rt None`. `rt 1.5m` (a Dec literal) does not parse; use `d4(rt 1)`-style
conversions for residual Decs.

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

- Compiler notes: `note: notes: N residual note(s) recorded`, and reduce
  budget notes (`note: reduce: ...`) when a budget left work residual.
- `--dump-reduced FILE`: the residual program as source.
- `--no-reduce`: build without reduction (for comparing behavior).
- Debug/check builds write `<out>.resid-graph.cbor` (the knowledge graph:
  every node's state, value, facts, derive edges with rules like `fold`,
  `beta`, `eval`, `specialize`, `select`, and the reason a node stayed
  residual) and `<out>.resid-notes.cbor` (actionable notes: `rt-binding`,
  `provider-call`, budget, loop, whistle).
- `resid-why <binary>` explains the notes; `resid-why <binary> SYMBOL`,
  `--node ID` or `--at FILE:LINE` walk the graph; `resid-debug` shows folded
  values next to live variables. See [tooling.md](tooling.md).

Example `resid-why` output for the program above:

```text
args.count(); @ prog.resid:8:13:
    provider-call
    -> queries an external provider (filesystem/env/git/...); grant the capability
       at build time with a concrete value to discharge it
```
