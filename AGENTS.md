# Guidance for coding agents

This repository keeps its agent-facing instructions in [`CLAUDE.md`](CLAUDE.md). Read that file
first: it maps the tree, lists the verification commands, and records the safety boundaries that
apply to `contracts/src/`, deployment evidence, and secrets.

Then read [`docs/NEXT-STEPS.md`](docs/NEXT-STEPS.md) for what is currently blocked, what is worth
picking up, and which CI failures are known not to be caused by the change under test.

Two boundaries worth repeating here, because getting them wrong is costly:

- The protocol is unaudited and has no public deployment. Do not describe it as audited,
  production-ready, or safe for meaningful funds in code, documentation, issues, or release notes.
- Never commit private keys, seed phrases, RPC credentials, or real deployment secrets. The local
  demo's Anvil mnemonic is public and disposable, and must never be used against a public RPC.
