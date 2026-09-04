"use client";

import { Alert } from "@/components/ui/Alert";
import { Badge } from "@/components/ui/Badge";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/Card";
import { Skeleton } from "@/components/ui/Skeleton";
import { useCpiAdapter } from "@/hooks/useCpiAdapter";
import { useDeployment } from "@/hooks/useDeployment";
import { usePsmState } from "@/hooks/usePsm";
import { formatDate, shortAddress } from "@/lib/format";

export function CpiAdapterCard() {
  const { deployment } = useDeployment();
  const adapter = useCpiAdapter();
  const psm = usePsmState();

  if (!deployment?.cpiAdapter) return null;

  const signerCountMatches =
    adapter.signerCount !== undefined &&
    adapter.signers !== undefined &&
    BigInt(adapter.signers.length) === adapter.signerCount;
  const quorumValid =
    adapter.threshold !== undefined &&
    adapter.signerCount !== undefined &&
    adapter.threshold > 0n &&
    adapter.threshold <= adapter.signerCount &&
    signerCountMatches;
  const wiringValid =
    deployment.cpiSource !== undefined &&
    deployment.cpiSourceId !== undefined &&
    psm.source === deployment.cpiSource &&
    adapter.psm?.toLowerCase() === deployment.psm.toLowerCase() &&
    adapter.owner?.toLowerCase() === deployment.timelock.toLowerCase() &&
    adapter.sourceId?.toLowerCase() === deployment.cpiSourceId?.toLowerCase();
  const reportSyncKnown = adapter.lastSubmittedTimestamp !== undefined && psm.lastReportTimestamp !== undefined;
  const reportSyncValid = reportSyncKnown && adapter.lastSubmittedTimestamp === psm.lastReportTimestamp;
  const rateSyncKnown = adapter.lastSubmittedCPI !== undefined && psm.cpiRate !== undefined;
  const rateSyncValid = rateSyncKnown && adapter.lastSubmittedCPI === psm.cpiRate;
  const isLoading = adapter.isLoading || psm.isLoading;
  const isError = adapter.isError || psm.isError;
  const isVerified = !isError && quorumValid && wiringValid && reportSyncValid && rateSyncValid;

  return (
    <Card>
      <CardHeader>
        <CardTitle>CPI report adapter</CardTitle>
        {isLoading ? (
          <Skeleton className="h-6 w-20" />
        ) : isError ? (
          <Badge tone="danger">Read failed</Badge>
        ) : (
          <Badge tone={isVerified ? "primary" : "danger"}>{isVerified ? "Verified quorum" : "Review wiring"}</Badge>
        )}
      </CardHeader>
      <CardBody className="space-y-4">
        {isError ? (
          <Alert tone="danger">The live adapter or PSM state could not be read. Do not sign a CPI report until the RPC is healthy.</Alert>
        ) : isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-5 w-48" />
            <Skeleton className="h-5 w-64" />
            <Skeleton className="h-5 w-56" />
          </div>
        ) : (
          <>
            <dl className="grid grid-cols-2 gap-3 text-xs">
              <div>
                <dt className="text-muted">Adapter</dt>
                <dd className="font-medium" title={adapter.adapter}>{shortAddress(adapter.adapter)}</dd>
              </div>
              <div>
                <dt className="text-muted">Owner</dt>
                <dd className="font-medium" title={adapter.owner}>{shortAddress(adapter.owner)}</dd>
              </div>
              <div>
                <dt className="text-muted">Source ID</dt>
                <dd className="font-medium" title={adapter.sourceId}>{shortAddress(adapter.sourceId, 6)}</dd>
              </div>
              <div>
                <dt className="text-muted">Last submitted report</dt>
                <dd className="font-medium">{formatDate(adapter.lastSubmittedTimestamp)}</dd>
              </div>
              <div>
                <dt className="text-muted">PSM report watermark</dt>
                <dd className="font-medium">{formatDate(psm.lastReportTimestamp)}</dd>
              </div>
              <div>
                <dt className="text-muted">Submitted CPI / PSM CPI</dt>
                <dd className="font-medium">{adapter.lastSubmittedCPI?.toString() ?? "—"} / {psm.cpiRate?.toString() ?? "—"}</dd>
              </div>
            </dl>
            <div className="rounded-xl bg-background-subtle p-3">
              <div className="flex items-center justify-between gap-3 text-xs">
                <span className="text-muted">Report quorum</span>
                <span className="tabular font-semibold">
                  {adapter.threshold?.toString() ?? "—"} of {adapter.signerCount?.toString() ?? "—"} signatures
                </span>
              </div>
              <div className="mt-3 space-y-2">
                {adapter.signers?.map((signer, index) => (
                  <div className="flex items-center justify-between text-xs" key={signer}>
                    <span className="text-muted">Signer {index + 1}</span>
                    <code title={signer}>{shortAddress(signer)}</code>
                  </div>
                ))}
              </div>
            </div>
            <p className="text-xs text-muted">
              The adapter authenticates the configured signer quorum, and its submitted CPI and report watermark should match the PSM.
              Source policy and signer custody still require independent operational review.
            </p>
          </>
        )}
      </CardBody>
    </Card>
  );
}
