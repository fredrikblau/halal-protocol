// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { HalalToken } from "./HalalToken.sol";

/// @title HalalPSM (Peg Stability Module)
/// @notice Mints HLC against a reserve asset (e.g. DAI) at a CPI-adjusted rate, and burns HLC to
/// return reserve on withdrawal. PSM issuance is collateralized by reserve held in this contract
/// at the applicable rate; CPI increases can create a shortfall that governance must top up before
/// all outstanding claims can be redeemed.
///
/// CPI rate design: `cpiRate` tracks the price of 1 HLC in reserve-asset terms, scaled by
/// `CPI_PRECISION`. As CPI (inflation) rises, `cpiRate` rises, so each HLC buys more reserve on
/// withdrawal and each unit of reserve mints fewer HLC on deposit -- HLC's real purchasing power is
/// held roughly constant while its reserve-asset price floats with inflation.
///
/// Redemption rights are per-depositor, not per-token: HLC is a single fungible ERC20 shared with
/// the genesis team/treasury allocation (see HalalToken), which was never backed by any reserve.
/// If `withdraw` let *any* HLC holder redeem against the shared reserve, genesis/vesting HLC --
/// costless to acquire -- could drain reserve contributed by actual depositors. `redeemableBalance`
/// tracks, per address, how much HLC that address itself minted via `deposit` and hasn't yet
/// redeemed; `withdraw` can never pull more than the caller's own credit, regardless of how much
/// HLC they hold. Use `transferRedeemable` to atomically transfer PSM-minted HLC together with its
/// redemption credit; a plain ERC20 transfer deliberately does not move that credit, see
/// docs/DESIGN-DECISIONS.md.
///
/// Chainlink Functions note: the original design calls for an on-chain Chainlink Functions request in
/// `updateCPI()`. To keep this repo self-contained and testable without a live Functions
/// subscription, `updateCPI` here is a bounds-, rate-, cadence-, and reserve-limited *report submission* function gated by
/// `UPDATER_ROLE`. In production, grant `UPDATER_ROLE` to a Chainlink Functions consumer (or Chainlink
/// Automation-triggered relayer) that fetches CPI off-chain and submits it here -- routine monthly
/// updates then don't require a full 9-day governance cycle, while who is allowed to submit, and the
/// bounds/step-limit those submissions are checked against, remain governance-controlled.
contract HalalPSM is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PARAM_ROLE = keccak256("PARAM_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    uint256 public constant CPI_PRECISION = 1_000_000; // 1.0 == 1_000_000
    uint256 public constant MIN_CPI = 100_000; // 0.1
    uint256 public constant MAX_CPI = 2_000_000; // 2.0
    uint256 public constant MAX_CPI_STEP_BPS = 2_000; // 20% max move per updateCPI() call
    uint256 public constant MAX_REPORT_AGE = 90 days;
    uint8 public constant MAX_RESERVE_DECIMALS = 77;

    IERC20 public immutable reserve;
    HalalToken public immutable hlc;
    uint8 private immutable _reserveDecimals;
    uint8 private constant HLC_DECIMALS = 18;

    uint256 public cpiRate = CPI_PRECISION;
    uint256 public previousCPI = CPI_PRECISION;
    uint256 public lastUpdated;
    /// @notice Timestamp supplied by the most recently accepted CPI report or governance override.
    /// Zero means no report has been accepted since deployment.
    uint256 public lastReportTimestamp;
    uint256 public minUpdateInterval = 25 days;
    uint256 public totalHlcIssued;
    string public source;

    /// @dev HLC amount each address minted via `deposit` and hasn't yet redeemed via `withdraw`.
    /// Sum over all addresses always equals `totalHlcIssued`. See the contract-level NatSpec for why
    /// this exists.
    mapping(address => uint256) public redeemableBalance;

    event Deposited(address indexed user, uint256 reserveIn, uint256 hlcOut);
    event Withdrawn(address indexed user, uint256 hlcIn, uint256 reserveOut);
    event CPIUpdated(uint256 previousCPI, uint256 newCPI, bool viaUpdater);
    event CPIReportAccepted(uint256 reportTimestamp);
    event SourceUpdated(string newSource);
    event MinUpdateIntervalUpdated(uint256 newInterval);
    event ReserveDeposited(address indexed from, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event RedeemableTransferred(address indexed from, address indexed to, uint256 amount);
    event RedeemableCancelled(address indexed user, uint256 amount);

    error ZeroAmount();
    error ZeroReceived();
    error InsufficientOutput();
    error NotContract();
    error UnsupportedDecimals();
    error ZeroAddress();
    error RateOutOfBounds();
    error StepTooLarge();
    error UpdateTooSoon();
    error InvalidUpdateInterval();
    error InsufficientReserve();
    error RateWouldUnderCollateralize();
    error TransferFailed();
    error InsufficientRedeemableBalance();
    error SlippageExceeded();
    error DeadlineExpired();
    error InvalidReportTimestamp();
    error ReportTooOld();
    error CpiReportMissing();
    error CpiReportStale();
    error EmptySource();

    /// @param reserve_ Reserve asset (e.g. DAI). Any ERC20Metadata-compliant token works; decimals
    /// are normalized against HLC's 18 decimals.
    /// @param hlc_ HalalToken address. This contract must be granted `HalalToken.MINTER_ROLE` for
    /// deposits to work.
    /// @param dao DAO timelock; receives `DEFAULT_ADMIN_ROLE` and `PARAM_ROLE`.
    /// @param updater_ Optional initial CPI updater. If nonzero, it receives `UPDATER_ROLE` at
    /// deployment; the DAO timelock remains the role admin and can revoke or replace it later.
    constructor(address reserve_, address hlc_, address dao, address updater_) {
        if (reserve_ == address(0) || hlc_ == address(0) || dao == address(0)) revert ZeroAddress();
        // A low-level call to an EOA succeeds with empty return data. Rejecting non-contract
        // token dependencies prevents a misconfigured PSM from accepting reserve while silently
        // failing to mint HLC. `dao` remains an address because the PSM only needs an AccessControl
        // role holder; production policy requires the timelock and the verifier checks it.
        if (reserve_.code.length == 0 || hlc_.code.length == 0) revert NotContract();

        reserve = IERC20(reserve_);
        hlc = HalalToken(hlc_);
        uint8 reserveDecimals = IERC20Metadata(reserve_).decimals();
        if (reserveDecimals > MAX_RESERVE_DECIMALS) revert UnsupportedDecimals();
        _reserveDecimals = reserveDecimals;
        lastUpdated = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(PARAM_ROLE, dao);
        if (updater_ != address(0)) _grantRole(UPDATER_ROLE, updater_);
    }

    // ── User-facing ──────────────────────────────────────────────────────

    /// @notice Compatibility deposit without an output bound. New integrations should use
    /// `depositWithMinHlcOut` so a CPI update between quoting and execution cannot worsen output.
    function deposit(uint256 reserveAmount) external nonReentrant {
        _deposit(reserveAmount, 0);
    }

    /// @notice Deposits reserve and reverts unless at least `minHlcOut` HLC is minted. Use this
    /// bounded entrypoint when the quote came from `previewDeposit`; CPI can change before a
    /// transaction executes.
    function depositWithMinHlcOut(uint256 reserveAmount, uint256 minHlcOut) external nonReentrant {
        _deposit(reserveAmount, minHlcOut);
    }

    /// @notice Deposits reserve with both an output bound and an execution deadline. New
    /// integrations should prefer this entrypoint when a quote must not remain executable after
    /// a caller-defined time.
    function depositWithMinHlcOutAndDeadline(uint256 reserveAmount, uint256 minHlcOut, uint256 deadline)
        external
        nonReentrant
    {
        _checkDeadline(deadline);
        _deposit(reserveAmount, minHlcOut);
    }

    /// @notice Deposits with an EIP-2612 reserve-token permit, output bound, and execution deadline.
    /// The reserve token must implement IERC20Permit; callers can use the approval-based entrypoints
    /// for tokens that do not support permits or for smart-contract wallets.
    function depositWithPermit(
        uint256 reserveAmount,
        uint256 minHlcOut,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        _checkDeadline(deadline);
        _tryPermit(address(reserve), reserveAmount, deadline, v, r, s);
        _deposit(reserveAmount, minHlcOut);
    }

    function _deposit(uint256 reserveAmount, uint256 minHlcOut) internal {
        _checkDepositSafety();
        if (reserveAmount == 0) revert ZeroAmount();
        uint256 balanceBefore = reserve.balanceOf(address(this));
        reserve.safeTransferFrom(msg.sender, address(this), reserveAmount);
        uint256 received = reserve.balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert ZeroReceived();

        uint256 hlcOut = _reserveToHlc(received);
        // Do not accept dust that rounds down to zero HLC. Without this check the reserve
        // transfer would succeed while the depositor receives no redeemable balance.
        if (hlcOut == 0) revert InsufficientOutput();
        if (hlcOut < minHlcOut) revert SlippageExceeded();
        totalHlcIssued += hlcOut;
        redeemableBalance[msg.sender] += hlcOut;
        hlc.mint(msg.sender, hlcOut);
        emit Deposited(msg.sender, received, hlcOut);
    }

    /// @notice Compatibility withdrawal without an output bound. New integrations should use
    /// `withdrawWithMinReserveOut` so a CPI update cannot worsen the quoted return.
    function withdraw(uint256 hlcAmount) external nonReentrant {
        _withdraw(hlcAmount, 0);
    }

    /// @notice Withdraws HLC and reverts unless at least `minReserveOut` reserve is returned. Use
    /// this bounded entrypoint when the quote came from `previewWithdraw`.
    function withdrawWithMinReserveOut(uint256 hlcAmount, uint256 minReserveOut) external nonReentrant {
        _withdraw(hlcAmount, minReserveOut);
    }

    /// @notice Withdraws HLC with both an output bound and an execution deadline. New integrations
    /// should prefer this entrypoint when a quote must not remain executable after a caller-defined time.
    function withdrawWithMinReserveOutAndDeadline(uint256 hlcAmount, uint256 minReserveOut, uint256 deadline)
        external
        nonReentrant
    {
        _checkDeadline(deadline);
        _withdraw(hlcAmount, minReserveOut);
    }

    /// @notice Withdraws with an EIP-2612 HLC permit, output bound, and execution deadline.
    /// HLC implements IERC20Permit; the approval-based withdrawal entrypoints remain available for
    /// smart-contract wallets that cannot sign permits.
    function withdrawWithPermit(
        uint256 hlcAmount,
        uint256 minReserveOut,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        _checkDeadline(deadline);
        _tryPermit(address(hlc), hlcAmount, deadline, v, r, s);
        _withdraw(hlcAmount, minReserveOut);
    }

    /// @notice Transfers PSM-issued HLC and its redemption credit in one atomic operation. The
    /// caller must approve this contract for `hlcAmount`; a plain ERC20 transfer cannot move the
    /// credit because the token has no knowledge of this PSM's per-address accounting.
    function transferRedeemable(address to, uint256 hlcAmount) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (hlcAmount == 0) revert ZeroAmount();
        if (redeemableBalance[msg.sender] < hlcAmount) revert InsufficientRedeemableBalance();

        bool ok = hlc.transferFrom(msg.sender, to, hlcAmount);
        if (!ok) revert TransferFailed();
        redeemableBalance[msg.sender] -= hlcAmount;
        redeemableBalance[to] += hlcAmount;
        emit RedeemableTransferred(msg.sender, to, hlcAmount);
    }

    /// @notice Transfers PSM-issued HLC and its redemption credit with an EIP-2612 HLC permit.
    /// The recipient receives the same accounting-aware credit as transferRedeemable.
    function transferRedeemableWithPermit(
        address to,
        uint256 hlcAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        _checkDeadline(deadline);
        _tryPermit(address(hlc), hlcAmount, deadline, v, r, s);
        if (to == address(0)) revert ZeroAddress();
        if (hlcAmount == 0) revert ZeroAmount();
        if (redeemableBalance[msg.sender] < hlcAmount) revert InsufficientRedeemableBalance();

        bool ok = hlc.transferFrom(msg.sender, to, hlcAmount);
        if (!ok) revert TransferFailed();
        redeemableBalance[msg.sender] -= hlcAmount;
        redeemableBalance[to] += hlcAmount;
        emit RedeemableTransferred(msg.sender, to, hlcAmount);
    }

    /// @notice Irreversibly burns HLC and retires the caller's matching redemption credit without
    /// returning reserve. This is the accounting-aware alternative to calling HLC's public
    /// `burn()` directly: it releases the surrendered claim from `totalHlcIssued`, allowing the
    /// corresponding reserve to become surplus. The caller must approve this contract for the HLC.
    function cancelRedeemable(uint256 hlcAmount) external nonReentrant {
        _cancelRedeemable(hlcAmount);
    }

    /// @notice Irreversibly burns HLC and retires the caller's redemption credit with an EIP-2612
    /// HLC permit. The permit is only an approval; the same accounting checks and irreversible
    /// burn semantics as `cancelRedeemable` still apply.
    function cancelRedeemableWithPermit(uint256 hlcAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
    {
        _checkDeadline(deadline);
        _tryPermit(address(hlc), hlcAmount, deadline, v, r, s);
        _cancelRedeemable(hlcAmount);
    }

    function _cancelRedeemable(uint256 hlcAmount) internal {
        if (hlcAmount == 0) revert ZeroAmount();
        if (redeemableBalance[msg.sender] < hlcAmount) revert InsufficientRedeemableBalance();

        totalHlcIssued -= hlcAmount;
        redeemableBalance[msg.sender] -= hlcAmount;
        bool ok = hlc.transferFrom(msg.sender, address(this), hlcAmount);
        if (!ok) revert TransferFailed();
        hlc.burn(hlcAmount);
        emit RedeemableCancelled(msg.sender, hlcAmount);
    }

    function _withdraw(uint256 hlcAmount, uint256 minReserveOut) internal {
        if (hlcAmount == 0) revert ZeroAmount();
        if (redeemableBalance[msg.sender] < hlcAmount) revert InsufficientRedeemableBalance();
        uint256 reserveBalanceBefore = reserve.balanceOf(address(this));
        uint256 reserveDeficitBefore = _reserveDeficit(reserveBalanceBefore, reserveRequired());
        uint256 reserveOut = _hlcToReserve(hlcAmount);
        if (reserveOut == 0) revert InsufficientOutput();
        if (reserveBalanceBefore < reserveOut) revert InsufficientReserve();
        if (reserveOut < minReserveOut) revert SlippageExceeded();

        totalHlcIssued -= hlcAmount;
        redeemableBalance[msg.sender] -= hlcAmount;
        bool ok = hlc.transferFrom(msg.sender, address(this), hlcAmount);
        if (!ok) revert TransferFailed();
        hlc.burn(hlcAmount);
        uint256 userReserveBefore = reserve.balanceOf(msg.sender);
        reserve.safeTransfer(msg.sender, reserveOut);
        uint256 received = reserve.balanceOf(msg.sender) - userReserveBefore;
        if (received == 0) revert ZeroReceived();
        if (received < minReserveOut) revert SlippageExceeded();
        uint256 reserveDeficitAfter = _reserveDeficit(reserve.balanceOf(address(this)), reserveRequired());
        if (reserveDeficitAfter > reserveDeficitBefore) revert InsufficientReserve();
        emit Withdrawn(msg.sender, hlcAmount, received);
    }

    /// @notice Reserve balance the PSM would need on hand to fully redeem all outstanding
    /// PSM-issued HLC at the current CPI rate. Because deposits lock in reserve at the CPI rate
    /// prevailing *at deposit time* while withdrawals pay out at the rate prevailing *at withdrawal
    /// time*, a rising CPI increases this requirement over time -- the DAO/treasury must keep the
    /// reserve topped up (fees, treasury allocations, `depositReserve`) to stay ahead of it. `deposit`
    /// itself is always exactly self-funding; the gap, if any, comes from CPI having risen since
    /// existing holders minted.
    function reserveRequired() public view returns (uint256) {
        return _hlcToReserve(totalHlcIssued);
    }

    /// @notice Actual reserve balance minus `reserveRequired()`. Negative means the PSM cannot
    /// currently redeem all outstanding PSM-issued HLC at the current rate (individual withdrawals
    /// up to the shortfall will still succeed on a first-come-first-served basis, while transfers
    /// that would make the deficit worse revert safely.
    function reserveSurplus() external view returns (int256) {
        uint256 balance = reserve.balanceOf(address(this));
        uint256 required = reserveRequired();
        uint256 maxInt = uint256(type(int256).max);

        if (balance >= required) {
            uint256 surplus = balance - required;
            // The branch guarantees surplus <= maxInt before this cast.
            // forge-lint: disable-next-line(unsafe-typecast)
            return surplus > maxInt ? type(int256).max : int256(surplus);
        }

        uint256 deficit = required - balance;
        // The branch guarantees deficit <= maxInt before this cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        return deficit > maxInt ? type(int256).min : -int256(deficit);
    }

    function previewDeposit(uint256 reserveAmount) external view returns (uint256) {
        return _reserveToHlc(reserveAmount);
    }

    function previewWithdraw(uint256 hlcAmount) external view returns (uint256) {
        return _hlcToReserve(hlcAmount);
    }

    /// @notice Returns whether the PSM has accepted a CPI report within the freshness window.
    /// Deposits enforce this same condition on-chain; frontends can use this view to explain a
    /// rejected deposit before the user signs a transaction.
    function isCPIReportFresh() public view returns (bool) {
        // forge-lint: disable-next-line(block-timestamp)
        return lastReportTimestamp != 0 && block.timestamp - lastReportTimestamp <= MAX_REPORT_AGE;
    }

    // ── Oracle / rate management ─────────────────────────────────────────

    /// @notice Submits a new CPI reading using the block timestamp as the report timestamp. It is
    /// rate- and step-limited, cadence-limited after bootstrap, and reserve-limited so a
    /// malfunctioning or compromised updater cannot move the peg further than `MAX_CPI_STEP_BPS`,
    /// more often than `minUpdateInterval`, or above the reserve currently held for all outstanding
    /// PSM-issued HLC. Governance can use `mockCPI` for an explicitly approved emergency override.
    function updateCPI(uint256 reportedCPI) external onlyRole(UPDATER_ROLE) {
        _updateCPI(reportedCPI, block.timestamp);
    }

    /// @notice Submits a CPI reading together with its source publication timestamp. In addition
    /// to the normal rate, step, cadence, and reserve checks, the timestamp must be in the past,
    /// newer than the last accepted report, and no more than `MAX_REPORT_AGE` old. Production
    /// oracle relayers should prefer this entrypoint so delayed or replayed source data fails
    /// closed on-chain.
    function updateCPIWithTimestamp(uint256 reportedCPI, uint256 reportedAt) external onlyRole(UPDATER_ROLE) {
        _updateCPI(reportedCPI, reportedAt);
    }

    function _updateCPI(uint256 reportedCPI, uint256 reportedAt) internal {
        // validator timestamp manipulation is bounded to seconds, negligible against a multi-day interval
        // The first fresh report bootstraps the feed immediately. Once a report or governance
        // override has established the watermark, enforce the configured cadence between updates.
        if (lastReportTimestamp != 0) {
            // forge-lint: disable-next-line(block-timestamp)
            if (block.timestamp < lastUpdated || block.timestamp - lastUpdated < minUpdateInterval) {
                revert UpdateTooSoon();
            }
        }
        if (reportedAt == 0) revert InvalidReportTimestamp();
        // forge-lint: disable-next-line(block-timestamp)
        if (reportedAt > block.timestamp || (lastReportTimestamp != 0 && reportedAt <= lastReportTimestamp)) {
            revert InvalidReportTimestamp();
        }
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - reportedAt > MAX_REPORT_AGE) revert ReportTooOld();
        _setCPI(reportedCPI, true);
        if (reserve.balanceOf(address(this)) < reserveRequired()) revert RateWouldUnderCollateralize();
        lastReportTimestamp = reportedAt;
        emit CPIReportAccepted(reportedAt);
        emit CPIUpdated(previousCPI, cpiRate, true);
    }

    /// @notice DAO-gated emergency/manual override, bypassing the step and interval limits (still
    /// bounded to [MIN_CPI, MAX_CPI]). Intended for governance-approved corrections, e.g. oracle
    /// failure or a disputed reading.
    function mockCPI(uint256 newCPI) external onlyRole(PARAM_ROLE) {
        _setCPI(newCPI, false);
        lastReportTimestamp = block.timestamp;
        emit CPIUpdated(previousCPI, cpiRate, false);
    }

    function setSource(string calldata newSource) external onlyRole(PARAM_ROLE) {
        bytes calldata sourceBytes = bytes(newSource);
        if (sourceBytes.length == 0) revert EmptySource();
        bool hasNonWhitespace;
        for (uint256 i = 0; i < sourceBytes.length; ++i) {
            bytes1 character = sourceBytes[i];
            if (
                character != 0x09 && character != 0x0a && character != 0x0b && character != 0x0c && character != 0x0d
                    && character != 0x20
            ) {
                hasNonWhitespace = true;
                break;
            }
        }
        if (!hasNonWhitespace) revert EmptySource();
        source = newSource;
        emit SourceUpdated(newSource);
    }

    /// @notice Updates the minimum cadence for the normal CPI updater. Zero is rejected; use the
    /// DAO-gated `mockCPI` path when an emergency update must bypass the normal cadence.
    function setMinUpdateInterval(uint256 newInterval) external onlyRole(PARAM_ROLE) {
        if (newInterval == 0) revert InvalidUpdateInterval();
        minUpdateInterval = newInterval;
        emit MinUpdateIntervalUpdated(newInterval);
    }

    /// @notice DAO-approved top-up of reserves (e.g. bootstrapping liquidity from the treasury).
    function depositReserve(uint256 amount) external onlyRole(PARAM_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balanceBefore = reserve.balanceOf(address(this));
        reserve.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = reserve.balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert ZeroReceived();
        emit ReserveDeposited(msg.sender, received);
    }

    /// @notice DAO-approved withdrawal of reserve surplus. The PSM never lets this path remove the
    /// reserve required to redeem outstanding PSM-issued HLC at the current CPI rate.
    function withdrawReserve(address to, uint256 amount) external onlyRole(PARAM_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 balance = reserve.balanceOf(address(this));
        uint256 required = reserveRequired();
        if (balance < required || amount > balance - required) revert InsufficientReserve();
        uint256 recipientBalanceBefore = reserve.balanceOf(to);
        reserve.safeTransfer(to, amount);
        uint256 received = reserve.balanceOf(to) - recipientBalanceBefore;
        if (received == 0) revert ZeroReceived();
        if (reserve.balanceOf(address(this)) < reserveRequired()) revert InsufficientReserve();
        emit ReserveWithdrawn(to, received);
    }

    // ── Internal ─────────────────────────────────────────────────────────

    function _checkDeadline(uint256 deadline) internal view {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert DeadlineExpired();
    }

    /// @dev A permit can be submitted by anyone and may have been consumed before this call is
    /// mined. Ignore a failed permit and let the following transferFrom decide whether an allowance
    /// already exists; this keeps a valid action tolerant to permit frontrunning.
    function _tryPermit(address permitToken, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal {
        try IERC20Permit(permitToken).permit(msg.sender, address(this), amount, deadline, v, r, s) { } catch { }
    }

    function _checkDepositSafety() internal view {
        if (lastReportTimestamp == 0) revert CpiReportMissing();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp - lastReportTimestamp > MAX_REPORT_AGE) revert CpiReportStale();
    }

    function _setCPI(uint256 newCPI, bool enforceStepLimit) internal {
        if (newCPI < MIN_CPI || newCPI > MAX_CPI) revert RateOutOfBounds();
        if (enforceStepLimit) {
            uint256 delta = newCPI > cpiRate ? newCPI - cpiRate : cpiRate - newCPI;
            if (delta > (cpiRate * MAX_CPI_STEP_BPS) / 10_000) revert StepTooLarge();
        }
        previousCPI = cpiRate;
        cpiRate = newCPI;
        lastUpdated = block.timestamp;
    }

    function _reserveDeficit(uint256 balance, uint256 required) internal pure returns (uint256) {
        return required > balance ? required - balance : 0;
    }

    function _reserveToHlc(uint256 reserveAmount) internal view returns (uint256) {
        if (_reserveDecimals < HLC_DECIMALS) {
            uint256 downScale = 10 ** (HLC_DECIMALS - _reserveDecimals);
            // `downScale * CPI_PRECISION` is bounded by 1e24 for supported decimals. Using mulDiv
            // avoids overflowing the reserve amount times the conversion numerator when the
            // resulting HLC amount itself still fits in uint256.
            return Math.mulDiv(reserveAmount, downScale * CPI_PRECISION, cpiRate);
        }

        uint256 upScale = 10 ** (_reserveDecimals - HLC_DECIMALS);
        // Keep extra reserve-token precision through the CPI conversion instead of truncating
        // to 18 decimals first. This preserves valid sub-18-decimal deposits.
        return Math.mulDiv(reserveAmount, CPI_PRECISION, cpiRate * upScale);
    }

    function _hlcToReserve(uint256 hlcAmount) internal view returns (uint256) {
        if (_reserveDecimals < HLC_DECIMALS) {
            uint256 downScale = 10 ** (HLC_DECIMALS - _reserveDecimals);
            return Math.mulDiv(hlcAmount, cpiRate, CPI_PRECISION * downScale);
        }
        if (_reserveDecimals == HLC_DECIMALS) {
            return Math.mulDiv(hlcAmount, cpiRate, CPI_PRECISION);
        }

        uint256 upScale = 10 ** (_reserveDecimals - HLC_DECIMALS);
        // Keep the reserve token's extra precision through the CPI conversion. A two-stage
        // round-down would materially underpay tiny withdrawals when CPI is not exactly 1.0.
        return Math.mulDiv(hlcAmount, cpiRate * upScale, CPI_PRECISION);
    }
}
