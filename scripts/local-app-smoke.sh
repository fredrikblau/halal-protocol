#!/usr/bin/env bash
set -euo pipefail

# Builds confidence in the configured dApp path with disposable Anvil state. This script never
# connects to a public RPC and never uses a production key.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ANVIL_PORT="${ANVIL_PORT:-18545}"
APP_PORT="${APP_PORT:-3001}"
LOCAL_RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
LOCAL_MNEMONIC="${ANVIL_MNEMONIC:-test test test test test test test test test test test junk}"
DEPLOY_LOG="$(mktemp)"
HEADER_FILE="$(mktemp)"
ANVIL_PID=""
APP_PID=""
APP_ENV_FILE="$ROOT_DIR/app/.env.local"
APP_ENV_BACKUP=""
APP_ENV_CREATED="false"

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill -- -"$APP_PID" 2>/dev/null || kill "$APP_PID" 2>/dev/null || true
  fi
  if [[ -n "$ANVIL_PID" ]]; then kill "$ANVIL_PID" 2>/dev/null || true; fi
  if [[ -n "$APP_ENV_BACKUP" && -f "$APP_ENV_BACKUP" ]]; then
    mv -f "$APP_ENV_BACKUP" "$APP_ENV_FILE"
  elif [[ "$APP_ENV_CREATED" == "true" ]]; then
    rm -f "$APP_ENV_FILE"
  fi
  rm -f "$DEPLOY_LOG"
  rm -f "$HEADER_FILE"
}
trap cleanup EXIT INT TERM

for command_name in anvil forge cast pnpm curl; do
  command -v "$command_name" >/dev/null || { echo "$command_name is required" >&2; exit 1; }
done

if cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; then
  echo "Refusing to use an existing process on $LOCAL_RPC_URL; stop it before running the smoke test." >&2
  exit 1
fi

anvil --silent --mnemonic "$LOCAL_MNEMONIC" --port "$ANVIL_PORT" >/tmp/halal-app-smoke-anvil.log 2>&1 &
ANVIL_PID=$!
for attempt in {1..60}; do
  cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1 && break
  sleep 1
  if [[ "$attempt" == 60 ]]; then
    echo "Anvil did not start; see /tmp/halal-app-smoke-anvil.log" >&2
    exit 1
  fi
done

DEPLOYER_KEY="$(cast wallet derive --insecure "$LOCAL_MNEMONIC" | awk '/Private key:/ { print $3; exit }')"
UPDATER_KEY="$(cast wallet derive --insecure --accounts 2 "$LOCAL_MNEMONIC" | awk '/Private key:/ { key=$3 } END { print key }')"
UPDATER_ADDRESS="$(cast wallet address --private-key "$UPDATER_KEY")"
CPI_SOURCE="LOCAL:APP:CPI"
(
  cd "$ROOT_DIR/contracts"
  PRIVATE_KEY="$DEPLOYER_KEY" CPI_UPDATER="$UPDATER_ADDRESS" \
    forge script script/DeployLocal.s.sol:DeployLocalHalalSystem \
    --rpc-url "$LOCAL_RPC_URL" --broadcast --non-interactive --force
) 2>&1 | tee "$DEPLOY_LOG"

value_from_env() {
  awk -F= -v key="$1" '$1 ~ key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' "$DEPLOY_LOG"
}

PSM_ADDRESS="$(value_from_env NEXT_PUBLIC_HLC_PSM_31337)"
TIMELOCK_ADDRESS="$(value_from_env NEXT_PUBLIC_HLC_TIMELOCK_31337)"
SOURCE_ID="$(cast keccak 'local-app-cpi-v1')"
SIGNER_ONE_KEY="$(cast wallet derive --insecure --accounts 3 "$LOCAL_MNEMONIC" | awk '/Private key:/ { key=$3 } END { print key }')"
SIGNER_TWO_KEY="$(cast wallet derive --insecure --accounts 4 "$LOCAL_MNEMONIC" | awk '/Private key:/ { key=$3 } END { print key }')"
SIGNER_ONE_ADDRESS="$(cast wallet address --private-key "$SIGNER_ONE_KEY")"
SIGNER_TWO_ADDRESS="$(cast wallet address --private-key "$SIGNER_TWO_KEY")"

cast rpc anvil_impersonateAccount "$TIMELOCK_ADDRESS" --rpc-url "$LOCAL_RPC_URL" >/dev/null
cast rpc anvil_setBalance "$TIMELOCK_ADDRESS" 0x3635C9ADC5DEA00000 --rpc-url "$LOCAL_RPC_URL" >/dev/null
cast send "$PSM_ADDRESS" 'setSource(string)' "$CPI_SOURCE" --from "$TIMELOCK_ADDRESS" --unlocked --rpc-url "$LOCAL_RPC_URL" >/dev/null

(
  cd "$ROOT_DIR/contracts"
  PRIVATE_KEY="$DEPLOYER_KEY" EXPECTED_CHAIN_ID=31337 PSM="$PSM_ADDRESS" \
    ADAPTER_OWNER="$TIMELOCK_ADDRESS" CPI_SOURCE_ID="$SOURCE_ID" CPI_THRESHOLD=2 \
    CPI_SIGNER_1="$SIGNER_ONE_ADDRESS" CPI_SIGNER_2="$SIGNER_TWO_ADDRESS" \
    forge script script/DeployCPIReportAdapter.s.sol:DeployCPIReportAdapter \
    --rpc-url "$LOCAL_RPC_URL" --broadcast --non-interactive
) 2>&1 | tee -a "$DEPLOY_LOG"

