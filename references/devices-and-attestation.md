# Devices, integrity labels and attestation

Three layers build on each other: the `device` provider reaches kernel
devices through descriptors from `lib/dev/` (spec §49); **integrity
labels** track which values came from outside the program; and
`lib/verify/` turns hardware-signed evidence into `Verified(T)` values that
`@decides` functions release secrets on (`PLAN-attestation.md`). The
Resid repo's `SECURITY.md` lists each guarantee with its tests.

## Device access (`device` capability)

A program never holds a device path, file descriptor or request number:
it calls a wrapper in `lib/dev/`, whose descriptor (a record only
`lib/dev/` may declare, E0260) says exactly what the call does.

```text
import "dev/sev_guest.resid";

@requires(device(readonly))
Int main() {
    Str s = match (snp_get_report(report_data_64_bytes, 0)) {
        Ok(report) => f"{report.len()}-byte report",
        Err(e) => device_error_text(e),
    };
    println(s);
    return 0;
}
```

- `device(readonly)` covers reading descriptors; one that writes (a TPM
  command, an NSM request, a derived key) needs `device`.
- A missing device is a value, `Err(Absent(name))`, never an abort; every
  failure is a `DeviceError` naming the descriptor.
- Buffers are `List(UInt(8))`, or `List(Secret(UInt(8)))` for secret
  outputs; never `Bytes`.
- Modules: `dev/sev_guest`, `sev_guest_ext`, `sev_guest_key`,
  `tdx_guest`, `nsm`, `tsm_report` (configfs: SNP, TDX, CCA), `tpm`
  (`/dev/tpmrm0`: reads, quotes, and for credential activation
  `tpm_ek_cert(ecc)`, `tpm_ek_chain_certs()`, `tpm_ek_ak(ecc)`,
  `tpm_activate_credential(ecc, blob, secret)`, `tpm_quote_ak`), `tpm_wire`
  (pure TPM 2.0 encoders and decoders, no grant), `pci_tsm` (the platform
  TSM, and a PCI function's attributes by `PciAddr {.domain, .bus,
  .device, .function}`: `pci_vendor`, `pci_class`, `pci_authenticated`,
  `pci_tsm_connected`, `pci_doe_spdm`; `pci_addr_parse("0000:3b:00.1")`).
- Verbs a module is written over: `device.ioctl`, `transact`,
  `transact_chain` (several commands on one open file, handles linked
  between them), `configfs_report`, `read_attr`, `read_pci_attr`,
  `sequence`.
- A dependency is bounded by `devices = [...]` in its manifest entry
  (E0261). Each call runs in a fresh, seccomp-confined host process.

## Integrity labels

Every value is **Internal** (computed from the program's own code and
constants) or **External** (anything outside had a say: provider calls,
device replies, native modules, `spawn` results). A value *chosen* by an
External condition is External too. Nothing is written in ordinary code;
`resid-why app --label name` shows the path a label took.

What the labels enforce today:

- **Keys** must hold at least min(length, 32) unpredictable bytes
  (`random_secret(n)`, `provisioned_key(k, "reason")` under the
  `provision` capability, or a library function marked `@key_from`/`@agree`
  over one). A constant or file-read key is E0270 (a warning for now); a
  constant AEAD nonce under a reused key is E0279.
- **Decisions**: outside data must not reach or select what a `@decides`
  function decides (E0286); outside data deciding whether or what a
  `declassify` (or a called function) discloses warns (E0291, E0292).
  `@robust_exempt(reason = "...")` exempts a decision path and is listed
  by `residc verify`.

## Attestation (`lib/verify/`)

A relying party issues a challenge, verifies the evidence under an
**anchor**, appraises it under a **policy**, and releases only inside a
`@decides` function whose gate the compiler checks:

```text
import "verify/core.resid";
import "verify/snp.resid";
import "verify/amd_anchors.resid";
import "verify/seal.resid";
import "challenge.resid";

@policy
SnpPolicy release_policy() { return SnpPolicy {...}; }

