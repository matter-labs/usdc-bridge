// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {L1USDCBridge} from "../src/L1USDCBridge.sol";
import {DeploymentUtils} from "../utils/DeploymentUtils.sol";

contract InitialiseL1USDCBridge is Script, DeploymentUtils {
    function run() public {
        vm.startBroadcast();

        uint256 sophonSepoliaChainId = vm.envUint("SOPHON_SEPOLIA_CHAIN_ID");
        // if first time, call initializeChainGovernance, else call reinitializeChainGovernance
        L1USDCBridge(getDeployedContract("L1USDCBridge")).initializeChainGovernance(
            sophonSepoliaChainId, getDeployedContract("L2USDCBridge", sophonSepoliaChainId)
        );
        // L1USDCBridge(getDeployedContract("L1USDCBridge")).reinitializeChainGovernance(
        //     sophonSepoliaChainId, getDeployedContract("L2USDCBridge", sophonSepoliaChainId)
        // );
        console.log(
            "L1USDCBridge successfully initialised with the L2USDCBridge address: ",
            vm.envAddress("SOPHON_CUSTOM_SHARED_BRIDGE_L2")
        );

        vm.stopBroadcast();
    }
}
