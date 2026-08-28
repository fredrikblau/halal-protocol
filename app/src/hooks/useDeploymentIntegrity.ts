"use client";

import { useReadContracts } from "wagmi";
import { keccak256, toBytes, zeroAddress, zeroHash, type Address, type ContractFunctionParameters } from "viem";
import {
  cpiReportAdapterAbi,
  halalDaoAbi,
  halalPsmAbi,
  halalTimelockAbi,
  halalTokenAbi,
  halalVestingAbi,
} from "@/abis";
import { hasReadFailure, partialReadError } from "@/lib/readResults";
import { useDeployment } from "./useDeployment";

const MINTER_ROLE = keccak256(toBytes("MINTER_ROLE"));
const BURNER_ROLE = keccak256(toBytes("BURNER_ROLE"));
const PARAM_ROLE = keccak256(toBytes("PARAM_ROLE"));
const UPDATER_ROLE = keccak256(toBytes("UPDATER_ROLE"));
const PROPOSER_ROLE = keccak256(toBytes("PROPOSER_ROLE"));
const EXECUTOR_ROLE = keccak256(toBytes("EXECUTOR_ROLE"));

/**
 * Verifies the configured addresses against the live contract graph before the dApp signs actions.
 * Environment variables are only a routing hint; they are not proof that the selected chain has
 * the intended Halal deployment. The role checks also ensure the configured graph is actually
 * governed as designed: the PSM can mint and burn through accounting-aware paths, the timelock
 * administers protocol contracts, the DAO can propose through the timelock, and anyone can execute
 * a queued proposal.
 */
