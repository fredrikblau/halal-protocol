# Contributor map

Pick a bounded problem, read the linked design note, and open an issue before changing protocol
behavior. A useful contribution leaves a test, a reproducible command, or a documented decision
that another reviewer can check.

New contributors can use the [ten-minute quickstart](CONTRIBUTOR-QUICKSTART.md) to verify a clean
checkout before choosing an issue.

The current security review scope is [issue #16](https://github.com/fredrikblau/halal-protocol/issues/16).
Start there if you want to inspect the PSM, CPI boundaries, reserve assumptions, or governance
operations. Report fund-risking findings through [`SECURITY.md`](../SECURITY.md), not the issue.
For a bounded way to help unblock the review queue, see the [independent reviewer call](https://github.com/fredrikblau/halal-protocol/discussions/154).

## Good first issues

Choose the task that matches your interests; each issue includes a bounded scope, acceptance
criteria, and a safe local verification path:

- The completed [release verification walkthrough](RELEASE-VERIFICATION.md) is a reference for
  clean-checkout tag, artifact, ABI, local-gate, and hosted-check review.
- [Incident-response tabletop example (#86)](https://github.com/fredrikblau/halal-protocol/issues/86) —
  rehearse detection, evidence preservation, governance response, and recovery verification for a
  fictional protocol incident; use the completed [`stale-CPI example`](INCIDENT-RESPONSE-TABLETOP-EXAMPLE.md)
  as a reference.
- The completed [read-only governance payload verifier (#90)](https://github.com/fredrikblau/halal-protocol/issues/90)
  is available at [`scripts/verify-governance-payload.mjs`](../scripts/verify-governance-payload.mjs).
- The completed [deterministic governance payload property coverage (#91)](https://github.com/fredrikblau/halal-protocol/issues/91)
  is available in [`verify-governance-payload.test.mjs`](../scripts/test/verify-governance-payload.test.mjs)
  as a reproducible example of seeded negative testing.
- The completed [governance review evidence template (#89)](https://github.com/fredrikblau/halal-protocol/issues/89)
  is available for recording the review outcome.
- The completed [governance proposal review case study (#87)](https://github.com/fredrikblau/halal-protocol/issues/87)
  is available as the reference for both starter tasks.
- The completed [machine-readable monitoring example](MONITORING-JSON-EXAMPLE.md) shows how to
  consume health JSON while preserving fail-closed exit behavior.
- The completed [offline deployment preflight](../scripts/preflight-deployment.mjs) shows how to
  report registry readiness without RPC access, credentials, signing, or file mutation (issue #93).
- The completed [reserve-asset due-diligence example](RESERVE-ASSET-DUE-DILIGENCE-EXAMPLE.md)
  demonstrates how to separate observations, assumptions, residual risks, and decisions.
- The completed [local deployment evidence example](LOCAL-DEPLOYMENT-EVIDENCE.md) shows how to
  record safe Anvil-only wiring and health rehearsals.
- [CPI source policy documentation (#80)](https://github.com/fredrikblau/halal-protocol/issues/80) —
  document how operators record source identity, cadence, custody, and fallback decisions.
- [Clean-clone quickstart verification (#118)](https://github.com/fredrikblau/halal-protocol/issues/118) —
  run the contributor quickstart on a second environment and record reproducible setup evidence without
  wallets, RPC credentials, deployment, or real funds.
- [Rebasing reserve-token model (#159)](https://github.com/fredrikblau/halal-protocol/issues/159) —
  currently claimed in [PR #160](https://github.com/fredrikblau/halal-protocol/pull/160); review and
  alternative edge cases remain welcome.
- The [accounting-aware transfer validation task (#156)](https://github.com/fredrikblau/halal-protocol/issues/156) is
  currently claimed in [PR #157](https://github.com/fredrikblau/halal-protocol/pull/157); review and follow-up
  improvements remain welcome.
- [First Arbitrum Sepolia reference deployment (#40)](https://github.com/fredrikblau/halal-protocol/issues/40) —
  coordinate a reviewed testnet deployment and publish reproducible address, source, health, and
  journal evidence; this requires maintainer coordination and is not a casual copy-paste task.
- [Production CPI adapter design (#17)](https://github.com/fredrikblau/halal-protocol/issues/17) —
  review the adapter boundary, signer custody, source provenance, freshness, rotation, and failure
  handling before any real deployment.
- [HalalPSM security review challenge (#16)](https://github.com/fredrikblau/halal-protocol/issues/16) —
  inspect accounting, reserve-token assumptions, CPI boundaries, and governance paths using the
  threat model and invariant suite; report suspected vulnerabilities privately.

The completed [CPI source-policy template (#54)](https://github.com/fredrikblau/halal-protocol/issues/54)
is available as a reference for the documentation standard, but is no longer an active starter task.

The completed [Markdown link validation (#98)](https://github.com/fredrikblau/halal-protocol/issues/98)
is available as a reference for adding a dependency-free repository quality gate with regression
coverage.

The completed [reserve-token integration decision tree (#97)](https://github.com/fredrikblau/halal-protocol/issues/97)
is available as a reference for turning existing operator checklists into a concise, evidence-driven
decision path.

The completed [CPI parser revision fixtures (#92)](https://github.com/fredrikblau/halal-protocol/issues/92)
are available as a reference for conservative, offline oracle testing and explicit revision policy.

The completed [CPI policy record validator (#94)](https://github.com/fredrikblau/halal-protocol/issues/94)
is available at [`scripts/validate-cpi-policy.mjs`](../scripts/validate-cpi-policy.mjs) as a reference
for offline, fail-closed evidence validation; it is not an active starter task.

The completed [local-demo troubleshooting guide](LOCAL-DEMO-TROUBLESHOOTING.md) covers prerequisites,
ports, stale configuration, cleanup, and expected success signals.

The completed [adversarial reserve-token invariant coverage (#53)](https://github.com/fredrikblau/halal-protocol/issues/53)
shows the expected standard for a deeper, test-first security contribution. New contributors should
start with the active tasks above.

The [deployment review worksheet (#42)](https://github.com/fredrikblau/halal-protocol/issues/42)
is a completed example of the contribution standard above.

## Choose a path

| Interest | Start here | A finished contribution proves |
| --- | --- | --- |
| Solidity security | [`docs/THREAT-MODEL.md`](THREAT-MODEL.md), [`contracts/test/`](../contracts/test/) | An adversarial test, the affected invariant, and a clear risk explanation |
| Reserve-token behavior | [`HalalPSM.t.sol`](../contracts/test/HalalPSM.t.sol), [`HalalPSMArithmetic.t.sol`](../contracts/test/HalalPSMArithmetic.t.sol) | A reserve-token fixture and tests for balance deltas, fees, decimals, or callback behavior |
| CPI/oracle integration | [`HalalPSM.sol`](../contracts/src/HalalPSM.sol), [`docs/CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md), [`docs/OPERATOR-RUNBOOK.md`](OPERATOR-RUNBOOK.md) | A reviewed adapter or relayer with source provenance, heartbeat, fallback, and rotation rules |
| Monitoring | [`scripts/check-deployment-health.sh`](../scripts/check-deployment-health.sh), [`docs/OPERATOR-RUNBOOK.md`](OPERATOR-RUNBOOK.md) | A read-only alert integration that preserves the scripts' fail-closed exit behavior |
| Economic research | [`docs/ECONOMIC-MODEL.md`](ECONOMIC-MODEL.md), [`scripts/model-psm.mjs`](../scripts/model-psm.mjs) | A reproducible scenario, explicit assumptions, and a comparison with the Solidity rounding rules |
| dApp UX | [`app/src/components/`](../app/src/components/), [`app/README.md`](../app/README.md) | A usable flow on the local demo, responsive states, and passing lint/build checks |
| Governance design | [`docs/DAO-Guide.md`](DAO-Guide.md), [`contracts/script/Examples.s.sol`](../contracts/script/Examples.s.sol) | Decoded proposal actions, timing analysis, and tests for the timelock path |
| Documentation | [`docs/DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md), [`deployment-config test guide`](DEPLOYMENT-CONFIG-TESTS.md) | A correction tied to current source code, with commands or links a reviewer can follow |

## Run the project

From the repository root:

```shell
make verify
make economic-model
./scripts/local-demo.sh
```

The local demo uses a disposable Anvil chain and a faucet-only `mDAI` token. Never use its
published development mnemonic or reserve token on a public network.

## Submit work

Open an issue for a non-trivial change and describe the problem, the smallest proposed scope, and
the evidence you plan to add. Use a topic branch and a Conventional Commit. A pull request should
link the issue, state whether it changes deployed behavior, and include the commands you ran.

Do not disclose security vulnerabilities in an issue or pull request. Follow [`SECURITY.md`](../SECURITY.md)
for private reporting. Contract changes require extra review because the reference contracts are
immutable and unaudited.

For the automated contract-review scope and its limitations, see the [static-analysis record](STATIC-ANALYSIS.md).
