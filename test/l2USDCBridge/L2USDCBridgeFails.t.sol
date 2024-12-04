// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2USDCBridgeTest} from "./_L2USDCBridge_Shared.t.sol";
import {L2USDCBridge} from "../../src/L2USDCBridge.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @notice Testing all the specified revert and require cases for L2USDCBridge
contract L2USDCBridgeFailTest is L2USDCBridgeTest {
    function test_constructor_zeroL2TokenAddress() public {
        vm.expectRevert("USDC-ShB: l2UsdcToken is zero address");
        new L2USDCBridge(address(mockL2Token), address(0));
    }

    function test_initialize_wrongL1Bridge() public {
        address proxyAdmin = makeAddr("proxyAdmin");
        L2USDCBridge sharedBridgeImpl = new L2USDCBridge(address(mockL2Token), address(mockL2Token));

        vm.expectRevert(bytes("bf"));
        new TransparentUpgradeableProxy(
            address(sharedBridgeImpl), proxyAdmin, abi.encodeWithSelector(L2USDCBridge.initialize.selector, address(0))
        );
    }

    function test_finalizeDeposit_wrongSender() public {
        vm.prank(alice);
        vm.expectRevert(bytes("mq"));
        bridge.finalizeDeposit(alice, bob, address(mockL2Token), depositAmount, "");
    }

    function test_withdraw_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Amount cannot be zero");
        bridge.withdraw(bob, address(mockL2Token), 0);
    }

    function test_l1TokenAddress_unsupportedToken() public {
        address randomToken = makeAddr("randomToken");
        vm.expectRevert("Unsupported L2 token");
        bridge.l1TokenAddress(randomToken);
    }

    function test_l2TokenAddress_unsupportedToken() public {
        address randomToken = makeAddr("randomToken");
        vm.expectRevert("Unsupported L1 token");
        bridge.l2TokenAddress(randomToken);
    }

    function test_initialize_alreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        bridge.initialize(l1USDCBridge);
    }

    function test_constructor_zeroL1TokenAddress() public {
        vm.expectRevert("USDC-ShB: l1UsdcToken is zero address");
        new L2USDCBridge(address(0), address(mockL2Token));
    }

    function testWithdraw_RevertIfZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert("Amount cannot be zero");
        bridge.withdraw(bob, address(mockL2Token), 0);
        vm.stopPrank();
    }
}