export function useDeploymentIntegrity() {
  const { deployment } = useDeployment();
  const adapterContracts: readonly ContractFunctionParameters[] = deployment?.cpiAdapter
    ? ([
        { address: deployment.cpiAdapter, abi: cpiReportAdapterAbi, functionName: "psm" },
        { address: deployment.cpiAdapter, abi: cpiReportAdapterAbi, functionName: "owner" },
        { address: deployment.cpiAdapter, abi: cpiReportAdapterAbi, functionName: "sourceId" },
        { address: deployment.cpiAdapter, abi: cpiReportAdapterAbi, functionName: "threshold" },
        { address: deployment.cpiAdapter, abi: cpiReportAdapterAbi, functionName: "signerCount" },
        { address: deployment.cpiAdapter, abi: cpiReportAdapterAbi, functionName: "getSigners" },
      ] as const)
    : [];
  const integrityContracts: readonly ContractFunctionParameters[] | undefined = deployment
    ? [
        { address: deployment.psm, abi: halalPsmAbi, functionName: "reserve" },
        { address: deployment.psm, abi: halalPsmAbi, functionName: "hlc" },
        { address: deployment.dao, abi: halalDaoAbi, functionName: "token" },
        { address: deployment.dao, abi: halalDaoAbi, functionName: "timelock" },
        { address: deployment.teamVesting, abi: halalVestingAbi, functionName: "token" },
        { address: deployment.teamVesting, abi: halalVestingAbi, functionName: "dao" },
        { address: deployment.treasuryVesting, abi: halalVestingAbi, functionName: "token" },
        { address: deployment.treasuryVesting, abi: halalVestingAbi, functionName: "dao" },
        { address: deployment.timelock, abi: halalTimelockAbi, functionName: "getMinDelay" },
        { address: deployment.token, abi: halalTokenAbi, functionName: "hasRole", args: [MINTER_ROLE, deployment.psm] },
        { address: deployment.token, abi: halalTokenAbi, functionName: "hasRole", args: [BURNER_ROLE, deployment.psm] },
        { address: deployment.token, abi: halalTokenAbi, functionName: "hasRole", args: [zeroHash, deployment.timelock] },
        { address: deployment.psm, abi: halalPsmAbi, functionName: "hasRole", args: [zeroHash, deployment.timelock] },
        { address: deployment.psm, abi: halalPsmAbi, functionName: "hasRole", args: [PARAM_ROLE, deployment.timelock] },
        {
          address: deployment.psm,
          abi: halalPsmAbi,
          functionName: "hasRole",
          args: [UPDATER_ROLE, deployment.cpiAdapter ?? zeroAddress],
        },
        { address: deployment.psm, abi: halalPsmAbi, functionName: "source" },
        { address: deployment.timelock, abi: halalTimelockAbi, functionName: "hasRole", args: [PROPOSER_ROLE, deployment.dao] },
        { address: deployment.timelock, abi: halalTimelockAbi, functionName: "hasRole", args: [EXECUTOR_ROLE, zeroAddress] },
        { address: deployment.timelock, abi: halalTimelockAbi, functionName: "hasRole", args: [zeroHash, deployment.timelock] },
        ...adapterContracts,
      ]
    : undefined;

  const { data, isLoading, isError, error, refetch } = useReadContracts({
    contracts: integrityContracts,
    query: { enabled: deployment !== undefined, refetchInterval: 30_000 },
  });

  const get = <T>(index: number): T | undefined =>
    data?.[index]?.status === "success" ? (data[index].result as T) : undefined;

  const reserve = get<Address>(0);
  const psmToken = get<Address>(1);
  const daoToken = get<Address>(2);
  const daoTimelock = get<Address>(3);
  const teamToken = get<Address>(4);
  const teamDao = get<Address>(5);
  const treasuryToken = get<Address>(6);
  const treasuryDao = get<Address>(7);
  const timelockDelay = get<bigint>(8);
  const psmMinter = get<boolean>(9);
  const psmBurner = get<boolean>(10);
  const tokenAdmin = get<boolean>(11);
  const psmAdmin = get<boolean>(12);
  const psmParam = get<boolean>(13);
  const adapterUpdater = get<boolean>(14);
  const psmSource = get<string>(15);
  const timelockProposer = get<boolean>(16);
  const timelockExecutor = get<boolean>(17);
  const timelockSelfAdmin = get<boolean>(18);
  const adapterPsm = get<Address>(19);
  const adapterOwner = get<Address>(20);
  const adapterSourceId = get<`0x${string}`>(21);
  const adapterThreshold = get<bigint>(22);
  const adapterSignerCount = get<bigint>(23);
  const adapterSigners = get<Address[]>(24);
  const expected = deployment;
  const adapterConfigurationComplete =
    expected?.cpiAdapter === undefined &&
    expected?.cpiSource === undefined &&
    expected?.cpiSourceId === undefined &&
    expected?.cpiPolicyUrl === undefined
      ? true
      : expected?.cpiAdapter !== undefined &&
        expected?.cpiSource !== undefined &&
        expected?.cpiSourceId !== undefined &&
        expected?.cpiPolicyUrl !== undefined;

  const readFailed = hasReadFailure(data);
  const isVerified =
    expected !== undefined &&
    reserve?.toLowerCase() === expected.reserveToken.toLowerCase() &&
    psmToken?.toLowerCase() === expected.token.toLowerCase() &&
    daoToken?.toLowerCase() === expected.token.toLowerCase() &&
    daoTimelock?.toLowerCase() === expected.timelock.toLowerCase() &&
    teamToken?.toLowerCase() === expected.token.toLowerCase() &&
    teamDao?.toLowerCase() === expected.timelock.toLowerCase() &&
    treasuryToken?.toLowerCase() === expected.token.toLowerCase() &&
    treasuryDao?.toLowerCase() === expected.timelock.toLowerCase() &&
    timelockDelay !== undefined &&
    timelockDelay > 0n &&
    psmMinter === true &&
    psmBurner === true &&
    tokenAdmin === true &&
    psmAdmin === true &&
    psmParam === true &&
    (expected?.cpiAdapter === undefined || adapterUpdater === true) &&
    timelockProposer === true &&
    timelockExecutor === true &&
    timelockSelfAdmin === true &&
    (adapterConfigurationComplete &&
      (expected?.cpiAdapter === undefined ||
        (psmSource === expected.cpiSource &&
        adapterPsm?.toLowerCase() === expected.psm.toLowerCase() &&
        adapterOwner?.toLowerCase() === expected.timelock.toLowerCase() &&
        adapterSourceId?.toLowerCase() === expected.cpiSourceId?.toLowerCase() &&
        adapterThreshold !== undefined &&
        adapterSignerCount !== undefined &&
        adapterSigners !== undefined &&
        adapterThreshold > 0n &&
        adapterThreshold <= adapterSignerCount &&
        BigInt(adapterSigners.length) === adapterSignerCount)));

  return {
    isVerified,
    isChecking: deployment !== undefined && (isLoading || data === undefined),
    isError: isError || readFailed,
    error: error ?? (readFailed ? partialReadError() : undefined),
    refetch,
  };
}
