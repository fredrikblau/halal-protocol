# Documentation index

This folder holds the protocol's design, security, operational, and contributor documentation.
It is grouped by what you are trying to do rather than alphabetically, because the alphabetical
listing GitHub shows above is not a useful reading order.

The protocol is unaudited, has no public deployment, and no bug bounty. Nothing in this folder
changes that; see [`../SECURITY.md`](../SECURITY.md) and the root
[README](../README.md#status--risk).

## Understand the protocol

| Document | What it answers |
|---|---|
| [`WHITEPAPER.md`](WHITEPAPER.md) | Why a CPI-indexed token, how settlement arithmetic works, the security model, prior art, and honest limitations. **Start here.** |
| [`Architecture.md`](Architecture.md) | System diagrams, contract call flow, and test-coverage summary. |
| [`TECHNICAL-DOCS.md`](TECHNICAL-DOCS.md) | The fullest reference: API surface, deployment steps, parameters. |
| [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md) | Why the code differs from the obvious design, including the redemption-credit trade-off. |
| [`GLOSSARY.md`](GLOSSARY.md) | Concise definitions with links to the implementation. |
| [`ECONOMIC-MODEL.md`](ECONOMIC-MODEL.md) | Deterministic reserve-adequacy scenarios under different CPI paths. |

## Run it locally

| Document | What it answers |
|---|---|
| [`LOCAL-DEVELOPMENT.md`](LOCAL-DEVELOPMENT.md) | Clean checkout to a running local system. |
| [`LOCAL-DEMO-TROUBLESHOOTING.md`](LOCAL-DEMO-TROUBLESHOOTING.md) | Ports, prerequisites, and stale local configuration. |
| [`LOCAL-CPI-REPORT-WALKTHROUGH.md`](LOCAL-CPI-REPORT-WALKTHROUGH.md) | Producing and submitting a signed CPI report against disposable state. |
| [`LOCAL-DEPLOYMENT-EVIDENCE.md`](LOCAL-DEPLOYMENT-EVIDENCE.md) | What a local run should produce, and what it does not prove. |

## Contribute

| Document | What it answers |
|---|---|
| [`NEXT-STEPS.md`](NEXT-STEPS.md) | What is blocked, what is worth doing next, and which CI failures are not your fault. |
| [`CONTRIBUTOR-QUICKSTART.md`](CONTRIBUTOR-QUICKSTART.md) | Ten minutes from clone to a verified checkout. |
| [`CONTRIBUTOR-MAP.md`](CONTRIBUTOR-MAP.md) | Bounded tasks matched to interests, with the design note to read first. |
| [`AddingFeature.md`](AddingFeature.md) | Adding capability as a new module rather than patching immutable contracts. |
| [`ROADMAP.md`](ROADMAP.md) | The risk-ordered arc toward testnet and production readiness. |

## Security and assurance

| Document | What it answers |
|---|---|
| [`THREAT-MODEL.md`](THREAT-MODEL.md) | Attacker capabilities, trust boundaries, and what is explicitly out of scope. |
| [`INVARIANTS.md`](INVARIANTS.md) | The properties the test suite tries to break. |
| [`SECURITY-REVIEW-QUICKSTART.md`](SECURITY-REVIEW-QUICKSTART.md) | How to start reviewing without a wallet, funds, or credentials. |
| [`SECURITY-REVIEW-LOG.md`](SECURITY-REVIEW-LOG.md) | Review history and what each pass covered. |
| [`STATIC-ANALYSIS.md`](STATIC-ANALYSIS.md) | Pinned Slither scope, command, and how to read its output. |

Report anything fund-risking privately through [`../SECURITY.md`](../SECURITY.md) — never in a
public issue or pull request.

## CPI data and the oracle boundary

| Document | What it answers |
|---|---|
| [`CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md) | Source provenance, signer custody, quorum, and the adapter handoff. |
| [`CPI-SOURCE-POLICY-TEMPLATE.md`](CPI-SOURCE-POLICY-TEMPLATE.md) | Provider-neutral template for recording a source policy. |
| [`CPI-SOURCE-POLICY-BLS-DRAFT.md`](CPI-SOURCE-POLICY-BLS-DRAFT.md) | A worked draft for the BLS CPI-U series. Draft, not an approval. |
| [`CPI-POLICY-RECORD.md`](CPI-POLICY-RECORD.md) | The machine-readable companion record and its offline validator. |

## Choosing a reserve asset

| Document | What it answers |
|---|---|
| [`RESERVE-TOKEN-DECISION-TREE.md`](RESERVE-TOKEN-DECISION-TREE.md) | Which questions disqualify a candidate outright. |
| [`RESERVE-ASSET-DUE-DILIGENCE.md`](RESERVE-ASSET-DUE-DILIGENCE.md) | The evidence a candidate must produce. |
| [`RESERVE-ASSET-DUE-DILIGENCE-EXAMPLE.md`](RESERVE-ASSET-DUE-DILIGENCE-EXAMPLE.md) | A completed example of that record. |

## Governance and treasury

| Document | What it answers |
|---|---|
| [`DAO-Guide.md`](DAO-Guide.md) | Proposal lifecycle end to end, with commands. |
| [`Treasury.md`](Treasury.md) | How vesting and treasury flows work in practice. |
| [`GOVERNANCE-PROPOSAL-REVIEW-EXAMPLE.md`](GOVERNANCE-PROPOSAL-REVIEW-EXAMPLE.md) | A worked review of a real proposal shape. |
| [`GOVERNANCE-REVIEW-EVIDENCE-TEMPLATE.md`](GOVERNANCE-REVIEW-EVIDENCE-TEMPLATE.md) | The evidence a reviewer should record before voting. |

## Deploy and operate

| Document | What it answers |
|---|---|
| [`DEPLOYMENT-REGISTRY.md`](DEPLOYMENT-REGISTRY.md) | The evidence required before an address is published to the dApp. |
| [`DEPLOYMENT-REVIEW-CHECKLIST.md`](DEPLOYMENT-REVIEW-CHECKLIST.md) | What a reviewer checks before a deployment is accepted. |
| [`DEPLOYMENT-CONFIG-TESTS.md`](DEPLOYMENT-CONFIG-TESTS.md) | The configuration gates enforced by tests. |
| [`DEPLOYMENT-JOURNAL-TEMPLATE.md`](DEPLOYMENT-JOURNAL-TEMPLATE.md) | The record a deployment must leave behind. |
| [`OPERATOR-RUNBOOK.md`](OPERATOR-RUNBOOK.md) | Recurring health checks and incident response. |
| [`MONITORING-JSON-EXAMPLE.md`](MONITORING-JSON-EXAMPLE.md) | The monitoring output shape and its diagnostics. |
| [`INCIDENT-TABLETOP-WORKSHEET.md`](INCIDENT-TABLETOP-WORKSHEET.md) | Rehearsing an incident before there is one. |
| [`INCIDENT-RESPONSE-TABLETOP-EXAMPLE.md`](INCIDENT-RESPONSE-TABLETOP-EXAMPLE.md) | A completed tabletop for reference. |
| [`RELEASE-VERIFICATION.md`](RELEASE-VERIFICATION.md) | Verifying a published release artifact. |
