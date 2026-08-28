// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { HalalPSM } from "../src/HalalPSM.sol";
import { HalalToken } from "../src/HalalToken.sol";
import { MockFeeOnTransferERC20 } from "./mocks/MockFeeOnTransferERC20.sol";
import { MockFalseReturnERC20 } from "./mocks/MockFalseReturnERC20.sol";
import { MockNoReturnERC20 } from "./mocks/MockNoReturnERC20.sol";
import { MockRebasingERC20 } from "./mocks/MockRebasingERC20.sol";
import { Deployers } from "./utils/Deployers.sol";

/// @notice Stateful actions for a reserve token that charges 1% on every user-to-user transfer.
/// Deposits are supported because HalalPSM values the balance delta; withdrawals may revert when
/// the token's extra sender debit would make the PSM undercollateralized.
contract FeeReserveHandler is Test {
    HalalPSM internal immutable psm;
    HalalToken internal immutable token;
    MockFeeOnTransferERC20 internal immutable reserve;
    address internal immutable governance;
    address internal immutable alice;
    address internal immutable bob;

    constructor(
        HalalPSM psm_,
        HalalToken token_,
        MockFeeOnTransferERC20 reserve_,
        address governance_,
        address alice_,
        address bob_
    ) {
        psm = psm_;
        token = token_;
        reserve = reserve_;
        governance = governance_;
        alice = alice_;
        bob = bob_;
    }

    function deposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(amountSeed, 1, 1e24);
        reserve.mint(actor, amount);

        vm.startPrank(actor);
        reserve.approve(address(psm), amount);
        psm.deposit(amount);
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 credit = psm.redeemableBalance(actor);
        uint256 balance = token.balanceOf(actor);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(actor);
        token.approve(address(psm), amount);
        psm.withdraw(amount);
        vm.stopPrank();
    }

    function transferRedeemable(uint256 actorSeed, uint256 amountSeed) external {
        address from = _actor(actorSeed);
        address to = from == alice ? bob : alice;
        uint256 credit = psm.redeemableBalance(from);
        uint256 balance = token.balanceOf(from);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(from);
        token.approve(address(psm), amount);
        psm.transferRedeemable(to, amount);
        vm.stopPrank();
    }

    function cancelRedeemable(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 credit = psm.redeemableBalance(actor);
        uint256 balance = token.balanceOf(actor);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(actor);
        token.approve(address(psm), amount);
        psm.cancelRedeemable(amount);
        vm.stopPrank();
    }

    function governCPI(uint256 cpiSeed) external {
        uint256 newCPI = bound(cpiSeed, psm.MIN_CPI(), psm.MAX_CPI());
        uint256 requiredAtNewRate = (psm.totalHlcIssued() * newCPI) / psm.CPI_PRECISION();
        uint256 reserveBalance = reserve.balanceOf(address(psm));

        if (requiredAtNewRate > reserveBalance) {
            uint256 gap = requiredAtNewRate - reserveBalance;
            // The token charges 100 bps on this transfer. Add one unit after rounding up so the
            // PSM receives at least the exact gap despite integer fee rounding.
            uint256 grossTopUp = (gap * 10_000) / 9_900 + 1;
            reserve.mint(governance, grossTopUp);
            vm.startPrank(governance);
            reserve.approve(address(psm), grossTopUp);
            psm.depositReserve(grossTopUp);
            vm.stopPrank();
        }

        vm.prank(governance);
        psm.mockCPI(newCPI);
    }

    function knownRedeemableCredit() external view returns (uint256) {
        return psm.redeemableBalance(alice) + psm.redeemableBalance(bob);
    }

    function _actor(uint256 seed) private view returns (address) {
        return seed % 2 == 0 ? alice : bob;
    }
}

/// @notice A false-returning reserve must never create issuance, even across repeated attempted
/// deposits. SafeERC20 is expected to revert before any PSM accounting mutation.
contract FalseReserveHandler is Test {
    HalalPSM internal immutable psm;
    MockFalseReturnERC20 internal immutable reserve;
    address internal immutable alice;

    constructor(HalalPSM psm_, MockFalseReturnERC20 reserve_, address alice_) {
        psm = psm_;
        reserve = reserve_;
        alice = alice_;
    }

    function attemptDeposit(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1e24);
        reserve.mint(alice, amount);
        vm.startPrank(alice);
        reserve.approve(address(psm), amount);
        try psm.deposit(amount) {
            fail("false-returning reserve unexpectedly succeeded");
        } catch { }
        vm.stopPrank();
    }
}

