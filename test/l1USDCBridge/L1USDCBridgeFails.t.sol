// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L1USDCBridgeTest} from "./_L1USDCBridge_Shared.t.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {L1USDCBridge} from "../../src/L1USDCBridge.sol";
import {ETH_TOKEN_ADDRESS} from "@era-contracts/l1-contracts/contracts/common/Config.sol";
import {IBridgehub} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";
import {L2Message, TxStatus} from "@era-contracts/l1-contracts/contracts/common/Messaging.sol";
import {IMailbox} from "@era-contracts/l1-contracts/contracts/state-transition/chain-interfaces/IMailbox.sol";
import {IL1ERC20Bridge} from "@era-contracts/l1-contracts/contracts/bridge/interfaces/IL1ERC20Bridge.sol";

/// We are testing all the specified revert and require cases.
contract L1USDCBridgeFailTest is L1USDCBridgeTest {
    function test_initialize_wrongOwner() public {
        vm.expectRevert("USDC-ShB owner 0");
        new TransparentUpgradeableProxy(
            address(sharedBridgeImpl),
            proxyAdmin,
            abi.encodeWithSelector(L1USDCBridge.initialize.selector, address(0), eraPostUpgradeFirstBatch)
        );
    }

    function test_initializeChainGovernance_bridgeAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert("USDC-ShB: l2 bridge already set");
        sharedBridge.initializeChainGovernance(chainId, address(1));
    }

    function test_initializeChainGovernance_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("USDC-ShB: l2 bridge 0");
        sharedBridge.initializeChainGovernance(2, address(0));
    }

    function test_reinitializeChainGovernance_neverSet() public {
        vm.prank(owner);
        vm.expectRevert("USDC-ShB: l2 bridge not yet set");
        sharedBridge.reinitializeChainGovernance(2, address(1));
    }

    function test_reinitializeChainGovernance_wrongCondition() public {
        address randomL2Bridge = makeAddr("randomL2Bridge");
        vm.prank(owner);
        sharedBridge.initializeChainGovernance(123, randomL2Bridge);

        vm.prank(owner);
        vm.expectRevert(bytes("USDC-ShB: l2 bridge not yet set"));
        sharedBridge.reinitializeChainGovernance(2, randomL2Bridge);
    }

    function test_bridgehubDeposit_wrongCaller() public {
        vm.prank(alice);
        vm.expectRevert("USDC-ShB not BH");
        sharedBridge.bridgehubDeposit(chainId, alice, 0, abi.encode(address(token), amount, bob));
    }

    function test_bridgehubDeposit_wrongL2Value() public {
        vm.prank(bridgehubAddress);
        vm.expectRevert("USDC-ShB: l2Value must be 0");
        sharedBridge.bridgehubDeposit(chainId, alice, 1, abi.encode(address(token), amount, bob));
    }

    function test_bridgehubDeposit_bridgeNotDeployed() public {
        vm.prank(bridgehubAddress);
        vm.expectRevert("USDC-ShB l2 bridge not deployed");
        sharedBridge.bridgehubDeposit(2, alice, 0, abi.encode(address(token), amount, bob));
    }

    function test_bridgehubDeposit_zeroDepositAmount() public {
        vm.expectRevert(bytes("6T"));
        vm.prank(bridgehubAddress);
        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );
        sharedBridge.bridgehubDeposit(chainId, alice, 0, abi.encode(address(token), 0, bob));
    }

    function test_bridgehubDeposit_unsupportedErc() public {
        vm.prank(bridgehubAddress);
        vm.expectRevert("USDC-ShB: Only USDC deposits supported");
        sharedBridge.bridgehubDeposit(chainId, alice, 0, abi.encode(l1WethAddress, amount, bob));
    }

    function test_bridgehubDeposit_Erc_msgValue() public {
        vm.deal(bridgehubAddress, amount);
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(sharedBridge), amount);
        vm.prank(bridgehubAddress);
        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );
        vm.expectRevert("USDC-ShB m.v > 0 for BH d.it 2");
        sharedBridge.bridgehubDeposit{value: amount}(chainId, alice, 0, abi.encode(address(token), amount, bob));
    }

    function test_bridgehubDeposit_Erc_wrongDepositAmount() public {
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(sharedBridge), amount);
        vm.prank(bridgehubAddress);
        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );
        vm.mockCall(address(token), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(10));
        bytes memory message = bytes("5T");
        vm.expectRevert(message);
        sharedBridge.bridgehubDeposit(chainId, alice, 0, abi.encode(address(token), amount, bob));
    }

    function test_bridgehubConfirmL2Transaction_depositAlreadyHappened() public {
        bytes32 txDataHash = keccak256(abi.encode(alice, address(token), amount));
        _setSharedBridgeDepositHappened(chainId, txHash, txDataHash);
        vm.prank(bridgehubAddress);
        vm.expectRevert("USDC-ShB tx hap");
        sharedBridge.bridgehubConfirmL2Transaction(chainId, txDataHash, txHash);
    }

    function test_claimFailedDeposit_proofInvalid() public {
        vm.mockCall(
            bridgehubAddress,
            abi.encodeWithSelector(IBridgehub.proveL1ToL2TransactionStatus.selector),
            abi.encode(address(0))
        );
        vm.prank(bridgehubAddress);
        bytes memory message = bytes("yn");
        vm.expectRevert(message);
        sharedBridge.claimFailedDeposit({
            _chainId: chainId,
            _depositSender: alice,
            _l1Token: ETH_TOKEN_ADDRESS,
            _amount: amount,
            _l2TxHash: txHash,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _merkleProof: merkleProof
        });
    }

    function test_claimFailedDeposit_amountZero() public {
        vm.deal(address(sharedBridge), amount);

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

        bytes memory message = bytes("y1");
        vm.expectRevert(message);
        sharedBridge.claimFailedDeposit({
            _chainId: chainId,
            _depositSender: alice,
            _l1Token: ETH_TOKEN_ADDRESS,
            _amount: 0,
            _l2TxHash: txHash,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _merkleProof: merkleProof
        });
    }

    function test_claimFailedDeposit_depositDidNotHappen() public {
        vm.deal(address(sharedBridge), amount);

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

        vm.expectRevert("USDC-ShB: d.it not hap");
        sharedBridge.claimFailedDeposit({
            _chainId: chainId,
            _depositSender: alice,
            _l1Token: ETH_TOKEN_ADDRESS,
            _amount: amount,
            _l2TxHash: txHash,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _merkleProof: merkleProof
        });
    }

    function test_claimFailedDeposit_chainBalanceLow() public {
        vm.deal(address(sharedBridge), amount);

        bytes32 txDataHash = keccak256(abi.encode(alice, ETH_TOKEN_ADDRESS, amount));
        _setSharedBridgeDepositHappened(chainId, txHash, txDataHash);
        require(sharedBridge.depositHappened(chainId, txHash) == txDataHash, "Deposit not set");

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

        vm.expectRevert("USDC-ShB n funds");
        sharedBridge.claimFailedDeposit({
            _chainId: chainId,
            _depositSender: alice,
            _l1Token: ETH_TOKEN_ADDRESS,
            _amount: amount,
            _l2TxHash: txHash,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _merkleProof: merkleProof
        });
    }

    function test_finalizeWithdrawal_alreadyFinalized() public {
        // set up balances and allowances
        token.mint(address(sharedBridge), amount);
        _setSharedBridgeChainBalance(chainId, address(token), amount);

        bytes memory message =
            abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, alice, address(token), amount);
        L2Message memory l2ToL1Message =
            L2Message({txNumberInBatch: l2TxNumberInBatch, sender: l2USDCBridge, data: message});

        // mock the necessary calls
        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );

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

        // first withdrawal should succeed
        sharedBridge.finalizeWithdrawal(chainId, l2BatchNumber, l2MessageIndex, l2TxNumberInBatch, message, merkleProof);

        // second withdrawal with same parameters should fail
        vm.expectRevert("Withdrawal is already finalized");
        sharedBridge.finalizeWithdrawal(chainId, l2BatchNumber, l2MessageIndex, l2TxNumberInBatch, message, merkleProof);
    }

    function test_finalizeWithdrawal_chainBalance() public {
        vm.deal(address(sharedBridge), amount);

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

        vm.expectRevert("USDC-ShB not enough funds 2");

        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_checkWithdrawal_wrongProof() public {
        vm.deal(address(sharedBridge), amount);

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
            abi.encode(false)
        );

        vm.expectRevert("USDC-ShB withd w proof");

        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_parseL2WithdrawalMessage_WrongMsgLength() public {
        vm.deal(address(sharedBridge), amount);

        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );

        bytes memory message = abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector);

        vm.expectRevert("USDC-ShB wrong msg len 2");
        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_parseL2WithdrawalMessage_WrongMsgLength2() public {
        vm.deal(address(sharedBridge), amount);

        vm.mockCall(
            bridgehubAddress,
            abi.encodeWithSelector(IBridgehub.baseToken.selector, alice, amount),
            abi.encode(ETH_TOKEN_ADDRESS)
        );

        bytes memory message = abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, alice, amount);
        // should have more data here

        vm.expectRevert("USDC-ShB wrong msg len 2");

        sharedBridge.finalizeWithdrawal({
            _chainId: eraChainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_parseL2WithdrawalMessage_WrongSelector() public {
        vm.deal(address(sharedBridge), amount);

        vm.mockCall(
            bridgehubAddress, abi.encodeWithSelector(IBridgehub.baseToken.selector), abi.encode(ETH_TOKEN_ADDRESS)
        );

        // notice that the selector is wrong
        bytes memory message = abi.encodePacked(IMailbox.proveL2LogInclusion.selector, alice, amount);

        vm.expectRevert("USDC-ShB Incorrect message function selector");
        sharedBridge.finalizeWithdrawal({
            _chainId: eraChainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });
    }

    function test_pause_wrongOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        sharedBridge.pause();
    }

    function test_unpause_wrongOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        sharedBridge.unpause();
    }
}
