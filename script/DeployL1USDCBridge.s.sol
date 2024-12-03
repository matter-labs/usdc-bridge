// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {L1USDCBridge} from "../src/L1USDCBridge.sol";
import {IBridgehub} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {DeploymentUtils} from "../utils/DeploymentUtils.sol";

contract DeployL1USDCBridge is Script, DeploymentUtils {
    function run() public {
        // TODO: fix and send corresponding network and config names
        _run("", "");
    }

    function run(string memory networkName, string memory configName) public {
        _run(networkName, configName);
    }

    // call from tests -- avoiding the return when calling from the script results in cleaner logs
    function runAndReturnResults(string memory networkName, string memory configName)
        public
        returns (address sharedBridgeProxy, address sharedBridgeImpl)
    {
        return _run(networkName, configName);
    }

    function _run(string memory networkName, string memory configName)
        internal
        returns (address sharedBridgeProxy, address sharedBridgeImpl)
    {
        // TODO: set proper addresses, maybe read from env
        address deployerAddress = msg.sender;
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");

        vm.startBroadcast();

        sharedBridgeProxy = getDeployedContract("L1USDCBridge");

        // deploy implementation
        sharedBridgeImpl =
            address(new L1USDCBridge(getDeployedContract("USDC"), IBridgehub(getDeployedContract("Bridgehub"))));

        // if proxy exists, upgrade proxy with new implementation
        if (sharedBridgeProxy != address(0)) {
            console.log("Upgrading L1USDCBridge");
            if (msg.sender != proxyAdmin) revert("Only proxy admin can upgrade the implementation");
            ITransparentUpgradeableProxy(payable(sharedBridgeProxy)).upgradeTo(sharedBridgeImpl);
            console.log("L1USDCBridge implementation upgraded @", sharedBridgeImpl);
            saveDeployedContract("L1USDCBridge-impl", sharedBridgeImpl);
            return (sharedBridgeProxy, sharedBridgeImpl);
        }

        // deploy proxy
        sharedBridgeProxy = address(
            new TransparentUpgradeableProxy(
                sharedBridgeImpl, proxyAdmin, abi.encodeWithSelector(L1USDCBridge.initialize.selector, deployerAddress)
            )
        );

        console.log("L1USDCBridge implementation deployed @", address(sharedBridgeImpl));
        console.log("L1USDCBridge proxy deployed @", address(sharedBridgeProxy));
        saveDeployedContract("L1USDCBridge", address(sharedBridgeProxy));
        saveDeployedContract("L1USDCBridge-impl", address(sharedBridgeImpl));

        vm.stopBroadcast();
        return (address(sharedBridgeProxy), address(sharedBridgeImpl));
    }
}