ADAPTER_ADDRESS="$(awk '/CPI report adapter:/ { print $NF; exit }' "$DEPLOY_LOG")"
test -n "$ADAPTER_ADDRESS"

# The local app is configured to inspect the optional adapter, so the disposable deployment must
# model the production handoff: the adapter, rather than the bootstrap updater account, owns the
# PSM updater role. Use the local timelock impersonation already established above; this keeps the
# fixture faithful to governance-controlled role wiring without changing the production deploy script.
PSM_UPDATER_ROLE="$(cast call "$PSM_ADDRESS" 'UPDATER_ROLE()(bytes32)' --rpc-url "$LOCAL_RPC_URL")"
cast send "$PSM_ADDRESS" 'grantRole(bytes32,address)' "$PSM_UPDATER_ROLE" "$ADAPTER_ADDRESS" \
  --from "$TIMELOCK_ADDRESS" --unlocked --rpc-url "$LOCAL_RPC_URL" >/dev/null

if [[ -e "$APP_ENV_FILE" ]]; then
  APP_ENV_BACKUP="$(mktemp)"
  cp -p "$APP_ENV_FILE" "$APP_ENV_BACKUP"
else
  APP_ENV_CREATED="true"
fi

DEPLOYMENT_BLOCK="$(cast block latest --field number --rpc-url "$LOCAL_RPC_URL")"
{
  echo "NEXT_PUBLIC_RPC_URL_31337=$LOCAL_RPC_URL"
  grep 'NEXT_PUBLIC_HLC_' "$DEPLOY_LOG" \
    | sed -e 's/^ *//' -e 's/= /=/' \
    | sed "s/^NEXT_PUBLIC_HLC_DEPLOYMENT_BLOCK_31337=.*/NEXT_PUBLIC_HLC_DEPLOYMENT_BLOCK_31337=$DEPLOYMENT_BLOCK/"
  echo "NEXT_PUBLIC_HLC_CPI_ADAPTER_31337=$ADAPTER_ADDRESS"
  echo "NEXT_PUBLIC_HLC_CPI_SOURCE_31337=$CPI_SOURCE"
  echo "NEXT_PUBLIC_HLC_CPI_SOURCE_ID_31337=$SOURCE_ID"
  echo "NEXT_PUBLIC_HLC_CPI_POLICY_31337=https://example.invalid/local-cpi-policy"
} > "$APP_ENV_FILE"

(
  cd "$ROOT_DIR/app"
  pnpm build
)

if [[ "${KEEP_SERVER:-false}" == "true" ]]; then
  # Playwright owns the lifetime of this process. Keep the server in the foreground so its
  # termination reaches this shell's cleanup trap and removes the disposable Anvil state.
  cd "$ROOT_DIR/app"
  exec pnpm start --hostname 127.0.0.1 --port "$APP_PORT" >/tmp/halal-app-smoke-next.log 2>&1
  exit 0
fi

setsid pnpm --dir "$ROOT_DIR/app" start --hostname 127.0.0.1 --port "$APP_PORT" \
  >/tmp/halal-app-smoke-next.log 2>&1 &
APP_PID=$!

for attempt in {1..60}; do
  if curl --fail --silent "http://127.0.0.1:${APP_PORT}/" >/tmp/halal-app-smoke-dashboard.html; then
    break
  fi
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Next.js exited; see /tmp/halal-app-smoke-next.log" >&2
    exit 1
  fi
  sleep 1
  if [[ "$attempt" == 60 ]]; then
    echo "Next.js did not start; see /tmp/halal-app-smoke-next.log" >&2
    exit 1
  fi
done

curl --fail --silent --show-error -D "$HEADER_FILE" -o /dev/null "http://127.0.0.1:${APP_PORT}/"
grep -Eiq '^x-content-type-options:[[:space:]]*nosniff[[:space:]]*$' "$HEADER_FILE"
grep -Eiq '^x-frame-options:[[:space:]]*DENY[[:space:]]*$' "$HEADER_FILE"
grep -Eiq '^referrer-policy:[[:space:]]*strict-origin-when-cross-origin[[:space:]]*$' "$HEADER_FILE"
grep -Eiq '^permissions-policy:[[:space:]]*camera=\(\),[[:space:]]*geolocation=\(\),[[:space:]]*microphone=\(\)[[:space:]]*$' "$HEADER_FILE"
curl --fail --silent --show-error "http://127.0.0.1:${APP_PORT}/governance" >/dev/null
curl --fail --silent --show-error "http://127.0.0.1:${APP_PORT}/psm" >/dev/null
curl --fail --silent --show-error "http://127.0.0.1:${APP_PORT}/vesting" >/dev/null
curl --fail --silent --show-error "http://127.0.0.1:${APP_PORT}/health" >/dev/null
grep -q "CPI update history" /tmp/halal-app-smoke-dashboard.html
echo "Configured local dApp smoke test passed on chain 31337."
