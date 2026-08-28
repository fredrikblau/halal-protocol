// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICPIReportSink {
    function updateCPIWithTimestamp(uint256 reportedCPI, uint256 reportedAt) external;
    function cpiRate() external view returns (uint256);
    function lastReportTimestamp() external view returns (uint256);
}

/// @title CPIReportAdapter
/// @notice Optional quorum adapter that authenticates EIP-712 CPI reports before forwarding them
/// to HalalPSM. The owner should be the protocol timelock, and the adapter itself should hold the
/// PSM's UPDATER_ROLE. This module does not authenticate a statistics agency; governance must choose
/// and document the source, parser, signer custody, and revision policy off-chain.
/// @dev This contract is an unaudited reference module. Review the signer policy and source
/// integration before granting it a role on a deployment with meaningful funds.
contract CPIReportAdapter is EIP712, Ownable2Step, ReentrancyGuard {
    bytes32 public constant REPORT_TYPEHASH =
        keccak256("CPIReport(uint256 reportedCPI,uint256 reportedAt,bytes32 sourceId)");
    uint256 public constant MAX_SIGNERS = 64;

    ICPIReportSink public immutable psm;
    bytes32 public immutable sourceId;
    mapping(address => bool) public isSigner;
    address[] private _signers;
    mapping(address => uint256) private _signerIndexPlusOne;
    uint256 public signerCount;
    uint256 public threshold;
    uint256 public lastSubmittedTimestamp;
    uint256 public lastSubmittedCPI;

    error ZeroAddress();
    error NotContract();
    error ZeroSourceId();
    error InvalidSignerSet();
    error SignerOwnerOverlap();
    error SignerSetTooLarge();
    error SignerAlreadyConfigured();
    error SignerNotConfigured();
    error InvalidThreshold();
    error InvalidSignatureCount();
    error UnauthorizedSigner();
    error SignaturesNotSorted();
    error InvalidReportTimestamp();
    error ReportTimestampNotIncreasing();
    error ReportNotAccepted();

    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event ThresholdUpdated(uint256 threshold);
    event SourceIdConfigured(bytes32 indexed sourceId);
    event ReportSubmitted(uint256 indexed reportedAt, uint256 reportedCPI, uint256 signerCount);

    constructor(address psm_, address owner_, address[] memory signers_, uint256 threshold_, bytes32 sourceId_)
        EIP712("Halal CPI Report Adapter", "1")
        Ownable(owner_)
    {
        if (psm_ == address(0)) revert ZeroAddress();
        // Calls to an EOA return success with no data, which could otherwise make the adapter mark
        // a report submitted even though no PSM state changed.
        if (psm_.code.length == 0) revert NotContract();
        if (sourceId_ == bytes32(0)) revert ZeroSourceId();
        if (signers_.length == 0 || threshold_ == 0 || threshold_ > signers_.length) revert InvalidSignerSet();
        if (signers_.length > MAX_SIGNERS) revert SignerSetTooLarge();
        psm = ICPIReportSink(psm_);
        sourceId = sourceId_;
        threshold = threshold_;
        emit SourceIdConfigured(sourceId_);

        for (uint256 i = 0; i < signers_.length; ++i) {
            address signer = signers_[i];
            if (signer == address(0) || signer == owner_ || isSigner[signer]) revert InvalidSignerSet();
            isSigner[signer] = true;
            _signerIndexPlusOne[signer] = _signers.length + 1;
            _signers.push(signer);
            ++signerCount;
            emit SignerAdded(signer);
        }
    }

    /// @notice Starts an ownership transfer only to an address outside the report signer set.
    /// Keeping custody boundaries disjoint prevents one compromised key from both changing the
    /// quorum and satisfying it.
    function transferOwnership(address newOwner) public override onlyOwner {
        if (isSigner[newOwner]) revert SignerOwnerOverlap();
        super.transferOwnership(newOwner);
    }

    /// @notice Completes the two-step transfer only when the accepting owner is not a signer.
    function acceptOwnership() public override {
        if (isSigner[msg.sender]) revert SignerOwnerOverlap();
        super.acceptOwnership();
    }

    /// @notice Adds a report signer. Governance should call this through the owner timelock.
    /// The pending owner is excluded as well as the active owner so a two-step handoff cannot be
    /// made unfinishable by adding its recipient to the signer set before acceptance.
    function addSigner(address signer) external onlyOwner {
        if (signer == address(0)) revert ZeroAddress();
        if (signer == owner() || signer == pendingOwner()) revert SignerOwnerOverlap();
        if (isSigner[signer]) revert SignerAlreadyConfigured();
        if (signerCount >= MAX_SIGNERS) revert SignerSetTooLarge();
        isSigner[signer] = true;
        _signerIndexPlusOne[signer] = _signers.length + 1;
        _signers.push(signer);
        ++signerCount;
        emit SignerAdded(signer);
    }

    /// @notice Removes a report signer while preserving the configured quorum.
    function removeSigner(address signer) external onlyOwner {
        if (!isSigner[signer]) revert SignerNotConfigured();
        if (signerCount - 1 < threshold) revert InvalidThreshold();
        isSigner[signer] = false;
        uint256 index = _signerIndexPlusOne[signer] - 1;
        uint256 lastIndex = _signers.length - 1;
        if (index != lastIndex) {
            address lastSigner = _signers[lastIndex];
            _signers[index] = lastSigner;
            _signerIndexPlusOne[lastSigner] = index + 1;
        }
        _signers.pop();
        delete _signerIndexPlusOne[signer];
        --signerCount;
        emit SignerRemoved(signer);
    }

    /// @notice Changes the number of distinct signatures required for each report.
    function setThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0 || newThreshold > signerCount) revert InvalidThreshold();
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    /// @notice Returns the EIP-712 digest that signers must approve.
    function reportDigest(uint256 reportedCPI, uint256 reportedAt) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(REPORT_TYPEHASH, reportedCPI, reportedAt, sourceId)));
    }

    /// @notice Returns the current signer set in configuration order, except that removing a
    /// signer may move the last configured signer into the removed slot. Consumers must treat the
    /// array as a set and compare addresses without relying on order.
    function getSigners() external view returns (address[] memory) {
        return _signers;
    }

    /// @notice Returns one signer from the current set for low-bandwidth monitoring clients.
    function signerAt(uint256 index) external view returns (address) {
        return _signers[index];
    }

    /// @notice Forwards a report after verifying exactly `threshold` distinct authorized signatures.
    /// Signatures must be ordered by recovered signer address in strictly ascending order.
    function submitReport(uint256 reportedCPI, uint256 reportedAt, bytes[] calldata signatures) external nonReentrant {
        // The PSM applies the same timestamp boundary. This check prevents the adapter from
        // forwarding a report that its sink could accept but the adapter's own watermark could not.
        // forge-lint: disable-next-line(block-timestamp)
        if (reportedAt == 0 || reportedAt > block.timestamp) revert InvalidReportTimestamp();
        if (reportedAt <= lastSubmittedTimestamp) revert ReportTimestampNotIncreasing();
        if (signatures.length != threshold) revert InvalidSignatureCount();

        bytes32 digest = reportDigest(reportedCPI, reportedAt);
        address previousSigner;
        for (uint256 i = 0; i < signatures.length; ++i) {
            address signer = ECDSA.recover(digest, signatures[i]);
            if (!isSigner[signer]) revert UnauthorizedSigner();
            if (i > 0 && signer <= previousSigner) revert SignaturesNotSorted();
            previousSigner = signer;
        }

        psm.updateCPIWithTimestamp(reportedCPI, reportedAt);
        // A successful external call is not proof that the configured sink accepted the report.
        // HalalPSM exposes this watermark; require it to advance before recording adapter state so
        // a no-op or incompatible sink cannot make the adapter look healthy.
        if (psm.lastReportTimestamp() != reportedAt || psm.cpiRate() != reportedCPI) {
            revert ReportNotAccepted();
        }
        lastSubmittedTimestamp = reportedAt;
        lastSubmittedCPI = reportedCPI;
        emit ReportSubmitted(reportedAt, reportedCPI, signatures.length);
    }
}
