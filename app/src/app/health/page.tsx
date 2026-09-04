"use client";

import Link from "next/link";
import { PageHeader } from "@/components/ui/PageHeader";
import { Alert } from "@/components/ui/Alert";
import { Card, CardBody, CardHeader, CardTitle } from "@/components/ui/Card";
import { NotDeployedState } from "@/components/NotDeployedState";
import { DeploymentIntegrityBanner } from "@/components/DeploymentIntegrityBanner";
import { CpiAdapterCard } from "@/components/dashboard/CpiAdapterCard";
import { CpiCard } from "@/components/dashboard/CpiCard";
import { ReserveHealthCard } from "@/components/dashboard/ReserveHealthCard";
import { HealthStatusCard, type HealthStatus } from "@/components/health/HealthStatusCard";
import { useCpiAdapter } from "@/hooks/useCpiAdapter";
import { useDeployment, type DeploymentInfo } from "@/hooks/useDeployment";
import { useDeploymentIntegrity } from "@/hooks/useDeploymentIntegrity";
import { usePsmSafety } from "@/hooks/usePsmSafety";
import { usePsmState } from "@/hooks/usePsm";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { shortAddress } from "@/lib/format";

function deploymentCheck(integrity: ReturnType<typeof useDeploymentIntegrity>): { status: HealthStatus; detail: string } {
  if (integrity.isChecking) return { status: "loading", detail: "Reading the configured contract graph and roles." };
  if (integrity.isError) return { status: "fail", detail: getFriendlyErrorMessage(integrity.error) };
  return integrity.isVerified
    ? { status: "pass", detail: "Addresses, roles, and timelock wiring match the configured deployment." }
    : { status: "fail", detail: "The live contract graph does not match the configured deployment." };
}

function reportCheck(psm: ReturnType<typeof usePsmState>, safety: ReturnType<typeof usePsmSafety>) {
  if (psm.isLoading) return { status: "loading" as const, detail: "Reading CPI report timestamps and freshness bounds." };
  if (psm.isError) return { status: "fail" as const, detail: getFriendlyErrorMessage(psm.error) };
  if (psm.lastReportTimestamp === undefined || psm.maxReportAge === undefined) {
    return { status: "fail" as const, detail: "CPI report freshness data could not be read. Refresh the page before relying on this status." };
  }
  if (safety.reportTimestampMissing) return { status: "fail" as const, detail: "No timestamped CPI report has been accepted." };
  if (safety.reportStale) return { status: "fail" as const, detail: "The accepted CPI report is older than the contract freshness window." };
  if (safety.updateOverdue) return { status: "warn" as const, detail: "The normal updater cadence has elapsed; inspect the operator feed." };
  return { status: "pass" as const, detail: "The accepted CPI report is present and within the freshness window." };
}

function reserveCheck(psm: ReturnType<typeof usePsmState>) {
  if (psm.isLoading) return { status: "loading" as const, detail: "Reading reserve balance and current redemption requirement." };
  if (psm.reserveSurplus === undefined) return { status: "fail" as const, detail: "Reserve health could not be read." };
  if (psm.reserveSurplus < 0n) return { status: "fail" as const, detail: "The PSM reserve is below the amount required to redeem all outstanding claims." };
  return { status: "pass" as const, detail: "The reserve covers the current PSM-issued redemption requirement." };
}

function adapterCheck(deployment: DeploymentInfo["deployment"], adapter: ReturnType<typeof useCpiAdapter>, psm: ReturnType<typeof usePsmState>) {
  if (!deployment?.cpiAdapter) return { status: "warn" as const, detail: "No signed CPI adapter is configured; review the updater custody path." };
  if (adapter.isLoading || psm.isLoading) return { status: "loading" as const, detail: "Reading adapter ownership, quorum, and report watermark." };
  if (adapter.isError) return { status: "fail" as const, detail: "The configured adapter state could not be read." };
  const quorumValid = adapter.threshold !== undefined && adapter.signerCount !== undefined && adapter.signers !== undefined && adapter.threshold > 0n && adapter.threshold <= adapter.signerCount && BigInt(adapter.signers.length) === adapter.signerCount;
  const wiringValid = deployment.cpiSource !== undefined && deployment.cpiSourceId !== undefined && psm.source === deployment.cpiSource && adapter.psm?.toLowerCase() === deployment.psm.toLowerCase() && adapter.owner?.toLowerCase() === deployment.timelock.toLowerCase() && adapter.sourceId?.toLowerCase() === deployment.cpiSourceId.toLowerCase();
  const watermarkValid = adapter.lastSubmittedTimestamp !== undefined && psm.lastReportTimestamp !== undefined && adapter.lastSubmittedTimestamp === psm.lastReportTimestamp;
  const rateValid = adapter.lastSubmittedCPI !== undefined && psm.cpiRate !== undefined && adapter.lastSubmittedCPI === psm.cpiRate;
  if (!quorumValid || !wiringValid || !watermarkValid || !rateValid) return { status: "fail" as const, detail: "Adapter quorum, ownership, source identity, CPI rate, or report watermark diverges from the deployment." };
  return { status: "pass" as const, detail: `${adapter.threshold} of ${adapter.signerCount} configured signers; adapter and PSM CPI state matches.` };
}

