#!/usr/bin/env bash
# Verify every example program and every ```resid snippet in the skill
# against a real Resid compiler.
#
# Usage: scripts/check-examples.sh [-r RESID_REPO] [-k] [FILTER]
#
#   RESID_REPO  checkout of the Resid compiler (default: $RESID_REPO, else
#               ../resid next to this repo). Needs build/boot/stage2.bin.
#   -k          keep the temp dir (prints its path)
#   FILTER      substring; only examples/snippets whose name contains it
#
# examples/NAME.resid   compiled and run; stdout must equal NAME.out.
#                       Optional NAME.args (program arguments, one line),
#                       NAME.exit (expected exit code, default 0),
#                       NAME.env (VAR=value pairs for the run, one line),
#                       NAME.stdin (fed to the program's standard input).
#
# Snippets: every ```resid block in SKILL.md and references/*.md.
#   - A block with `main(` is compiled and run as is.
#   - A block without `main(` gets `Int main() { return 0; }` appended
#     (declarations only), compiled, not run.
#   - `//> text` lines give the expected stdout, one line each, in order
#     (checked only when the block has at least one `//>` line).
#   - `//! exit N`           expected exit code (default 0)
#   - `//! compile-error: S` compilation must fail and print S
#   - `//! args: A B`        program arguments
#   - `//! skip`             not compiled (use sparingly; say why)
#
# Each program is compiled in a fresh dir holding a copy of RESID_REPO/lib,
# so `import "crypto.resid";` resolves. It runs with that dir as cwd.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${RESID_REPO:-$HERE/../resid}"
KEEP=0
while getopts "r:k" opt; do
    case "$opt" in
        r) REPO="$OPTARG" ;;
        k) KEEP=1 ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
FILTER="${1:-}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "resid repo not found (set RESID_REPO or -r)"; exit 2; }
COMPILER="$REPO/build/boot/stage2.bin"
[ -x "$COMPILER" ] || { echo "compiler not found: $COMPILER"; exit 2; }
export RESID_HOME="${RESID_HOME:-$REPO/build/boot}"

WORK="$(mktemp -d)"
if [ "$KEEP" = 1 ]; then echo "work dir: $WORK"; else trap 'rm -rf "$WORK"' EXIT; fi

pass=0
fail=0

# run_one NAME SRC EXPECTED_OUT_FILE|"" EXIT ARGS COMPILE_ERR RUN(1/0) [ENV] [STDIN_FILE]
run_one() {
    local name="$1" src="$2" want="$3" wexit="$4" args="$5" cerr="$6" run="$7" envs="${8:-}" input="${9:-/dev/null}"
    local dir="$WORK/$name"
    mkdir -p "$dir"
    cp "$REPO"/lib/*.resid "$dir"/ 2>/dev/null
    cp "$src" "$dir/prog.resid"
    (cd "$REPO" && timeout 300 "$COMPILER" "$dir/prog.resid" -o "$dir/bin" --profile debug) > "$dir/compile.log" 2>&1
    local crc=$?
    if [ -n "$cerr" ]; then
        if [ "$crc" -eq 0 ]; then fail=$((fail + 1)); echo "FAIL $name: expected compile error '$cerr', compiled"; return; fi
        if ! grep -qF -- "$cerr" "$dir/compile.log"; then
            fail=$((fail + 1)); echo "FAIL $name: compile log lacks '$cerr':"; grep -v '^OK \|^typecheck OK' "$dir/compile.log" | head -5 | sed 's/^/    /'; return
        fi
        pass=$((pass + 1)); return
    fi
    if [ "$crc" -ne 0 ]; then
        fail=$((fail + 1)); echo "FAIL $name: compile failed:"; grep -v '^OK \|^typecheck OK\|^note:' "$dir/compile.log" | head -8 | sed 's/^/    /'; return
    fi
    if [ "$run" = 0 ]; then pass=$((pass + 1)); return; fi
    # shellcheck disable=SC2086
    { (cd "$dir" && env $envs timeout 60 ./bin $args > "$dir/stdout" 2> "$dir/stderr" < "$input"); } 2>/dev/null
    local rc=$?
    if [ "$rc" -ne "$wexit" ]; then
        fail=$((fail + 1)); echo "FAIL $name: exit $rc, expected $wexit"; head -3 "$dir/stderr" | sed 's/^/    /'; return
    fi
    if [ -n "$want" ] && ! diff -u "$want" "$dir/stdout" > "$dir/diff"; then
        fail=$((fail + 1)); echo "FAIL $name: stdout differs"; head -20 "$dir/diff" | sed 's/^/    /'; return
    fi
    pass=$((pass + 1))
}

# ---- examples/ ----
for f in "$HERE"/examples/*.resid; do
    [ -f "$f" ] || continue
    n="$(basename "$f" .resid)"
    [ -n "$FILTER" ] && [[ "$n" != *"$FILTER"* ]] && continue
    base="${f%.resid}"
    [ -f "$base.out" ] || { fail=$((fail + 1)); echo "FAIL ex_$n: missing $n.out"; continue; }
    wexit=0; [ -f "$base.exit" ] && wexit="$(cat "$base.exit")"
    args=""; [ -f "$base.args" ] && args="$(cat "$base.args")"
    envs=""; [ -f "$base.env" ] && envs="$(cat "$base.env")"
    input="/dev/null"; [ -f "$base.stdin" ] && input="$base.stdin"
    run_one "ex_$n" "$f" "$base.out" "$wexit" "$args" "" 1 "$envs" "$input"
done

# ---- snippets in markdown ----
SNIP="$WORK/_snippets"
mkdir -p "$SNIP"
for md in "$HERE"/SKILL.md "$HERE"/references/*.md; do
    [ -f "$md" ] || continue
    stem="$(basename "$md" .md)"
    awk -v dir="$SNIP" -v stem="$stem" '
        /^```resid[ \t]*$/ { inb = 1; n++; file = sprintf("%s/%s__%02d.resid", dir, stem, n); line0 = NR; printf "" > file; next }
        /^```/ && inb { inb = 0; close(file); print line0 > (file ".line"); close(file ".line"); next }
        inb { print >> file }
    ' "$md"
done
for s in "$SNIP"/*.resid; do
    [ -f "$s" ] || continue
    n="$(basename "$s" .resid)"
    [ -n "$FILTER" ] && [[ "$n" != *"$FILTER"* ]] && continue
    line="$(cat "$s.line" 2>/dev/null)"
    label="${n%__*}.md:$line"
    grep -q '^[[:space:]]*//! skip' "$s" && continue
    cerr="$(sed -n 's#^[[:space:]]*//! compile-error: ##p' "$s" | head -1)"
    wexit="$(sed -n 's#^[[:space:]]*//! exit ##p' "$s" | head -1)"; wexit="${wexit:-0}"
    args="$(sed -n 's#^[[:space:]]*//! args: ##p' "$s" | head -1)"
    want=""
    if grep -q '//> \|//>$' "$s"; then
        want="$s.want"
        sed -n 's#.*//>\(.*\)$#\1#p' "$s" | sed 's/^ //' > "$want"
    fi
    run=1
    if ! grep -q 'main(' "$s"; then
        printf '\nInt main() { return 0; }\n' >> "$s"
        run=0
    fi
    run_one "$label" "$s" "$want" "$wexit" "$args" "$cerr" "$run"
done

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
