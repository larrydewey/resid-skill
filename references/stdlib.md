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
| `resid_read_byte()` | `() -> Int` | one stdin byte; `-1` at EOF (buffered, mixes with `resid_read_line`) |
| `resid_crypto_random_byte()` | `() -> Int` | OS randomness, 0..255 |

None of these need a capability. The terminal builtins (`resid_term_is_tty`,
`resid_term_cols`, `resid_term_rows`, `resid_term_raw`, `resid_term_restore`)
need `terminal` ([capabilities-and-security.md](capabilities-and-security.md));
for interactive input use `lib/readline.resid` instead of calling them. The `Bool` result can be ignored in
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

Use `str_len(s)`, never `s.len()`: on a `Str` the method type-checks but
returns garbage at HEAD.

Legacy string builder builtins `str_sb_new()`, `str_sb_append(sb, s)`,
`str_sb_append_cp(sb, cp)`, `str_sb_append_slice(sb, s, a, b)` (code points
`[a, b)` of `s`, no intermediate slice) and `str_sb_finish(sb)` still exist
(the builder is a `Str` value); new code should use `StrBuf`.

## Builtins: numbers

| Function | Notes |
|---|---|
| `abs(x)`, `min(a, b)`, `max(a, b)`, `clamp(x, lo, hi)` | any one numeric type (not Dec) |
| `sqrt(x)` | `Float` (or a Float vector, lanewise): correctly rounded; negative gives `nan` |
| `i8`...`i512`, `u8`...`u512`, `isize`, `usize`, `f16`...`f128`, `dN` | checked conversions (abort when out of range) |
| `wrapping_i8`...`wrapping_u512` | truncating conversions (`wrapping_u8(300)` is 44) |
| `wrapping_add/sub/mul/div`, `saturating_add/sub/mul` | signed; `u` forms (`wrapping_uadd`, `saturating_umul`) for unsigned; result has the wider operand's width |
| `ct_secret(x)`, `ct_public(x)`, `ct_hide(x)` | constant-time helpers (spec §6.8); each returns `x` unchanged |

User functions named `abs`, `clamp` or `sqrt` replace the builtin
everywhere in the program. `min` and `max` are `Bounded` verbs, so a
function of that name is E0231.

Caveats at HEAD: `checked_add/sub/mul/div` (and `u` forms) type-check but
wrap on overflow instead of trapping or returning an `Option`, so do not use
them; plain `+ - *` already trap. `wrapping_div(MIN, -1)` is wrong too (see the
known issues in [idioms-and-antipatterns.md](idioms-and-antipatterns.md)).

There is no other math: no `pow`, `exp`, `log`, `sin`, `floor`. Write what
you need:

```resid
// Integer square root (floor) by Newton's method.
Int isqrt_step(Int n, Int x) {
    Int y = (x + n / x) / 2;
    return if (y >= x) { x } else { isqrt_step(n, y) };
}
Int isqrt(Int n) { return if (n < 2) { n } else { isqrt_step(n, n) }; }

Int ipow(Int b, Int e) { return if (e == 0) { 1 } else { b * ipow(b, e - 1) }; }

Float floor_f(Float x) {
    Float t = (Float)((Int)x);            // (Int) truncates toward zero
    return if (t > x) { t - 1.0 } else { t };
}

Int main() {
    println(f"{isqrt(1000000)} {isqrt(99)} {ipow(3, 4)}");   //> 1000 9 81
    println(f"{sqrt(2.0)} {sqrt(16.0)}");                   //> 1.4142135623730951 4
    println(f"{floor_f(-2.5)} {floor_f(2.5)}");              //> -3 2
    return 0;
}
```

## Builtins: collections

`List`: `len`, `xs[i]`, `xs[a..b]`, `concat`, `contains`, `reverse`,
`sum`, `sort(xs)`, `sort(xs, using = B(T))`. `Map`: `get` and `m[k]` (both
`Option(V)`), `insert`, `remove`, `contains`, `keys`, `values`, `len`. `Set`:
`insert`, `remove`, `contains`, `union`, `intersection`, `difference`,
`to_list`, `len`. Maps and sets iterate and print in hash order, not
insertion order. Builders: `StrBuf()` (`push`, `push_char`, `finish`), `ListBuf()` (`push`,
`finish`). Details: [types-and-values.md](types-and-values.md),
[performance-and-memory.md](performance-and-memory.md).

## Builtins: checks and knowledge