/// @notice Stateful actions for a legacy ERC-20 that omits return data from transfer functions.
/// SafeERC20 intentionally supports this common token behavior, so the full PSM accounting model
/// must remain valid across mixed issuance and redemption sequences.
contract NoReturnReserveHandler is Test {
    HalalPSM internal immutable psm;
    HalalToken internal immutable token;
    MockNoReturnERC20 internal immutable reserve;
    address internal immutable alice;
    address internal immutable bob;

    constructor(HalalPSM psm_, HalalToken token_, MockNoReturnERC20 reserve_, address alice_, address bob_) {
        psm = psm_;
        token = token_;
        reserve = reserve_;
        alice = alice_;
        bob = bob_;
    }

    function deposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 amount = bound(amountSeed, 1, 1e24);
        reserve.mint(actor, amount);

        vm.startPrank(actor);
        reserve.approve(address(psm), amount);
        psm.deposit(amount);
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 credit = psm.redeemableBalance(actor);
        uint256 balance = token.balanceOf(actor);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(actor);
        token.approve(address(psm), amount);
        psm.withdraw(amount);
        vm.stopPrank();
    }

    function transferRedeemable(uint256 actorSeed, uint256 amountSeed) external {
        address from = _actor(actorSeed);
        address to = from == alice ? bob : alice;
        uint256 credit = psm.redeemableBalance(from);
        uint256 balance = token.balanceOf(from);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(from);
        token.approve(address(psm), amount);
        psm.transferRedeemable(to, amount);
        vm.stopPrank();
    }

    function cancelRedeemable(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 credit = psm.redeemableBalance(actor);
        uint256 balance = token.balanceOf(actor);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(actor);
        token.approve(address(psm), amount);
        psm.cancelRedeemable(amount);
        vm.stopPrank();
    }

    function knownRedeemableCredit() external view returns (uint256) {
        return psm.redeemableBalance(alice) + psm.redeemableBalance(bob);
    }

    function _actor(uint256 seed) private view returns (address) {
        return seed % 2 == 0 ? alice : bob;
    }
}

/// @notice Stateful actions for a reserve whose issuer can change balances outside the PSM.
/// A negative rebase may create a reserve deficit; the PSM must not make that deficit worse through
/// a withdrawal, while HLC accounting remains conserved across successful operations.
contract RebasingReserveHandler is Test {
    HalalPSM internal immutable psm;
    HalalToken internal immutable token;
    MockRebasingERC20 internal immutable reserve;
    address internal immutable alice;

    constructor(HalalPSM psm_, HalalToken token_, MockRebasingERC20 reserve_, address alice_) {
        psm = psm_;
        token = token_;
        reserve = reserve_;
        alice = alice_;
    }

    function deposit(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1e24);
        reserve.mint(alice, amount);
        vm.startPrank(alice);
        reserve.approve(address(psm), amount);
        try psm.deposit(amount) { } catch { }
        vm.stopPrank();
    }

    function withdraw(uint256 amountSeed) external {
        uint256 credit = psm.redeemableBalance(alice);
        uint256 balance = token.balanceOf(alice);
        uint256 maximum = credit < balance ? credit : balance;
        if (maximum == 0) return;

        uint256 amount = bound(amountSeed, 1, maximum);
        vm.startPrank(alice);
        token.approve(address(psm), amount);
        try psm.withdraw(amount) { } catch { }
        vm.stopPrank();
    }

    function rebasePsm(uint256 amountSeed) external {
        uint256 balance = reserve.balanceOf(address(psm));
        if (amountSeed % 2 == 0) {
            reserve.rebase(address(psm), int256(bound(amountSeed, 1, 1e24)));
        } else if (balance != 0) {
            reserve.rebase(address(psm), -int256(bound(amountSeed, 1, balance)));
        }
    }

    function rebaseAlice(uint256 amountSeed) external {
        uint256 balance = reserve.balanceOf(alice);
        if (amountSeed % 2 == 0) {
            reserve.rebase(alice, int256(bound(amountSeed, 1, 1e24)));
        } else if (balance != 0) {
            reserve.rebase(alice, -int256(bound(amountSeed, 1, balance)));
        }
    }

    function knownRedeemableCredit() external view returns (uint256) {
        return psm.redeemableBalance(alice);
    }
}

