# Standard library

Two parts: **builtins** the compiler knows (always available, no import) and
**library modules** in the Resid repo's `lib/` (plain Resid source you
import by path).

## Builtins: output and input

| Function | Type | Notes |
|---|---|---|
| `println(s)` / `print(s)` | `(Str) -> Bool` | exactly one `Str`; format with f-strings |
| `eprintln(s)` | `(Str) -> Bool` | stderr |
| `print_bytes(bs)` | `(List(Int)) -> Bool` | raw bytes (low 8 bits of each) |
| `resid_read_line()` | `() -> Str` | one stdin line **including** `\n`; `""` at EOF |
| `resid_crypto_random_byte()` | `() -> Int` | OS randomness, 0..255 |

None of these need a capability. The `Bool` result can be ignored in
statement position (`println("x");`).

## Builtins: strings

All indices are code points; `str_slice` end is exclusive.

| Function | Type |
|---|---|
| `str_len(s)` | `Int` |
| `str_char_at(s, i)` | `Int` code point |
| `str_from_code(cp)` | `Str` of one code point |
| `str_slice(s, start, end)` | `Str` |
| `str_index_of(s, needle, from)` | `Int` (-1 if absent; negative `from` = 0) |
| `str_contains(s, t)` / `str_starts_with(s, t)` / `str_ends_with(s, t)` | `Bool` |
| `str_count(s, t)` | `Int`, non-overlapping |
| `str_replace(s, from, to)` | `Str`, all occurrences |
| `str_split(s, sep)` | `List(Str)` (keeps empty fields) |
| `str_join(parts, sep)` | `Str` |
| `str_trim(s)` | `Str` |
| `str_to_upper(s)` / `str_to_lower(s)` | `Str` (full Unicode case mapping) |
| `str_reverse(s)` | `Str` (by code point) |
| `str_repeat(s, n)` | `Str` |
| `str_is_int(s)` / `str_parse_int(s)` | `Bool` / `Int` (0 on bad input: check first) |
| `str_is_float(s)` / `str_parse_float(s)` | `Bool` / `Float` |
| `str_sha256(s)` | `Str` hex digest |

Also `s == t`, `s != t`, `s < t` (code-point order), `s + t`, and `f"..."`.
There is
no `s[i]`, no `format()`/`printf`; build text with f-strings and `StrBuf`.

```resid
Int main() {
    Str s = "  Hello, World  ";
    Str t = str_trim(s);
    println(str_to_lower(t));                                   //> hello, world
    println(f"{str_index_of(t, "o", 5)} {str_count("banana", "an")}");  //> 8 2
    println(str_replace("a-b-c", "-", "+"));                    //> a+b+c
    println(str_join(str_split("x,y,,z", ","), "|"));           //> x|y||z
    println(f"{str_starts_with(t, "Hell")} {str_ends_with(t, "d")}");   //> true true
    println(str_reverse("héllo") + " " + str_repeat("ab", 3));  //> olléh ababab
    if (str_is_int("-42")) { println(f"{str_parse_int("-42") + 1}"); }  //> -41
    println(f"{str_parse_float("2.5") * 2.0}");                 //> 5
    println(str_sha256("abc"));                                 //> ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    return 0;
}
```

Legacy string builder builtins `str_sb_new()`, `str_sb_append(sb, s)`,
`str_sb_append_cp(sb, cp)`, `str_sb_finish(sb)` still exist (the builder is
a `Str` value); new code should use `StrBuf`.

## Builtins: numbers

| Function | Notes |
|---|---|
| `abs(x)`, `min(a, b)`, `max(a, b)`, `clamp(x, lo, hi)` | any one numeric type (not Dec) |
| `i8`...`i512`, `u8`...`u512`, `isize`, `usize`, `f16`...`f128`, `dN` | checked conversions |
| `wrapping_i8`...`wrapping_u512` | truncating conversions |
| `wrapping_add/sub/mul/div`, `saturating_add/sub/mul`, `checked_add/sub/mul/div` | signed; `u` forms (`wrapping_uadd`, `saturating_umul`) for unsigned |

There is no math library: no `sqrt`, `pow`, `exp`, `log`, `sin`,
`floor`. Write what you need:

```resid
// Integer square root (floor) by Newton's method.
Int isqrt_step(Int n, Int x) {
    Int y = (x + n / x) / 2;
    return if (y >= x) { x } else { isqrt_step(n, y) };
}
Int isqrt(Int n) { return if (n < 2) { n } else { isqrt_step(n, n) }; }

// Float square root: Newton from a rough start; within ~1 ulp (not correctly rounded).
Float fsqrt_iter(Float d, Float x, Int k) {
    return if (k <= 0) { x } else { fsqrt_iter(d, 0.5 * (x + d / x), k - 1) };
}
Float fsqrt(Float d) { return if (d <= 0.0) { 0.0 } else { fsqrt_iter(d, if (d > 1.0) { d } else { 1.0 }, 60) }; }

Int ipow(Int b, Int e) { return if (e == 0) { 1 } else { b * ipow(b, e - 1) }; }

Float floor_f(Float x) {
    Float t = (Float)((Int)x);            // (Int) truncates toward zero
    return if (t > x) { t - 1.0 } else { t };
}

Int main() {
    println(f"{isqrt(1000000)} {isqrt(99)} {ipow(3, 4)}");   //> 1000 9 81
    println(f"{fsqrt(2.0)} {fsqrt(16.0)}");                 //> 1.414213562373095 4
    println(f"{floor_f(-2.5)} {floor_f(2.5)}");              //> -3 2
    return 0;
}
```

(The Resid benchmark `bench/suite/src/st/nbody/resid/nbody.resid` has a
correctly rounded `sqrt` using Dekker's two-product.)

## Builtins: collections

`List`: `len`, index, slice, `concat`, `contains`, `reverse`, `sum`,
`sort(xs)`, `sort(xs, using = B(T))`. `Map`: `get`, `[k]`, `insert`,
`remove`, `contains`, `keys`, `values`, `len`. `Set`: `insert`, `remove`,
`contains`, `union`, `intersection`, `difference`, `to_list`, `len`.
Builders: `StrBuf()` (`push`, `push_char`, `finish`), `ListBuf()` (`push`,
`finish`). Details: [types-and-values.md](types-and-values.md),
[performance-and-memory.md](performance-and-memory.md).

## Builtins: checks and knowledge

`assert(c, msg)`, `rt_assert(c, msg)`, `todo(msg?)`, `unimplemented(msg?)`,
`known(x)`, `rt_known(x)`, `comptime_print(x)`, `#location` (a `SourceLoc`
with `file`, `line`, `col`). See [compile-time-reduction.md](compile-time-reduction.md).

## Library modules (`lib/` in the Resid repo)

`import "crypto.resid";` works from any directory: a name not found next to
the importing file falls back to the stdlib directory (`RESID_HOME/../../lib`,
then `./lib`). A file of the same name next to yours wins. Only `pub`
functions are visible.

| Module | Provides (main entry points) |
|---|---|
| `crypto.resid` | `sha256(Str) -> Str` hex, `sha256_bytes(List(Int))`, `sha512_bytes`, `hex_encode(List(Int)) -> Str`, `hmac_sha256_bytes(key, msg)`, `hkdf_sha256(salt, ikm, info, len)`, `pbkdf2_hmac_sha256(pass, salt, iters, block_index)`, `ct_equal(a, b)`, `random_bytes(n)`, `random_hex(n)`, `base64_encode` |
| `ed25519.resid` | `pub_key`, `sign_msg(seed, Str)`, `verify_sig(Str, sig, pub)` (strict RFC 8032) |
| `x25519.resid` | `x25519(k, u)` key agreement |
| `chacha.resid` | `chacha20poly1305_seal` / `_open` (RFC 8439) |
| `aesgcm.resid` | `aes128_gcm_seal` / `_open` |
| `ec256.resid` | P-256 ECDSA verification helpers |
| `rsa.resid` | bignum + RSA PKCS#1 v1.5 verification |
| `der.resid`, `x509.resid`, `chain.resid` | DER decoding, certificate fields, chain and SAN checks |
| `tls.resid`, `tlsmsg.resid` | TLS 1.3 key schedule, records, handshake messages (client does **not** authenticate servers) |
| `http.resid`, `h2.resid` | HTTP/1.1 client (`http_get(host, port, path)`, needs `network`), HTTP/2 framing + HPACK |
| `cose.resid` | CBOR encoding, COSE_Sign1 / COSE_Encrypt0 |
| `testing.resid` | `test_case`, `run_tests` ([testing.md](testing.md)) |
| `dwarf.resid`, `kgart.resid` | ELF/DWARF reader, knowledge-graph artifact reader (tooling) |

Byte strings in the library are `List(Int)`, one byte per element. Some
older modules (`der`, `rsa`) use a "seeded" convention where index 0 is a
dummy element; read a module's header comment before calling it.
As with any library, check output against a known test vector before
relying on a routine you have not used before.

```resid
import "crypto.resid";

Int main() {
    println(sha256("abc"));   //> ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    println(hex_encode(hmac_sha256_bytes([107, 101, 121], [104, 105])));  //> 1c9dc82e5f8e5ed5a0180aad33b8204dea12fde2fb62ffb5e963035bf324a7a4
    println(f"{ct_equal([1, 2], [1, 2])}");   //> true
    return 0;
}
```

The crypto code is pure Resid and slow compared to native libraries; it is
fine for keys and messages, not bulk data.
