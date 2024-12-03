// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L1USDCBridgeTest} from "./_L1USDCBridge_Shared.t.sol";

/// We are testing all the specified revert and require cases.
contract L1USDCBridgeAdminTest is L1USDCBridgeTest {
    uint256 internal randomChainId = 123456;

    function testAdminCanInitializeChainGovernance() public {
        address randomL2Bridge = makeAddr("randomL2Bridge");

        vm.prank(admin);
        sharedBridge.initializeChainGovernance(randomChainId, randomL2Bridge);

        assertEq(sharedBridge.l2BridgeAddress(randomChainId), randomL2Bridge);
    }

    function testAdminCanReinitializeChainGovernance() public {
        address randomNewBridge = makeAddr("randomNewBridge");
        vm.prank(owner);
        sharedBridge.reinitializeChainGovernance(chainId, randomNewBridge);
        assertEq(sharedBridge.l2BridgeAddress(chainId), randomNewBridge);
    }

    function testAdminCanNotReinitializeChainGovernance() public {
        address randomNewBridge = makeAddr("randomNewBridge");

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(admin);
        sharedBridge.reinitializeChainGovernance(randomChainId, randomNewBridge);
    }

    function testAdminCanSetPendingAdmin() public {
        address newPendingAdmin = makeAddr("newPendingAdmin");

        vm.prank(admin);
        sharedBridge.setPendingAdmin(newPendingAdmin);

        assertEq(sharedBridge.pendingAdmin(), newPendingAdmin);
    }

    function testPendingAdminCanAcceptAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        sharedBridge.setPendingAdmin(newAdmin);

        vm.prank(newAdmin);
        sharedBridge.acceptAdmin();

        assertEq(sharedBridge.admin(), newAdmin);
        assertEq(sharedBridge.pendingAdmin(), address(0));
    }

    function testNonOwnerOrAdminCannotSetPendingAdmin() public {
        address randomUser = makeAddr("randomUser");
        address newPendingAdmin = makeAddr("newPendingAdmin");

        vm.prank(randomUser);
        vm.expectRevert("USDC-ShB not owner or admin");
        sharedBridge.setPendingAdmin(newPendingAdmin);
    }

    function testNonPendingAdminCannotAcceptAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        address randomUser = makeAddr("randomUser");

        vm.prank(admin);
        sharedBridge.setPendingAdmin(newAdmin);

        vm.prank(randomUser);
        vm.expectRevert("USDC-ShB not pending admin");
        sharedBridge.acceptAdmin();
    }

    function testOwnerCanSetPendingAdmin() public {
        address newPendingAdmin = makeAddr("newPendingAdmin");

        vm.prank(owner);
        sharedBridge.setPendingAdmin(newPendingAdmin);

        assertEq(sharedBridge.pendingAdmin(), newPendingAdmin);
    }

    function testAdminCannotPause() public {
        vm.prank(admin);
        vm.expectRevert("Ownable: caller is not the owner");
        sharedBridge.pause();
    }

    function testAdminCannotUnpause() public {
        vm.prank(owner);
        sharedBridge.pause();

        vm.prank(admin);
        vm.expectRevert("Ownable: caller is not the owner");
        sharedBridge.unpause();
    }

    function test_onlyOwnerOrAdmin_whenCallerIsOwner() public {
        vm.prank(owner);
        sharedBridge.setPendingAdmin(alice);
        assertEq(sharedBridge.pendingAdmin(), alice);
    }

    function test_onlyOwnerOrAdmin_whenCallerIsAdmin() public {
        vm.prank(admin);
        sharedBridge.setPendingAdmin(alice);
        assertEq(sharedBridge.pendingAdmin(), alice);
    }
}