@decides(accept = [amd_ark_genoa], appraised = release_policy, identity = key_bound)
@requires(declassify)
Result(HpkeMessage, VerifyError) release(List(UInt(8)) report, ChallengeRecord c, SnpCollateral col, List(Int) pk, List(Secret(UInt(8))) key, List(Secret(UInt(8))) sender) {
    Verified(SnpReport) v = snp_verify_key_bound(report, c, amd_ark_genoa(), col, kernel_time(), 32, pk)?;
    Appraised(SnpReport) a = snp_appraise(v, release_policy())?;
    return seal_to_evidence(a, 32, pk, key, sender);
}
```

- **Challenges**: `challenge_issue(n)` (32 bytes for SPDM, TPM quotes and TPM credentials,
  64 for CCA, at most 64 for the others); `challenge_with_key(value, kem, sk)` binds the attester's
  HPKE key into the value, `challenge_with_channel` a TLS exporter.
- **Verifiers** (each with `_key_bound`, `_channel_bound` where the
  platform allows, and `_replayable` forms): `snp_verify`,
  `tdx_verify_quote`, `nsm_verify`, `cca_verify`, `tpm_verify_quote`,
  `spdm_verify(rec, c, root, t)` (SPDM 1.0-1.3 measurements, an
  `SpdmRecord` of the negotiation, certificates leaf first, OCSP answers
  and the signed exchange), `spdm_verify_challenge`, `spdm_session_verify`
  (a 1.1-1.3 key exchange), `corim_verify` (signed reference values,
  endorsements and keys). Each returns `Verified(T)`, which only
  `lib/verify/` can build (E0276).
- **TPM AKs by credential activation**: `tpm_ak_challenge(ek_cert,
  ak_public, c)` makes the credential, the attester's
  `tpm_activate_credential` answers it, `tpm_verify_ak(ek_chain, crls,
  ak_public, activated, c, root, t)` checks it under a manufacturer's EK
  root (kind `TpmEk`; `verify/tpm_anchors.resid` has 46, e.g.
  `tpm_ek_infineon_optiga_tm_ecc_root_ca()`), giving `Verified(TpmAk)`;
  then `tpm_verify_quote_activated(attest, sig, pcrs, c2, ak, t)`.
- **SPDM requester** (`lib/spdm_requester.resid`): `spdm_connect(io,
  cfg)`, `spdm_get_digests`, `spdm_get_certificate`, `spdm_challenge`,
  `spdm_get_measurements`, `spdm_start_session`, `spdm_start_psk_session`,
  `spdm_heartbeat`, `spdm_key_update`, `spdm_end_session`, over an
  `SpdmIo` transport closure (`lib/spdm_transport.resid`: MCTP, PCI DOE,
  TCP framing; `spdm_emu_connect` for DMTF's emulator). Each step returns
  the bytes a verifier's record needs.
- **Anchors** are nullary `@anchor(kind = ..., fingerprint = ...,
  formats = [...], algorithms = [...], expires = ...)` functions returning
  `anchor_der(bytes)`; the standard ones are generated
  (`amd_anchors`, `intel_anchors`, `aws_anchors`, `nvidia_anchors`). A
  verifier's anchor must be a call of one (E0282).
- **Policies** are nullary `@policy` functions; an appraisal's policy must
  be a direct call of one (E0283).
- **`@decides`** names the anchors it accepts (and may `require`), the
  policy (`appraised`), and the identity (`key_bound`, `channel_bound`,
  `local`, or `none`); the gate must meet all of it (E0284, E0285). A
  key-bound decision releases only through `seal_to_evidence`, a
  channel-bound one through `seal_to_channel` (E0287); no gate inside a
  loop (E0288).
- **Endorsements**: `corim_verify(corim, endorser, t)` under an
  `Endorser` anchor reads every CoRIM triple. `*_appraise_endorsed` (SNP,
  TDX, CCA, `spdm_appraise_endorsed(v, policy, refs, env)`, TPM, NSM)
  accept what a reference value corroborates; `snp_corim(v, refs)` and the
  like give the accepted claims set for `corim_corroborated`,
  `corim_holds` (endorsed flags, versions) and `corim_endorsements`.
  Attest-key triples replace a pinned key in `cca_verify_endorsed` and
  `tpm_verify_quote_endorsed`, identity triples a device chain in
  `spdm_verify_endorsed`. Either way the result rests on the endorser, so
  `accept` names it.
- **Devices bound to a guest**: the guest's report carries
  `challenge_session_value(challenge_value(c), s.value.th)` for an SPDM
  session `s`; `snp_verify_device_bound`, `tdx_verify_quote_device_bound`,
  `nsm_verify_device_bound`, `cca_verify_device_bound` and the TPM forms
  check it, and the result rests on both anchors. The requester's session
  keys and secured messages are `lib/spdm_session.resid`.
- **Assumptions**: `assume(x, a)` with an application's
  `@assumption(reason = ..., pins = ...)` function stands in for evidence
  and must be accepted by name (E0289; needs the `assume` capability).
- **Pins**: a program that reaches `lib/verify/` compiles only against the
  verify closure its compiler was released with (E0290);
  `--verify-lib-dev` lifts it for development and is recorded.

## Error codes

| Code | Meaning |
|---|---|
| E0260 | a device descriptor outside `lib/dev/`, or a `device` verb without one |
| E0261 | a dependency reaches a device outside its manifest `devices = [...]` |
| E0262-E0264 | a descriptor not known after reduction, or with a bad layout or sequence |
| E0270 | (warning) a key that could be known to someone else |
| E0276 | a literal of an `@opaque` type (`Verified`, `Anchor`, ...) outside its file |
| E0279 | (warning) a constant AEAD nonce under a reused key |
| E0280 | `@primitive`/`@verify_internal` outside `lib/verify/`, or calling an internal verifier |
| E0281 | a malformed `@anchor` |
| E0282 | a verifier's anchor not a call of an `@anchor` function, or of the wrong kind, algorithm or format |
| E0283 | an appraisal's policy not a direct call of a `@policy` function |
| E0284 | a `@decides` function with a success return no verifier gates |
| E0285 | the gate does not meet the decision: anchors not accepted, another policy, not fresh, no identity |
| E0286 | outside data reaches or selects what a decision decides |
| E0287 | a release outside a decision, or not on its gate |
| E0288 | a gate formed inside a loop |
| E0289 | a malformed `@assumption`, or one in the standard library |
| E0290 | `lib/verify/` built against a closure this compiler was not released with |
| E0291, E0292 | (warnings) outside data decides a disclosure |
| E0293 | challenges for several purposes and a decision naming none (`bind = "..."`) |
| E0294 | an instance replacing the standard library's in a program that verifies |
