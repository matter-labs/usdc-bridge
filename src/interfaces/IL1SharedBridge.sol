// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {
    IBridgehub,
    L2TransactionRequestTwoBridgesInner
} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";
import {IL1ERC20Bridge} from "./IL1ERC20Bridge.sol";

/// @title L1 Bridge contract interface
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IL1SharedBridge {
    /// @notice pendingAdmin is changed
    /// @dev Also emitted when new admin is accepted and in this case, `newPendingAdmin` would be zero address
    event NewPendingAdmin(address indexed oldPendingAdmin, address indexed newPendingAdmin);

    /// @notice Admin changed
    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);

    event LegacyDepositInitiated(
        uint256 indexed chainId,
        bytes32 indexed l2DepositTxHash,
        address indexed from,
        address to,
        address l1Token,
        uint256 amount
    );

    event BridgehubDepositInitiated(
        uint256 indexed chainId,
        bytes32 indexed txDataHash,
        address indexed from,
        address to,
        address l1Token,
        uint256 amount
    );

    event BridgehubDepositBaseTokenInitiated(
        uint256 indexed chainId, address indexed from, address l1Token, uint256 amount
    );

    event BridgehubDepositFinalized(
        uint256 indexed chainId, bytes32 indexed txDataHash, bytes32 indexed l2DepositTxHash
    );

    event WithdrawalFinalizedSharedBridge(
        uint256 indexed chainId, address indexed to, address indexed l1Token, uint256 amount
    );

    event ClaimedFailedDepositSharedBridge(
        uint256 indexed chainId, address indexed to, address indexed l1Token, uint256 amount
    );

    function isWithdrawalFinalized(uint256 _chainId, uint256 _l2BatchNumber, uint256 _l2MessageIndex)
        external
        view
        returns (bool);

    function claimFailedDeposit(
        uint256 _chainId,
        address _depositSender,
        address _l1Token,
        uint256 _amount,
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof
    ) external;

    function finalizeWithdrawal(
        uint256 _chainId,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external;

    function BRIDGE_HUB() external view returns (IBridgehub);

    function l2BridgeAddress(uint256 _chainId) external view returns (address);

    function depositHappened(uint256 _chainId, bytes32 _l2TxHash) external view returns (bytes32);

    /// data is abi encoded :
    /// address _l1Token,
    /// uint256 _amount,
    /// address _l2Receiver
    function bridgehubDeposit(uint256 _chainId, address _prevMsgSender, uint256 _l2Value, bytes calldata _data)
        external
        payable
        returns (L2TransactionRequestTwoBridgesInner memory request);

    function bridgehubConfirmL2Transaction(uint256 _chainId, bytes32 _txDataHash, bytes32 _txHash) external;

    /// @notice Starts the transfer of admin rights. Only the current admin can propose a new pending one.
    /// @notice New admin can accept admin rights by calling `acceptAdmin` function.
    /// @param _newPendingAdmin Address of the new admin
    function setPendingAdmin(address _newPendingAdmin) external;

    /// @notice Accepts transfer of admin rights. Only pending admin can accept the role.
    function acceptAdmin() external;
}