contract HalalPSMAdversarialInvariantTest is Deployers {
    address internal feeAlice = makeAddr("feeInvariantAlice");
    address internal feeBob = makeAddr("feeInvariantBob");
    MockFeeOnTransferERC20 internal feeReserve;
    HalalPSM internal feePsm;
    FeeReserveHandler internal feeHandler;

    function setUp() public {
        deployAll();
        feeReserve = new MockFeeOnTransferERC20(100);
        feePsm = new HalalPSM(address(feeReserve), address(token), address(timelock), address(0xBEEF));
        _grantPsmTokenRoles(feePsm);
        feeHandler = new FeeReserveHandler(feePsm, token, feeReserve, address(timelock), feeAlice, feeBob);
        targetContract(address(feeHandler));
    }

    function invariant_FeeReserveCreditConservation() public view {
        assertEq(feeHandler.knownRedeemableCredit(), feePsm.totalHlcIssued());
    }

    function invariant_FeeReserveSupplyRemainsCollateralized() public view {
        assertGe(feeReserve.balanceOf(address(feePsm)), feePsm.reserveRequired());
    }

    function invariant_FeeReserveTokenSupplyDecomposition() public view {
        assertEq(token.totalSupply(), 10_000_000e18 + feePsm.totalHlcIssued());
    }

    function _grantPsmTokenRoles(HalalPSM target) internal {
        vm.startPrank(address(timelock));
        token.grantRole(token.MINTER_ROLE(), address(target));
        token.grantRole(token.BURNER_ROLE(), address(target));
        vm.stopPrank();
        vm.prank(address(0xBEEF));
        target.updateCPI(1_000_000);
    }
}

contract HalalPSMFalseReserveInvariantTest is Deployers {
    MockFalseReturnERC20 internal falseReserve;
    HalalPSM internal falsePsm;
    FalseReserveHandler internal falseHandler;

    function setUp() public {
        deployAll();
        falseReserve = new MockFalseReturnERC20();
        falsePsm = new HalalPSM(address(falseReserve), address(token), address(timelock), address(0xBEEF));
        vm.startPrank(address(timelock));
        token.grantRole(token.MINTER_ROLE(), address(falsePsm));
        token.grantRole(token.BURNER_ROLE(), address(falsePsm));
        vm.stopPrank();
        vm.prank(address(0xBEEF));
        falsePsm.updateCPI(1_000_000);

        falseHandler = new FalseReserveHandler(falsePsm, falseReserve, makeAddr("falseInvariantAlice"));
        targetContract(address(falseHandler));
    }

    function invariant_FalseReserveCannotIssueHLC() public view {
        assertEq(falsePsm.totalHlcIssued(), 0);
        assertEq(falsePsm.redeemableBalance(address(falseHandler)), 0);
        assertEq(falseReserve.balanceOf(address(falsePsm)), 0);
    }

    function invariant_FalseReserveCannotChangeTokenSupply() public view {
        assertEq(token.totalSupply(), 10_000_000e18);
    }
}

contract HalalPSMNoReturnReserveInvariantTest is Deployers {
    address internal noReturnAlice = makeAddr("noReturnInvariantAlice");
    address internal noReturnBob = makeAddr("noReturnInvariantBob");
    MockNoReturnERC20 internal noReturnReserve;
    HalalPSM internal noReturnPsm;
    NoReturnReserveHandler internal noReturnHandler;

    function setUp() public {
        deployAll();
        noReturnReserve = new MockNoReturnERC20();
        noReturnPsm = new HalalPSM(address(noReturnReserve), address(token), address(timelock), address(0xBEEF));
        _grantPsmTokenRoles(noReturnPsm);
        noReturnHandler = new NoReturnReserveHandler(noReturnPsm, token, noReturnReserve, noReturnAlice, noReturnBob);
        targetContract(address(noReturnHandler));
    }

    function invariant_NoReturnReserveCreditConservation() public view {
        assertEq(noReturnHandler.knownRedeemableCredit(), noReturnPsm.totalHlcIssued());
    }

    function invariant_NoReturnReserveRemainsCollateralized() public view {
        assertGe(noReturnReserve.balanceOf(address(noReturnPsm)), noReturnPsm.reserveRequired());
    }

    function invariant_NoReturnReserveSupplyDecomposition() public view {
        assertEq(token.totalSupply(), 10_000_000e18 + noReturnPsm.totalHlcIssued());
    }

    function _grantPsmTokenRoles(HalalPSM target) internal {
        vm.startPrank(address(timelock));
        token.grantRole(token.MINTER_ROLE(), address(target));
        token.grantRole(token.BURNER_ROLE(), address(target));
        vm.stopPrank();
        vm.prank(address(0xBEEF));
        target.updateCPI(1_000_000);
    }
}

