// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { DeployHalalSystem } from "../script/Deploy.s.sol";
import { DeployCPIReportAdapter } from "../script/DeployCPIReportAdapter.s.sol";
import { Test } from "forge-std/Test.sol";

contract DeployHalalSystemHarness is DeployHalalSystem {
    function defaultVotingPeriod(uint256 chainId) external pure returns (uint256) {
        return _defaultVotingPeriod(chainId);
    }

    function expectedChainIdMatches(uint256 expectedChainId, uint256 actualChainId) external pure returns (bool) {
        return _isExpectedChainId(expectedChainId, actualChainId);
    }

    function beneficiariesAreDistinct(address teamBeneficiary, address treasuryBeneficiary)
        external
        pure
        returns (bool)
    {
        return _beneficiariesAreDistinct(teamBeneficiary, treasuryBeneficiary);
    }

    function beneficiariesAreContracts(address teamBeneficiary, address treasuryBeneficiary)
        external
        view
        returns (bool)
    {
        return _beneficiariesAreContracts(teamBeneficiary, treasuryBeneficiary);
    }

    function reserveTokenIsContract(address reserveToken) external view returns (bool) {
        return _reserveTokenIsContract(reserveToken);
    }

    function beneficiaryIsNotDeployer(address deployer, address beneficiary) external pure returns (bool) {
        return beneficiary != address(0) && beneficiary != deployer;
    }
}

contract DeployCPIReportAdapterHarness is DeployCPIReportAdapter {
    function configIsValid(
        uint256 privateKey,
        uint256 expectedChainId,
        address deployer,
        address psm,
        address owner,
        address signerOne,
        address signerTwo,
        address signerThree,
        uint256 threshold,
        bytes32 sourceId
    ) external view returns (bool) {
        return _configIsValid(
            privateKey, expectedChainId, deployer, psm, owner, signerOne, signerTwo, signerThree, threshold, sourceId
        );
    }

    function psmIsContract(address psm) external view returns (bool) {
        return _psmIsContract(psm);
    }

    function ownerIsContract(address owner) external view returns (bool) {
        return owner.code.length > 0;
    }

    function adapterSignersAreSafe(
        address deployer,
        address owner,
        address signerOne,
        address signerTwo,
        address signerThree
    ) external pure returns (bool) {
        return _adapterSignersAreSafe(deployer, owner, signerOne, signerTwo, signerThree);
    }
}

