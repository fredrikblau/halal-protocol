import { test, expect, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import {
  createPublicClient,
  createTestClient,
  createWalletClient,
  http,
  parseUnits,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Focused accessibility smoke for critical dApp states (/health, /psm).
 * Prefer role/name assertions so status is not color- or icon-only.
 * Runs on disposable Anvil via playwright webServer (local-app-smoke.sh).
 */

const RPC_URL = "http://127.0.0.1:18545";
const ANVIL_ACCOUNT = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266" as const;
const ANVIL_UPDATER_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const ANVIL_UPDATER_ACCOUNT = privateKeyToAccount(ANVIL_UPDATER_KEY);
const CPI_SIGNER_KEYS = [
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
] as const;
const CPI_SIGNER_ACCOUNTS = CPI_SIGNER_KEYS.map((key) => privateKeyToAccount(key));
const LOCAL_CHAIN = {
  id: 31_337,
  name: "Anvil (Local)",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
} as const;

const ERC20_ABI = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

const PSM_ABI = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [{ name: "reserveAmount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "updateCPIWithTimestamp",
    stateMutability: "nonpayable",
    inputs: [
      { name: "reportedCPI", type: "uint256" },
      { name: "reportedAt", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "mockCPI",
    stateMutability: "nonpayable",
    inputs: [{ name: "newCPI", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "redeemableBalance",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "PARAM_ROLE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bytes32" }],
  },
  {
    type: "function",
    name: "hasRole",
    stateMutability: "view",
    inputs: [
      { name: "role", type: "bytes32" },
      { name: "account", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  { type: "function", name: "cpiRate", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "lastUpdated", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  {
    type: "function",
    name: "lastReportTimestamp",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  { type: "error", name: "RateOutOfBounds", inputs: [] },
  { type: "error", name: "UpdateTooSoon", inputs: [] },
  { type: "error", name: "RateWouldUnderCollateralize", inputs: [] },
  {
    type: "error",
    name: "AccessControlUnauthorizedAccount",
    inputs: [
      { name: "account", type: "address" },
      { name: "neededRole", type: "bytes32" },
    ],
  },
] as const;

// A reverted receipt reports no reason, which makes an intermittent governance failure
// undiagnosable from CI logs alone (see issue #188). Replay the call at the parent block to
// recover the decoded custom error, and report gas so an out-of-gas result is distinguishable
// from a genuine revert.
async function assertGovernanceCallSucceeded(
  publicClient: ReturnType<typeof createPublicClient>,
  hash: Hex,
  context: { psm: `0x${string}`; timelock: `0x${string}`; label: string },
) {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status === "success") return receipt;

  const transaction = await publicClient.getTransaction({ hash });
  const lines = [
    `${context.label} reverted (tx ${hash})`,
    `gasUsed=${receipt.gasUsed} gasLimit=${transaction.gas}` +
      (receipt.gasUsed === transaction.gas ? " -- equal, so this is out of gas, not a revert" : ""),
    `block=${receipt.blockNumber} from=${transaction.from}`,
  ];

  try {
    await publicClient.call({
      account: transaction.from,
      to: transaction.to ?? undefined,
      data: transaction.input,
      blockNumber: receipt.blockNumber - 1n,
    });
    lines.push("replay at the parent block SUCCEEDED: failure is gas- or ordering-dependent");
  } catch (error) {
    lines.push(`replay at the parent block reverted with: ${(error as Error).message.split("\n")[0]}`);
  }

  try {
    const paramRole = await publicClient.readContract({
      address: context.psm, abi: PSM_ABI, functionName: "PARAM_ROLE",
    });
    const [hasRole, cpiRate, lastUpdated, lastReportTimestamp] = await Promise.all([
      publicClient.readContract({ address: context.psm, abi: PSM_ABI, functionName: "hasRole", args: [paramRole, context.timelock] }),
      publicClient.readContract({ address: context.psm, abi: PSM_ABI, functionName: "cpiRate" }),
      publicClient.readContract({ address: context.psm, abi: PSM_ABI, functionName: "lastUpdated" }),
      publicClient.readContract({ address: context.psm, abi: PSM_ABI, functionName: "lastReportTimestamp" }),
    ]);
    lines.push(
      `psm=${context.psm} timelock=${context.timelock} hasRole(PARAM_ROLE)=${hasRole}`,
      `cpiRate=${cpiRate} lastUpdated=${lastUpdated} lastReportTimestamp=${lastReportTimestamp}`,
    );
  } catch (error) {
    lines.push(`could not read PSM diagnostics: ${(error as Error).message.split("\n")[0]}`);
  }

  throw new Error(lines.join("\n"));
}

const CPI_ADAPTER_ABI = [
  {
    type: "function",
    name: "submitReport",
    stateMutability: "nonpayable",
    inputs: [
      { name: "reportedCPI", type: "uint256" },
      { name: "reportedAt", type: "uint256" },
      { name: "signatures", type: "bytes[]" },
    ],
    outputs: [],
  },
] as const;

function readLocalEnv(): Record<string, string> {
  const source = readFileSync(".env.local", "utf8");
  return Object.fromEntries(
    source
      .split(/\r?\n/)
      .filter((line: string) => line && !line.startsWith("#"))
      .map((line: string) => {
        const separator = line.indexOf("=");
        return [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

async function seedRedeemableHlc() {
  const env = readLocalEnv();
  const account = ANVIL_ACCOUNT;
  const updaterPublicClient = createPublicClient({ chain: LOCAL_CHAIN, transport: http(RPC_URL) });
  const existingCredit = await updaterPublicClient.readContract({
    address: env.NEXT_PUBLIC_HLC_PSM_31337 as `0x${string}`,
    abi: PSM_ABI,
    functionName: "redeemableBalance",
    args: [account],
  });
  if (existingCredit > 0n) return;

  const updaterWallet = createWalletClient({
    account: ANVIL_UPDATER_ACCOUNT,
    chain: LOCAL_CHAIN,
    transport: http(RPC_URL),
  });
  const block = await updaterPublicClient.getBlock({ blockTag: "latest" });
  const reportedAt = block.timestamp - 1n;
  const signatures = await Promise.all(
    CPI_SIGNER_ACCOUNTS.map((account) =>
      account.signTypedData({
        domain: {
          name: "Halal CPI Report Adapter",
          version: "1",
          chainId: LOCAL_CHAIN.id,
          verifyingContract: env.NEXT_PUBLIC_HLC_CPI_ADAPTER_31337 as `0x${string}`,
        },
        types: { CPIReport: [
          { name: "reportedCPI", type: "uint256" },
          { name: "reportedAt", type: "uint256" },
          { name: "sourceId", type: "bytes32" },
        ] },
        primaryType: "CPIReport",
        message: {
          reportedCPI: 1_000_000n,
          reportedAt,
          sourceId: env.NEXT_PUBLIC_HLC_CPI_SOURCE_ID_31337 as Hex,
        },
      }),
    ),
  );
  const orderedSignatures = CPI_SIGNER_ACCOUNTS
    .map((account, index) => ({ address: account.address.toLowerCase(), signature: signatures[index] }))
    .sort((left, right) => left.address.localeCompare(right.address))
    .map(({ signature }) => signature);
  const reportHash = await updaterWallet.writeContract({
    account: ANVIL_UPDATER_ACCOUNT,
    address: env.NEXT_PUBLIC_HLC_CPI_ADAPTER_31337 as `0x${string}`,
    abi: CPI_ADAPTER_ABI,
    functionName: "submitReport",
    args: [1_000_000n, reportedAt, orderedSignatures],
  });
  await updaterPublicClient.waitForTransactionReceipt({ hash: reportHash });
  const wallet = createWalletClient({ account, chain: LOCAL_CHAIN, transport: http(RPC_URL) });
  const publicClient = createPublicClient({ chain: LOCAL_CHAIN, transport: http(RPC_URL) });
  const reserveAmount = parseUnits("1000", 18);
  const approvalHash = await wallet.writeContract({
    account,
    address: env.NEXT_PUBLIC_HLC_RESERVE_TOKEN_31337 as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [env.NEXT_PUBLIC_HLC_PSM_31337 as `0x${string}`, reserveAmount],
  });
  await publicClient.waitForTransactionReceipt({ hash: approvalHash });
  const depositHash = await wallet.writeContract({
    account,
    address: env.NEXT_PUBLIC_HLC_PSM_31337 as `0x${string}`,
    abi: PSM_ABI,
    functionName: "deposit",
    args: [reserveAmount],
  });
  await publicClient.waitForTransactionReceipt({ hash: depositHash });
}

async function installAnvilProvider(
  page: Page,
  chainId: number = LOCAL_CHAIN.id,
  account: string = ANVIL_ACCOUNT,
) {
  await page.addInitScript(
    ({ rpcUrl, account: injectedAccount, chainId: injectedChainId }) => {
      const listeners = new Map<string, Set<(...args: unknown[]) => void>>();
      const currentAccount = injectedAccount;
      const currentChainId = injectedChainId;
      const provider = {
        isMetaMask: true,
        request: async ({ method, params = [] }: { method: string; params?: unknown[] }) => {
          if (method === "eth_accounts" || method === "eth_requestAccounts") return [currentAccount];
          if (method === "eth_chainId") return `0x${currentChainId.toString(16)}`;
          if (method === "wallet_switchEthereumChain" || method === "wallet_addEthereumChain") {
            return null;
          }
          const response = await fetch(rpcUrl, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              jsonrpc: "2.0",
              id: Date.now(),
              method,
              params,
            }),
          });
          const payload = (await response.json()) as { result?: unknown; error?: { message: string } };
          if (payload.error) throw new Error(payload.error.message);
          return payload.result;
        },
        on: (event: string, listener: (...args: unknown[]) => void) => {
          const current = listeners.get(event) ?? new Set();
          current.add(listener);
          listeners.set(event, current);
        },
        removeListener: (event: string, listener: (...args: unknown[]) => void) =>
          listeners.get(event)?.delete(listener),
      };
      Object.defineProperty(window, "ethereum", { configurable: false, value: provider });
    },
    { rpcUrl: RPC_URL, account, chainId },
  );
}

async function connectBrowserWallet(page: Page) {
  const connectButton = page.getByTestId("rk-connect-button");
  if (await connectButton.count()) await connectButton.click();
  const browserWallet = page.getByTestId("rk-wallet-option-injected");
  if (await browserWallet.count()) {
    await expect(browserWallet).toBeVisible();
    await browserWallet.dispatchEvent("click");
  }
}

test.describe("a11y smoke: critical dApp states", () => {
  test("health healthy state exposes heading hierarchy and labeled checks", async ({ page }) => {
    await seedRedeemableHlc();
    await page.goto("/health");

    await expect(page.getByRole("heading", { name: "Deployment health", level: 1 })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Deployment checks", level: 3 })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Selected network", level: 3 })).toBeVisible();

    const overall = page.getByRole("status", { name: "Overall deployment health" });
    await expect(overall).toBeVisible();
    await expect(overall).toContainText("Healthy");

    const checks = page.getByRole("list", { name: "Deployment health checks" });
    await expect(
      checks.getByRole("listitem", { name: "Contract wiring and roles Healthy" }),
    ).toContainText("Addresses, roles, and timelock wiring match the configured deployment.");
    await expect(
      checks.getByRole("listitem", { name: "CPI report freshness Healthy" }),
    ).toContainText("The accepted CPI report is present and within the freshness window.");
    await expect(
      checks.getByRole("listitem", { name: "PSM reserve coverage Healthy" }),
    ).toContainText("The reserve covers the current PSM-issued redemption requirement.");

    await expect(page.getByRole("button", { name: "Copy deployment health summary" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Open protocol dashboard" })).toHaveAttribute(
      "href",
      "/",
    );
    await expect(page.getByText("Read-only checks from the selected chain.")).toBeVisible();
  });

  test("health review state announces overdue CPI with accessible status text", async ({ page }) => {
    await seedRedeemableHlc();
    const testClient = createTestClient({
      chain: LOCAL_CHAIN,
      mode: "anvil",
      transport: http(RPC_URL),
    });
    const snapshot = await testClient.snapshot();
    // minUpdateInterval is 25 days; stay well under MAX_REPORT_AGE (90 days).
    const overdueSeconds = 25 * 24 * 60 * 60 + 60;
    await testClient.increaseTime({ seconds: overdueSeconds });
    await testClient.mine({ blocks: 1 });
    await page.addInitScript(
      ({ seconds }) => {
        const realNow = Date.now;
        Date.now = () => realNow() + seconds * 1000;
      },
      { seconds: overdueSeconds },
    );

    await page.goto("/health");
    await expect(page.getByRole("heading", { name: "Deployment health", level: 1 })).toBeVisible();
    await expect(page.getByRole("status", { name: "Overall deployment health" })).toContainText(
      "Review",
    );
    const checks = page.getByRole("list", { name: "Deployment health checks" });
    await expect(
      checks.getByRole("listitem", { name: "CPI report freshness Review" }),
    ).toContainText("The normal updater cadence has elapsed; inspect the operator feed.");
    await expect(page.getByText("Resolve blocking items before signing protocol transactions.")).toBeVisible();

    await testClient.revert({ id: snapshot });
  });

  test("health blocking state and psm deposit pause use alerts and disabled controls", async ({
    page,
  }) => {
    await seedRedeemableHlc();
    const testClient = createTestClient({
      chain: LOCAL_CHAIN,
      mode: "anvil",
      transport: http(RPC_URL),
    });
    const snapshot = await testClient.snapshot();
    const env = readLocalEnv();
    const timelock = env.NEXT_PUBLIC_HLC_TIMELOCK_31337 as `0x${string}`;
    const publicClient = createPublicClient({ chain: LOCAL_CHAIN, transport: http(RPC_URL) });
    await testClient.impersonateAccount({ address: timelock });
    await testClient.setBalance({ address: timelock, value: 10n ** 18n });
    const governanceWallet = createWalletClient({
      account: timelock,
      chain: LOCAL_CHAIN,
      transport: http(RPC_URL),
    });
    const cpiHash = await governanceWallet.writeContract({
      account: timelock,
      address: env.NEXT_PUBLIC_HLC_PSM_31337 as `0x${string}`,
      abi: PSM_ABI,
      functionName: "mockCPI",
      args: [1_500_000n],
      // Automatic estimation is used as the gas limit with no headroom. mockCPI's cost depends on
      // whether previousCPI and lastReportTimestamp move from zero (~20k per slot) or are merely
      // updated (~5k), and the snapshot reverts these tests rely on flip those slots back to zero.
      // An estimate taken in one state is then short for execution in another, and the transaction
      // runs out of gas rather than reverting (issue #188). Local disposable chain: bound it
      // generously instead of depending on estimation.
      gas: 200_000n,
    });
    await assertGovernanceCallSucceeded(publicClient, cpiHash, {
      psm: env.NEXT_PUBLIC_HLC_PSM_31337 as `0x${string}`,
      timelock,
      label: "governance mockCPI",
    });
    await testClient.stopImpersonatingAccount({ address: timelock });

    await page.goto("/health");
    await expect(page.getByRole("heading", { name: "Deployment health", level: 1 })).toBeVisible();
    await expect(page.getByRole("status", { name: "Overall deployment health" })).toContainText(
      "Blocking",
    );
    const checks = page.getByRole("list", { name: "Deployment health checks" });
    await expect(
      checks.getByRole("listitem", { name: "PSM reserve coverage Blocking" }),
    ).toContainText(
      "The PSM reserve is below the amount required to redeem all outstanding claims.",
    );

    await installAnvilProvider(page);
    await page.goto("/psm");
    await connectBrowserWallet(page);
    await expect(page.getByRole("heading", { name: "PSM Swap", level: 1 })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Swap", level: 3 })).toBeVisible();
    const pauseAlert = page.getByRole("alert").filter({ hasText: "New PSM deposits are paused" });
    await expect(pauseAlert).toBeVisible();
    await expect(pauseAlert).toContainText(/under-reserved|The PSM is under-reserved/i);
    await expect(
      page.getByRole("button", { name: "Deposits paused until the protocol is healthy" }),
    ).toBeDisabled();
    await testClient.revert({ id: snapshot });
  });

  test("not-deployed health and psm states explain absence of signing actions", async ({ page }) => {
    await installAnvilProvider(page, 421_614);
    await page.goto("/health");

    await expect(page.getByRole("heading", { name: "Deployment health", level: 1 })).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Not deployed on this network", level: 3 }),
    ).toBeVisible();
    await expect(
      page.getByText(/Halal has no contracts configured for Arbitrum Sepolia yet/),
    ).toBeVisible();
    await expect(
      page.getByText(
        "Connect to a supported network or check the project's deployment configuration for chain id 421614.",
      ),
    ).toBeVisible();
    await expect(page.getByRole("status", { name: "Overall deployment health" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Deposit" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Withdraw" })).toHaveCount(0);

    await page.goto("/psm");
    await expect(page.getByRole("heading", { name: "PSM Swap", level: 1 })).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Not deployed on this network", level: 3 }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Deposit" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Withdraw" })).toHaveCount(0);
    await expect(
      page.getByRole("button", { name: "Sign & withdraw in one transaction" }),
    ).toHaveCount(0);
  });

  test("unsupported psm network blocks deposit and withdraw with accessible copy", async ({
    page,
  }) => {
    await installAnvilProvider(page, 1);
    await page.goto("/psm");
    await connectBrowserWallet(page);

    await expect(page.getByRole("heading", { name: "PSM Swap", level: 1 })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Unsupported network", level: 3 })).toBeVisible();
    await expect(
      page.getByText(/Your wallet is connected to a network Halal doesn.t support/),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Switch to Arbitrum Sepolia" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Deposit" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Withdraw" })).toHaveCount(0);
    await expect(page.getByRole("textbox", { name: "Amount to deposit" })).toHaveCount(0);
    await expect(page.getByRole("textbox", { name: "Amount to withdraw" })).toHaveCount(0);
  });
});