contract HalalPSMRebasingReserveInvariantTest is Deployers {
    address internal rebasingAlice = makeAddr("rebasingInvariantAlice");
    MockRebasingERC20 internal rebasingReserve;
    HalalPSM internal rebasingPsm;
    RebasingReserveHandler internal rebasingHandler;

    function setUp() public {
        deployAll();
        rebasingReserve = new MockRebasingERC20();
        rebasingPsm = new HalalPSM(address(rebasingReserve), address(token), address(timelock), address(0xBEEF));
        vm.startPrank(address(timelock));
        token.grantRole(token.MINTER_ROLE(), address(rebasingPsm));
        token.grantRole(token.BURNER_ROLE(), address(rebasingPsm));
        vm.stopPrank();
        vm.prank(address(0xBEEF));
        rebasingPsm.updateCPI(1_000_000);

        rebasingHandler = new RebasingReserveHandler(rebasingPsm, token, rebasingReserve, rebasingAlice);
        targetContract(address(rebasingHandler));
    }

    function invariant_RebasingReserveCreditConservation() public view {
        assertEq(rebasingHandler.knownRedeemableCredit(), rebasingPsm.totalHlcIssued());
    }

    function invariant_RebasingReserveTokenSupplyDecomposition() public view {
        assertEq(token.totalSupply(), 10_000_000e18 + rebasingPsm.totalHlcIssued());
    }
}

/// @notice Regression coverage for a reserve loss occurring between PSM operations.
contract HalalPSMRebasingReserveTest is Deployers {
    address internal rebasingAlice = makeAddr("rebasingRegressionAlice");
    MockRebasingERC20 internal rebasingReserve;
    HalalPSM internal rebasingPsm;

    function setUp() public {
        deployAll();
        rebasingReserve = new MockRebasingERC20();
        rebasingPsm = new HalalPSM(address(rebasingReserve), address(token), address(timelock), address(0xBEEF));

        vm.startPrank(address(timelock));
        token.grantRole(token.MINTER_ROLE(), address(rebasingPsm));
        token.grantRole(token.BURNER_ROLE(), address(rebasingPsm));
        vm.stopPrank();
        vm.prank(address(0xBEEF));
        rebasingPsm.updateCPI(1_000_000);
    }

    function test_RebasingLossBlocksWithdrawalThatWorsensDeficit() public {
        rebasingReserve.mint(rebasingAlice, 1_000e18);
        vm.startPrank(rebasingAlice);
        rebasingReserve.approve(address(rebasingPsm), 1_000e18);
        rebasingPsm.deposit(1_000e18);
        vm.stopPrank();

        rebasingReserve.rebase(address(rebasingPsm), -int256(100e18));
        assertEq(rebasingReserve.balanceOf(address(rebasingPsm)), 900e18);
        assertEq(rebasingPsm.reserveRequired(), 1_000e18);
        assertEq(rebasingPsm.reserveSurplus(), -int256(100e18));

        vm.startPrank(rebasingAlice);
        token.approve(address(rebasingPsm), 1_000e18);
        vm.expectRevert(HalalPSM.InsufficientReserve.selector);
        rebasingPsm.withdraw(1_000e18);
        rebasingPsm.withdraw(100e18);
        vm.stopPrank();

        assertEq(rebasingReserve.balanceOf(address(rebasingPsm)), 800e18);
        assertEq(rebasingPsm.reserveRequired(), 900e18);
        assertEq(rebasingPsm.reserveSurplus(), -int256(100e18));
        assertEq(token.balanceOf(rebasingAlice), 900e18);
        assertEq(rebasingPsm.redeemableBalance(rebasingAlice), 900e18);
    }
}
