# Secret values (`Secret(T)`, spec §48)

`Secret(T)` is a value the program holds but may not observe through
control flow, a memory address or an output. The compiler enforces it;
`tests/ct/run.sh` checks the optimized binary under valgrind as a
backstop. Full design: `PLAN-secret-type.md` in the Resid repo.

```resid
@requires(declassify)
Int main() {
    Secret(Int) k = secret(rt 41);
    Secret(Int) m = (k ^ 7) & 255;          // bitwise work stays secret
    Secret(Int) w = wrapping_add(m, k);     // so does wrapping arithmetic
    Int out = declassify(w, "test output"); // the one exit, authorized and recorded
    println(f"{out}");                      //> 87
    return 0;
}
```

## Making and publishing

- `secret(x)` wraps a value read at run time. A secret the compiler knows
  after reduction is refused (E0250): it would be in the binary.
- `declassify(s, "reason")` returns the `T`. It needs
  `@requires(declassify)`, carried to every caller (E0219) and through spawn
  lists and sandboxes. The reason is a non-empty string literal (E0251) and
  is recorded in the graph (effect `declassify.<reason>`).
- `declassify` is also checked **at run time**: a function, lambda or spawn
  body that declassifies checks the grant on entry, so a closure that
  declassifies, run inside `spawn ()` or `sandbox (filesystem)` without
  `declassify`, aborts (`capability not granted: declassify`; a spawn
  region fails with that RegionError).
- `classify(x)` lifts a public value into secret computation (padding,
  public message bytes). E0250 does not apply to it.
- `secret`, `declassify`, `classify`, `secret_split`, `secret_join`,
  `ct_select` are reserved names (E0259).

## What a secret may do

| Allowed (result secret) | Refused |
|---|---|
| `& \| ^`; `<<`/`>>` by a public amount | checked `+ - *` (E0254): use `wrapping_*` |
| `wrapping_add/sub/mul`, `wrapping_u8`.. conversions | `/ %`, comparisons, `&& \|\|` (E0255) |
| `ct_hide`, `ct_select(c, a, b)` with `Secret(Bool)` `c` | deciding `if`/`while`/`match`/ternary (E0255) |
| `aesni_enc_round`, `aesni_enc_last_round`, `gf128_mul_hw` | a secret index, range bound or shift amount (E0255) |
| lossless casts (`(UInt(576)) b`) | lossy casts (E0255) |
| list read at a public index; `.len()` is public | other methods; provider args; spawn results (E0255) |
| record fields, lists | `Map` key / `Set` element; `Option`/`Result`/sum/handle/fn payload (E0253) |

- Secret ints wider than 32 bits may not live in `List`/`ListBuf`/`Vec`/
  `Map`/`Set` (E0258): keep 64-bit secret words in records and parameters.
- Structural `Show` of anything holding a secret is E0256 (names the field
  path). `Show`/`Serialize`/`Hash`/`Eq`/`Ord` instances for a secret are
  E0257. A type holding a secret may have its own `Show` instance; its body
  can reach the secret only through `declassify`.

## Byte strings and the library

- Secret bytes are `UInt(8)`: `List(Secret(UInt(8)))` (or
  `Secret(List(UInt(8)))`; `secret_split`/`secret_join` convert, free at run
  time). `secret_bytes(bs)` in `lib/word.resid` turns run-time bytes into
  `List(Secret(UInt(8)))`.
- Crypto is written once, generic over behaviors in `lib/word.resid`
  (`Word(W, B)`, `Word64`, `Wide512`, `Block128`, `P256Word`/`P384Word`);
  the `List(Int)` APIs are the public copies. Generic secret entry points:
  `sha256g`/`hmac256g`/`hkdf256g`, `sha512g`, `chacha20poly1305g_*`,
  `aes_gcmg_*`, `aes_key_unwrapg`, `x25519g_*`, `ed25519g_*`, `ecdsag_*`,
  `ecdhg`, `ec_public_keyg`, `hpkeg_*`, `tlsg_*`, `base64g_decode`.
- What is public by design leaves through behaviors whose secret instance
  declassifies (`Publish(B)`, `CtSame(B)`, `X25519Pub(B)`, `TlsPublish(B)`),
  so the secret copies of signing, sealing, opening, key derivation, ECDH,
  and **all TLS** (server, client, transport, `tls_key_load`) need
  `@requires(declassify)`. `ct_eq` in `lib/crypto.resid` compares secret
  byte lists and publishes one bit.

```text
List(Secret(UInt(8))) key = secret_bytes(read_key());
List(Secret(UInt(8))) sealed = aes_gcmg_seal(key, iv, secret_bytes(msg), aad);
List(UInt(8)) wire = declassify(secret_join(sealed), "AEAD output is public");
Option(ServerKey) k = tls_key_load("srv.key");   // needs @requires(filesystem(readonly), declassify)
```

- Persist key material with
  `filesystem.write_secret(path, declassify(key, "persist the key"))`
  (mode 0600, no symlink follow).

## Run time

`Secret(T)` lowers exactly as `T`. A program that uses secrets runs its
allocator in secret mode (switched on before `main`): heap, region,
thread-stack and TLS mappings are `MADV_DONTDUMP`, and memory is zeroed on
free and before reuse. Cost is about 2% wall time on a TLS workload.

## Adding library code on secrets

A new `lib/` function that takes, returns or declassifies a secret needs a
`ct_case_<name>` function in `tests/ct/secretprobe.resid` (or a reason in
`tests/ct/uncovered.txt`): `tests/ct/run.sh` derives its cases and a
coverage gate from the knowledge graph and fails otherwise.
