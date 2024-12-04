// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L1USDCBridgeTest} from "./_L1USDCBridge_Shared.t.sol";

import {ETH_TOKEN_ADDRESS} from "@era-contracts/l1-contracts/contracts/common/Config.sol";
import {IBridgehub} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";
import {L2Message, TxStatus} from "@era-contracts/l1-contracts/contracts/common/Messaging.sol";
import {IMailbox} from "@era-contracts/l1-contracts/contracts/state-transition/chain-interfaces/IMailbox.sol";
import {IL1ERC20Bridge} from "@era-contracts/l1-contracts/contracts/bridge/interfaces/IL1ERC20Bridge.sol";
import {L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR} from "@era-contracts/l1-contracts/contracts/common/L2ContractAddresses.sol";
import {IGetters} from "@era-contracts/l1-contracts/contracts/state-transition/chain-interfaces/IGetters.sol";

contract L1USDCBridgeTestBase is L1USDCBridgeTest {
    function test_bridgehubDeposit_Erc() public {
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(sharedBridge), amount);
        vm.prank(bridgehubAddress);
        vm.expectEmit(true, true, true, true, address(sharedBridge));
        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );
        bytes32 txDataHash = keccak256(abi.encode(alice, address(token), amount));
        emit BridgehubDepositInitiated({
            chainId: chainId,
            txDataHash: txDataHash,
            from: alice,
            to: zkSync,
            l1Token: address(token),
            amount: amount
        });
        sharedBridge.bridgehubDeposit(chainId, alice, 0, abi.encode(address(token), amount, bob));
    }

    function test_bridgehubConfirmL2Transaction() public {
        vm.expectEmit(true, true, true, true, address(sharedBridge));
        bytes32 txDataHash = keccak256(abi.encode(alice, address(token), amount));
        emit BridgehubDepositFinalized(chainId, txDataHash, txHash);
        vm.prank(bridgehubAddress);
        sharedBridge.bridgehubConfirmL2Transaction(chainId, txDataHash, txHash);
    }

    function test_claimFailedDeposit_Erc() public {
        token.mint(address(sharedBridge), amount);
        bytes32 txDataHash = keccak256(abi.encode(alice, address(token), amount));
        _setSharedBridgeDepositHappened(chainId, txHash, txDataHash);
        require(sharedBridge.depositHappened(chainId, txHash) == txDataHash, "Deposit not set");
        _setSharedBridgeChainBalance(chainId, address(token), amount);

        vm.mockCall(
            bridgehubAddress,
            abi.encodeWithSelector(
                IBridgehub.proveL1ToL2TransactionStatus.selector,
                chainId,
                txHash,
                l2BatchNumber,
                l2MessageIndex,
                l2TxNumberInBatch,
                merkleProof,
                TxStatus.Failure
            ),
            abi.encode(true)
        );

        vm.expectEmit(true, true, true, true, address(sharedBridge));
        emit ClaimedFailedDepositSharedBridge({chainId: chainId, to: alice, l1Token: address(token), amount: amount});
        sharedBridge.claimFailedDeposit({
            _chainId: chainId,
            _depositSender: alice,
            _l1Token: address(token),
            _amount: amount,
            _l2TxHash: txHash,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _merkleProof: merkleProof
        });
    }

    function test_finalizeWithdrawal_ErcOnEth() public {
        token.mint(address(sharedBridge), amount);

        _setSharedBridgeChainBalance(chainId, address(token), amount);
        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );

        bytes memory message =
            abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, alice, address(token), amount);
        L2Message memory l2ToL1Message =
            L2Message({txNumberInBatch: l2TxNumberInBatch, sender: l2USDCBridge, data: message});

        vm.mockCall(
            bridgehubAddress,
            abi.encodeWithSelector(
                IBridgehub.proveL2MessageInclusion.selector,
                chainId,
                l2BatchNumber,
                l2MessageIndex,
                l2ToL1Message,
                merkleProof
            ),
            abi.encode(true)
        );

        vm.expectEmit(true, true, true, true, address(sharedBridge));
        emit WithdrawalFinalizedSharedBridge(chainId, alice, address(token), amount);
        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_finalizeWithdrawal_BaseErcOnErc() public {
        token.mint(address(sharedBridge), amount);

        _setSharedBridgeChainBalance(chainId, address(token), amount);
        vm.mockCall(bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(address(token)));

        bytes memory message =
            abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, alice, address(token), amount);
        L2Message memory l2ToL1Message =
            L2Message({txNumberInBatch: l2TxNumberInBatch, sender: L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR, data: message});

        vm.mockCall(
            bridgehubAddress,
            abi.encodeWithSelector(
                IBridgehub.proveL2MessageInclusion.selector,
                chainId,
                l2BatchNumber,
                l2MessageIndex,
                l2ToL1Message,
                merkleProof
            ),
            abi.encode(true)
        );

        vm.expectEmit(true, true, true, true, address(sharedBridge));
        emit WithdrawalFinalizedSharedBridge(chainId, alice, address(token), amount);
        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_finalizeWithdrawal_NonBaseErcOnErc() public {
        token.mint(address(sharedBridge), amount);

        _setSharedBridgeChainBalance(chainId, address(token), amount);

        bytes memory message =
            abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, alice, address(token), amount);
        vm.mockCall(bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(address(2))); //alt base token
        L2Message memory l2ToL1Message =
            L2Message({txNumberInBatch: l2TxNumberInBatch, sender: l2USDCBridge, data: message});

        vm.mockCall(
            bridgehubAddress,
            abi.encodeWithSelector(
                IBridgehub.proveL2MessageInclusion.selector,
                chainId,
                l2BatchNumber,
                l2MessageIndex,
                l2ToL1Message,
                merkleProof
            ),
            abi.encode(true)
        );

        vm.expectEmit(true, true, true, true, address(sharedBridge));
        emit WithdrawalFinalizedSharedBridge(chainId, alice, address(token), amount);
        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_pause() public {
        vm.prank(owner);
        sharedBridge.pause();
        assertTrue(sharedBridge.paused());
    }

    function test_unpause() public {
        vm.prank(owner);
        sharedBridge.pause();
        vm.prank(owner);
        sharedBridge.unpause();
        assertFalse(sharedBridge.paused());
    }
}
