// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Deployers } from "./utils/Deployers.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { Governor } from "@openzeppelin/contracts/governance/Governor.sol";
import { HalalVesting } from "../src/HalalVesting.sol";
import { HalalPSM } from "../src/HalalPSM.sol";
import { HalalDAO } from "../src/HalalDAO.sol";
import { HalalTimelock } from "../src/HalalTimelock.sol";

contract MockGovernedModule { }

contract HalalDAOTest is Deployers {
    address internal voter = makeAddr("voter");
    address internal smallHolder = makeAddr("smallHolder");

    function setUp() public {
        deployAll();
        // ~5% of post-deposit supply, comfortably above both the 100 HLC proposal threshold and the 4% quorum
        giveVotingPower(voter, 550_000e18);
    }

    // ── Setup & role wiring ──────────────────────────────────────────────

    function test_InitialState() public view {
        assertEq(token.balanceOf(address(teamVesting)) + token.balanceOf(address(treasuryVesting)), 10_000_000e18);
        assertEq(teamVesting.beneficiary(), teamBeneficiary);
        assertEq(treasuryVesting.beneficiary(), treasuryBeneficiary);
        assertEq(teamVesting.cliff(), 365 days);
        assertEq(teamVesting.duration(), 4 * 365 days);
        assertTrue(teamVesting.revocable());
        assertEq(treasuryVesting.cliff(), 0);
        assertEq(treasuryVesting.duration(), 3 * 365 days);
        assertFalse(treasuryVesting.revocable());
    }

    function test_RolesTransferredToDAO() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertTrue(psm.hasRole(psm.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(dao)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer));
    }

    // ── Governance parameters ───────────────────────────────────────────

    function test_ProposalThreshold() public view {
        assertEq(dao.proposalThreshold(), 100e18);
    }

    function test_Quorum() public view {
        assertEq(dao.quorumNumerator(), 4);
        assertEq(dao.quorumDenominator(), 100);
        assertEq(dao.quorum(block.number - 1), (token.getPastTotalSupply(block.number - 1) * 4) / 100);
    }

    function test_VotingDelay() public view {
        assertEq(dao.votingDelay(), VOTING_DELAY);
    }

    function test_VotingPeriod() public view {
        assertEq(dao.votingPeriod(), VOTING_PERIOD);
    }

    function test_TimelockDelay() public view {
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    }

    function test_ProposalNeedsQueuingUsesTimelockPolicy() public view {
        assertTrue(dao.proposalNeedsQueuing(0));
    }

    function test_RevertWhen_DAOHasZeroToken() public {
        vm.expectRevert();
        new HalalDAO(IVotes(address(0)), timelock, 1, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_PERCENT);
    }

    function test_RevertWhen_DAOHasZeroTimelock() public {
        vm.expectRevert(HalalDAO.ZeroAddress.selector);
        new HalalDAO(token, HalalTimelock(payable(address(0))), 1, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_PERCENT);
    }

    function test_RevertWhen_DAOHasNonContractDependency() public {
        // GovernorVotes probes the voting token's clock during base construction, so an EOA token
        // may fail before HalalDAO's explicit dependency guard; either way deployment must revert.
        vm.expectRevert();
        new HalalDAO(IVotes(address(1)), timelock, 1, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_PERCENT);

        vm.expectRevert(HalalDAO.NotContract.selector);
        new HalalDAO(token, HalalTimelock(payable(address(1))), 1, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_PERCENT);
    }

    function test_RevertWhen_DAOVotingPeriodIsZero() public {
        vm.expectRevert();
        new HalalDAO(token, timelock, 1, 0, PROPOSAL_THRESHOLD, QUORUM_PERCENT);
    }

    function test_RevertWhen_DAOQuorumIsZero() public {
        vm.expectRevert(HalalDAO.InvalidQuorum.selector);
        new HalalDAO(token, timelock, 1, VOTING_PERIOD, PROPOSAL_THRESHOLD, 0);
    }

    function test_RevertWhen_DAOProposalThresholdIsZero() public {
        vm.expectRevert(HalalDAO.InvalidProposalThreshold.selector);
        new HalalDAO(token, timelock, 1, VOTING_PERIOD, 0, QUORUM_PERCENT);
    }

    function test_RevertWhen_TimelockDelayIsZero() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.expectRevert(HalalTimelock.ZeroDelay.selector);
        new HalalTimelock(0, proposers, executors, address(this));
    }

    // ── Proposal creation ────────────────────────────────────────────────

    function _psmCPIProposal(uint256 newCPI)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        targets = new address[](1);
        targets[0] = address(0); // filled in by caller
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(HalalPSM.mockCPI, (newCPI));
        desc = "Update CPI";
    }

    function test_CreateProposal_UpdateCPI() public {
        address[] memory targets = new address[](1);
        targets[0] = address(psm);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(HalalPSM.mockCPI, (1_100_000));

        vm.prank(voter);
        uint256 proposalId = dao.propose(targets, values, calldatas, "Update CPI");

        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
    }

    function test_CreateProposal_GrantMinterRole() public {
        address newModule = address(new MockGovernedModule());
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(token.grantRole, (token.MINTER_ROLE(), newModule));

        vm.prank(voter);
        uint256 proposalId = dao.propose(targets, values, calldatas, "Add Lending Module");
        assertGt(proposalId, 0);
    }

    function test_FailProposal_BelowThreshold() public {
        giveVotingPower(smallHolder, 50e18); // below the 100 HLC threshold
        address[] memory targets = new address[](1);
        targets[0] = address(psm);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(HalalPSM.mockCPI, (1_100_000));

        vm.prank(smallHolder);
        vm.expectRevert();
        dao.propose(targets, values, calldatas, "Should fail");
    }

    function test_MultiTargetProposal() public {
        address[] memory targets = new address[](2);
        targets[0] = address(psm);
        targets[1] = address(psm);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeCall(HalalPSM.mockCPI, (1_050_000));
        calldatas[1] = abi.encodeCall(HalalPSM.setSource, ("https://example.com/cpi.js"));

        vm.prank(voter);
        uint256 proposalId = dao.propose(targets, values, calldatas, "Two actions");
        assertGt(proposalId, 0);
    }

    // ── Voting ───────────────────────────────────────────────────────────

    struct Proposal {
        uint256 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
    }

    function _proposeCPIUpdate(uint256 newCPI, string memory description) internal returns (Proposal memory p) {
        p.targets = new address[](1);
        p.targets[0] = address(psm);
        p.values = new uint256[](1);
        p.calldatas = new bytes[](1);
        p.calldatas[0] = abi.encodeCall(HalalPSM.mockCPI, (newCPI));
        p.descriptionHash = keccak256(bytes(description));

        vm.prank(voter);
        p.id = dao.propose(p.targets, p.values, p.calldatas, description);
    }

    function _rollToActive() internal {
        vm.roll(block.number + dao.votingDelay() + 1);
    }

    function _rollToVotingEnd() internal {
        vm.roll(block.number + dao.votingPeriod() + 1);
    }

    function test_CastVote_For() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "For vote");
        _rollToActive();

        vm.prank(voter);
        dao.castVote(p.id, 1);

        (uint256 against, uint256 forVotes, uint256 abstain) = dao.proposalVotes(p.id);
        assertEq(forVotes, 550_000e18);
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    function test_CastVote_Against() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Against vote");
        _rollToActive();

        vm.prank(voter);
        dao.castVote(p.id, 0);

        (uint256 against,,) = dao.proposalVotes(p.id);
        assertEq(against, 550_000e18);
    }

    function test_CastVote_Abstain() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Abstain vote");
        _rollToActive();

        vm.prank(voter);
        dao.castVote(p.id, 2);

        (,, uint256 abstain) = dao.proposalVotes(p.id);
        assertEq(abstain, 550_000e18);
    }

    function test_RevertWhen_DuplicateVote() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Duplicate vote");
        _rollToActive();

        vm.startPrank(voter);
        dao.castVote(p.id, 1);
        vm.expectRevert();
        dao.castVote(p.id, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteBeforeActive() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Too early");
        vm.prank(voter);
        vm.expectRevert();
        dao.castVote(p.id, 1);
    }

    function test_VotingPowerSnapshot() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Snapshot test");
        _rollToActive();

        // acquire voting power *after* the snapshot has already been taken
        giveVotingPower(smallHolder, 10_000e18);

        vm.prank(smallHolder);
        dao.castVote(p.id, 1); // does not revert, but contributes zero weight

        (, uint256 forVotes,) = dao.proposalVotes(p.id);
        assertEq(forVotes, 0);
    }

    // ── Execution ────────────────────────────────────────────────────────

    function _passProposal(Proposal memory p) internal {
        _rollToActive();
        vm.prank(voter);
        dao.castVote(p.id, 1);
        _rollToVotingEnd();
    }

    function test_ProposalState_Transitions() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Lifecycle");
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Pending));

        _rollToActive();
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Active));

        vm.prank(voter);
        dao.castVote(p.id, 1);
        _rollToVotingEnd();
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Succeeded));

        dao.queue(p.targets, p.values, p.calldatas, p.descriptionHash);
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        dao.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Executed));
    }

    function test_FullProposalFlow() public {
        Proposal memory p = _proposeCPIUpdate(1_200_000, "Full flow");
        _passProposal(p);

        dao.queue(p.targets, p.values, p.calldatas, p.descriptionHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        dao.execute(p.targets, p.values, p.calldatas, p.descriptionHash);

        assertEq(psm.cpiRate(), 1_200_000);
    }

    function test_TimelockPreventsImmediateExecution() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "No rush");
        _passProposal(p);
        dao.queue(p.targets, p.values, p.calldatas, p.descriptionHash);

        vm.expectRevert();
        dao.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
    }

    function test_RevertWhen_QueueBeforeSucceeded() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Premature queue");
        _rollToActive();

        vm.expectRevert();
        dao.queue(p.targets, p.values, p.calldatas, p.descriptionHash);
    }

    function test_ZeroVotes() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "No one votes");
        _rollToActive();
        _rollToVotingEnd();
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_ProposalDefeatedIfAgainstExceedsFor() public {
        giveVotingPower(smallHolder, 600_000e18);
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Contested");
        _rollToActive();

        vm.prank(voter);
        dao.castVote(p.id, 1); // 550k for
        vm.prank(smallHolder);
        dao.castVote(p.id, 0); // 600k against

        _rollToVotingEnd();
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_ProposalCancellation() public {
        Proposal memory p = _proposeCPIUpdate(1_100_000, "Cancel me");
        vm.prank(voter);
        dao.cancel(p.targets, p.values, p.calldatas, p.descriptionHash);
        assertEq(uint8(dao.state(p.id)), uint8(IGovernor.ProposalState.Canceled));
    }

    // ── DAO control over the rest of the system ─────────────────────────

    function test_DAO_ControlsPSM_AfterTakeover() public {
        Proposal memory p = _proposeCPIUpdate(1_500_000, "DAO controls PSM");
        _passProposal(p);
        dao.queue(p.targets, p.values, p.calldatas, p.descriptionHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        dao.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
        assertEq(psm.cpiRate(), 1_500_000);
    }

    function test_DAO_ControlsToken_CanGrantMinterRole() public {
        address newModule = address(new MockGovernedModule());
        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(token.grantRole, (token.MINTER_ROLE(), newModule));
        bytes32 descHash = keccak256(bytes("Grant minter to staking module"));

        vm.prank(voter);
        uint256 proposalId = dao.propose(targets, values, calldatas, "Grant minter to staking module");

        _rollToActive();
        vm.prank(voter);
        dao.castVote(proposalId, 1);
        _rollToVotingEnd();

        dao.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        dao.execute(targets, values, calldatas, descHash);

        assertTrue(token.hasRole(token.MINTER_ROLE(), newModule));
    }

    function test_DAO_ControlsVesting_CanRevoke() public {
        address[] memory targets = new address[](1);
        targets[0] = address(teamVesting);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(HalalVesting.revoke, ());
        bytes32 descHash = keccak256(bytes("EMERGENCY: Revoke team vesting"));

        vm.prank(voter);
        uint256 proposalId = dao.propose(targets, values, calldatas, "EMERGENCY: Revoke team vesting");

        _rollToActive();
        vm.prank(voter);
        dao.castVote(proposalId, 1);
        _rollToVotingEnd();

        dao.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        dao.execute(targets, values, calldatas, descHash);

        assertTrue(teamVesting.revoked());
    }

    function test_EmergencyExecute_RevokeReturnsFundsToTimelock() public {
        vm.warp(block.timestamp + 2 * 365 days); // halfway through team vesting

        address[] memory targets = new address[](1);
        targets[0] = address(teamVesting);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(HalalVesting.revoke, ());
        bytes32 descHash = keccak256(bytes("Emergency revoke"));

        vm.prank(voter);
        uint256 proposalId = dao.propose(targets, values, calldatas, "Emergency revoke");
        _rollToActive();
        vm.prank(voter);
        dao.castVote(proposalId, 1);
        _rollToVotingEnd();
        dao.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // snapshot right before execution -- vesting keeps accruing through the voting period and
        // timelock delay, so "vested" must be measured at the moment revoke() actually runs
        uint256 vestedAtExecution = teamVesting.vestedAmount(uint64(block.timestamp));
        dao.execute(targets, values, calldatas, descHash);

        assertEq(token.balanceOf(address(timelock)), 6_000_000e18 - vestedAtExecution);
    }
}
