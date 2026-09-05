#!/usr/bin/env bash
set -euo pipefail

# Read-only PSM health check for cron, CI, and monitoring agents.
# Required: RPC_URL and PSM. Optional: CPI_UPDATER, CPI_ADAPTER, EXPECTED_CPI_ADAPTER_OWNER,
# EXPECTED_CPI_SOURCE, EXPECTED_CPI_SOURCE_ID, and FAIL_ON_UPDATE_OVERDUE (default: true).

for variable in RPC_URL PSM; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required environment variable: $variable" >&2
    exit 1
  fi
done

command -v cast >/dev/null || { echo "cast is required (install Foundry first)" >&2; exit 1; }

unhealthy_input() {
  echo "status=unhealthy"
  echo "reason=invalid_${1}"
  echo "value=${2}"
  exit 1
}

unhealthy_reason() {
  echo "status=unhealthy"
  echo "reason=${1}"
  echo "value=${2}"
  exit 1
}

require_uint() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || unhealthy_input "$label" "$value"
}

require_int() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^-?[0-9]+$ ]] || unhealthy_input "$label" "$value"
}

# Bash arithmetic is signed and platform-sized. Keep values used in arithmetic comparisons inside
# that range so an oversized RPC response becomes a structured unhealthy result instead of an
# unhandled arithmetic error.
require_bash_uint() {
  local label="$1"
  local value="$2"
  local normalized="${value#"${value%%[!0]*}"}"
  [[ -n "$normalized" ]] || normalized=0
  if (( ${#normalized} > 19 )) || {
    (( ${#normalized} == 19 )) && {
      # shellcheck disable=SC2071 # Deliberate lexicographic comparison after length validation; arithmetic would overflow.
      [[ "$normalized" > "9223372036854775807" ]]
    }
  }; then
    unhealthy_input "${label}_range" "$value"
  fi
}

if [[ "${FAIL_ON_UPDATE_OVERDUE:-true}" != "true" && "${FAIL_ON_UPDATE_OVERDUE:-true}" != "false" ]]; then
  unhealthy_input "fail_on_update_overdue" "${FAIL_ON_UPDATE_OVERDUE}"
fi

if [[ -n "${CPI_ADAPTER:-}" ]]; then
  if [[ ! "${CPI_ADAPTER}" =~ ^0x[0-9a-fA-F]{40}$ || "${CPI_ADAPTER}" =~ ^0x0{40}$ ]]; then
    unhealthy_input "cpi_adapter" "${CPI_ADAPTER}"
  fi
  if [[ -z "${EXPECTED_CPI_ADAPTER_OWNER:-}" ]]; then
    unhealthy_reason "cpi_adapter_owner_expectation_missing" ""
  fi
  if [[ ! "${EXPECTED_CPI_ADAPTER_OWNER}" =~ ^0x[0-9a-fA-F]{40}$ || "${EXPECTED_CPI_ADAPTER_OWNER}" =~ ^0x0{40}$ ]]; then
    unhealthy_input "expected_cpi_adapter_owner" "${EXPECTED_CPI_ADAPTER_OWNER}"
  fi
  if [[ -z "${EXPECTED_CPI_SOURCE:-}" || "${EXPECTED_CPI_SOURCE//[[:space:]]/}" == "" ]]; then
    unhealthy_reason "cpi_source_expectation_missing" ""
  fi
  if [[ -z "${EXPECTED_CPI_SOURCE_ID:-}" ]]; then
    unhealthy_reason "cpi_adapter_source_id_expectation_missing" ""
  fi
  if [[ ! "${EXPECTED_CPI_SOURCE_ID}" =~ ^0x[0-9a-fA-F]{64}$ || "${EXPECTED_CPI_SOURCE_ID}" =~ ^0x0{64}$ ]]; then
    unhealthy_input "expected_cpi_source_id" "${EXPECTED_CPI_SOURCE_ID}"
  fi
fi

require_contract_code() {
  local label="$1"
  local address="$2"
  local code
  if ! code="$(cast code "$address" --rpc-url "$RPC_URL" 2>/dev/null)"; then
    unhealthy_reason "${label}_code_read_failed" "$address"
  fi
  if [[ -z "$code" || "$code" == "0x" ]]; then
    unhealthy_reason "${label}_no_code" "$address"
  fi
}

require_contract_code "psm" "$PSM"
if [[ -n "${CPI_ADAPTER:-}" ]]; then
  require_contract_code "cpi_adapter" "${CPI_ADAPTER}"
fi

call_at() {
  cast call "$@" --rpc-url "$RPC_URL" | awk 'NR == 1 { print $1; exit }'
}

call() {
  call_at "$PSM" "$@"
}

address_call() {
  call "$@" | tr '[:upper:]' '[:lower:]'
}

now="$(cast block latest --field timestamp --rpc-url "$RPC_URL")"
reserve_surplus="$(call 'reserveSurplus()(int256)')"
last_report="$(call 'lastReportTimestamp()(uint256)')"
cpi_rate="$(call 'cpiRate()(uint256)')"
max_report_age="$(call 'MAX_REPORT_AGE()(uint256)')"
last_updated="$(call 'lastUpdated()(uint256)')"
min_update_interval="$(call 'minUpdateInterval()(uint256)')"
cpi_source="$(call 'source()(string)' | sed -e 's/^"//' -e 's/"$//')"

require_uint "checked_at" "$now"
require_int "reserve_surplus" "$reserve_surplus"
require_uint "last_report_timestamp" "$last_report"
require_uint "cpi_rate" "$cpi_rate"
require_uint "max_report_age" "$max_report_age"
require_uint "last_updated" "$last_updated"
require_uint "min_update_interval" "$min_update_interval"
require_bash_uint "checked_at" "$now"
require_bash_uint "last_report_timestamp" "$last_report"
require_bash_uint "cpi_rate" "$cpi_rate"
require_bash_uint "max_report_age" "$max_report_age"
require_bash_uint "last_updated" "$last_updated"
require_bash_uint "min_update_interval" "$min_update_interval"

echo "psm=$PSM"
echo "checked_at=$now"
echo "reserve_surplus=$reserve_surplus"
echo "last_report_timestamp=$last_report"
echo "cpi_rate=$cpi_rate"
echo "max_report_age=$max_report_age"
echo "last_updated=$last_updated"
echo "min_update_interval=$min_update_interval"
echo "cpi_source=$cpi_source"

failure=0

if [[ -n "${CPI_UPDATER:-}" ]]; then
  CPI_UPDATER="${CPI_UPDATER,,}"
  updater_role="$(call 'UPDATER_ROLE()(bytes32)')"
  updater_configured="$(address_call 'hasRole(bytes32,address)(bool)' "$updater_role" "$CPI_UPDATER")"
  echo "cpi_updater=$CPI_UPDATER"
  if [[ "$updater_configured" != "true" ]]; then
    echo "status=unhealthy"
    echo "reason=configured_cpi_updater_missing_role"
    failure=1
  fi
fi

if [[ -n "${EXPECTED_CPI_SOURCE:-}" && "$cpi_source" != "$EXPECTED_CPI_SOURCE" ]]; then
  echo "status=unhealthy"
  echo "reason=cpi_source_mismatch"
  failure=1
fi

if [[ -n "${CPI_ADAPTER:-}" ]]; then
  CPI_ADAPTER="${CPI_ADAPTER,,}"
  updater_role="$(call 'UPDATER_ROLE()(bytes32)')"
  adapter_updater_configured="$(address_call 'hasRole(bytes32,address)(bool)' "$updater_role" "$CPI_ADAPTER")"
  echo "cpi_adapter_updater_role=$adapter_updater_configured"
  if [[ "$adapter_updater_configured" != "true" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_missing_updater_role"
    failure=1
  fi
  adapter_psm="$(call_at "$CPI_ADAPTER" 'psm()(address)' | tr '[:upper:]' '[:lower:]')"
  adapter_owner="$(call_at "$CPI_ADAPTER" 'owner()(address)' | tr '[:upper:]' '[:lower:]')"
  adapter_source_id="$(call_at "$CPI_ADAPTER" 'sourceId()(bytes32)' | tr '[:upper:]' '[:lower:]')"
  adapter_threshold="$(call_at "$CPI_ADAPTER" 'threshold()(uint256)')"
  adapter_signer_count="$(call_at "$CPI_ADAPTER" 'signerCount()(uint256)')"
  adapter_last_submitted="$(call_at "$CPI_ADAPTER" 'lastSubmittedTimestamp()(uint256)')"
  adapter_last_submitted_cpi="$(call_at "$CPI_ADAPTER" 'lastSubmittedCPI()(uint256)')"
  require_uint "adapter_threshold" "$adapter_threshold"
  require_uint "adapter_signer_count" "$adapter_signer_count"
  require_uint "adapter_last_submitted_timestamp" "$adapter_last_submitted"
  require_uint "adapter_last_submitted_cpi" "$adapter_last_submitted_cpi"
  require_bash_uint "adapter_threshold" "$adapter_threshold"
  require_bash_uint "adapter_signer_count" "$adapter_signer_count"
  require_bash_uint "adapter_last_submitted_timestamp" "$adapter_last_submitted"
  require_bash_uint "adapter_last_submitted_cpi" "$adapter_last_submitted_cpi"
  echo "cpi_adapter=$CPI_ADAPTER"
  echo "cpi_adapter_owner=$adapter_owner"
  echo "cpi_adapter_source_id=$adapter_source_id"
  echo "cpi_adapter_threshold=$adapter_threshold"
  echo "cpi_adapter_signer_count=$adapter_signer_count"
  echo "cpi_adapter_last_submitted_timestamp=$adapter_last_submitted"
  echo "cpi_adapter_last_submitted_cpi=$adapter_last_submitted_cpi"
  signer_addresses=()
  if [[ "$adapter_signer_count" =~ ^[0-9]+$ ]]; then
    for (( signer_index = 0; signer_index < adapter_signer_count; signer_index++ )); do
      signer_address="$(call_at "$CPI_ADAPTER" 'signerAt(uint256)(address)' "$signer_index" | tr '[:upper:]' '[:lower:]')"
      signer_addresses+=("$signer_address")
      echo "cpi_adapter_signer_${signer_index}=$signer_address"
    done
  fi

  if [[ "$adapter_psm" != "${PSM,,}" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_psm_mismatch"
    failure=1
  fi
  if [[ -n "${EXPECTED_CPI_ADAPTER_OWNER:-}" && "$adapter_owner" != "${EXPECTED_CPI_ADAPTER_OWNER,,}" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_owner_mismatch"
    failure=1
  fi
  if [[ -n "${EXPECTED_CPI_SOURCE_ID:-}" && "$adapter_source_id" != "${EXPECTED_CPI_SOURCE_ID,,}" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_source_id_mismatch"
    failure=1
  fi
  if [[ "$adapter_threshold" == "0" || "$adapter_signer_count" == "0" || "$adapter_threshold" -gt "$adapter_signer_count" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_quorum_invalid"
    failure=1
  fi
  for (( signer_index = 0; signer_index < ${#signer_addresses[@]}; signer_index++ )); do
    if [[ "${signer_addresses[$signer_index]}" == "$adapter_owner" ]]; then
      echo "status=unhealthy"
      echo "reason=cpi_adapter_signer_owner_overlap"
      failure=1
    fi
    for (( previous_index = 0; previous_index < signer_index; previous_index++ )); do
      if [[ "${signer_addresses[$signer_index]}" == "${signer_addresses[$previous_index]}" ]]; then
        echo "status=unhealthy"
        echo "reason=cpi_adapter_signer_duplicate"
        failure=1
      fi
    done
  done
  if [[ "$adapter_last_submitted" != "$last_report" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_watermark_mismatch"
    failure=1
  fi
  if [[ "$adapter_last_submitted_cpi" != "$cpi_rate" ]]; then
    echo "status=unhealthy"
    echo "reason=cpi_adapter_rate_mismatch"
    failure=1
  fi
fi

if [[ "$reserve_surplus" == -* ]]; then
  echo "status=unhealthy"
  echo "reason=reserve_deficit"
  failure=1
fi

if [[ "$last_report" == "0" ]]; then
  echo "status=unhealthy"
  echo "reason=timestamped_cpi_report_missing"
  failure=1
elif (( last_report > now )); then
  echo "status=unhealthy"
  echo "reason=timestamped_cpi_report_in_future"
  failure=1
elif (( now - last_report > max_report_age )); then
  echo "status=unhealthy"
  echo "reason=timestamped_cpi_report_stale"
  failure=1
fi

if (( last_updated > now )); then
  echo "status=unhealthy"
  echo "reason=last_updated_in_future"
  failure=1
elif (( now - last_updated > min_update_interval )); then
  echo "warning=normal_cpi_update_overdue"
  if [[ "${FAIL_ON_UPDATE_OVERDUE:-true}" == "true" ]]; then
    failure=1
  fi
fi

if (( failure == 0 )); then
  echo "status=healthy"
  exit 0
fi

exit 1
