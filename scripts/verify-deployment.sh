#!/usr/bin/env bash
set -euo pipefail

# Read-only post-deployment verifier. Required: RPC_URL, EXPECTED_CHAIN_ID, TIMELOCK, TOKEN,
# TEAM_VESTING, TREASURY_VESTING, DAO, PSM, RESERVE_TOKEN, TEAM_BENEFICIARY, TREASURY_BENEFICIARY,
# and DEPLOYER_ADDRESS. Optional: CPI_UPDATER, CPI_ADAPTER, EXPECTED_CPI_SOURCE,
# EXPECTED_CPI_SOURCE_ID. The
# adapter metadata is verified against the PSM and timelock when supplied. ALLOW_DEPLOYER_BENEFICIARY=true
# is for the disposable local demo only.

required_vars=(
  RPC_URL EXPECTED_CHAIN_ID TIMELOCK TOKEN TEAM_VESTING TREASURY_VESTING DAO PSM RESERVE_TOKEN
  TEAM_BENEFICIARY TREASURY_BENEFICIARY DEPLOYER_ADDRESS
)
for variable in "${required_vars[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required environment variable: $variable" >&2
    exit 1
  fi
done

command -v cast >/dev/null || { echo "cast is required (install Foundry first)" >&2; exit 1; }

case "$RPC_URL" in
  https://*) ;;
  http://127.0.0.1:*|http://localhost:*|http://\[::1\]:*) ;;
  *)
    echo "RPC_URL must use HTTPS, or loopback HTTP for a disposable local demo" >&2
    exit 1
    ;;
esac

call() {
  # Foundry may append a human-readable scientific-notation rendering to large integers.
  # Keep the canonical first field so exact checks remain stable across cast versions.
  cast call "$1" "$2" "${@:3}" --rpc-url "$RPC_URL" | awk 'NR == 1 { print $1; exit }'
}

address_call() {
  call "$@" | tr '[:upper:]' '[:lower:]'
}

string_call() {
  cast call "$1" "$2" --rpc-url "$RPC_URL" | sed -e 's/^"//' -e 's/"$//'
}

expect_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAILED: $label (expected $expected, got $actual)" >&2
    exit 1
  fi
}

expect_true() {
  local label="$1"
  local actual="$2"
  if [[ "$actual" != "true" ]]; then
    echo "FAILED: $label (expected true, got $actual)" >&2
    exit 1
  fi
}

expect_positive() {
  local label="$1"
  local actual="$2"
  if [[ -z "$actual" || "$actual" =~ ^\[?0+(\.0+)?([eE][+-]?0+)?\]?$ ]]; then
    echo "FAILED: $label (expected a positive integer, got $actual)" >&2
    exit 1
  fi
}

