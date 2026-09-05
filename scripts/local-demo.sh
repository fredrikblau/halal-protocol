#!/usr/bin/env bash
set -euo pipefail

# This wrapper is intentionally local-only. The default mnemonic is a published Anvil demo
# mnemonic and must never be used with a public RPC. Set ANVIL_MNEMONIC to use another local seed.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ANVIL_PORT="${ANVIL_PORT:-8545}"
APP_PORT="${APP_PORT:-3000}"
LOCAL_RPC_URL="http://127.0.0.1:${ANVIL_PORT}"
LOCAL_MNEMONIC="${ANVIL_MNEMONIC:-test test test test test test test test test test test junk}"
DEPLOY_LOG="$(mktemp)"
ANVIL_PID=""
APP_PID=""
APP_ENV_FILE="$ROOT_DIR/app/.env.local"
APP_ENV_BACKUP=""
APP_ENV_CREATED="false"

require_port() {
  local label="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]{1,5}$ ]] || (( value < 1 || value > 65535 )); then
    echo "$label must be an integer between 1 and 65535 (got $value)" >&2
    exit 1
  fi
}

require_port "ANVIL_PORT" "$ANVIL_PORT"
require_port "APP_PORT" "$APP_PORT"
if [[ "$ANVIL_PORT" == "$APP_PORT" ]]; then
  echo "ANVIL_PORT and APP_PORT must be different (both are $ANVIL_PORT)" >&2
  exit 1
fi

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
}
trap cleanup EXIT INT TERM

command -v anvil >/dev/null || { echo "anvil is required (install Foundry first)" >&2; exit 1; }
command -v forge >/dev/null || { echo "forge is required (install Foundry first)" >&2; exit 1; }
command -v cast >/dev/null || { echo "cast is required (install Foundry first)" >&2; exit 1; }
command -v pnpm >/dev/null || { echo "pnpm is required (install pnpm 11 first)" >&2; exit 1; }

if cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; then
  echo "Refusing to use an existing process on $LOCAL_RPC_URL; stop it before running the demo." >&2
  exit 1
fi

echo "Starting disposable Anvil chain..."
anvil --silent --mnemonic "$LOCAL_MNEMONIC" --port "$ANVIL_PORT" >/tmp/halal-anvil.log 2>&1 &
ANVIL_PID=$!
until cast chain-id --rpc-url "$LOCAL_RPC_URL" >/dev/null 2>&1; do sleep 1; done
LOCAL_PRIVATE_KEY="$(cast wallet derive --insecure "$LOCAL_MNEMONIC" | awk '/Private key:/ { print $3; exit }')"
LOCAL_UPDATER_KEY="$(cast wallet derive --insecure --accounts 2 "$LOCAL_MNEMONIC" | awk '/Private key:/ { key=$3 } END { print key }')"
if [[ -z "$LOCAL_PRIVATE_KEY" ]]; then
  echo "Could not derive the local demo account from ANVIL_MNEMONIC" >&2
  exit 1
fi
if [[ -z "$LOCAL_UPDATER_KEY" ]]; then
  echo "Could not derive the local CPI updater from ANVIL_MNEMONIC" >&2
  exit 1
fi
LOCAL_UPDATER_ADDRESS="$(cast wallet address --private-key "$LOCAL_UPDATER_KEY")"

echo "Deploying Halal locally..."
(
  cd "$ROOT_DIR/contracts"
  forge build --force
  PRIVATE_KEY="$LOCAL_PRIVATE_KEY" CPI_UPDATER="$LOCAL_UPDATER_ADDRESS" forge script script/DeployLocal.s.sol:DeployLocalHalalSystem \
    --rpc-url "$LOCAL_RPC_URL" --broadcast --non-interactive
) | tee "$DEPLOY_LOG"