contract DeployConfigTest is Test {
    DeployHalalSystemHarness internal deployer = new DeployHalalSystemHarness();
    DeployCPIReportAdapterHarness internal adapterDeployer = new DeployCPIReportAdapterHarness();

    function test_ArbitrumDefaultsToOneWeekVotingPeriod() public view {
        require(deployer.defaultVotingPeriod(42_161) == 2_419_200);
        require(deployer.defaultVotingPeriod(421_614) == 2_419_200);
    }

    function test_NonArbitrumKeepsEthereumOrLocalDefault() public view {
        require(deployer.defaultVotingPeriod(1) == 50_400);
        require(deployer.defaultVotingPeriod(31_337) == 50_400);
    }

    function test_ExpectedChainIdMustMatchAndBeNonzero() public view {
        require(deployer.expectedChainIdMatches(31_337, 31_337));
        require(!deployer.expectedChainIdMatches(31_337, 42_161));
        require(!deployer.expectedChainIdMatches(0, 31_337));
    }

    function test_BeneficiariesMustBeDistinctAndNonzero() public view {
        require(deployer.beneficiariesAreDistinct(address(0x1), address(0x2)));
        require(!deployer.beneficiariesAreDistinct(address(0), address(0x2)));
        require(!deployer.beneficiariesAreDistinct(address(0x1), address(0)));
        require(!deployer.beneficiariesAreDistinct(address(0x1), address(0x1)));
    }

    function test_ProductionBeneficiariesMustNotBeTheDeployer() public view {
        require(deployer.beneficiaryIsNotDeployer(address(0x1), address(0x2)));
        require(!deployer.beneficiaryIsNotDeployer(address(0x1), address(0x1)));
        require(!deployer.beneficiaryIsNotDeployer(address(0x1), address(0)));
    }

    function test_ProductionBeneficiariesMustBeDeployedContracts() public view {
        require(deployer.beneficiariesAreContracts(address(deployer), address(adapterDeployer)));
        require(!deployer.beneficiariesAreContracts(address(deployer), address(0x1)));
        require(!deployer.beneficiariesAreContracts(address(0x1), address(adapterDeployer)));
    }

    function test_ProductionReserveTokenMustBeADeployedContract() public view {
        require(deployer.reserveTokenIsContract(address(adapterDeployer)));
        require(!deployer.reserveTokenIsContract(address(0x1)));
        require(!deployer.reserveTokenIsContract(address(0)));
    }

    function test_AdapterSignersMustBeDistinctAndIndependentFromDeployer() public view {
        require(
            adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x3), address(0))
        );
        require(
            adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x3), address(0x4))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x1), address(0x3), address(0))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x2), address(0))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x1), address(0x3), address(0x4))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x3), address(0x1))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x3), address(0x2))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x5), address(0x3), address(0))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x5), address(0))
        );
        require(
            !adapterDeployer.adapterSignersAreSafe(address(0x1), address(0x5), address(0x2), address(0x3), address(0x5))
        );
        _assertAdapterDeploymentConfigurationGate();
    }

    function test_AdapterDeploymentRequiresAContractPSM() public view {
        require(adapterDeployer.psmIsContract(address(adapterDeployer)));
        require(!adapterDeployer.psmIsContract(address(0x1)));
        require(!adapterDeployer.psmIsContract(address(0)));
    }

    function test_AdapterDeploymentRequiresAContractOwner() public view {
        require(adapterDeployer.ownerIsContract(address(deployer)));
        require(!adapterDeployer.ownerIsContract(address(0x1)));
        require(!adapterDeployer.ownerIsContract(address(0)));
    }

    function _assertAdapterDeploymentConfigurationGate() internal view {
        uint256 privateKey = 0x1234;
        address deployerAddress = vm.addr(privateKey);
        address psm = address(deployer);
        address owner = address(adapterDeployer);
        uint256 chainId = block.chainid;

        require(
            adapterDeployer.configIsValid(
                privateKey,
                chainId,
                deployerAddress,
                psm,
                owner,
                address(0x2),
                address(0x3),
                address(0),
                2,
                keccak256("source")
            )
        );
        require(
            adapterDeployer.configIsValid(
                privateKey,
                chainId,
                deployerAddress,
                psm,
                owner,
                address(0x2),
                address(0x3),
                address(0x4),
                3,
                keccak256("source")
            )
        );
        require(
            !adapterDeployer.configIsValid(
                0, chainId, deployerAddress, psm, owner, address(0x2), address(0x3), address(0), 2, keccak256("source")
            )
        );
        require(
            !adapterDeployer.configIsValid(
                privateKey,
                chainId + 1,
                deployerAddress,
                psm,
                owner,
                address(0x2),
                address(0x3),
                address(0),
                2,
                keccak256("source")
            )
        );
        require(
            !adapterDeployer.configIsValid(
                privateKey,
                chainId,
                deployerAddress,
                address(0x1),
                owner,
                address(0x2),
                address(0x3),
                address(0),
                2,
                keccak256("source")
            )
        );
        require(
            !adapterDeployer.configIsValid(
                privateKey,
                chainId,
                deployerAddress,
                psm,
                address(0x1),
                address(0x2),
                address(0x3),
                address(0),
                2,
                keccak256("source")
            )
        );
        require(
            !adapterDeployer.configIsValid(
                privateKey,
                chainId,
                deployerAddress,
                psm,
                owner,
                address(0x2),
                address(0x3),
                address(0),
                3,
                keccak256("source")
            )
        );
        require(
            !adapterDeployer.configIsValid(
                privateKey, chainId, deployerAddress, psm, owner, address(0x2), address(0x3), address(0), 2, bytes32(0)
            )
        );
    }
}
