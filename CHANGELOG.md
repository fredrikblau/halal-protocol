# Changelog

All notable changes to this project are documented here.

## Unreleased

- Added governance-boundary regression coverage for CPI adapter signer duplication and two-step
  ownership acceptance, plus DAO quorum and timelock policy behavior.
- Synchronized current contributor, technical, governance, architecture, and security-review
  documentation with the 199-test Solidity suite (186 unit/configuration tests and 13 invariants).

## 0.1.0-alpha.266 - 2026-08-27

- Made the offline CPI adapter handoff builder reject the same empty and whitespace-only source
  labels rejected by the PSM, preventing doomed governance payloads from being generated.

## 0.1.0-alpha.265 - 2026-08-27

- Extended PSM source-label hardening to reject ASCII whitespace-only values, while preserving
  meaningful labels that contain spaces.

## 0.1.0-alpha.264 - 2026-08-27

- Made the PSM reject empty CPI source labels at the contract boundary, adding defense in depth
  beyond adapter-handoff validation.
- Synchronized current evidence to 194 Solidity, 81 Node, and 26 browser tests.

## 0.1.0-alpha.263 - 2026-08-27

- Added a release-workflow gate that fails if `CITATION.cff` does not identify the exact published
  tag, preventing stale citation metadata from accompanying a release artifact.

## 0.1.0-alpha.262 - 2026-08-27

- Synchronized `CITATION.cff` with the current published release for reproducible scholarly and
  software citations.

## 0.1.0-alpha.261 - 2026-08-27

- Added direct monitoring regression coverage proving a configured CPI adapter becomes unhealthy
  when the PSM's human-readable source label changes.

## 0.1.0-alpha.260 - 2026-08-27

- Made the governed CPI source label a required, end-to-end deployment identity alongside the
  adapter address and immutable source ID.
- Added fail-closed verifier, registry, monitoring, frontend, and local rehearsal coverage when
  the on-chain PSM `source()` label diverges from recorded evidence.

## 0.1.0-alpha.259 - 2026-08-27

- Added an evidence-driven reserve-token integration decision tree and linked it from the public deployment worksheet.

## 0.1.0-alpha.258 - 2026-08-27

- Made the production deployment script reject reserve-token addresses without contract bytecode before deploying the rest of the system.
- Added configuration regression coverage, documented the preflight behavior for operators, and synchronized current documentation with the verified 193-test Solidity and 77-test Node suites.

## 0.1.0-alpha.257 - 2026-08-26

- Kept the contributor map synchronized after completing the Markdown link validation issue.

## 0.1.0-alpha.256 - 2026-08-26

- Added a dependency-free Markdown link and heading-anchor checker with regression coverage.
- Added the checker to `make verify` and a path-filtered documentation CI job.

## 0.1.0-alpha.255 - 2026-08-26

- Synchronized current public documentation with the verified 192-test Solidity suite and 73-test Node suite.
- Refreshed the contributor map and opened focused good-first issues for reserve-token documentation and Markdown link validation.

## 0.1.0-alpha.254 - 2026-08-26

- Made the CPI adapter governance handoff builder reject empty source metadata, preventing an
  otherwise valid proposal from clearing the source label during adapter activation.
- Added a Foundry regression test for the fail-closed handoff path.

## 0.1.0-alpha.253 - 2026-08-26

- Hardened reviewed CPI policy validation to reject impossible UTC calendar dates and malformed
  retrieval timestamps instead of accepting regex-valid but invalid evidence.
- Added regression coverage; all 73 Node script tests passed.

## 0.1.0-alpha.252 - 2026-08-26

- Added a copy-pasteable clean-checkout contributor quickstart covering local verification,
  safe contribution boundaries, and pull-request evidence.
- Linked the quickstart from the main contributing guide and contributor map.
- `git diff --check` and the configured local dApp smoke test passed.

## 0.1.0-alpha.251 - 2026-08-26

- Improved deployment-health accessibility with semantic check lists and explicit relationships
  between each check's label, status, and explanatory detail.
- Added browser regression coverage for accessible healthy and blocking check states.
- Focused health scenarios and frontend lint passed.

## 0.1.0-alpha.250 - 2026-08-26

- Required adapter-backed deployment records to link an HTTPS CPI policy evidence URL alongside
  adapter and source identity metadata; deployment recorder and offline preflight now fail closed
  when that evidence is missing.
- Displayed the CPI policy link in the dApp deployment-evidence card and added regression coverage.
- Full local verification passed with 72 Node, 191 Solidity, and 26 browser tests.

## 0.1.0-alpha.249 - 2026-08-26

- Required adapter-backed deployment registry entries to include an HTTPS CPI policy evidence URL
  alongside the adapter address and source ID.
- Added registry/preflight regression coverage and displayed the policy link in the dApp evidence card.
- Full local verification passed with 72 Node, 191 Solidity, and 26 browser tests.

## 0.1.0-alpha.248 - 2026-08-26

- Hardened the CPI policy validator to reject all-zero parser commits and SHA-256 values as
  evidence placeholders, exposed the policy check in `make help`, and added regression coverage.
- Full local verification passed with 70 Node, 191 Solidity, and 26 browser tests.

## 0.1.0-alpha.247 - 2026-08-26

- Implemented issue #94 with an offline CPI policy-record validator, draft/reviewable status
  semantics, HTTPS/hash/address/quorum checks, fictional fixtures, and operator documentation.
- Full local verification passed with 69 Node, 191 Solidity, and 26 browser tests.

## 0.1.0-alpha.244 - 2026-08-26

- Synchronized the engineering security review log with the current 64-test Node suite.

## 0.1.0-alpha.243 - 2026-08-26

- Corrected the deployment-health JSON wrapper so failed health commands pass their nonzero status
  to the formatter and produce structured fail-closed output.
- Added end-to-end regression coverage and reran the complete local verification gate.

## 0.1.0-alpha.242 - 2026-08-26

- Added fail-closed classification for unstructured deployment-health command failures and a
  regression test. The pipeline propagation correction was published in alpha.243.

## 0.1.0-alpha.241 - 2026-08-26

- Strengthened public issue and pull-request guidance with safe security-reporting prompts, full-gate
  expectations, generated-ABI checks, deployment-impact declarations, and the complete active
  contributor issue map.

## 0.1.0-alpha.240 - 2026-08-26

- Made the offline governance verifier independently derive Ethereum function selectors with a
  dependency-free Keccak-256 implementation and reject selector/signature mismatches.
- Added fixed Keccak test vectors and preserved the dependency-light, no-RPC verification path.

## 0.1.0-alpha.239 - 2026-08-26

- Hardened the offline governance payload verifier against ambiguous policy definitions and invalid
  ABI signatures, including duplicate case-variant targets/selectors and unsupported argument types.

## 0.1.0-alpha.238 - 2026-08-26