expect_bounded_positive() {
  local label="$1"
  local actual="$2"
  local maximum="$3"
  if [[ ! "$actual" =~ ^[1-9][0-9]*$ || ${#actual} -gt ${#maximum} || ( ${#actual} -eq ${#maximum} && "$actual" > "$maximum" ) ]]; then
    echo "FAILED: $label (expected an integer between 1 and $maximum, got $actual)" >&2
    exit 1
  fi
}

expect_contract() {
  local label="$1"
  local address="$2"
  local code
  code="$(cast code "$address" --rpc-url "$RPC_URL")"
  if [[ -z "$code" || "$code" == "0x" ]]; then
    echo "FAILED: $label has no deployed contract bytecode at $address" >&2
    exit 1
  fi
}

expect_equal "RPC chain ID" "$(cast chain-id --rpc-url "$RPC_URL")" "$EXPECTED_CHAIN_ID"

TIMELOCK="${TIMELOCK,,}"
TOKEN="${TOKEN,,}"
TEAM_VESTING="${TEAM_VESTING,,}"
TREASURY_VESTING="${TREASURY_VESTING,,}"
DAO="${DAO,,}"
PSM="${PSM,,}"
RESERVE_TOKEN="${RESERVE_TOKEN,,}"
TEAM_BENEFICIARY="${TEAM_BENEFICIARY,,}"
TREASURY_BENEFICIARY="${TREASURY_BENEFICIARY,,}"
DEPLOYER_ADDRESS="${DEPLOYER_ADDRESS,,}"

if [[ -n "${CPI_ADAPTER:-}" || -n "${EXPECTED_CPI_SOURCE:-}" || -n "${EXPECTED_CPI_SOURCE_ID:-}" ]]; then
  if [[ -z "${CPI_ADAPTER:-}" || -z "${EXPECTED_CPI_SOURCE:-}" || -z "${EXPECTED_CPI_SOURCE_ID:-}" ]]; then
    echo "CPI_ADAPTER, EXPECTED_CPI_SOURCE, and EXPECTED_CPI_SOURCE_ID must be provided together" >&2
    exit 1
  fi
  if [[ -z "${EXPECTED_CPI_SOURCE//[[:space:]]/}" ]]; then
    echo "EXPECTED_CPI_SOURCE must contain non-whitespace source metadata" >&2
    exit 1
  fi
  if [[ ! "$CPI_ADAPTER" =~ ^0x[0-9a-fA-F]{40}$ || "$CPI_ADAPTER" =~ ^0x0{40}$ ]]; then
    echo "CPI_ADAPTER must be a non-zero Ethereum address" >&2
    exit 1
  fi
  if [[ ! "$EXPECTED_CPI_SOURCE_ID" =~ ^0x[0-9a-fA-F]{64}$ || "$EXPECTED_CPI_SOURCE_ID" =~ ^0x0{64}$ ]]; then
    echo "EXPECTED_CPI_SOURCE_ID must be a non-zero bytes32 value" >&2
    exit 1
  fi
  EXPECTED_CPI_ADAPTER_OWNER="${EXPECTED_CPI_ADAPTER_OWNER:-$TIMELOCK}"
  if [[ ! "$EXPECTED_CPI_ADAPTER_OWNER" =~ ^0x[0-9a-fA-F]{40}$ || "$EXPECTED_CPI_ADAPTER_OWNER" =~ ^0x0{40}$ ]]; then
    echo "EXPECTED_CPI_ADAPTER_OWNER must be a non-zero Ethereum address" >&2
    exit 1
  fi
  CPI_ADAPTER="${CPI_ADAPTER,,}"
  EXPECTED_CPI_SOURCE_ID="${EXPECTED_CPI_SOURCE_ID,,}"
  EXPECTED_CPI_ADAPTER_OWNER="${EXPECTED_CPI_ADAPTER_OWNER,,}"
fi

if [[ "${ALLOW_DEPLOYER_BENEFICIARY:-false}" != "true" && "${ALLOW_DEPLOYER_BENEFICIARY:-false}" != "false" ]]; then
  echo "ALLOW_DEPLOYER_BENEFICIARY must be true or false" >&2
  exit 1
fi

if [[ "${ALLOW_DEPLOYER_BENEFICIARY:-false}" != "true" && (
  "$TEAM_BENEFICIARY" == "$DEPLOYER_ADDRESS" || "$TREASURY_BENEFICIARY" == "$DEPLOYER_ADDRESS"
) ]]; then
  echo "FAILED: production beneficiaries must not equal the deployer (set ALLOW_DEPLOYER_BENEFICIARY=true only for the disposable local demo)" >&2
  exit 1
fi

if [[ "${ALLOW_DEPLOYER_BENEFICIARY:-false}" != "true" && "$TEAM_BENEFICIARY" == "$TREASURY_BENEFICIARY" ]]; then
  echo "FAILED: production team and treasury beneficiaries must be distinct" >&2
  exit 1
fi

if [[ "${ALLOW_DEPLOYER_BENEFICIARY:-false}" == "true" ]]; then
  if [[ "$EXPECTED_CHAIN_ID" != "31337" ]]; then
    echo "FAILED: ALLOW_DEPLOYER_BENEFICIARY=true is restricted to Anvil chain 31337" >&2
    exit 1
  fi
  case "$RPC_URL" in
    http://127.0.0.1:*|http://localhost:*|http://\[::1\]:*) ;;
    *) echo "FAILED: ALLOW_DEPLOYER_BENEFICIARY=true requires a loopback HTTP RPC" >&2; exit 1 ;;
  esac
fi

expect_contract "timelock" "$TIMELOCK"
expect_contract "token" "$TOKEN"
expect_contract "team vesting" "$TEAM_VESTING"
expect_contract "treasury vesting" "$TREASURY_VESTING"
expect_contract "DAO" "$DAO"
expect_contract "PSM" "$PSM"
expect_contract "reserve token" "$RESERVE_TOKEN"
if [[ "${ALLOW_DEPLOYER_BENEFICIARY:-false}" != "true" ]]; then
  expect_contract "team beneficiary" "$TEAM_BENEFICIARY"
  expect_contract "treasury beneficiary" "$TREASURY_BENEFICIARY"
fi

expect_equal "PSM reserve" "$(address_call "$PSM" 'reserve()(address)')" "$RESERVE_TOKEN"
expect_equal "PSM HLC token" "$(address_call "$PSM" 'hlc()(address)')" "$TOKEN"
expect_equal "team vesting token" "$(address_call "$TEAM_VESTING" 'token()(address)')" "$TOKEN"
expect_equal "treasury vesting token" "$(address_call "$TREASURY_VESTING" 'token()(address)')" "$TOKEN"
expect_equal "team vesting DAO" "$(address_call "$TEAM_VESTING" 'dao()(address)')" "$TIMELOCK"
expect_equal "treasury vesting DAO" "$(address_call "$TREASURY_VESTING" 'dao()(address)')" "$TIMELOCK"
expect_equal "DAO HLC token" "$(address_call "$DAO" 'token()(address)')" "$TOKEN"
expect_equal "DAO timelock" "$(address_call "$DAO" 'timelock()(address)')" "$TIMELOCK"
expect_positive "timelock delay" "$(call "$TIMELOCK" 'getMinDelay()(uint256)')"

expect_true "genesis allocation minted" "$(call "$TOKEN" 'genesisMinted()(bool)')"
team_allocation="$(call "$TOKEN" 'TEAM_ALLOCATION()(uint256)')"
treasury_allocation="$(call "$TOKEN" 'TREASURY_ALLOCATION()(uint256)')"
# These allocations are immutable schedule values, while live balances decrease as vesting
# releases occur. Checking balances would make a valid deployment fail on every later audit.
expect_equal "team vesting allocation" "$(call "$TEAM_VESTING" 'totalAllocation()(uint256)')" "$team_allocation"
expect_equal "treasury vesting allocation" "$(call "$TREASURY_VESTING" 'totalAllocation()(uint256)')" "$treasury_allocation"
expect_equal "team vesting cliff" "$(call "$TEAM_VESTING" 'cliff()(uint64)')" "31536000"
expect_equal "team vesting duration" "$(call "$TEAM_VESTING" 'duration()(uint64)')" "126144000"
expect_equal "team vesting revocability" "$(call "$TEAM_VESTING" 'revocable()(bool)')" "true"
expect_equal "treasury vesting cliff" "$(call "$TREASURY_VESTING" 'cliff()(uint64)')" "0"
expect_equal "treasury vesting duration" "$(call "$TREASURY_VESTING" 'duration()(uint64)')" "94608000"
expect_equal "treasury vesting revocability" "$(call "$TREASURY_VESTING" 'revocable()(bool)')" "false"

expect_equal "team beneficiary" "$(address_call "$TEAM_VESTING" 'beneficiary()(address)')" "$TEAM_BENEFICIARY"
expect_equal "treasury beneficiary" "$(address_call "$TREASURY_VESTING" 'beneficiary()(address)')" "$TREASURY_BENEFICIARY"

minter_role="$(call "$TOKEN" 'MINTER_ROLE()(bytes32)')"
burner_role="$(call "$TOKEN" 'BURNER_ROLE()(bytes32)')"
admin_role="$(call "$TOKEN" 'DEFAULT_ADMIN_ROLE()(bytes32)')"
timelock_admin_role="$(call "$TIMELOCK" 'DEFAULT_ADMIN_ROLE()(bytes32)')"
proposer_role="$(call "$TIMELOCK" 'PROPOSER_ROLE()(bytes32)')"
executor_role="$(call "$TIMELOCK" 'EXECUTOR_ROLE()(bytes32)')"
psm_param_role="$(call "$PSM" 'PARAM_ROLE()(bytes32)')"
psm_admin_role="$(call "$PSM" 'DEFAULT_ADMIN_ROLE()(bytes32)')"
psm_updater_role="$(call "$PSM" 'UPDATER_ROLE()(bytes32)')"

expect_true "PSM has HLC minter role" "$(call "$TOKEN" 'hasRole(bytes32,address)(bool)' "$minter_role" "$PSM")"
expect_true "PSM has HLC burner role" "$(call "$TOKEN" 'hasRole(bytes32,address)(bool)' "$burner_role" "$PSM")"
expect_true "timelock has HLC admin role" "$(call "$TOKEN" 'hasRole(bytes32,address)(bool)' "$admin_role" "$TIMELOCK")"
expect_true "DAO has timelock proposer role" "$(call "$TIMELOCK" 'hasRole(bytes32,address)(bool)' "$proposer_role" "$DAO")"
expect_true "timelock retains self-admin role" "$(call "$TIMELOCK" 'hasRole(bytes32,address)(bool)' "$timelock_admin_role" "$TIMELOCK")"
expect_true "timelock has PSM admin role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_admin_role" "$TIMELOCK")"
expect_true "timelock has PSM parameter role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_param_role" "$TIMELOCK")"
expect_true "timelock has open executor role" "$(call "$TIMELOCK" 'hasRole(bytes32,address)(bool)' "$executor_role" "0x0000000000000000000000000000000000000000")"

