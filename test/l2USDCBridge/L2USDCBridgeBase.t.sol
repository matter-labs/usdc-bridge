// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2USDCBridgeTest} from "./_L2USDCBridge_Shared.t.sol";
import {IL1ERC20Bridge} from "../../src/interfaces/IL1ERC20Bridge.sol";
import {IL2Messenger} from "../../src/interfaces/IL2Messenger.sol";
import {IL2SharedBridge} from "../../src/interfaces/IL2SharedBridge.sol";

contract MockL2Messenger {
    function sendToL1(bytes memory message) external returns (bytes32) {
        return keccak256(message);
    }
}

contract L2USDCBridgeTestBase is L2USDCBridgeTest {
    function testFinalizeDeposit() public {
        uint256 initialBalance = mockL2Token.balanceOf(bob);
        address aliasedL1USDCBridge =
            address(uint160(l1USDCBridge) + uint160(0x1111000000000000000000000000000000001111));

        vm.expectEmit(true, true, true, true);
        emit FinalizeDeposit(alice, bob, address(mockL2Token), depositAmount);

        vm.prank(aliasedL1USDCBridge);
        bridge.finalizeDeposit(alice, bob, address(mockL2Token), depositAmount, "");

        uint256 finalBalance = mockL2Token.balanceOf(bob);
        assertEq(finalBalance - initialBalance, depositAmount);
    }

    function testFinalizeDeposit_RevertIfWrongCaller() public {
        vm.expectRevert(bytes("mq"));
        bridge.finalizeDeposit(alice, bob, address(mockL2Token), depositAmount, "");
    }

    function testWithdraw() public {
        mockL2Token.mint(alice, depositAmount);

        vm.startPrank(alice);
        mockL2Token.approve(address(bridge), depositAmount);

        bytes memory expectedMessage =
            abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, bob, address(mockL2Token), depositAmount);

        MockL2Messenger mockMessenger = new MockL2Messenger();
        vm.etch(address(SYSTEM_CONTRACTS_OFFSET + 0x08), address(mockMessenger).code);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(alice, bob, address(mockL2Token), depositAmount);

        vm.expectCall(address(SYSTEM_CONTRACTS_OFFSET + 0x08), abi.encodeCall(IL2Messenger.sendToL1, expectedMessage));
        bridge.withdraw(bob, address(mockL2Token), depositAmount);

        uint256 aliceBalance = mockL2Token.balanceOf(alice);
        assertEq(aliceBalance, 0);

        vm.stopPrank();
    }

    function testL2TokenAddress() public {
        address l2TokenAddress = bridge.l2TokenAddress(address(mockL2Token));
        assertEq(l2TokenAddress, address(mockL2Token));
    }

    function testL1TokenAddress() public {
        address l1TokenAddress = bridge.l1TokenAddress(address(mockL2Token));
        assertEq(l1TokenAddress, address(mockL2Token));
    }
}