export default function HealthPage() {
  const { deployment, isDeployed, chainId } = useDeployment();
  const integrity = useDeploymentIntegrity();
  const psm = usePsmState();
  const adapter = useCpiAdapter();
  const safety = usePsmSafety(psm);

  if (!isDeployed) {
    return <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8"><PageHeader title="Deployment health" description="Read-only checks for the selected Halal network." /><NotDeployedState /></div>;
  }

  const deploymentState = deploymentCheck(integrity);
  const reportState = reportCheck(psm, safety);
  const reserveState = reserveCheck(psm);
  const adapterState = adapterCheck(deployment, adapter, psm);
  const checks = [
    { label: "Contract wiring and roles", ...deploymentState },
    { label: "CPI report freshness", ...reportState },
    { label: "PSM reserve coverage", ...reserveState },
    { label: "Signed CPI adapter", ...adapterState },
  ];
  const summary = [
    "Halal deployment health",
    `Chain ID: ${chainId}`,
    `Checked at: ${new Date().toISOString()}`,
    ...checks.map((check) => `${check.label}: ${check.status.toUpperCase()} — ${check.detail}`),
  ].join("\n");

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader title="Deployment health" description="Inspect the live contract wiring, CPI feed, reserve coverage, and adapter custody before signing." />
      <div className="space-y-6">
        <DeploymentIntegrityBanner />
        <HealthStatusCard checks={checks} summary={summary} />

        {psm.isError && <Alert tone="danger" title="Health data is incomplete">{getFriendlyErrorMessage(psm.error)} Refresh the page before relying on any status.</Alert>}

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader><CardTitle>Selected network</CardTitle></CardHeader>
            <CardBody className="space-y-2 text-sm">
              <p><span className="text-muted">Chain ID:</span> <span className="tabular font-medium">{chainId}</span></p>
              <p><span className="text-muted">PSM:</span> <code title={deployment?.psm}>{shortAddress(deployment?.psm)}</code></p>
              <p><span className="text-muted">Reserve:</span> <code title={deployment?.reserveToken}>{shortAddress(deployment?.reserveToken)}</code></p>
              <Link href="/" className="inline-block pt-2 text-sm font-medium text-primary underline">Open protocol dashboard</Link>
            </CardBody>
          </Card>
          <CpiCard cpiRate={psm.cpiRate} previousCPI={psm.previousCPI} lastUpdated={psm.lastUpdated} lastReportTimestamp={psm.lastReportTimestamp} maxReportAge={psm.maxReportAge} minUpdateInterval={psm.minUpdateInterval} source={psm.source} reserveSymbol={psm.reserveSymbol} isLoading={psm.isLoading} />
        </div>

        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <ReserveHealthCard reserveBalance={psm.reserveBalance} reserveRequired={psm.reserveRequired} reserveSurplus={psm.reserveSurplus} reserveDecimals={psm.reserveDecimals} reserveSymbol={psm.reserveSymbol} isLoading={psm.isLoading} />
          {deployment?.cpiAdapter ? <CpiAdapterCard /> : <Card><CardHeader><CardTitle>CPI adapter</CardTitle></CardHeader><CardBody><p className="text-sm text-muted">No signed adapter is configured for this deployment. Review the updater role and source policy before launch.</p></CardBody></Card>}
        </div>
      </div>
    </div>
  );
}
