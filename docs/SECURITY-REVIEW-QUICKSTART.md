# Security-review quickstart

This is a practical entrypoint for the [Halal security review challenge](https://github.com/fredrikblau/halal-protocol/issues/16).
It helps a reviewer reproduce the repository's current evidence and choose a bounded question. It
is not an audit scope, a guarantee, or permission to disclose an exploitable finding publicly.

## Before you start

Use a clean checkout and the pinned toolchain described in the
[contributor quickstart](CONTRIBUTOR-QUICKSTART.md). Read these documents first:

1. [`THREAT-MODEL.md`](THREAT-MODEL.md) — assets, trust boundaries, and known residual risks.
2. [`INVARIANTS.md`](INVARIANTS.md) — the stateful properties and their exact limits.
3. [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md) — deliberate behavior that may differ from older
   planning documents.
4. [`SECURITY-REVIEW-LOG.md`](SECURITY-REVIEW-LOG.md) — work already checked, without treating it
   as independent assurance.

The most security-sensitive code is [`HalalPSM.sol`](../contracts/src/HalalPSM.sol), followed by
[`CPIReportAdapter.sol`](../contracts/src/CPIReportAdapter.sol), the deployment scripts, and the
role-wiring tests.

## Reproduce the baseline

From the repository root:

```sh
make verify
```

The complete gate covers the current contract, script, frontend, ABI, formatting, and disposable
deployment checks. For a faster contract-only loop:

```sh
cd contracts
forge test --match-path test/HalalPSM.t.sol
forge test --match-path test/CPIReportAdapter.t.sol
forge test --match-path test/HalalPSMInvariant.t.sol
```

For a deeper challenge run, use the same settings as the scheduled deep workflow:

```sh
cd contracts
FOUNDRY_FUZZ_RUNS=10000 FOUNDRY_INVARIANT_RUNS=128 FOUNDRY_INVARIANT_DEPTH=64 \
  forge test --match-test testFuzz_RoundTripNeverOverpays
FOUNDRY_INVARIANT_RUNS=128 FOUNDRY_INVARIANT_DEPTH=64 \
  forge test --match-path test/HalalPSMInvariant.t.sol
```

Record the exact commit, Foundry version, command, and result. A passing test is evidence for the
property it exercises, not proof that untested behavior is safe.

## Choose one review question

Keep a first review narrow enough that another person can reproduce it:

| Boundary | Questions to investigate | Useful evidence |
| --- | --- | --- |
| PSM accounting | Can minting, burning, transfer-credit, or cancellation make HLC supply differ from reserve-backed redemption credit? | A minimal Foundry test and the affected invariant |
| Reserve token | What happens with fee-on-transfer, false-return, no-return, paused, reentrant, upgradeable, or unusual-decimal tokens? | Balance-delta trace, mock, and collateralization assertion |
| CPI freshness | Can a stale, future, replayed, too-rapid, too-large, or under-reserving report change the rate? | Report payload, timestamp arithmetic, revert selector, and regression test |
| Signed adapter | Are domain, chain, source, signer ordering, threshold, ownership, signer rotation, and sink watermark checks mutually consistent? | Typed-data digest, recovered signers, adapter/PSM state before and after |
| Governance | Can a caller bypass the DAO/timelock, alter a protected role, or execute a malformed multi-action payload? | Exact target/value/calldata arrays and proposal lifecycle trace |
| Deployment | Can invalid dependencies, beneficiaries, source metadata, or adapter wiring be recorded as healthy evidence? | Offline preflight/verifier output and a fake-RPC regression |

Do not widen the contract's guarantees while writing the report. If the behavior is an accepted
trust assumption—such as reserve-token issuer control or off-chain CPI authenticity—record the
residual risk and the operator control instead of labeling it a code vulnerability.

## Reporting boundary

If a finding could drain or freeze funds, mint without authorization, bypass governance, corrupt
redemption accounting, or compromise a deployed role, do **not** put exploit details in a public
issue, pull request, discussion, or review comment. Use the private [GitHub Security Advisory
form](../SECURITY.md) and include the affected commit, minimal reproduction, impact, and severity
reasoning.

For a non-sensitive bug, open a focused public issue first. A useful security contribution usually
contains:

- the exact affected file/function and commit;
- a minimal failing test or deterministic reproduction;
- the violated security property and realistic impact;
- whether the behavior affects local demos, testnet deployments, or already deployed instances;
- a proposed fix or mitigation, if one is clear; and
- the command and tool versions used to verify the result.

A review that finds no confirmed issue is still useful when it records the tested scope, assumptions,
evidence, and unresolved questions. The repository is unaudited and has no bug bounty; do not use
real funds while reviewing or demonstrating it.
