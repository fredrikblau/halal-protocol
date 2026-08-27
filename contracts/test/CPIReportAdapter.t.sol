// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { CPIReportAdapter } from "../src/CPIReportAdapter.sol";
import { CPIAdapterGovernance } from "../src/CPIAdapterGovernance.sol";
import { HalalPSM } from "../src/HalalPSM.sol";
import { HalalToken } from "../src/HalalToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { MockCPIReportSink } from "./mocks/MockCPIReportSink.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract CPIAdapterGovernanceHarness {
    function buildHandoff(address psm, address adapter, string calldata source, address oldUpdater)
        external
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        return CPIAdapterGovernance.buildHandoff(psm, adapter, source, oldUpdater);
    }
}

contract MockNoOpCPIReportSink {
    function updateCPIWithTimestamp(uint256, uint256) external { }

    function lastReportTimestamp() external pure returns (uint256) {
        return 0;
    }
}

contract CPIReportAdapterTest is Test {
    uint256 internal constant SIGNER_ONE_KEY = 0xA11CE;
    uint256 internal constant SIGNER_TWO_KEY = 0xB0B;
    uint256 internal constant SIGNER_THREE_KEY = 0xC0DE;
    bytes32 internal constant SOURCE_ID = keccak256("official-cpi-series-v1");

    address internal signerOne;
    address internal signerTwo;
    address internal signerThree;
    MockCPIReportSink internal sink;
    CPIReportAdapter internal adapter;

    function setUp() public {
        vm.warp(100 days);
        signerOne = vm.addr(SIGNER_ONE_KEY);
        signerTwo = vm.addr(SIGNER_TWO_KEY);
        signerThree = vm.addr(SIGNER_THREE_KEY);
        address[] memory signers = new address[](3);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        signers[2] = signerThree;
        sink = new MockCPIReportSink();
        adapter = new CPIReportAdapter(address(sink), address(this), signers, 2, SOURCE_ID);
    }

    function test_SubmitsQuorumReportToSink() public {
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReport(1_010_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);

        adapter.submitReport(1_010_000, reportedAt, signatures);

        assertEq(sink.lastCPI(), 1_010_000);
        assertEq(sink.lastReportTimestamp(), reportedAt);
        assertEq(sink.lastCaller(), address(adapter));
        assertEq(adapter.lastSubmittedTimestamp(), reportedAt);
    }

    function test_ForwardsReportToHalalPSM() public {
        MockERC20 reserve = new MockERC20("Mock DAI", "mDAI", 18);
        HalalToken token = new HalalToken(address(this));
        HalalPSM psm = new HalalPSM(address(reserve), address(token), address(this), address(0));
        address[] memory signers = new address[](2);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        CPIReportAdapter psmAdapter = new CPIReportAdapter(address(psm), address(this), signers, 2, SOURCE_ID);
        psm.grantRole(psm.UPDATER_ROLE(), address(psmAdapter));

        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReportFor(psmAdapter, 1_010_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);
        psmAdapter.submitReport(1_010_000, reportedAt, signatures);

        assertEq(psm.cpiRate(), 1_010_000);
        assertEq(psm.lastReportTimestamp(), reportedAt);
    }

    function test_RevertWhen_ReportHasOnlyOneSignature() public {
        bytes[] memory signatures = _signReport(1_000_000, block.timestamp - 1, SIGNER_ONE_KEY);
        vm.expectRevert(CPIReportAdapter.InvalidSignatureCount.selector);
        adapter.submitReport(1_000_000, block.timestamp - 1, signatures);
    }

    function test_RevertWhen_SignaturesUseAnotherSourceId() public {
        address[] memory signers = new address[](3);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        signers[2] = signerThree;
        CPIReportAdapter otherSource =
            new CPIReportAdapter(address(sink), address(this), signers, 2, keccak256("official-cpi-series-v2"));
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReportFor(otherSource, 1_000_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);

        vm.expectRevert(CPIReportAdapter.UnauthorizedSigner.selector);
        adapter.submitReport(1_000_000, reportedAt, signatures);
    }

    function test_RevertWhen_SignerIsNotAuthorized() public {
        uint256 outsiderKey = 0xD00D;
        bytes[] memory signatures = _signReport(1_000_000, block.timestamp - 1, SIGNER_ONE_KEY, outsiderKey);
        vm.expectRevert(CPIReportAdapter.UnauthorizedSigner.selector);
        adapter.submitReport(1_000_000, block.timestamp - 1, signatures);
    }

    function test_RevertWhen_SignaturesAreNotSorted() public {
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = new bytes[](2);
        if (signerOne < signerTwo) {
            signatures[0] = _signature(1_000_000, reportedAt, SIGNER_TWO_KEY);
            signatures[1] = _signature(1_000_000, reportedAt, SIGNER_ONE_KEY);
        } else {
            signatures[0] = _signature(1_000_000, reportedAt, SIGNER_ONE_KEY);
            signatures[1] = _signature(1_000_000, reportedAt, SIGNER_TWO_KEY);
        }
        vm.expectRevert(CPIReportAdapter.SignaturesNotSorted.selector);
        adapter.submitReport(1_000_000, reportedAt, signatures);
    }

    function test_RevertWhen_SameSignerIsSubmittedTwice() public {
        uint256 reportedAt = block.timestamp - 1;
        bytes memory signature = _signature(1_000_000, reportedAt, SIGNER_ONE_KEY);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = signature;
        signatures[1] = signature;

        vm.expectRevert(CPIReportAdapter.SignaturesNotSorted.selector);
        adapter.submitReport(1_000_000, reportedAt, signatures);
    }

    function test_RevertWhen_SignatureWasCreatedOnAnotherChain() public {
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReport(1_000_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);

        vm.chainId(31_338);
        vm.expectRevert(CPIReportAdapter.UnauthorizedSigner.selector);
        adapter.submitReport(1_000_000, reportedAt, signatures);
    }

    function test_RevertWhen_ReportTimestampDoesNotIncrease() public {
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReport(1_000_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);
        adapter.submitReport(1_000_000, reportedAt, signatures);

        vm.expectRevert(CPIReportAdapter.ReportTimestampNotIncreasing.selector);
        adapter.submitReport(1_010_000, reportedAt, signatures);
    }

    function test_RevertWhen_ReportTimestampIsInTheFuture() public {
        uint256 reportedAt = block.timestamp + 1;
        bytes[] memory signatures = _signReport(1_000_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);
        vm.expectRevert(CPIReportAdapter.InvalidReportTimestamp.selector);
        adapter.submitReport(1_000_000, reportedAt, signatures);
    }

    function test_OwnerCanRotateSignersWithoutBreakingQuorum() public {
        uint256 replacementKey = 0xE11E;
        address replacement = vm.addr(replacementKey);
        adapter.removeSigner(signerThree);
        adapter.addSigner(replacement);

        assertFalse(adapter.isSigner(signerThree));
        assertTrue(adapter.isSigner(replacement));
        assertEq(adapter.signerCount(), 3);

        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReport(1_010_000, reportedAt, SIGNER_ONE_KEY, replacementKey);
        adapter.submitReport(1_010_000, reportedAt, signatures);
        assertEq(sink.lastCPI(), 1_010_000);
    }

    function test_RevertWhen_ConstructorSignerIsOwner() public {
        address[] memory signers = new address[](2);
        signers[0] = address(this);
        signers[1] = signerOne;

        vm.expectRevert(CPIReportAdapter.InvalidSignerSet.selector);
        new CPIReportAdapter(address(sink), address(this), signers, 2, SOURCE_ID);
    }

    function test_RevertWhen_AdapterPsmIsNotContract() public {
        address[] memory signers = new address[](2);
        signers[0] = signerOne;
        signers[1] = signerTwo;

        vm.expectRevert(CPIReportAdapter.NotContract.selector);
        new CPIReportAdapter(address(1), address(this), signers, 2, SOURCE_ID);
    }

    function test_RevertWhen_SinkDoesNotAcceptReport() public {
        MockNoOpCPIReportSink noOpSink = new MockNoOpCPIReportSink();
        address[] memory signers = new address[](2);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        CPIReportAdapter noOpAdapter = new CPIReportAdapter(address(noOpSink), address(this), signers, 2, SOURCE_ID);
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReportFor(noOpAdapter, 1_000_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);

        vm.expectRevert(CPIReportAdapter.ReportNotAccepted.selector);
        noOpAdapter.submitReport(1_000_000, reportedAt, signatures);

        assertEq(noOpAdapter.lastSubmittedTimestamp(), 0);
    }

    function test_RevertWhen_OwnerIsAddedAsSigner() public {
        vm.expectRevert(CPIReportAdapter.SignerOwnerOverlap.selector);
        adapter.addSigner(address(this));
    }

    function test_RevertWhen_OwnershipTransferTargetsSigner() public {
        vm.expectRevert(CPIReportAdapter.SignerOwnerOverlap.selector);
        adapter.transferOwnership(signerOne);
    }

    function test_RevertWhen_PendingOwnerIsAddedAsSigner() public {
        address newOwner = address(0xCAFE);
        adapter.transferOwnership(newOwner);

        vm.expectRevert(CPIReportAdapter.SignerOwnerOverlap.selector);
        adapter.addSigner(newOwner);
    }

    function test_RevertWhen_RemovedSignerSubmitsReport() public {
        adapter.removeSigner(signerThree);
        uint256 reportedAt = block.timestamp - 1;
        bytes[] memory signatures = _signReport(1_000_000, reportedAt, SIGNER_TWO_KEY, SIGNER_THREE_KEY);

        vm.expectRevert(CPIReportAdapter.UnauthorizedSigner.selector);
        adapter.submitReport(1_000_000, reportedAt, signatures);
    }

    function test_RevertWhen_SinkRejectsStaleReport() public {
        MockERC20 reserve = new MockERC20("Mock DAI", "mDAI", 18);
        HalalToken token = new HalalToken(address(this));
        HalalPSM psm = new HalalPSM(address(reserve), address(token), address(this), address(0));
        address[] memory signers = new address[](2);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        CPIReportAdapter psmAdapter = new CPIReportAdapter(address(psm), address(this), signers, 2, SOURCE_ID);
        psm.grantRole(psm.UPDATER_ROLE(), address(psmAdapter));

        vm.warp(block.timestamp + 91 days);
        uint256 reportedAt = block.timestamp - psm.MAX_REPORT_AGE() - 1;
        bytes[] memory signatures = _signReportFor(psmAdapter, 1_000_000, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);

        vm.expectRevert(HalalPSM.ReportTooOld.selector);
        psmAdapter.submitReport(1_000_000, reportedAt, signatures);

        assertEq(psm.lastReportTimestamp(), 0);
        assertEq(psmAdapter.lastSubmittedTimestamp(), 0);
    }

    function test_RevertWhen_SinkRejectsOutOfRangeReport() public {
        MockERC20 reserve = new MockERC20("Mock DAI", "mDAI", 18);
        HalalToken token = new HalalToken(address(this));
        HalalPSM psm = new HalalPSM(address(reserve), address(token), address(this), address(0));
        address[] memory signers = new address[](2);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        CPIReportAdapter psmAdapter = new CPIReportAdapter(address(psm), address(this), signers, 2, SOURCE_ID);
        psm.grantRole(psm.UPDATER_ROLE(), address(psmAdapter));

        uint256 reportedAt = block.timestamp - 1;
        uint256 outOfRangeCpi = psm.MAX_CPI() + 1;
        bytes[] memory signatures =
            _signReportFor(psmAdapter, outOfRangeCpi, reportedAt, SIGNER_ONE_KEY, SIGNER_TWO_KEY);

        vm.expectRevert(HalalPSM.RateOutOfBounds.selector);
        psmAdapter.submitReport(outOfRangeCpi, reportedAt, signatures);

        assertEq(psm.lastReportTimestamp(), 0);
        assertEq(psmAdapter.lastSubmittedTimestamp(), 0);
    }

    function test_EnumeratesSignerSetAfterRotation() public {
        uint256 replacementKey = 0xE11E;
        address replacement = vm.addr(replacementKey);

        adapter.removeSigner(signerTwo);
        adapter.addSigner(replacement);

        address[] memory currentSigners = adapter.getSigners();
        assertEq(currentSigners.length, 3);
        assertEq(currentSigners[0], signerOne);
        assertEq(currentSigners[1], signerThree);
        assertEq(currentSigners[2], replacement);
        assertEq(adapter.signerCount(), currentSigners.length);
        assertEq(adapter.signerAt(0), signerOne);
        assertEq(adapter.signerAt(1), signerThree);
        assertEq(adapter.signerAt(2), replacement);
        assertFalse(adapter.isSigner(signerTwo));
        assertTrue(adapter.isSigner(signerThree));
        assertTrue(adapter.isSigner(replacement));
    }

    function test_RevertWhen_OwnerRemovesSignerBelowThreshold() public {
        adapter.setThreshold(3);
        vm.expectRevert(CPIReportAdapter.InvalidThreshold.selector);
        adapter.removeSigner(signerOne);
    }

    function test_RevertWhen_SignerSetExceedsGasSafeMaximum() public {
        address[] memory signers = new address[](adapter.MAX_SIGNERS() + 1);
        for (uint256 i = 0; i < signers.length; ++i) {
            signers[i] = vm.addr(i + 1_000);
        }

        vm.expectRevert(CPIReportAdapter.SignerSetTooLarge.selector);
        new CPIReportAdapter(address(sink), address(this), signers, 1, SOURCE_ID);

        address[] memory maximumSigners = new address[](adapter.MAX_SIGNERS());
        for (uint256 i = 0; i < maximumSigners.length; ++i) {
            maximumSigners[i] = vm.addr(i + 2_000);
        }
        CPIReportAdapter maximumAdapter =
            new CPIReportAdapter(address(sink), address(this), maximumSigners, 1, SOURCE_ID);

        vm.expectRevert(CPIReportAdapter.SignerSetTooLarge.selector);
        maximumAdapter.addSigner(vm.addr(9_999));
    }

    function test_BuildsDecodeableGovernanceHandoff() public view {
        address oldUpdater = address(0xBEEF);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            CPIAdapterGovernance.buildHandoff(address(sink), address(adapter), "BLS:CUUR0000SA0", oldUpdater);

        assertEq(targets.length, 3);
        assertEq(values.length, 3);
        assertEq(calldatas.length, 3);
        assertEq(targets[0], address(sink));
        assertEq(targets[1], address(sink));
        assertEq(targets[2], address(sink));
        assertEq(values[0], 0);
        assertEq(values[1], 0);
        assertEq(values[2], 0);
        assertEq(calldatas[0], abi.encodeCall(IAccessControl.grantRole, (keccak256("UPDATER_ROLE"), address(adapter))));
        assertEq(calldatas[1], abi.encodeCall(HalalPSM.setSource, ("BLS:CUUR0000SA0")));
        assertEq(calldatas[2], abi.encodeCall(IAccessControl.revokeRole, (keccak256("UPDATER_ROLE"), oldUpdater)));

        (targets, values, calldatas) =
            CPIAdapterGovernance.buildHandoff(address(sink), address(adapter), "BLS:CUUR0000SA0", address(0));
        assertEq(targets.length, 2);
        assertEq(values.length, 2);
        assertEq(calldatas.length, 2);
        assertEq(calldatas[0], abi.encodeCall(IAccessControl.grantRole, (keccak256("UPDATER_ROLE"), address(adapter))));
        assertEq(calldatas[1], abi.encodeCall(HalalPSM.setSource, ("BLS:CUUR0000SA0")));
    }

    function test_RevertWhen_HandoffWouldRevokeTheAdapter() public {
        CPIAdapterGovernanceHarness harness = new CPIAdapterGovernanceHarness();
        vm.expectRevert(CPIAdapterGovernance.InvalidHandoffAddresses.selector);
        harness.buildHandoff(address(sink), address(adapter), "BLS:CUUR0000SA0", address(adapter));
    }

    function test_RevertWhen_HandoffSourceIsEmpty() public {
        CPIAdapterGovernanceHarness harness = new CPIAdapterGovernanceHarness();
        vm.expectRevert(CPIAdapterGovernance.EmptySource.selector);
        harness.buildHandoff(address(sink), address(adapter), "", address(0));
    }

    function test_RevertWhen_HandoffSourceIsWhitespaceOnly() public {
        CPIAdapterGovernanceHarness harness = new CPIAdapterGovernanceHarness();
        vm.expectRevert(CPIAdapterGovernance.EmptySource.selector);
        harness.buildHandoff(address(sink), address(adapter), " \t\n", address(0));
    }

    function test_RevertWhen_HandoffSourceIsFormFeedOrVerticalTabOnly() public {
        CPIAdapterGovernanceHarness harness = new CPIAdapterGovernanceHarness();
        vm.expectRevert(CPIAdapterGovernance.EmptySource.selector);
        harness.buildHandoff(address(sink), address(adapter), string(abi.encodePacked(bytes1(0x0b))), address(0));

        vm.expectRevert(CPIAdapterGovernance.EmptySource.selector);
        harness.buildHandoff(address(sink), address(adapter), string(abi.encodePacked(bytes1(0x0c))), address(0));
    }

    function _signReport(uint256 reportedCPI, uint256 reportedAt, uint256 firstKey)
        internal
        view
        returns (bytes[] memory signatures)
    {
        signatures = new bytes[](1);
        signatures[0] = _signature(reportedCPI, reportedAt, firstKey);
    }

    function _signReport(uint256 reportedCPI, uint256 reportedAt, uint256 firstKey, uint256 secondKey)
        internal
        view
        returns (bytes[] memory signatures)
    {
        address firstSigner = vm.addr(firstKey);
        address secondSigner = vm.addr(secondKey);
        signatures = new bytes[](2);
        if (firstSigner < secondSigner) {
            signatures[0] = _signature(reportedCPI, reportedAt, firstKey);
            signatures[1] = _signature(reportedCPI, reportedAt, secondKey);
        } else {
            signatures[0] = _signature(reportedCPI, reportedAt, secondKey);
            signatures[1] = _signature(reportedCPI, reportedAt, firstKey);
        }
    }

    function _signature(uint256 reportedCPI, uint256 reportedAt, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, adapter.reportDigest(reportedCPI, reportedAt));
        return abi.encodePacked(r, s, v);
    }

    function _signReportFor(
        CPIReportAdapter target,
        uint256 reportedCPI,
        uint256 reportedAt,
        uint256 firstKey,
        uint256 secondKey
    ) internal view returns (bytes[] memory signatures) {
        address firstSigner = vm.addr(firstKey);
        address secondSigner = vm.addr(secondKey);
        signatures = new bytes[](2);
        if (firstSigner < secondSigner) {
            signatures[0] = _signatureFor(target, reportedCPI, reportedAt, firstKey);
            signatures[1] = _signatureFor(target, reportedCPI, reportedAt, secondKey);
        } else {
            signatures[0] = _signatureFor(target, reportedCPI, reportedAt, secondKey);
            signatures[1] = _signatureFor(target, reportedCPI, reportedAt, firstKey);
        }
    }

    function _signatureFor(CPIReportAdapter target, uint256 reportedCPI, uint256 reportedAt, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, target.reportDigest(reportedCPI, reportedAt));
        return abi.encodePacked(r, s, v);
    }
}
