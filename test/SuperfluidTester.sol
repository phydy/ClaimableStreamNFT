// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.3;

import {Test} from "forge-std/Test.sol";
import {IERC1820Registry} from "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import {Superfluid, ConstantFlowAgreementV1, InstantDistributionAgreementV1, SuperTokenFactory, SuperfluidFrameworkDeployer} from "@superfluid/utils/SuperfluidFrameworkDeployer.sol";
import {ERC1820RegistryCompiled} from "@superfluid/libs/ERC1820RegistryCompiled.sol";
import {CFAv1Library} from "@superfluid/apps/CFAv1Library.sol";
import {IDAv1Library} from "@superfluid/apps/IDAv1Library.sol";

/// @title Superfluid Framework Tester
/// @author phydy.eth
contract SuperfluidTester is Test {
    /// @dev Everything you need from framework is in it. See `README.md` for more.
    SuperfluidFrameworkDeployer.Framework internal sf;

    /// @notice Deploys everything... probably
    /// @param admin Desired address of Admin
    constructor(address admin) {
        // everything will be deployed as if `admin` was the message sender of each
        vm.startPrank(admin);

        // Deploy ERC1820Registry by 'etching' the bytecode into the address
        // mother of god this can not be real
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        sf = new SuperfluidFrameworkDeployer().getFramework();

        vm.stopPrank();
    }
}