if [[ -n "${CPI_UPDATER:-}" ]]; then
  CPI_UPDATER="${CPI_UPDATER,,}"
  expect_true "configured CPI updater role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_updater_role" "$CPI_UPDATER")"
fi

if [[ -n "${CPI_ADAPTER:-}" ]]; then
  expect_contract "CPI adapter" "$CPI_ADAPTER"
  expect_contract "CPI adapter owner" "$EXPECTED_CPI_ADAPTER_OWNER"
  expect_equal "CPI adapter PSM" "$(address_call "$CPI_ADAPTER" 'psm()(address)')" "$PSM"
  expect_equal "CPI adapter owner" "$(address_call "$CPI_ADAPTER" 'owner()(address)')" "$EXPECTED_CPI_ADAPTER_OWNER"
  expect_equal "CPI adapter source ID" "$(address_call "$CPI_ADAPTER" 'sourceId()(bytes32)')" "$EXPECTED_CPI_SOURCE_ID"
  expect_equal "PSM CPI source" "$(string_call "$PSM" 'source()(string)')" "$EXPECTED_CPI_SOURCE"
  expect_true "PSM has CPI adapter updater role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_updater_role" "$CPI_ADAPTER")"
  expect_equal "CPI adapter report watermark" "$(call "$CPI_ADAPTER" 'lastSubmittedTimestamp()(uint256)')" "$(call "$PSM" 'lastReportTimestamp()(uint256)')"

  adapter_threshold="$(call "$CPI_ADAPTER" 'threshold()(uint256)')"
  adapter_signer_count="$(call "$CPI_ADAPTER" 'signerCount()(uint256)')"
  expect_bounded_positive "CPI adapter threshold" "$adapter_threshold" "64"
  expect_bounded_positive "CPI adapter signer count" "$adapter_signer_count" "64"
  if (( adapter_threshold > adapter_signer_count )); then
    echo "FAILED: CPI adapter threshold exceeds signer count" >&2
    exit 1
  fi
  adapter_signers=()
  for (( signer_index = 0; signer_index < adapter_signer_count; signer_index++ )); do
    signer_address="$(address_call "$CPI_ADAPTER" 'signerAt(uint256)(address)' "$signer_index")"
    adapter_signers+=("$signer_address")
    if [[ "$signer_address" == "$EXPECTED_CPI_ADAPTER_OWNER" ]]; then
      echo "FAILED: CPI adapter signer overlaps the owner" >&2
      exit 1
    fi
    for (( previous_index = 0; previous_index < signer_index; previous_index++ )); do
      if [[ "$signer_address" == "${adapter_signers[$previous_index]}" ]]; then
        echo "FAILED: CPI adapter signer set contains a duplicate" >&2
        exit 1
      fi
    done
  done
fi

expect_equal "deployer HLC minter role" "$(call "$TOKEN" 'hasRole(bytes32,address)(bool)' "$minter_role" "$DEPLOYER_ADDRESS")" "false"
expect_equal "deployer HLC burner role" "$(call "$TOKEN" 'hasRole(bytes32,address)(bool)' "$burner_role" "$DEPLOYER_ADDRESS")" "false"
expect_equal "deployer HLC admin role" "$(call "$TOKEN" 'hasRole(bytes32,address)(bool)' "$admin_role" "$DEPLOYER_ADDRESS")" "false"
expect_equal "deployer timelock admin role" "$(call "$TIMELOCK" 'hasRole(bytes32,address)(bool)' "$timelock_admin_role" "$DEPLOYER_ADDRESS")" "false"
expect_equal "deployer PSM admin role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_admin_role" "$DEPLOYER_ADDRESS")" "false"
expect_equal "deployer PSM parameter role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_param_role" "$DEPLOYER_ADDRESS")" "false"
expect_equal "deployer PSM updater role" "$(call "$PSM" 'hasRole(bytes32,address)(bool)' "$psm_updater_role" "$DEPLOYER_ADDRESS")" "false"

echo "Halal deployment wiring verified: $PSM"
