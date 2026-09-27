# resid-skill

An Agent Skill that makes an LLM a competent [Resid](../resid) programmer:
the language's mental model, rules, gotchas, idioms, tooling, error codes and
the known limitations of the current self-hosted compiler.

Every Resid code block in the skill and every program in `examples/` is
compiled (and, where it has a `main`, run and compared with its expected
output) by `scripts/check-examples.sh` against a real compiler.

## Layout

```
SKILL.md                    entry point: mental model, rules, checklist, workflow
references/
  language-tour.md          the whole surface in one page
  types-and-values.md       numbers, Dec, Str, collections, Option/Result, records, sums
  control-flow.md           if, match, for, loops as tail recursion
  functions-and-closures.md functions, closures, higher-order helpers
  behaviors.md              behaviors, generic functions/records, coherence, behavioralizing
  errors-and-results.md     ?, else, error types, aborts
  capabilities-and-security.md  @requires, providers, sandbox, spawn, handles
  testing.md                test blocks, lib/testing.resid, matchers
  stdlib.md                 builtins and lib/ modules
  performance-and-memory.md builders, in-place updates, quadratic traps
  compile-time-reduction.md what the compiler evaluates, rt/known/comptime_print
  tooling.md                compiler flags, profiles, resid-fmt/why/graph/debug, packages
  error-codes.md            E-codes, common messages, post-check failures
  idioms-and-antipatterns.md  idioms, anti-patterns, known compiler issues
examples/NN_name.resid      complete programs; NN_name.out = exact stdout
                            (optional .args, .env, .exit)
scripts/check-examples.sh   verifies examples and snippets
```

## Installing

Copy or symlink this directory into your agent's skills directory, e.g.
`~/.claude/skills/resid` for Claude Code.

## Verifying

Needs a Resid checkout with a built compiler (`build/boot/stage2.bin`):

```sh
RESID_REPO=/path/to/resid scripts/check-examples.sh          # everything
scripts/check-examples.sh -r /path/to/resid behaviors        # filter by name
```

Snippet conventions (in ```` ```resid ```` blocks):

- `//> text` expected stdout line (checked when present)
- `//! exit N`, `//! args: A B`, `//! compile-error: SUBSTRING`, `//! skip`
- blocks without `main(` are declarations: compiled with an empty `main`

When the compiler changes, run the script; a failing block means the skill
needs updating (or the compiler regressed).

## License

MIT, see `LICENSE`.
