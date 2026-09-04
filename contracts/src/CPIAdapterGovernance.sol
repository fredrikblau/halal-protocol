// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Encodes the DAO actions required to hand CPI reporting to a quorum adapter.
/// @dev The caller must verify the adapter address, source policy, and old updater before
/// submitting the returned proposal. The optional old updater is revoked last so the adapter
/// remains authorized throughout the handoff.
library CPIAdapterGovernance {
    bytes32 internal constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    error InvalidHandoffAddresses();
    error EmptySource();

    function buildHandoff(address psm, address adapter, string memory source, address oldUpdater)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        if (psm == address(0) || adapter == address(0) || (oldUpdater != address(0) && oldUpdater == adapter)) {
            revert InvalidHandoffAddresses();
        }
        bytes memory sourceBytes = bytes(source);
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
        uint256 actionCount = oldUpdater == address(0) ? 2 : 3;
        targets = new address[](actionCount);
        values = new uint256[](actionCount);
        calldatas = new bytes[](actionCount);

        targets[0] = psm;
        calldatas[0] = abi.encodeWithSignature("grantRole(bytes32,address)", UPDATER_ROLE, adapter);
        targets[1] = psm;
        calldatas[1] = abi.encodeWithSignature("setSource(string)", source);

        if (oldUpdater != address(0)) {
            targets[2] = psm;
            calldatas[2] = abi.encodeWithSignature("revokeRole(bytes32,address)", UPDATER_ROLE, oldUpdater);
        }
    }
}
