// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Script.sol";
import {L1USDCBridge} from "../../src/L1USDCBridge.sol";
import {L2USDCBridge} from "../../src/L2USDCBridge.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IBridgehub} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";

contract SharedBridgesTest is Test {
    uint256 sepoliaTestnet = vm.createSelectFork("sepoliaTestnet");
    uint256 sophonTestnet = vm.createSelectFork("sophonTestnet");

    address l1USDCBridge;
    address l2USDCBridge;
    address alice;

    function deployL1Contracts() public {
        vm.selectFork(sepoliaTestnet);

        // deploy implementation
        L1USDCBridge sharedBridgeImpl = new L1USDCBridge{salt: "1"}(
            vm.envAddress("L1_USDC_TOKEN"),
            IBridgehub(vm.envAddress("SEPOLIA_L1_BRIDGEHUB")) // Sepolia L1 Bridgehub
        );

        // deploy proxy
        TransparentUpgradeableProxy sharedBridgeProxy = new TransparentUpgradeableProxy(
            address(sharedBridgeImpl),
            address(alice), // proxy admin
            abi.encodeWithSelector(L1USDCBridge.initialize.selector, address(this)) // implementation owner
        );

        l1USDCBridge = address(sharedBridgeProxy);
    }

    function deployL2Contracts() public {
        vm.selectFork(sophonTestnet);

        // deploy implementation
        L2USDCBridge sharedBridgeImpl = new L2USDCBridge(vm.envAddress("L1_USDC_TOKEN"), vm.envAddress("L2_USDC_TOKEN"));

        // deploy proxy
        TransparentUpgradeableProxy sharedBridgeProxy = new TransparentUpgradeableProxy(
            address(sharedBridgeImpl),
            address(this),
            abi.encodeWithSelector(L2USDCBridge.initialize.selector, l1USDCBridge)
        );

        l2USDCBridge = address(sharedBridgeProxy);
    }

    function setUp() public {
        alice = makeAddr("alice");

        deployL1Contracts();
        deployL2Contracts();

        // initialise L1 shared bridge with L2 shared bridge address
        vm.selectFork(sepoliaTestnet);
        L1USDCBridge(l1USDCBridge).initializeChainGovernance(vm.envUint("SOPHON_SEPOLIA_CHAIN_ID"), l2USDCBridge);

        // add L2 shared bridge as minter on USDC
    }
}