if ! grep -q "NEXT_PUBLIC_HLC_TOKEN_31337" "$DEPLOY_LOG"; then
  echo "Deployment did not print frontend configuration; see /tmp/halal-anvil.log" >&2
  exit 1
fi

value_from_env() {
  awk -F= -v key="$1" '$1 ~ key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' "$DEPLOY_LOG"
}

LOCAL_PSM="$(value_from_env NEXT_PUBLIC_HLC_PSM_31337)"
echo "Seeding a fresh local CPI report..."
LOCAL_REPORT_AT="$(cast block latest --field timestamp --rpc-url "$LOCAL_RPC_URL")"
cast send "$LOCAL_PSM" 'updateCPIWithTimestamp(uint256,uint256)' 1000000 "$LOCAL_REPORT_AT" \
  --private-key "$LOCAL_UPDATER_KEY" --rpc-url "$LOCAL_RPC_URL" >/dev/null

RPC_URL="$LOCAL_RPC_URL" EXPECTED_CHAIN_ID=31337 \
  TIMELOCK="$(value_from_env NEXT_PUBLIC_HLC_TIMELOCK_31337)" \
  TOKEN="$(value_from_env NEXT_PUBLIC_HLC_TOKEN_31337)" \
  TEAM_VESTING="$(value_from_env NEXT_PUBLIC_HLC_TEAM_VESTING_31337)" \
  TREASURY_VESTING="$(value_from_env NEXT_PUBLIC_HLC_TREASURY_VESTING_31337)" \
  DAO="$(value_from_env NEXT_PUBLIC_HLC_DAO_31337)" \
  PSM="$(value_from_env NEXT_PUBLIC_HLC_PSM_31337)" \
  RESERVE_TOKEN="$(awk '/Local demo reserve:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}' "$DEPLOY_LOG")" \
  TEAM_BENEFICIARY="$(cast wallet address --private-key "$LOCAL_PRIVATE_KEY")" \
  TREASURY_BENEFICIARY="$(cast wallet address --private-key "$LOCAL_PRIVATE_KEY")" \
  DEPLOYER_ADDRESS="$(cast wallet address --private-key "$LOCAL_PRIVATE_KEY")" \
  ALLOW_DEPLOYER_BENEFICIARY=true \
  CPI_UPDATER="$LOCAL_UPDATER_ADDRESS" \
  "$ROOT_DIR/scripts/verify-deployment.sh"

RPC_URL="$LOCAL_RPC_URL" PSM="$LOCAL_PSM" CPI_UPDATER="$LOCAL_UPDATER_ADDRESS" \
  "$ROOT_DIR/scripts/check-psm-health.sh"

if [[ -e "$APP_ENV_FILE" ]]; then
  APP_ENV_BACKUP="$(mktemp)"
  cp -p "$APP_ENV_FILE" "$APP_ENV_BACKUP"
else
  APP_ENV_CREATED="true"
fi

LOCAL_DEPLOYMENT_BLOCK="$(cast block latest --field number --rpc-url "$LOCAL_RPC_URL")"

{
  echo "NEXT_PUBLIC_RPC_URL_31337=$LOCAL_RPC_URL"
  grep 'NEXT_PUBLIC_HLC_' "$DEPLOY_LOG" \
    | sed -e 's/^ *//' -e 's/= /=/' \
    | sed "s/^NEXT_PUBLIC_HLC_DEPLOYMENT_BLOCK_31337=.*/NEXT_PUBLIC_HLC_DEPLOYMENT_BLOCK_31337=$LOCAL_DEPLOYMENT_BLOCK/"
} > "$APP_ENV_FILE"

echo "Temporary frontend configuration written to app/.env.local (restored on exit)"
echo "Starting the dApp at http://localhost:${APP_PORT} (Ctrl-C to stop both processes)..."
setsid pnpm --dir "$ROOT_DIR/app" dev --hostname 127.0.0.1 --port "$APP_PORT" &
APP_PID=$!
wait "$APP_PID"
