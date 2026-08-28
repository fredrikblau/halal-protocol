import test from "node:test";
import assert from "node:assert/strict";
import { validateAdapterSignerSet, validateReportState, validateSignatureSet, validateTypedData } from "../verify-cpi-report.mjs";

const signerOne = "0x1111111111111111111111111111111111111111";
const signerTwo = "0x2222222222222222222222222222222222222222";
const typedData = {
  types: { CPIReport: [] },
  primaryType: "CPIReport",
  domain: {
    name: "Halal CPI Report Adapter",
    version: "1",
    chainId: "421614",
    verifyingContract: "0x1234567890123456789012345678901234567890",
  },
  message: {
    reportedCPI: "1000000",
    reportedAt: "1780000000",
    sourceId: `0x${"ab".repeat(32)}`,
  },
};

test("validates the adapter domain and report message", () => {
  assert.equal(validateTypedData(typedData), typedData);
});

test("requires sorted unique signers and one signature per signer", () => {
  const signatures = `0x${"11".repeat(65)},0x${"22".repeat(65)}`;
  assert.deepEqual(validateSignatureSet(`${signerOne},${signerTwo}`, signatures), {
    signers: [signerOne, signerTwo],
    signatures: signatures.split(","),
  });
  assert.throws(
    () => validateSignatureSet(`${signerTwo},${signerOne}`, signatures),
    /strictly ascending/,
  );
  assert.throws(() => validateSignatureSet(signerOne, signatures), /same nonzero/);
});

test("requires the adapter signer count to match its enumerated signer set", () => {
  assert.deepEqual(
    validateAdapterSignerSet({
      threshold: "2",
      signerCount: "2",
      onChainSigners: [signerOne, signerTwo],
    }),
    [signerOne, signerTwo],
  );
  assert.throws(
    () => validateAdapterSignerSet({ threshold: "2", signerCount: "3", onChainSigners: [signerOne, signerTwo] }),
    /does not match/,
  );
  assert.throws(
    () => validateAdapterSignerSet({ threshold: "3", signerCount: "2", onChainSigners: [signerOne, signerTwo] }),
    /quorum is invalid/,
  );
  assert.throws(
    () => validateAdapterSignerSet({ threshold: "2", signerCount: "2", onChainSigners: [signerOne, signerOne] }),
    /duplicates/,
  );
});

test("rejects a typed data file for another domain", () => {
  assert.throws(() => validateTypedData({ ...typedData, domain: { ...typedData.domain, version: "2" } }), /domain/);
  assert.throws(() => validateTypedData({ ...typedData, primaryType: "OtherReport" }), /primaryType/);
  assert.throws(
    () => validateTypedData({ ...typedData, message: { ...typedData.message, reportedCPI: "2000001" } }),
    /outside the PSM range/,
  );
});

test("preflights the live adapter and PSM report watermarks", () => {
  assert.deepEqual(
    validateReportState({
      typedData,
      now: "1780001000",
      adapterLastSubmittedTimestamp: "0",
      adapterLastSubmittedCPI: "0",
      psmLastReportTimestamp: "0",
      psmCPI: "0",
      psmMaxReportAge: "7776000",
    }),
    {
      reportedAt: "1780000000",
      checkedAt: "1780001000",
      adapterPreviousReportTimestamp: "0",
      adapterPreviousCPI: "0",
      psmPreviousReportTimestamp: "0",
      psmCPI: "0",
      maxReportAge: "7776000",
    },
  );
});

test("rejects stale, replayed, and future reports before signature recovery", () => {
  const base = {
    now: "1780001000",
    adapterLastSubmittedTimestamp: "0",
    adapterLastSubmittedCPI: "0",
    psmLastReportTimestamp: "0",
    psmCPI: "0",
    psmMaxReportAge: "7776000",
  };
  assert.throws(() => validateReportState({ typedData, ...base, now: "1787776001" }), /older than/);
  assert.throws(() => validateReportState({ typedData, ...base, adapterLastSubmittedTimestamp: "1780000000" }), /adapter watermark/);
  assert.throws(() => validateReportState({ typedData, ...base, psmLastReportTimestamp: "1780000000" }), /PSM watermark/);
  assert.throws(() => validateReportState({ typedData, ...base, adapterLastSubmittedCPI: "1" }), /CPI rates diverge/);
  assert.throws(
    () => validateReportState({ typedData, ...base, now: "1779999999" }),
    /future for the live RPC/,
  );
});
