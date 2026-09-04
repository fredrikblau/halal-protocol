# Engineering security review log

This log records repository-level review activity. It is not a professional audit, formal
verification, economic review, oracle certification, or deployment approval. The project remains
unaudited and must not be used with meaningful funds.

## Review record — 2026-08-26

### Scope

- `contracts/src/HalalPSM.sol`: reserve balance-delta accounting, per-address redemption credit,
  CPI bounds/cadence/freshness, reserve-floor checks, permit paths, and DAO reserve operations.
- `contracts/src/CPIReportAdapter.sol`: EIP-712 domain/source binding, sorted quorum recovery,
  timestamp watermark, sink acceptance, and owner/signer separation.
- Related evidence in `contracts/test/HalalPSM.t.sol`, the stateful invariant suites,
  `contracts/test/CPIReportAdapter.t.sol`, and `docs/THREAT-MODEL.md`.

### Result

No confirmed vulnerability was identified in this pass. The reviewed properties have executable
regression or invariant coverage, including:

- PSM-issued credit conservation and separation from genesis HLC;
- collateralization across governance CPI changes and reserve-token transfer variants;
- fail-closed behavior for stale, future, replayed, or under-collateralizing reports;
- adapter signer uniqueness, threshold, source/domain binding, ownership handoff, and sink
  watermark alignment;
- reserve transfer reentrancy and false/no-return/fee-on-transfer compatibility boundaries.

This is a record of what was checked, not evidence that no vulnerability exists.

### Reproduction evidence

From the repository root:

```sh
make verify
```

The review run passed 199 Solidity tests (including stateful invariants), 81 Node tests, and 26
browser tests, plus contract lint, frontend lint/build, local Anvil smoke tests, and the signed CPI
adapter rehearsal. The pinned Slither record is maintained separately in
[`STATIC-ANALYSIS.md`](STATIC-ANALYSIS.md).

As an additional challenge after the baseline run, the PSM invariant suites passed with
`FOUNDRY_INVARIANT_RUNS=128` and `FOUNDRY_INVARIANT_DEPTH=64` (8,192 calls per invariant suite),
and `testFuzz_RoundTripNeverOverpays` passed 10,000 fuzz cases. These deeper runs increase
confidence in the tested properties but do not expand the contract's stated guarantees or replace
independent review.

### Residual questions

- The reserve token's issuer controls, upgrade path, pause/blacklist behavior, and fee policy
  require deployment-specific due diligence.
- CPI source authenticity, revision policy, signer custody, and relayer operations remain off-chain
  trust boundaries; see the [CPI adapter specification](CPI-ADAPTER-SPEC.md).
- Governance capture, economic adequacy under prolonged inflation, and incident response require
  independent review and a deployment-specific journal.
- No public testnet deployment or professional third-party audit exists yet.

Invite independent reviewers to reproduce the scope, challenge the assumptions, and report any
fund-risking finding privately through [`SECURITY.md`](../SECURITY.md), not in this public log.