- Hardened the offline governance payload verifier to validate canonical ABI argument encoding and
  reject malformed known selectors, non-canonical addresses, invalid dynamic offsets, and
  out-of-range integer values.

## 0.1.0-alpha.237 - 2026-08-26

- Recorded higher-depth PSM invariant evidence: 128 runs at depth 64 and 10,000 round-trip fuzz
  cases passed, while preserving the explicit non-audit limitations.

## 0.1.0-alpha.236 - 2026-08-26

- Made the release-verification walkthrough select the newest published alpha tag automatically,
  while retaining an override for historical release reviews.

## 0.1.0-alpha.235 - 2026-08-26

- Added a dated engineering security review log for PSM accounting and CPI adapter boundaries,
  including reproducible evidence and explicit residual risks without overstating the result as an
  audit.

## 0.1.0-alpha.234 - 2026-08-26

- Added a dated engineering security review log covering the PSM accounting and CPI adapter
  boundaries, with reproducible evidence and explicit residual risks. It does not claim an audit.

## 0.1.0-alpha.233 - 2026-08-26

- Refreshed the contributor map after completing the CPI parser fixture task, leaving the active
  starter list focused on unresolved policy, deployment, adapter, and security-review work.

## 0.1.0-alpha.232 - 2026-08-26

- Hardened the BLS CPI parser against duplicate periods and revision-marked (`R`) observations;
  revised input now fails closed pending explicit policy review.
- Added deterministic coverage proving the parser preserves the caller-supplied publication
  timestamp and rejects future timestamps.

## 0.1.0-alpha.231 - 2026-08-26

- Marked the offline deployment preflight contribution complete in the contributor map and linked
  its implementation as a reference for future tooling contributors.

## 0.1.0-alpha.230 - 2026-08-26

- Added an offline, read-only deployment preflight that reports missing registry evidence, supports
  a requested chain, emits versioned JSON, and fails closed on an empty or malformed registry.
- Documented the preflight in the README, Makefile, and operator runbook, with CLI and fixture
  coverage in the 60-test Node suite.

## 0.1.0-alpha.229 - 2026-08-26

- Extended protected `main` checks to require Slither static analysis, extended fuzzing/invariants,
  and both CodeQL language analyses in addition to the core CI jobs.

## 0.1.0-alpha.228 - 2026-08-26

- Strengthened `main` branch protection so pull requests require path detection plus every applicable
  Contracts, Scripts, generated-ABI, and Frontend CI check, while retaining strict ordering and code-owner review.

## 0.1.0-alpha.227 - 2026-08-26

- Added a scoped static-analysis record documenting the pinned Slither 0.11.6 reproduction, 66
  contracts, 102 detectors, zero reported results, and the limits of that evidence.

## 0.1.0-alpha.226 - 2026-08-26

- Refreshed the public onboarding path by removing a stale closed-issue link from the README and
  documenting the hosted contracts, scripts, ABI, and frontend CI coverage accurately.

## 0.1.0-alpha.225 - 2026-08-26

- Increased the frontend CI job timeout from 15 to 30 minutes after a hosted run completed all 26
  browser tests successfully but was canceled during post-test cleanup.

## 0.1.0-alpha.224 - 2026-08-26

- Fixed the hosted `Scripts (Node)` CI job to install Foundry, matching the local script suite's
  disposable CPI-adapter rehearsal dependency after the first hosted run exposed the omission.

## 0.1.0-alpha.223 - 2026-08-26

- Added a hosted `Scripts (Node)` CI job for shell syntax, deployment-registry validation, and all
  dependency-light script tests, making governance and health-tool regressions visible to contributors.

## 0.1.0-alpha.222 - 2026-08-26

- Added fixed-seed property coverage for governance payload verification, exercising 1,280 malformed
  and unauthorized cases without RPC, signing, or network access.
- Closed contributor issue #91 and retained the test as a reproducible negative-testing example.

## 0.1.0-alpha.221 - 2026-08-26

- Refreshed the contributor map and README with the offline governance verifier and replaced the
  duplicate decoder-fixture issue #88 with deterministic property-coverage issue #91.

## 0.1.0-alpha.220 - 2026-08-26

- Added an offline, dependency-light governance payload verifier that fails closed on unknown targets,
  malformed calldata, disallowed selectors, array mismatches, and unexpected ETH values while
  preserving raw action diagnostics.
- Added five focused tests, documented the explicit target-policy format, closed #90 and the duplicate
  coverage issue #88, and opened deterministic property-coverage issue #91.

## 0.1.0-alpha.219 - 2026-08-26

- Added a copyable governance review evidence template for preserving raw action arrays, independent
  impact checks, observed facts, assumptions, decisions, and timelock receipts.
- Closed #89 and opened labeled read-only governance payload verifier issue #90.

## 0.1.0-alpha.218 - 2026-08-26

- Added a fictional governance proposal review case study with reproducible raw calldata, an unsafe
  reserve-withdrawal comparison, and independent role, reserve, simulation, and timelock checks.