`assert(c, msg)`, `rt_assert(c, msg)`, `todo(msg?)`, `unimplemented(msg?)`,
`known(x);` and `rt_known(x);` (statements, not `Bool` values), `comptime_print(x)`, `#location` (a `SourceLoc`
with `file`, `line`, `col`). See [compile-time-reduction.md](compile-time-reduction.md).

## Library modules (`lib/` in the Resid repo)

`import "crypto.resid";` works from any directory: a name not found next to
the importing file falls back to the stdlib directory (`$RESID_HOME/lib` in
an install, else `RESID_HOME/../../lib`, then `./lib`). A file of the same name next to yours wins. Only `pub`
functions are visible.

Capability needs are what the module's `pub` functions declare; a caller
must hold at least that grant (E0219). Unlisted means pure.

| Module | Provides (main entry points) |
|---|---|
| `crypto.resid` | SHA-256 (`sha256(Str) -> Str` hex, `sha256_bytes`), `sha512_bytes`, `sha1_bytes`, `hex_encode(List(Int)) -> Str`, `hmac_sha256_bytes(key, msg)`, `hkdf_sha256(salt, ikm, info, len)`, `pbkdf2_hmac_sha256(pass, salt, iters, block_index)`, `ct_equal(a, b)`, `random_bytes(n)`, `random_hex(n)`, `base64_encode`/`base64_decode`. SHA-256/512 use the CPU's SHA instructions when present |
| `hash.resid` | `HashAlg = Sha1 \| Sha256 \| Sha384 \| Sha512`: `hash_bytes(h, msg)`, `hash_len`, `sha384_bytes`, `hmac_bytes(h, key, msg)`, `hmac_verify`, `hkdf_with(h, salt, ikm, info, len)` (and `_extract_with`/`_expand_with`) |
| `ecdsa.resid` | ECDSA and ECDH over `Curve = P256 \| P384` (on generated `p256.resid`/`p384.resid`): `ec_generate(c)`, `ec_public_key(c, priv)`, `ecdsa_sign(c, h, priv, msg)` (DER, RFC 6979 nonces), `ecdsa_verify(c, h, pub, msg, der)`, `_raw` forms for r‖s, `ecdh(c, priv, peer)` |
| `ed25519.resid` | `pub_key(seed)`, `sign_msg(seed, Str)`, `sign_msg_bytes`, `verify_sig(Str, sig, pub)`, `verify_sig_bytes` (strict RFC 8032) |
| `x25519.resid` | `x25519(k, u)`, `x25519_public(priv)`, `x25519_shared(priv, peer)` |
| `rsa.resid` | RSA verification only, 2048-16384 bits: `rsa_pub(n_be, e_be)`, `rsa_pub_der`, `rsa_pkcs1_verify(h, key, msg, sig)`, `rsa_pss_verify(h, mgf, salt_len, key, msg, sig)` |
| `chacha.resid` | `chacha20poly1305_seal(key, nonce, pt, aad)`, `chacha20poly1305_decrypt -> Option(List(Int))` (RFC 8439) |
| `aesgcm.resid` | AES-128/192/256-GCM with any IV length: `aes_gcm_seal(key, iv, pt, aad)`, `aes_gcm_decrypt -> Option(List(Int))`; key wrap `aes_key_wrap`/`aes_key_unwrap` (RFC 3394). AES-NI/PCLMULQDQ when present |
| `hpke.resid` | HPKE (RFC 9180): `hpke_suite(kem, kdf, aead)`, `hpke_generate_keypair`, `hpke_seal_to(suite, pkR, info, aad, pt)`, `hpke_open_with(suite, enc, skR, info, aad, ct) -> Option(List(Int))`, plus setup/seal/open/export contexts |
| `cose.resid` | CBOR encoding, COSE_Sign1 with Ed25519 (`cose_sign1`, `cose_sign1_parse`, `cose_sign1_check`) and COSE_Encrypt0 with ChaCha20-Poly1305 |
| `cosesig.resid` | COSE_Sign1 with every algorithm the library verifies (ES256/384, PS256-512, RS256-512, EdDSA): `cose_sign1_open(bytes, PubKey, aad) -> Option(List(Int))`, `cose_sign1_ecdsa`, `cose_key_public` |
| `der.resid`, `x509.resid` | DER reader; `x509_parse(der) -> Result(Cert, Str)` (strict), `spki_parse_der -> PubKey`, `cert_san`, `cert_is_ca`, `x509_subject_str`, `x509_time_to_unix`. `der.resid` uses the seeded convention (index 0 is a dummy) |
| `certverify.resid` | `sig_verify(SigAlg, PubKey, msg, sig)` (the one signature dispatch), `x509_signed_by(der, issuer)`, OCSP response checking (`ocsp_*`) |
| `chain.resid` | `TrustStore`: `trust_store_load(path)` (PEM bundle or DER directory, `filesystem(readonly)`), `trust_store_add`, `trust_store_add_pem`, CRLs and OCSP, `trust_store_requiring_revocation`; `tls_server_trusted(leaf, inters, host, now, store)` (fail-closed); `chain_verify`, `cert_san_match` |
| `tls.resid`, `tlsmsg.resid` | TLS 1.3 key schedule, records and handshake messages shared by client and server |
| `tlsclient.resid` | TLS 1.3 client, `network, clock(readonly), declassify` (record keys are `Secret`, see [secrets.md](secrets.md)); authenticates the server before sending anything; no store means refusal, no skip flag: `tls_client_cfg(name, store, alpn)`, `tls_client_connect(host, port, cfg)` (`network(readonly), clock(readonly), declassify`), `tls_https_get(url, name, store, alpn) -> HttpsGet` (`status`, `bytes`, `err`, `head`; Content-Length required, 64 MB cap, 5 min deadline), `tls_https_get_within`, `tls_https_request(url, name, store, alpn, ms, method, headers, body)` |
| `tlsserver.resid`, `tlskey.resid`, `tlswire.resid` | TLS 1.3 server, `network(readonly), declassify`: `TLS_AES_128_GCM_SHA256` and x25519 only; signs with Ed25519 or ECDSA P-256/P-384. `tls_key_load(path) -> Option(ServerKey)` (`filesystem(readonly), declassify`; constant-time PEM/DER parse, key held as secret bytes) and `tls_chain_load(path)` (PKCS#8 or SEC1, PEM or DER; `filesystem(readonly)`), `tls_key_cert_matches`; `tls_cfg(key, chain, alpn)`, `tls_accept_loop(lfd, cfg, handler, limits, max_conns)`, `tls_stream_loop` |
| `wire.resid` | the `Wire(T)` connection vocabulary shared by TCP and TLS, `network(readonly)`: `plain_cfg()`, `wire_connect(host, port)` |
| `http.resid`, `h2.resid` | HTTP/1.1 client over plain TCP, `network`: `http_get(host, port, path) -> HttpResponse` (`status`, `headers`, `body`), `http_get_body(url)`, `http_get_status(url)`; `Connection: close`, no chunked bodies, no TLS (use `tlsclient`). `h2`: HTTP/2 framing and HPACK |
| `httpserv.resid` | HTTP/1.1 server, `network(readonly)` (`http_listen_at` needs `network`): `http_listen(port)` (loopback), `http_listen_at(host, port)`, `http_bound_port`, `http_accept_loop(lfd, HttpReply closure(HttpRequest) handler, http_limits(), max_conns)` (0 = forever; spawn several on one listener for workers); `HttpRequest` has `method target path query version headers` (lower-cased `Map(Str, Str)`) `body` (`List(Int)`) `keep_alive`; replies `http_reply_text(status, ctype, Str)`, `http_reply_bytes`, `http_reply_empty`, `http_reply_status(code)`, `http_with_header`; `http_route(pattern, path) -> Option(Map(Str, Str))` (`:name`, final `*`); `http_header(r, name)`, `http_body_text`, `http_query_param`, `http_url_decode(s, form)`. Streamed replies: a handler returning `HttpOut(K)` under `http_stream_loop`. Chunked and Content-Length bodies, keep-alive, pipelining; smuggling shapes refused; per-request and per-reply deadlines in `HttpLimits`; an event loop, so a stalled client costs a socket, not a worker |
| `clock.resid` | the only clock surface, `clock(readonly)` to read, `clock` to sleep: `clock_now() -> Instant`, `clock_now_seconds`, `clock_now_nanos`, `clock_monotonic_ns`, `clock_now_utc`, `clock_today_utc`, `clock_sleep_ms`, `clock_sleep(Span)` |
| `instant.resid`, `duration.resid`, `calendar.resid`, `zone.resid`, `datetime.resid` | pure time library. `Instant` (`instant_of_seconds`, `instant_add`, `instant_diff`, `instant_to_utc`, `instant_format`, leap seconds/TAI); `Span` (`span_of_millis`, `span_add`, `span_format`, `span_parse`, ISO 8601); proleptic Gregorian `cal_*`; zones from TZif or POSIX TZ strings (`zone_load(name)` needs `filesystem(readonly)`, `zone_load_system()` also `environment(readonly)`; `zone_fixed`, `zone_utc` are pure); `Zoned` readings (`zoned_utc`, `zoned_from_instant`, `datetime_to_instant`, `datetime_format_rfc3339`, `datetime_strftime`, `datetime_parse`) |
| `readline.resid` | line editing with history and Tab completion, `terminal`: `readline(prompt, History) -> ReadResult`, `readline_with(prompt, h, List(Str) closure(Str) complete)`, `history_new(max)`, `history_add(h, line)`; `ReadResult` is `Line(Str) \| Eof \| Interrupted`. Not a terminal: prints the prompt and reads one plain line |
| `regex.resid` | linear-time regular expressions, RE2 syntax, leftmost-first (no backreferences or lookaround): `regex(p)` (aborts on a bad pattern), `regex_compile(p) -> Result(Regex, Str)`, `regex_is_match`, `regex_full_match`, `regex_find(_from)`, `regex_captures(_from)`, `regex_find_all`, `regex_captures_all`, `regex_count`, `regex_replace(_all)` (`$1`, `${name}`, `$$`), `regex_replace_with(re, s, closure)`, `regex_split`, `regex_escape`; a `RegexMatch` has `start`, `end` (code point offsets) and `groups`; read text with `regex_text(m, s)`, `regex_group(m, s, i) -> Option(Str)`, `regex_named(re, m, s, name)` |
| `testing.resid` | `test_case`, `property_case`, `run_tests` ([testing.md](testing.md)) |
| `dwarf.resid`, `kgart.resid` | ELF/DWARF reader and knowledge-graph artifact reader, for tools |

Byte strings in the library are `List(Int)`, one byte per element, zero-based
except in `der.resid`. Read a module's header comment before calling it, and
check a routine you have not used before against a known test vector.

```resid
import "crypto.resid";
import "hash.resid";
import "ecdsa.resid";

Int main() {
    println(sha256("abc"));   //> ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    println(hex_encode(hmac_sha256_bytes([107, 101, 121], [104, 105])));  //> 1c9dc82e5f8e5ed5a0180aad33b8204dea12fde2fb62ffb5e963035bf324a7a4
    println(str_slice(hex_encode(hash_bytes(Sha384, [97, 98, 99])), 0, 16));  //> cb00753f45a35e8b
    List(Int) priv = ec_generate(P256);
    List(Int) pubkey = ec_public_key(P256, priv);
    List(Int) sig = ecdsa_sign(P256, Sha256, priv, [104, 105]);
    println(f"{ecdsa_verify(P256, Sha256, pubkey, [104, 105], sig)} {ecdsa_verify(P256, Sha256, pubkey, [0], sig)}");  //> true false
    println(f"{ct_equal([1, 2], [1, 2])}");   //> true
    return 0;
}
```

```resid
import "regex.resid";

Int main() {
    Regex re = regex("(?P<y>\\d{4})-(\\d{2})");
    Str s = "from 2024-03 to 2025-11";
    Str out = regex_replace_all(re, s, "$2/${y}");   // `{` inside a string inside an f-string hole is misparsed
    println(f"{regex_count(re, s)} {out}");          //> 2 from 03/2024 to 11/2025
    Option(RegexMatch) m = regex_find(re, s);
    println(match (m) { Some(x) => regex_text(x, s), None => "-" });   //> 2024-03
    return 0;
}
```

```resid
import "instant.resid";
import "duration.resid";
import "datetime.resid";
import "clock.resid";

@requires(clock(readonly))
Span since(Instant start) { return instant_diff(clock_now(), start); }

Int main() {
    Instant t = instant_add(instant_of_seconds(1700000000), span_of_hours(36));
    println(datetime_format_rfc3339(zoned_utc(t)));     //> 2023-11-16T10:13:20Z
    println(span_format(span_of_millis(90061001)));     //> 1d 1h 1m 1.001s
    return 0;
}
```

The library is pure Resid. Hashing and AES run on CPU instructions where
present; the public-key code is slower than native libraries: fine for keys
and messages, not bulk signing.
