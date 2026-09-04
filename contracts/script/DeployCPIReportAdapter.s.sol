// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CPIReportAdapter } from "../src/CPIReportAdapter.sol";

/// @notice Deploys the optional signed CPI adapter without granting it a PSM role. Governance must
/// review the printed constructor values and grant UPDATER_ROLE in a separate proposal.
///
/// Required environment variables:
///   PRIVATE_KEY, EXPECTED_CHAIN_ID, PSM, ADAPTER_OWNER, CPI_SOURCE_ID, CPI_SIGNER_1,
///   CPI_SIGNER_2, and CPI_THRESHOLD.
/// Optional environment variable:
///   CPI_SIGNER_3.
contract DeployCPIReportAdapter is Script {
    error InvalidConfig();

    function run() external returns (CPIReportAdapter adapter) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        address deployer = vm.addr(privateKey);
        address psm = vm.envAddress("PSM");
        address owner = vm.envAddress("ADAPTER_OWNER");
        address signerOne = vm.envAddress("CPI_SIGNER_1");
        address signerTwo = vm.envAddress("CPI_SIGNER_2");
        address signerThree = vm.envOr("CPI_SIGNER_3", address(0));
        uint256 threshold = vm.envUint("CPI_THRESHOLD");
        bytes32 sourceId = vm.envBytes32("CPI_SOURCE_ID");

        if (!_configIsValid(
                privateKey,
                expectedChainId,
                deployer,
                psm,
                owner,
                signerOne,
                signerTwo,
                signerThree,
                threshold,
                sourceId
            )) revert InvalidConfig();

        address[] memory signers = new address[](signerThree == address(0) ? 2 : 3);
        signers[0] = signerOne;
        signers[1] = signerTwo;
        if (signerThree != address(0)) signers[2] = signerThree;

        vm.startBroadcast(privateKey);
        adapter = new CPIReportAdapter(psm, owner, signers, threshold, sourceId);
        vm.stopBroadcast();

        console.log("CPI report adapter:", address(adapter));
        console.log("PSM:", psm);
        console.log("Owner:", owner);
        console.log("Threshold:", threshold);
        console.log("Signer 1:", signerOne);
        console.log("Signer 2:", signerTwo);
        if (signerThree != address(0)) console.log("Signer 3:", signerThree);
        console.logBytes32(sourceId);
        console.log("Grant UPDATER_ROLE to the adapter only after governance review.");
    }

    function _configIsValid(
        uint256 privateKey,
        uint256 expectedChainId,
        address deployer,
        address psm_,
        address owner_,
        address signerOne,
        address signerTwo,
        address signerThree,
        uint256 threshold_,
        bytes32 sourceId_
    ) internal view returns (bool) {
        return privateKey != 0 && expectedChainId != 0 && block.chainid == expectedChainId && _psmIsContract(psm_)
            && owner_ != address(0) && owner_ != deployer && owner_.code.length > 0
            && _adapterSignersAreSafe(deployer, owner_, signerOne, signerTwo, signerThree) && threshold_ != 0
            && sourceId_ != bytes32(0) && (signerThree != address(0) || threshold_ <= 2)
            && (signerThree == address(0) || threshold_ <= 3);
    }

    function _psmIsContract(address psm) internal view returns (bool) {
        return psm.code.length > 0;
    }

    function _adapterSignersAreSafe(
        address deployer,
        address owner,
        address signerOne,
        address signerTwo,
        address signerThree
    ) internal pure returns (bool) {
        if (
            signerOne == address(0) || signerTwo == address(0) || signerOne == signerTwo || signerOne == deployer
                || signerTwo == deployer || signerOne == owner || signerTwo == owner
        ) return false;
        if (signerThree == address(0)) return true;
        return signerThree != signerOne && signerThree != signerTwo && signerThree != deployer && signerThree != owner;
    }
}
