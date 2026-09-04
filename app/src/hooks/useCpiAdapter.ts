"use client";

import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { cpiReportAdapterAbi } from "@/abis";
import { hasReadFailure, partialReadError } from "@/lib/readResults";
import { useDeployment } from "./useDeployment";

/** Reads the optional CPI adapter's live ownership, quorum, signer, and report state. */
export function useCpiAdapter() {
  const { deployment } = useDeployment();
  const adapter = deployment?.cpiAdapter;
  const { data, isLoading, isError, error, refetch } = useReadContracts({
    contracts: adapter
      ? ([
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "psm" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "owner" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "sourceId" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "threshold" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "signerCount" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "getSigners" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "lastSubmittedTimestamp" },
          { address: adapter, abi: cpiReportAdapterAbi, functionName: "lastSubmittedCPI" },
        ] as const)
      : [],
    query: { enabled: adapter !== undefined, refetchInterval: 30_000 },
  });

  const get = <T>(index: number): T | undefined =>
    data?.[index]?.status === "success" ? (data[index].result as T) : undefined;
  const readFailed = hasReadFailure(data);

  return {
    configured: adapter !== undefined,
    adapter,
    psm: get<Address>(0),
    owner: get<Address>(1),
    sourceId: get<`0x${string}`>(2),
    threshold: get<bigint>(3),
    signerCount: get<bigint>(4),
    signers: get<Address[]>(5),
    lastSubmittedTimestamp: get<bigint>(6),
    lastSubmittedCPI: get<bigint>(7),
    isLoading: adapter !== undefined && (isLoading || data === undefined),
    isError: isError || readFailed,
    error: error ?? (readFailed ? partialReadError() : undefined),
    refetch,
  };
}
