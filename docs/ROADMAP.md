# Halal Roadmap

This roadmap describes the work required to move Halal from an unaudited reference implementation
to a protocol that can responsibly support a public testnet and, eventually, meaningful funds. It is
deliberately ordered by risk reduction rather than feature count. The current contracts are
immutable, so production changes should normally arrive as separately reviewed modules granted
narrow roles by governance.

For the shorter "what should I work on today" view, including current blockers and known CI
failure modes, see [`NEXT-STEPS.md`](NEXT-STEPS.md).

## Now: make the reference deployment audit-ready

- Complete an independent smart-contract security review and publish the findings and remediation
  commits.
- Deploy the unchanged reference system to Arbitrum Sepolia with multisig beneficiaries, a
  documented reserve token, and a separately reviewed CPI updater ([issue #40](https://github.com/fredrikblau/halal-protocol/issues/40)).
- Publish the deployment addresses, verified source links, deployment log, and the output of
  `scripts/verify-deployment.sh`.
- [x] Publish an operator runbook for reserve health, CPI freshness, updater rotation, governance
  proposal review, and incident response ([`docs/OPERATOR-RUNBOOK.md`](OPERATOR-RUNBOOK.md)).
- [x] Add independent differential arithmetic checks across every supported reserve-decimal count
  and CPI bound ([`contracts/test/HalalPSMArithmetic.t.sol`](../contracts/test/HalalPSMArithmetic.t.sol)).
- [x] Extend the adversarial reserve-token matrix. The stateful suite now models fee-on-transfer,
  false-returning, no-return, transfer-capped, and rebasing reserve tokens
  ([`contracts/test/HalalPSMAdversarialInvariant.t.sol`](../contracts/test/HalalPSMAdversarialInvariant.t.sol)).
- Run longer stateful invariant campaigns on every release candidate.
- [x] Enforce documented Foundry test counts against the live suite so contributor-facing evidence
  cannot drift (`make test-counts`).

## Next: make the system useful to real participants

- Add a production CPI adapter/consumer with an explicit data-source policy, heartbeat, fallback,
  and key-rotation procedure. Start from the [`CPI adapter specification`](CPI-ADAPTER-SPEC.md);
  the current contract accepts bounded reports but intentionally does not fetch CPI data itself.
- Add monitoring for reserve deficits, stale CPI reports, role changes, vesting releases, and
  governance proposals, with documented alert thresholds.
- Run a public testnet program that records deposits, withdrawals, CPI changes, governance actions,
  and any discovered issues in a reproducible deployment journal.
- [x] Improve the dApp's deployment registry so a new participant can verify the active deployment
  without copying undocumented addresses from a chat message ([registry format](DEPLOYMENT-REGISTRY.md));
  transaction-history improvements remain future work.

## Research: resolve the hard economic and UX questions

- Model reserve-adequacy requirements under different CPI paths, redemption timing, fees, and
  treasury funding policies; publish the assumptions and sensitivity analysis.
- Evaluate whether per-address redemption credit is the right long-term settlement model. Ordinary
  HLC transfers deliberately do not move PSM redemption credit today, which is safe against genesis
  allocation leakage but surprising for standard ERC20 users.
- [x] Publish a deterministic 18-decimal reserve-adequacy scenario model ([`docs/ECONOMIC-MODEL.md`](ECONOMIC-MODEL.md)).
- Evaluate isolated multi-reserve PSMs and a canonical cross-chain strategy only after the single-
  reserve deployment has meaningful testnet evidence.

## How to help now

- Run `./scripts/local-demo.sh` and report reproducible bugs with the commit, chain, and transaction
  details.
- Review the threat model, invariants, deployment verifier, and design decisions; documentation
  corrections are valuable contributions.
- Pick a focused issue or open a design discussion before changing `contracts/src/`.
- Fork the repository to experiment with oracle adapters, monitoring, economic simulations, or a
  separate extension module without modifying the immutable reference contracts.

The project is unaudited and has no production deployment or bug bounty at this time. A roadmap
item is not evidence that the underlying risk has been solved; the repository's tests, deployment
logs, and published security reports are the evidence to trust.
