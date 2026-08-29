.DEFAULT_GOAL := help

.PHONY: help verify contracts-build contracts-test contracts-lint contracts-coverage app-lint app-build app-smoke app-e2e abis psm-health deployment-health deployment-preflight economic-model oracle-test adapter-demo registry-check shell-check cpi-policy-check test-counts markdown-links

help:
	@printf '%s\n' 'Halal development commands:' '' '  make verify             Run the complete local verification suite' '  make contracts-test     Run the Foundry contract tests' '  make app-build          Build the Next.js dApp' '  make app-smoke          Deploy disposable Anvil state and smoke-test the dApp' '  make app-e2e            Exercise the browser permit flow on disposable Anvil state' '  make adapter-demo       Rehearse signed CPI reporting on disposable Anvil state' '  make deployment-preflight  Check registry readiness without RPC or credentials' '  make cpi-policy-check   Validate draft/reviewable CPI policy record fixtures offline' '  make test-counts        Verify current Foundry test counts match documentation' '  make markdown-links     Validate tracked Markdown links and anchors' '  make economic-model     Run the deterministic reserve-adequacy model' '' 'Read CONTRIBUTING.md before changing contracts/src/.'

verify: registry-check shell-check oracle-test markdown-links adapter-demo contracts-build contracts-test contracts-lint app-lint app-smoke app-e2e

registry-check:
	node scripts/validate-deployment-registry.mjs

shell-check:
	bash -n scripts/*.sh

oracle-test:
	node --test scripts/test/*.test.mjs

test-counts:
	node scripts/check-test-counts.mjs

cpi-policy-check:
	node scripts/validate-cpi-policy.mjs --input scripts/test/fixtures/cpi-policy-draft.json
	node scripts/validate-cpi-policy.mjs --input scripts/test/fixtures/cpi-policy-reviewed.json

markdown-links:
	node scripts/check-markdown-links.mjs

adapter-demo:
	./scripts/local-adapter-demo.sh

contracts-build:
	cd contracts && forge build

contracts-test:
	cd contracts && forge test --force

contracts-lint:
	cd contracts && forge fmt --check src test script && forge lint src test script --severity high --severity med --severity low --severity gas

contracts-coverage:
	cd contracts && forge coverage --report summary

app-lint:
	cd app && pnpm lint

app-build:
	cd app && pnpm build

app-smoke:
	./scripts/local-app-smoke.sh

app-e2e:
	cd app && pnpm test:e2e

abis:
	cd app && pnpm gen:abis

psm-health:
	./scripts/check-psm-health.sh

deployment-health:
	./scripts/check-deployment-health.sh

deployment-preflight:
	node scripts/preflight-deployment.mjs

economic-model:
	node scripts/model-psm.mjs
