# Protocol glossary

This page translates the terms used in the README, contracts, and contributor issues. The linked
source files are authoritative when this short glossary and a planning document differ.

## HLC

HLC is the protocol's ERC-20 governance and payment token, implemented by [`HalalToken`](../contracts/src/HalalToken.sol).
Its fixed genesis allocation is vested to the team and treasury; additional HLC is minted by the
PSM only when a reserve deposit creates a redeemable claim.

## PSM (Peg Stability Module)

The [`HalalPSM`](../contracts/src/HalalPSM.sol) exchanges reserve tokens for HLC and HLC for
reserve tokens at the current CPI-adjusted rate. It also owns the accounting that separates
redeemable PSM claims from ordinary HLC balances.

## CPI rate

The CPI rate is the integer-scaled price used to convert between HLC and the reserve token;
`CPI_PRECISION` is 1,000,000 in `HalalPSM`. Normal updater submissions are bounded by the
configured range, per-update step, cadence, timestamp freshness, and reserve-safety checks.

## Redeemable credit

`redeemableBalance` is the per-address amount of PSM-issued HLC that can be withdrawn for reserve
tokens. Transfers through `transferRedeemable` move this credit together with the HLC, while
ordinary ERC-20 transfers do not create or move a redemption claim.

## Reserve surplus and deficit

`reserveRequired()` is the reserve amount needed to honor outstanding redeemable credit at the
current CPI rate. [`reserveSurplus()`](../contracts/src/HalalPSM.sol) reports the reserve balance
minus that requirement: positive means surplus, and negative means deficit; the PSM blocks new
deposits and reserve withdrawals that would worsen an unsafe state.

## CPI adapter

[`CPIReportAdapter`](../contracts/src/CPIReportAdapter.sol) is an optional EIP-712 quorum module
that authenticates signed CPI payloads before forwarding them to the PSM. It proves signer
authorization and source-ID consistency, but it does not authenticate the underlying statistics;
source selection, custody, and deployment remain governance and operational responsibilities.

## CPI source and source ID

The PSM's `source` is a human-readable label for the selected CPI publication, while the adapter's
`sourceId` is the bytes32 value bound into each signed report. Operators should record both with
the policy evidence described in the [CPI adapter specification](CPI-ADAPTER-SPEC.md).

## Updater

An updater is an account or adapter holding `HalalPSM.UPDATER_ROLE`, which permits normal
timestamped CPI report submission. The role is separate from `PARAM_ROLE`, which is intended for
DAO-controlled configuration and emergency governance overrides.

## Timelock

[`HalalTimelock`](../contracts/src/HalalTimelock.sol) is the delayed execution controller for
governance actions. The DAO proposes and queues operations through it; the delay gives holders and
operators time to inspect a transaction before execution.

## Vesting

[`HalalVesting`](../contracts/src/HalalVesting.sol) linearly releases one funded allocation to one
beneficiary, optionally after a cliff. Team vesting is revocable by the DAO timelock; treasury
vesting is configured as non-revocable.