- Closed #87 and replenished the contributor funnel with labeled decoder-fixture (#88) and governance
  evidence-template (#89) starter tasks.

## 0.1.0-alpha.217 - 2026-08-26

- Added a fictional stale-CPI incident-response tabletop showing detection, safe containment,
  governance/external recovery authority, retained evidence, and recovery proof.
- Replenished the contributor funnel with the labeled governance proposal review task in issue #87.

## 0.1.0-alpha.216 - 2026-08-26

- Added a dependency-free machine-readable health consumer with explicit healthy, unhealthy, and
  invalid-schema exit codes, tests, and an operator integration example.
- Replenished the contributor funnel with the labeled incident-response tabletop task in issue #86.

## 0.1.0-alpha.215 - 2026-08-26

- Added a fictional, non-binding reserve-asset due-diligence example that separates observed facts,
  assumptions, open questions, monitoring obligations, and deployment decisions.
- Replenished the contributor funnel with the labeled machine-readable monitoring task in issue #85.

## 0.1.0-alpha.214 - 2026-08-26

- Refreshed contributor links after closing issue #83 so active issue #84 is surfaced as the next
  reserve-asset due-diligence starter task.

## 0.1.0-alpha.213 - 2026-08-26

- Added a safe, Anvil-only local deployment evidence walkthrough covering healthy checks, an
  intentional unhealthy result, journal mapping, and the registry recorder boundary.
- Replenished the contributor funnel with the labeled reserve-asset due-diligence task in issue #84.

## 0.1.0-alpha.212 - 2026-08-26

- Added a 20-minute job bound to the extended fuzzing and invariant workflow so runner or Foundry
  hangs become actionable failures instead of indefinite hosted checks.

## 0.1.0-alpha.211 - 2026-08-26

- Hardened deployment manifest recording so the supplied deployment transaction must have a
  matching successful receipt and a mined block at or after the claimed deployment block.
- Added deterministic receipt-validation tests and documented the stronger registry evidence gate.

## 0.1.0-alpha.210 - 2026-08-26

- Extended the reserve-token matrix with a configurable fee mock and a regression proving that a
  fee change after deposit cannot silently underpay a bounded withdrawal.
- Updated current documentation to the verified 191-test suite and recorded the operator-matrix
  evidence for changing fee policies.
- Replenished the contributor funnel with the labeled local deployment-evidence task in issue #83.

## 0.1.0-alpha.209 - 2026-08-26

- Refreshed the README and contributor map so the active changing-fee reserve-token starter task
  (#82) is visible alongside the CPI source-policy task.

## 0.1.0-alpha.208 - 2026-08-26

- Added a paused-reserve-token regression proving a failed withdrawal preserves HLC supply,
  redemption credit, and reserve accounting.
- Expanded the operator compatibility matrix with the tested pause/freeze behavior and refreshed
  current documentation to the verified 190-test suite.

## 0.1.0-alpha.207 - 2026-08-26

- Hardened the read-only PSM health check against timestamp-addition overflow and future RPC
  timestamps, with structured unhealthy reasons and regression coverage.

## 0.1.0-alpha.206 - 2026-08-26

- Added a clean-clone release verification walkthrough covering tag identity, source-bundle checksums,
  attestations, local gates, deterministic ABIs, hosted checks, and safe review records.
- Linked the walkthrough from contributor guidance and the deployment/release review path.

## 0.1.0-alpha.205 - 2026-08-26

- Added a source-linked BLS CPI-U policy draft with reproducible scaling, timestamp, archive, and
  custody requirements while explicitly preserving its draft/non-approval status.
- Linked the draft from the deployment journal and operator runbook for safer handoff review.

## 0.1.0-alpha.204 - 2026-08-26

- Added a 15-minute timeout to the configured frontend smoke-test job so local process hangs fail
  visibly instead of leaving required CI indefinitely in progress.

## 0.1.0-alpha.203 - 2026-08-26

- Hardened governance action decoding to use the configured target contract ABI, preventing misleading
  function labels for selectors sent to unrelated contracts.
- Added browser coverage for known, unknown-target, and malformed-selector calldata fallbacks.
- Replenished the contributor funnel with the labeled CPI source-policy task in issue #80.

## 0.1.0-alpha.202 - 2026-08-26

- Added browser coverage proving advanced proposals preserve multiple actions, ordering, ETH values, and raw calldata.
- Replenished the contributor funnel with the labeled action-decoder task in issue #79.

## 0.1.0-alpha.201 - 2026-08-26

- Added browser coverage proving governance payloads are rebuilt safely when switching between CPI and
  advanced templates, including invalid-state submission gating.
- Replenished the contributor funnel with the labeled multi-action governance task in issue #78.

## 0.1.0-alpha.200 - 2026-08-26

- Added end-to-end coverage for both inclusive CPI bounds and exact encoded governance calldata.
- Replenished the contributor funnel with the labeled template-switching task in issue #77.

## 0.1.0-alpha.199 - 2026-08-26

- Added below-threshold governance browser coverage using an isolated wallet, proving both proposal
  templates keep submission disabled and emit no transaction without 100 HLC of voting power.
- Replenished the contributor funnel with the labeled valid-CPI-boundary task in issue #76.

## 0.1.0-alpha.198 - 2026-08-26

- Added a source-verified governance lifecycle walkthrough with local dApp steps, exact Foundry
  commands, timing parameters, and expected proposal states.
- Replenished the contributor funnel with the labeled threshold-gating task in issue #75.

## 0.1.0-alpha.197 - 2026-08-26

- Corrected proposal-detail status aggregation so secondary snapshot/quorum reads participate in
  loading and failure state, with browser coverage proving incomplete live data cannot expose action controls.
- Replenished the contributor funnel with the labeled governance lifecycle walkthrough in issue #74.

## 0.1.0-alpha.196 - 2026-08-26

- Added required-description governance regression coverage, including disabled-submit and
  no-wallet-transaction assertions while recovering to a valid proposal description.
- Stabilized network-switch failure UX and refreshed the labeled contributor queue with issue #73.

## 0.1.0-alpha.195 - 2026-08-26

- Hardened the CPI governance form against over-precision input that `parseUnits` would otherwise
  round, and added browser coverage for every invalid rate boundary with no-wallet-submit checks.
- Stabilized the injected-wallet browser fixture and made network-switch errors contextual so wallet
  rejection guidance remains actionable across provider implementations.
- Replenished the contributor funnel with issue #72 after completing the previous validation task.

## 0.1.0-alpha.194 - 2026-08-26

- Added a disposable-Anvil browser regression for creating a valid CPI governance proposal,
  including delegated voting power, configured PSM targeting, decoded `mockCPI` calldata, and
  proposal list/detail visibility.
- Replenished the contributor funnel with a clearly scoped, labeled CPI-template validation task
  after closing the completed governance-flow issue.

## 0.1.0-alpha.170 - 2026-08-26

- Audited the contributor queue, closed the already-covered adapter health task, and opened a
  focused reserve-deficit health-state task for the next frontend testing contribution.

## 0.1.0-alpha.169 - 2026-08-26

- Added a provider-neutral CPI source-policy template covering source identity, value transformation,
  parser evidence, revisions, signer custody, and operational review.
- Linked the template from the adapter specification, operator runbook, deployment checklist, and README.

## 0.1.0-alpha.168 - 2026-08-26

- Replenished the contributor funnel with two active, labeled starter issues and removed completed
  work from the README and contributor map's good-first-issue entry points.

## 0.1.0-alpha.167 - 2026-08-26

- Hardened the production CPI adapter deployment preflight so its owner must already be a deployed
  contract, normally the protocol timelock, rather than an EOA.
- Added deployment-config coverage and synchronized public test-count claims to 185 tests.

## 0.1.0-alpha.166 - 2026-08-26

- Added stateful PSM coverage for a supported fee-on-transfer reserve and a rejected false-returning
  reserve, preserving credit, supply, and reserve-floor invariants across randomized action sequences.
- Documented the reserve-token behavior boundary and synchronized the public suite count to 184 tests.

## 0.1.0-alpha.165 - 2026-08-26

- Hardened the production deployment preflight so team and treasury vesting beneficiaries must be
  deployed contracts, matching the multisig/custody launch policy; the local demo remains EOA-compatible.
- Added deployment-config regression coverage and synchronized the public suite count to 179 tests.

## 0.1.0-alpha.164 - 2026-08-26

- Added a worked redeemable-credit example documenting ordinary HLC transfers, accounting-aware
  claim transfers, withdrawal, and claim retirement with explicit balance and credit changes.

## 0.1.0-alpha.163 - 2026-08-26

- Stabilized the vesting handoff browser regression by asserting the durable beneficiary and
  pending-state transitions instead of timing-sensitive notification text after confirmation.

## 0.1.0-alpha.162 - 2026-08-26

- Made pending vesting beneficiaries visible in the dApp so they can complete the two-step
  beneficiary handoff; active-beneficiary release permissions remain unchanged.
- Added an end-to-end two-wallet browser regression for proposal and acceptance.

## 0.1.0-alpha.161 - 2026-08-26

- Added an accessible deployment-health summary action that copies the selected chain, timestamp,
  and visible public check results without exposing wallet or signer data.
- Added browser coverage for the copy feedback and summary contents.

## 0.1.0-alpha.160 - 2026-08-26

- Added a deeper test-first contributor task for stateful PSM coverage across adversarial reserve
  token behavior, and linked it from the public contributor guides.

## 0.1.0-alpha.159 - 2026-08-26

- Replaced stale completed good-first-issue links with three active, bounded contributor tasks for
  vesting browser coverage, deployment-health UX, and redeemable-credit documentation.

## 0.1.0-alpha.158 - 2026-08-26

- Synchronized current README, contributor, architecture, DAO, technical, and contracts
  documentation with the verified 178-test Foundry suite (175 unit/configuration tests plus
  3 stateful invariants).

## 0.1.0-alpha.157 - 2026-08-26

- Refreshed the checked-in dApp ABIs after the vesting dependency validation added in alpha156.

## 0.1.0-alpha.156 - 2026-08-26

- Hardened vesting deployment checks so a non-contract token or DAO dependency cannot produce
  an apparently deployed but unusable custody contract; added constructor regression coverage.

## 0.1.0-alpha.155 - 2026-08-26

- Hardened governance deployment checks so a non-contract timelock cannot produce an apparently
  deployed but unusable `HalalDAO`; added constructor regression coverage.

## 0.1.0-alpha.154 - 2026-08-26

- Hardened CPI adapter signer rotation so a pending ownership recipient cannot be added as a signer
  before accepting ownership, preserving custody separation and handoff liveness.

## 0.1.0-alpha.153 - 2026-08-26

- Added browser coverage for ordinary approval-based redeemable-credit transfers and irreversible
  claim retirement, including on-chain HLC balance, credit, and total-supply assertions.

## 0.1.0-alpha.152 - 2026-08-26

- Added browser regressions proving stale minimum-output quotes and expired withdrawal deadlines
  fail closed with reverted transactions and visible failure states.

## 0.1.0-alpha.151 - 2026-08-26

- Hardened the reusable CPI adapter governance handoff builder against zero addresses and the
  self-revoking adapter edge case, with regression coverage.

## 0.1.0-alpha.150 - 2026-08-26

- Added deterministic economic-model regression tests for exact CPI progression, reserve shortfall,
  top-up behavior, and rejected unsafe inputs.

## 0.1.0-alpha.149 - 2026-08-26

- Added pre-signing simulation for approval-based redeemable-credit transfers and claim retirement
  in the dApp; permit flows remain available for one-transaction actions.
- Hardened deployment integrity checks so incomplete CPI adapter metadata fails closed across the
  dApp, dashboard, and deployment-health page.
- Hardened `check-psm-health.sh` with strict RPC numeric validation, adapter metadata preflight,
  mandatory expected CPI source identity, and PSM/adapter bytecode checks with machine-readable
  failure reasons.
- Refreshed the contributor funnel with open, labelled issues #45, #47, and #48, and synchronized
  current documentation with the verified 174-test Solidity suite.

## 0.1.0-alpha.148 - 2026-08-26

- Regenerated the checked-in dApp ABIs for the constructor-level dependency validation errors added
  in alpha147.
- Restored generated-ABI verification consistency after the hosted CI gate identified the drift.

## 0.1.0-alpha.147 - 2026-08-26

- Hardened `HalalPSM` and `CPIReportAdapter` constructors against non-contract token and sink
  dependencies.
- Added regression coverage for the EOA sink edge, which could otherwise make an adapter advance
  its report watermark after a successful empty-data call without changing PSM state.

## 0.1.0-alpha.146 - 2026-08-26

- Added a copy-paste local CPI report walkthrough covering preparation, signer ordering, live
  adapter checks, verification, intentional failure, and safety boundaries.
- Linked the walkthrough from the CPI adapter specification and README.
- Completed issue #44 without exposing keys, RPC credentials, or real deployment values.

## 0.1.0-alpha.145 - 2026-08-26

- Added deterministic standalone PSM health-check tests for healthy output, stale CPI reports, and
  reserve deficits using a local fake-`cast` harness.
- Completed issue #43 without requiring an RPC endpoint, private key, funds, or contract changes.

## 0.1.0-alpha.144 - 2026-08-26

- Added `docs/DEPLOYMENT-REVIEW-CHECKLIST.md`, a copyable evidence worksheet for public testnet
  deployment review, reserve due diligence, CPI bootstrap, monitoring, and registry acceptance.
- Completed issue #42 and kept the remaining newcomer tasks (#43 and #44) visible in the contributor
  funnel.

## 0.1.0-alpha.143 - 2026-08-26

- Added two clearly scoped `good first issue` contributor paths for standalone health-check tests
  (#43) and a local CPI report walkthrough (#44).
- Linked all three newcomer tasks from the contributor map and README.

## 0.1.0-alpha.142 - 2026-08-26

- Added automated coverage for healthy disposable adapter output and machine-readable deployment-health
  failure reasons.
- Replaced the completed health-check starter task with active issue #42 for a deployment-review
  worksheet, keeping the contributor funnel current.

## 0.1.0-alpha.141 - 2026-08-26

- Removed stale links to completed contributor tasks from the README contribution funnel.
- Added active issue #41 with a bounded first contribution for deployment-health shell regression
  coverage.

## 0.1.0-alpha.140 - 2026-08-26

- Refreshed the README contributor funnel so it links only to active work instead of completed
  starter issues.
- Added issue #41 with a bounded, reproducible first contribution for deployment-health regression
  coverage.

## 0.1.0-alpha.139 - 2026-08-26

- Made combined deployment-health failures machine-readable with explicit reasons for missing
  configuration and failed wiring verification.
- Preserved the original verifier diagnostics while making cron, CI, and alert wrappers able to
  distinguish failure classes without parsing human-readable text.

## 0.1.0-alpha.138 - 2026-08-26

- Added reproducible local monitoring examples for the healthy adapter path and fail-closed missing
  configuration path.
- Documented the exact exit-code and output expectations for cron, systemd, CI, and metric wrappers.

## 0.1.0-alpha.137 - 2026-08-26

- Added browser coverage for a supported network with no configured deployment, asserting the
  operator-facing chain-specific recovery guidance.
- Made the disposable dApp suite cover six deterministic health, governance, and transaction paths.

## 0.1.0-alpha.136 - 2026-08-26

- Added browser coverage for malformed governance ETH values, asserting the user-facing validation
  error and that no wallet transaction is requested.
- Expanded the disposable dApp end-to-end suite to five deterministic scenarios.

## 0.1.0-alpha.135 - 2026-08-26

- Added a worked deployment-configuration regression example with expected failure behavior and a
  focused Foundry command for contributors.
- Clarified the boundary between pure deployment guards, local-demo defaults, and production safety.

## 0.1.0-alpha.134 - 2026-08-26

- Added a five-minute contributor map to the architecture guide, linking the deposit, CPI,
  redemption, governance, and operations paths to their implementation entry points.
- Made the first-contribution workflow explicit for new reviewers and issue participants.

## 0.1.0-alpha.133 - 2026-08-26

- Required every public deployment-registry entry to include an HTTPS deployment journal, matching
  the documented evidence policy.
- Added regression coverage for missing journal evidence and updated the recording workflow.

## 0.1.0-alpha.132 - 2026-08-26

- Made deployment-registry validation reject chain IDs that the frontend does not support, preventing
  apparently valid entries from being silently ignored by the dApp.
- Added regression coverage and documented the supported-network boundary.

## 0.1.0-alpha.131 - 2026-08-26

- Exposed deployment-registry evidence in the dApp dashboard, including deployment transaction,
  source-verification, and journal links when published.
- Replaced stale coding-agent guidance with an accurate map of the current contracts, tooling,
  safety boundaries, and contributor workflow.

## 0.1.0-alpha.130 - 2026-08-26

- Added a regression test proving that stale CPI data blocks new deposits while preserving an
  existing holder's withdrawal path during an oracle outage.
- Documented the one-sided freshness invariant and synchronized contributor-facing test counts with
  the 172-test suite.

## 0.1.0-alpha.129 - 2026-08-26

- Added fail-closed health alerts for duplicate CPI adapter signers and signer-owner overlap,
  including on legacy deployments.
- Documented the new monitoring signals and operator responses.

## 0.1.0-alpha.128 - 2026-08-26

- Extended the read-only PSM health check to flag duplicate CPI adapter signers and signer-owner
  overlap, including for legacy deployments predating the on-chain custody guard.
- Documented the new fail-closed monitoring reasons.

## 0.1.0-alpha.127 - 2026-08-26

- Added an exact-input SHA-256 hash to BLS-generated CPI report source metadata, making normalized
  reports unambiguously match their archived source response.
- Added parser validation coverage and operator guidance for retaining the provenance hash.

## 0.1.0-alpha.126 - 2026-08-26

- Enforced independent CPI adapter ownership and signer custody across construction, signer
  rotation, and two-step ownership transfers.
- Added custody-boundary regression coverage and synchronized published documentation with 171
  Foundry tests.

## 0.1.0-alpha.125 - 2026-08-26

- Rejected zero-valued CPI publication timestamps in the PSM, keeping direct updater bootstrap
  behavior consistent with the signed adapter and freshness watermark.
- Added a regression test and synchronized published documentation with 168 Foundry tests.

## 0.1.0-alpha.124 - 2026-08-26

- Hardened the CPI adapter deployment preflight so it rejects a zero private key and PSM addresses
  without contract bytecode before broadcasting.
- Added deployment-config regression coverage and synchronized contributor-facing documentation with
  167 Foundry tests.

## 0.1.0-alpha.114 - 2026-08-25

- Made the production deployment script reject shared team/treasury beneficiary addresses, keeping
  the two vesting allocations under distinct custody boundaries.
- Added deployment-config regression coverage and synchronized docs with 163 Foundry tests.

## 0.1.0-alpha.113 - 2026-08-25

- Regenerated the checked-in CPI adapter frontend ABI after the signer-set liveness hardening,
  restoring the hosted ABI-sync CI gate.

## 0.1.0-alpha.112 - 2026-08-25

- Bounded CPI adapter signer-set growth at 64 members to keep ECDSA verification work and report
  liveness within a practical gas envelope.
- Added constructor and rotation regression coverage and documented the governance trade-off.
- Synchronized published documentation with the 162-test Foundry suite.

## 0.1.0-alpha.111 - 2026-08-25

- Added wallet-free browser coverage proving `/health` blocks when a direct PSM report advances
  without advancing the configured CPI adapter watermark.

## 0.1.0-alpha.110 - 2026-08-25

- Added a no-return ERC20 reserve fixture proving `SafeERC20` compatibility through a complete
  PSM deposit/withdraw round trip, and documented the reserve-token transfer-return policy.
- Synchronized published documentation with the 161-test Foundry suite.

## 0.1.0-alpha.109 - 2026-08-25

- Hardened BLS CPI response parsing with explicit rejection of ambiguous series/data-point
  cardinality, non-object records, malformed years, and invalid index values.

## 0.1.0-alpha.108 - 2026-08-25

- Replaced the closed contributor quickstart link with three live, tagged good-first issues covering
  adapter health failures, BLS parser validation, and reserve-token edge cases.

## 0.1.0-alpha.107 - 2026-08-25

- Extended the disposable app/browser smoke fixture with a configured signed CPI adapter and
  health-page assertions for quorum and matching report watermarks.

## 0.1.0-alpha.106 - 2026-08-25

- Refreshed the contributor quickstart with a live good-first issue for configured CPI adapter
  health-page coverage.

## 0.1.0-alpha.105 - 2026-08-25

- Added an adapter-to-PSM integration regression proving out-of-range signed CPI reports revert
  without advancing either report watermark.

## 0.1.0-alpha.104 - 2026-08-25

- Added a dependency-free Prometheus textfile-style exporter example for read-only PSM health
  output, preserving unhealthy exit codes and exposing adapter watermark drift.

## 0.1.0-alpha.103 - 2026-08-25

- Added an accessible overall health status region and browser assertions for the health-page
  heading, status, read-only checks, and dashboard navigation.

## 0.1.0-alpha.102 - 2026-08-25

- Refreshed the contributor quickstart with two live, bounded `good first issue` tasks for frontend
  accessibility testing and machine-readable operator monitoring examples.

## 0.1.0-alpha.101 - 2026-08-25

- Synchronized project documentation with the verified 159-test Foundry suite, including the new
  redemption-boundary regression.

## 0.1.0-alpha.100 - 2026-08-25

- Extended the read-only CPI health check to compare the adapter and PSM report watermarks, making
  unintended updater paths and incomplete adapter handoffs visible to operators.

## 0.1.0-alpha.99 - 2026-08-25

- Added a security regression test proving that transferred PSM credit cannot unlock a recipient's
  separate, unbacked genesis HLC balance.

## 0.1.0-alpha.98 - 2026-08-25

- Added browser coverage proving the wallet-free deployment health page renders its read-only
  checks on the disposable local deployment.

## 0.1.0-alpha.97 - 2026-08-25

- Added a reserve-token compatibility matrix that separates tested transfer and decimal behavior
  from operator due diligence for hostile, frozen, or issuer-controlled tokens.

## 0.1.0-alpha.96 - 2026-08-25

- Added a dependency-free cron/systemd health-wrapper example that preserves read-only checks,
  nonzero failure status, and explicit unhealthy reasons.

## 0.1.0-alpha.95 - 2026-08-25

- Clarified that CPI freshness is an on-chain deposit gate while reserve-deficit blocking remains a
  conservative frontend operating policy; deposits remain self-funding during recovery.

## 0.1.0-alpha.94 - 2026-08-25

- Added a contributor quickstart linking the local demo, verification command, good-first issues,
  Discussions, and private security reporting.

## 0.1.0-alpha.93 - 2026-08-25

- Hardened the private-key-free CPI report verifier to reject invalid adapter quorums, duplicate
  signer enumeration, and signer-count mismatches before signature recovery.

## 0.1.0-alpha.92 - 2026-08-25

- Added a deployment-proposal issue form that requires chain, reserve, role, CPI, verification, and
  post-bootstrap health evidence before a public deployment enters the registry.

## 0.1.0-alpha.91 - 2026-08-25

- Added a CPI adapter submission sequence and evidence map so reviewers can trace source, signer,
  relayer, adapter, and PSM boundaries with reproducible commands.

## 0.1.0-alpha.90 - 2026-08-25

- Hardened the shared deployment-integrity check to verify that the configured CPI adapter's
  enumerated signer set matches its reported signer count.

## 0.1.0-alpha.89 - 2026-08-25

- Added a wallet-free `/health` operator view that checks deployment wiring, CPI freshness, reserve
  coverage, and signed-adapter alignment before protocol transactions are signed.

## 0.1.0-alpha.88 - 2026-08-25

- Added a 400,000-gas ceiling to frontend EIP-2612 PSM actions so RPC estimators cannot underfund
  the combined permit and accounting transaction.

## 0.1.0-alpha.87 - 2026-08-25

- Fixed the disposable browser wallet shim's gas ceiling so the E2E permit withdrawal covers the
  complete permit, transfer, and burn transaction.

## 0.1.0-alpha.86 - 2026-08-25

- Made the browser permit test wait for the asynchronous wallet transaction hash before checking
  the Anvil receipt in slower CI runners.

## 0.1.0-alpha.85 - 2026-08-25

- Fixed disposable app smoke cleanup so its background Next.js process cannot block the browser
  E2E server on port 3001.

## 0.1.0-alpha.84 - 2026-08-25

- Fixed client-side loading of per-chain `NEXT_PUBLIC_HLC_*` deployment overrides in Next.js.
- Added a disposable-Anvil Playwright test for the browser HLC permit withdrawal flow and wired it
  into `make verify` and frontend CI.

## 0.1.0-alpha.83 - 2026-08-25

- Added a safe default `make` help target that lists the verification, demo, and development
  commands for new contributors.

## 0.1.0-alpha.82 - 2026-08-25

- Added `cancelRedeemableWithPermit` so claim retirement can combine HLC approval and the
  accounting-aware burn in one transaction.
- Exposed the permit retirement path in the dApp, with selector detection for older immutable PSM
  deployments, and updated the generated ABI and protocol docs.

## 0.1.0-alpha.81 - 2026-08-25

- Enabled protected-main contribution rules requiring pull requests, code-owner review, linear
  history, and conversation resolution; documented the workflow for contributors.

## 0.1.0-alpha.80 - 2026-08-25

- Extended the disposable dApp smoke test to assert the runtime browser security headers, preventing
  regressions from being hidden by a successful build alone.

## 0.1.0-alpha.79 - 2026-08-25

- Corrected the contributor guide's Foundry test-suite count to match the current 157-test suite.
- Added baseline browser security headers to the Next.js dApp (frame, MIME-sniffing, referrer, and
  device-permission restrictions).

## 0.1.0-alpha.78 - 2026-08-25

- Added the HLC permit path to the dApp withdrawal form, with runtime selector detection for older
  immutable PSM deployments and an approval fallback.
- Added typed-data signing and signature encoding to the withdrawal smoke-tested frontend build.

## 0.1.0-alpha.77 - 2026-08-25

- Added the HLC permit transfer path to the dApp's redeemable-credit form, with a standard approval
  fallback for wallets that cannot sign typed data.
- Added frontend build coverage for the typed-data signing and signature encoding flow.

## 0.1.0-alpha.76 - 2026-08-25

- Fixed the release checksum file so downloaded assets verify from the same directory.

## 0.1.0-alpha.75 - 2026-08-25

- Pinned the Slither wheel by its SHA-256 hash instead of installing a mutable package reference.
- Added a release workflow that creates a reproducible source bundle, checksum, and GitHub build
  provenance attestation for each published release.

## 0.1.0-alpha.74 - 2026-08-25

- Added EIP-2612 permit entrypoints for bounded PSM deposits, withdrawals, and redeemable-credit
  transfers, while retaining approval-based paths for tokens and wallets without permit support.
- Added Foundry coverage for signed reserve and HLC approvals and regenerated the frontend PSM ABI.

## 0.1.0-alpha.73 - 2026-08-25

- Corrected the Scorecard SARIF uploader pin to the immutable commit behind the CodeQL release tag.

## 0.1.0-alpha.72 - 2026-08-25

- Corrected the Scorecard action pin to the immutable commit behind its annotated release tag.

## 0.1.0-alpha.71 - 2026-08-25

- Pinned every third-party GitHub Action to an immutable commit so workflow changes cannot silently
  follow a mutable tag.
- Added a scheduled OpenSSF Scorecard workflow with SARIF upload and a public security badge.

## 0.1.0-alpha.70 - 2026-08-25

- Added a disposable Anvil-backed production dApp smoke test that writes a temporary deployment
  environment, builds the configured app, checks all primary routes, and restores the developer's
  environment on exit.
- CI now runs that configured smoke test for app, script, and Makefile changes.

## 0.1.0-alpha.69 - 2026-08-25

- Added a read-only CPI update history card to the dashboard, sourced from the PSM event log with
  block numbers, transaction hashes, update type, and recent rate changes.

## 0.1.0-alpha.68 - 2026-08-25

- Extended the private-key-free CPI report verifier with live adapter and PSM watermark checks,
  freshness preflight, and RPC-time validation.
- Fixed the local adapter rehearsal to derive report timestamps from the Anvil chain instead of the
  host clock.

## 0.1.0-alpha.67 - 2026-08-25

- Added CPI adapter authorization tests for duplicate signatures, chain separation, signer removal,
  and stale-report rejection at the PSM boundary.
- The dApp now compares the adapter's report watermark with the PSM's accepted-report watermark and
  marks a deployment for review when they diverge.

## 0.1.0-alpha.66 - 2026-08-25

- Added a read-only CPI adapter card to the dashboard and PSM page, exposing live owner, source ID,
  quorum, signer addresses, and last-report state for reviewer visibility.

## 0.1.0-alpha.65 - 2026-08-25

- Added a private-key-free EIP-712 CPI report verifier that checks signer ordering and recovers
  each signature through Foundry before a quorum report is submitted.

## 0.1.0-alpha.64 - 2026-08-25

- Added enumerable CPI adapter signer views and rotation-safe bookkeeping, plus health-check output
  for each active signer so deployment journals can verify custody changes.

## 0.1.0-alpha.63 - 2026-08-25

- Promoted the signed CPI adapter rehearsal into `make verify` and the hosted contract workflow,
  so every release candidate exercises the two-of-two report path on disposable Anvil state.

## 0.1.0-alpha.62 - 2026-08-25

- Added a 31337-only adapter rehearsal that deploys a disposable PSM, signs a two-of-two report,
  and verifies the report reaches the PSM without using a public RPC.

## 0.1.0-alpha.61 - 2026-08-25

- Added optional adapter metadata to deployment manifests and the dApp integrity gate, which now
  verifies the adapter's PSM, timelock owner, source ID, and signer quorum before signing.
- Added registry-validator tests for valid adapter metadata and zero source IDs.
- Extended the read-only adapter health check to verify the expected timelock owner and emit
  explicit owner-missing and owner-mismatch reasons.

## 0.1.0-alpha.59 - 2026-08-25

- Added a generated `CPIReportAdapter` ABI so the dApp can decode adapter governance actions
  instead of displaying their raw calldata.

## 0.1.0-alpha.58 - 2026-08-25

- Added a non-broadcasting CPI adapter handoff generator that checks the adapter's PSM, timelock
  owner, and source ID before printing grant, source, and optional old-updater revocation actions.
- Added a decodeability test for the handoff action builder and refreshed public test-count references
  to the current 149-test Solidity suite.

## Unreleased
- Made the PSM reject deposits when no CPI report exists or the accepted report is older than
  `MAX_REPORT_AGE`, so the safety gate applies to direct contract callers as well as the dApp.
- Made public deployment manifests carry a deployment transaction and HTTPS explorer/source links.
- Opened a bounded public security-review challenge for the PSM, CPI boundaries, and reserve accounting.
- Added a one-command read-only deployment audit that checks wiring before recurring PSM health.
- Added a verifier-backed deployment manifest recorder and strict string handling for deployment block heights.
- Added a checked-in deployment registry with strict validation and per-field environment overrides,
  so public dApp addresses can ship with chain, release, commit, and deployment-block evidence.
- Allowed the first fresh CPI report immediately after deployment while retaining the step,
  timestamp, freshness, and reserve-adequacy checks; later reports still observe the configured
  cadence. The local demo and CI smoke test no longer fake a 25-day wait.
- Forced test recompilation in the primary Make and CI verification paths so stale Foundry
  artifacts cannot produce a false-green run with no discovered tests.
- Made the dApp reject zero deployment blocks, preventing an incomplete registry entry from
  triggering an unbounded governance history scan.
- Added vesting regression coverage for partial-release revocation and full-vesting revocation,
  confirming that the DAO receives only unvested tokens and released balances remain accounted for.
- Added wallet-free read-only dApp onboarding: the first configured deployment (or
  `NEXT_PUBLIC_READ_CHAIN_ID`) is browsable before a wallet connects, while signing remains gated
  by wallet connection and deployment integrity.
- Added a contributor map with bounded paths for security, reserve tokens, oracle integrations,
  monitoring, economics, governance, dApp UX, and documentation; refreshed contribution and
  citation metadata for the alpha.38 release.
- Added a dependency-free CPI and reserve-adequacy scenario model with CSV output and optional
  modeled top-ups (`make economic-model`).
- Added a CI smoke test that confirms the model reports a deficit without top-ups and full reserve
  coverage when modeled top-ups are enabled.
- Added an adversarial reserve-token test for ERC20 calls that return `false`, confirming the PSM
  fails closed through `SafeERC20`; the documented suite now has 133 tests.
- Added the differential arithmetic suite to the scheduled deep workflow at 10,000 fuzz runs per
  conversion direction.
- Corrected the differential arithmetic fuzz bounds so cases whose mathematically correct output
  exceeds `uint256` are excluded without reducing coverage of representable boundary values.
- Added independent differential PSM arithmetic fuzzing across every supported reserve-decimal
  count, CPI bound, and representable large input.
- Published `docs/OPERATOR-RUNBOOK.md` with launch acceptance, recurring monitoring, updater
  rotation, governance review, and incident-response procedures.
- Updated the local demo and CI smoke test to bootstrap a disposable CPI updater and seed a fresh
  timestamped report, so the demo exercises the usable dApp path after the safety gate.
- Added a read-only `check-psm-health.sh` operator check with key/value metrics and fail-closed
  exits for reserve deficits, missing/stale CPI reports, and overdue updater cadence.
- Added `CPI_UPDATER` support to the local deployment helper so operator checks can exercise a
  real timestamped updater report on Anvil.
- Added dApp-level PSM safety gates: new deposits pause when the CPI report is missing/stale or the
  reserve is under-collateralized, while users retain a visible recovery path for withdrawals.
- Restricted HLC burning to the PSM's accounting-aware `BURNER_ROLE`, preventing direct token burns
  from stranding PSM redemption credit; deployment verification and tests now assert the new role.
- Added a risk-ordered public roadmap covering audit readiness, testnet operations, monitoring, and
  the unresolved redemption-credit and economic-model questions.
- Made vesting beneficiary and deployer-role assertions mandatory in the post-deployment verifier,
  so a successful audit cannot omit deployment identity checks.
- Extended the local demo and CI deployment smoke test to assert both vesting beneficiaries, and
  included chain/block identity in local deployment output for repeatable handoffs.
- Added optional beneficiary checks to the deployment verifier, deployment-time beneficiary
  assertions, and chain/block identity output for repeatable operator audits.
- Hardened deployment assertions and repeat verification to enforce the intended team and treasury
  vesting cliffs, durations, and revocability policies.
- Made the deployment verifier safe to rerun after vesting releases by checking immutable vesting
  allocations instead of requiring the contracts' live token balances to remain untouched.
- Extended the stateful PSM invariant harness to exercise mixed user actions across governance CPI
  changes and reserve top-ups, not only at the genesis rate.
- Added deadline-bounded PSM deposit and withdrawal entrypoints so new integrations can combine
  slippage protection with an explicit maximum execution time; the existing entrypoints remain for
  compatibility with already-deployed immutable PSMs.
- Updated the dApp to detect deadline-capable PSM bytecode and use a 15-minute execution deadline
  automatically, while retaining the bounded compatibility path for older immutable deployments.
- Added a concise protocol rationale and evidence-at-a-glance section to the landing README for
  reviewers, contributors, and potential integrators.
- Made the production deployment script require `EXPECTED_CHAIN_ID` and fail closed before
  broadcasting if the selected RPC is on another network.
- Added wallet-side PSM transaction preflight simulation so stale quotes, allowance changes, and
  reserve shortfalls are shown before a user signs a bounded deposit or withdrawal.
- Extended deployment verification to require the timelock's self-admin role, which is necessary
  for queued governance operations to manage protocol roles.
- Made the dApp's deployment-integrity gate fail closed unless the live token, PSM, and timelock
  critical roles match the production wiring; the CLI verifier now also checks the open executor
  role.
- Made DAO reserve-withdrawal events report the recipient's actual fee-adjusted receipt and reject
  zero-value withdrawals.
- Added reentrancy protection to DAO reserve deposits and withdrawals, with callback-based regression
  coverage for malicious reserve-token behavior.
- Made deployment verification fail closed when the RPC chain ID does not match the operator's
  declared target network, and wired the check into the local demo and CI smoke test.
- Exposed CPI source-report timestamps and the on-chain freshness bound in the dApp, while keeping
  the new metadata reads optional for older immutable deployments.
- Fixed first-report bootstrap so a fresh timestamped CPI report published immediately before
  deployment is accepted.
- Added timestamped CPI reports with monotonic replay protection and a 90-day freshness bound;
  governance overrides now advance the report watermark.
- Fixed the PSM swap form to parse withdrawals in HLC's fixed 18-decimal units while preserving
  the reserve token's native decimals for deposit and output formatting.
- Added a visible dashboard warning when the on-chain CPI updater cadence is overdue.
- Kept vesting and reserve progress indicators precise for arbitrarily large on-chain amounts by
  using bounded bigint ratios instead of JavaScript `Number` conversion.
- Made the local demo build its contracts before deployment and restore any pre-existing
  `app/.env.local` when it exits.
- Strengthened the read-only deployment verifier to reject EOAs/wrong-chain addresses and verify
  the DAO's token/timelock links plus a nonzero timelock delay.
- Made incomplete PSM wallet and reserve reads produce an explicit waiting state instead of a
  silently disabled deposit/withdraw button.
- Added a client-side on-chain deployment-integrity check and blocked governance, PSM, and vesting
  signing actions until the configured contract graph is verified.
- Added live governance timelock ETA handling so queued proposals cannot present an executable
  action before the delay has elapsed.
- Hardened the PSM against quote drift, unsupported decimals, fee-on-transfer reserves, reserve
  shortfalls, outgoing-transfer floor breaches, zero-receipt top-ups, zero-output withdrawals, and
  unauthorized redemption.
- Prevented governance from disabling the updater cadence with a zero interval.
- Added atomic `transferRedeemable` support for transferring PSM-issued HLC together with its
  redemption credit.
- Added `cancelRedeemable` so users can retire a PSM claim while keeping supply and reserve
  accounting accurate.
- Switched PSM decimal conversions to full-precision arithmetic and added regression coverage for
  large values that previously could overflow an intermediate calculation.
- Added constructor and deployment-wiring validation across the token, vesting, DAO, timelock, and
  deployment script.
- Added 111 unit tests plus 3 stateful PSM invariants, reproducible ABI generation, and CI checks for
  formatting, linting, builds, dependency advisories, and generated-interface drift.
- Improved the Next.js dashboard with validated deployment configuration, bounded swap actions,
  explicit slippage controls, governance proposal validation, and safer incomplete-read handling.
- Added an atomic redemption-credit transfer form to the PSM page and made governance history
  reads fail visibly instead of silently omitting unreadable log ranges.
- Added visible, transaction-blocking errors for partial wallet reads and a safe UI action for
  retiring redemption claims without reserve.
- Added a source-sensitive Foundry CI cache key, a stateful cancellation invariant, patched all
  reachable `uuid` versions, CodeQL/dependency-review workflows, and a zero-finding Slither pass
  for the first-party contracts. Added scheduled deep testing with 10,000 fuzz runs and 128
  invariant sequences at depth 64.
- Added a local Anvil deployment script that reuses production role wiring and prints a ready-to-paste
  frontend environment configuration with a clearly labeled faucet reserve.
- Added a one-command local demo wrapper that starts Anvil, writes the frontend environment, and
  launches the dApp while refusing to use an already-running RPC process.
- Added production route smoke tests, Dependabot update groups, and issue routing that directs
  security reports to private advisories.
- Added permissionless vesting release triggering and the two-step beneficiary rotation flow to
  the frontend.
- Added contributor templates, proposal examples, operational documentation, and a root `make verify`
  workflow.

The project remains unaudited and is not production-ready. See [`SECURITY.md`](SECURITY.md).
## [0.1.0-alpha.115] - 2026-08-25

- Made the production deployment script reject team or treasury beneficiaries equal to the
  temporary deployer, reducing accidental custody centralization during deployment.
- Added deployment-config regression coverage and clarified the local-demo exception.

## [0.1.0-alpha.116] - 2026-08-25

- Made the read-only deployment verifier reject deployer-controlled vesting beneficiaries by
  default, while documenting the explicit disposable-local-demo exception.
- Refreshed the README contributor links and corrected the contracts test-suite count.
## [0.1.0-alpha.117] - 2026-08-25

- Added a canonical clean-checkout local development walkthrough covering the disposable Anvil
  smoke test, interactive demo, verification commands, and production custody boundary.
- Linked the walkthrough from the README and contributor guide.
## [0.1.0-alpha.118] - 2026-08-25

- Added browser coverage proving the governance proposal form blocks malformed advanced actions
  before any wallet transaction is submitted.
- Expanded the end-to-end suite to four deterministic disposable-Anvil tests.
## [0.1.0-alpha.119] - 2026-08-25

- Added a contributor guide for extending deployment-configuration regression tests, including the
  production/local-demo boundary, focused commands, and documentation-count checklist.
- Linked the guide from the contributor map and contribution instructions.
## [0.1.0-alpha.120] - 2026-08-25

- Made `HalalToken.initialMint` reject identical team and treasury vesting recipients as a
  defense-in-depth custody boundary.
- Added a focused regression and synchronized the current Foundry test counts.
## [0.1.0-alpha.121] - 2026-08-25

- Synchronized the generated frontend HalalToken ABI with the alpha120 genesis-recipient guard,
  restoring the generated-ABI CI gate.
## [0.1.0-alpha.122] - 2026-08-26

- Made the CPI adapter deployment script reject duplicate or deployer-controlled signer addresses
  before broadcasting.
- Added focused deployment-config coverage for the adapter signer boundary.
