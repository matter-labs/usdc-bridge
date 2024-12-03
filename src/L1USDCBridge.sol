// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IL1ERC20Bridge} from "@era-contracts/l1-contracts/contracts/bridge/interfaces/IL1ERC20Bridge.sol";
import {IL1SharedBridge} from "./interfaces/IL1SharedBridge.sol";
import {IL2Bridge} from "@era-contracts/l1-contracts/contracts/bridge/interfaces/IL2Bridge.sol";

import {IMailbox} from "@era-contracts/l1-contracts/contracts/state-transition/chain-interfaces/IMailbox.sol";
import {L2Message, TxStatus} from "@era-contracts/l1-contracts/contracts/common/Messaging.sol";
import {UnsafeBytes} from "@era-contracts/l1-contracts/contracts/common/libraries/UnsafeBytes.sol";
import {ReentrancyGuard} from "@era-contracts/l1-contracts/contracts/common/ReentrancyGuard.sol";
import {ETH_TOKEN_ADDRESS, TWO_BRIDGES_MAGIC_VALUE} from "@era-contracts/l1-contracts/contracts/common/Config.sol";
import {
    IBridgehub,
    L2TransactionRequestTwoBridgesInner,
    L2TransactionRequestDirect
} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";
import {IGetters} from "@era-contracts/l1-contracts/contracts/state-transition/chain-interfaces/IGetters.sol";
import {L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR} from "@era-contracts/l1-contracts/contracts/common/L2ContractAddresses.sol";

/// @author Sophon
/// @notice Forked from ML L1USDCBridge contract
/// @custom:security-contact security@matterlabs.dev
/// @dev Bridges assets between L1 and hyperchains, supporting both ETH and ERC20 tokens.
/// @dev Designed for use with a proxy for upgradability.
contract L1USDCBridge is IL1SharedBridge, ReentrancyGuard, Ownable2StepUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev The address of the USDC token on L1.
    address public immutable L1_USDC_TOKEN;

    /// @dev Bridgehub smart contract that is used to operate with L2 via asynchronous L2 <-> L1 communication.
    IBridgehub public immutable override BRIDGE_HUB;

    /// @dev A mapping chainId => bridgeProxy. Used to store the bridge proxy's address, and to see if it has been deployed yet.
    mapping(uint256 chainId => address l2Bridge) public override l2BridgeAddress;

    /// @dev A mapping chainId => L2 deposit transaction hash => keccak256(abi.encode(account, tokenAddress, amount))
    /// @dev Tracks deposit transactions from L2 to enable users to claim their funds if a deposit fails.
    mapping(uint256 chainId => mapping(bytes32 l2DepositTxHash => bytes32 depositDataHash)) public override
        depositHappened;

    /// @dev Tracks the processing status of L2 to L1 messages, indicating whether a message has already been finalized.
    mapping(
        uint256 chainId => mapping(uint256 l2BatchNumber => mapping(uint256 l2ToL1MessageNumber => bool isFinalized))
    ) public isWithdrawalFinalized;

    /// @dev Indicates whether the hyperbridging is enabled for a given chain.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 chainId => bool enabled) internal hyperbridgingEnabled;

    /// @dev Maps token balances for each chain to prevent unauthorized spending across hyperchains.
    /// This serves as a security measure until hyperbridging is implemented.
    /// NOTE: this function may be removed in the future, don't rely on it!
    mapping(uint256 chainId => mapping(address l1Token => uint256 balance)) public chainBalance;

    /// @dev Admin has the ability to register new chains within the shared bridge.
    address public admin;

    /// @dev The pending admin, i.e. the candidate to the admin role.
    address public pendingAdmin;

    /// @notice Checks that the message sender is the bridgehub.
    modifier onlyBridgehub() {
        require(msg.sender == address(BRIDGE_HUB), "USDC-ShB not BH");
        _;
    }

    /// @notice Checks that the message sender is either the owner or admin.
    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner() || msg.sender == admin, "USDC-ShB not owner or admin");
        _;
    }

    /// @dev Contract is expected to be used as proxy implementation.
    /// @dev Initialize the implementation to prevent Parity hack.
    constructor(address _l1UsdcAddress, IBridgehub _bridgehub) reentrancyGuardInitializer {
        _disableInitializers();
        require(_l1UsdcAddress != address(0), "USDC-ShB: l1 usdc is zero address");
        require(address(_bridgehub) != address(0), "USDC-ShB: bridgehub is zero address");
        L1_USDC_TOKEN = _l1UsdcAddress;
        BRIDGE_HUB = _bridgehub;
    }

    /// @dev Initializes a contract bridge for later use. Expected to be used in the proxy
    /// @param _owner Address which can change L2 token implementation and upgrade the bridge
    /// implementation. The owner is the Governor and separate from the ProxyAdmin from now on, so that the Governor can call the bridge.
    function initialize(address _owner) external reentrancyGuardInitializer initializer {
        require(_owner != address(0), "USDC-ShB owner 0");
        _transferOwnership(_owner);
    }

    /// @inheritdoc IL1SharedBridge
    /// @dev Please note, if the owner wants to enforce the admin change it must execute both `setPendingAdmin` and
    /// `acceptAdmin` atomically. Otherwise `admin` can set different pending admin and so fail to accept the admin rights.
    function setPendingAdmin(address _newPendingAdmin) external onlyOwnerOrAdmin {
        // Save previous value into the stack to put it into the event later
        address oldPendingAdmin = pendingAdmin;
        // Change pending admin
        pendingAdmin = _newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, _newPendingAdmin);
    }

    /// @inheritdoc IL1SharedBridge
    /// @notice Accepts transfer of admin rights. Only pending admin can accept the role.
    function acceptAdmin() external {
        address currentPendingAdmin = pendingAdmin;
        require(msg.sender == currentPendingAdmin, "USDC-ShB not pending admin"); // Only proposed by current admin address can claim the admin rights

        address previousAdmin = admin;
        admin = currentPendingAdmin;
        delete pendingAdmin;

        emit NewPendingAdmin(currentPendingAdmin, address(0));
        emit NewAdmin(previousAdmin, currentPendingAdmin);
    }

    /// @dev Initializes the l2Bridge address by governance for a specific chain.
    /// @param _chainId The chain ID for which the l2Bridge address is being initialized.
    /// @param _l2BridgeAddress The address of the L2 bridge contract.
    function initializeChainGovernance(uint256 _chainId, address _l2BridgeAddress) external onlyOwnerOrAdmin {
        require(l2BridgeAddress[_chainId] == address(0), "USDC-ShB: l2 bridge already set");
        require(_l2BridgeAddress != address(0), "USDC-ShB: l2 bridge 0");
        l2BridgeAddress[_chainId] = _l2BridgeAddress;
    }

    /// @dev Reinitializes the l2Bridge address by governance for a specific chain.
    /// @dev Only accessible to the owner of the bridge to prevent malicious admin from changing the bridge address for
    /// an existing chain.
    /// @param _chainId The chain ID for which the l2Bridge address is being initialized.
    /// @param _l2BridgeAddress The address of the L2 bridge contract.
    function reinitializeChainGovernance(uint256 _chainId, address _l2BridgeAddress) external onlyOwner {
        require(l2BridgeAddress[_chainId] != address(0), "USDC-ShB: l2 bridge not yet set");
        l2BridgeAddress[_chainId] = _l2BridgeAddress;
    }

    /// @dev Transfers tokens from the depositor address to the smart contract address.
    /// @return The difference between the contract balance before and after the transferring of funds.
    function _depositFunds(address _from, IERC20 _token, uint256 _amount) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        // slither-disable-next-line arbitrary-send-erc20
        _token.safeTransferFrom(_from, address(this), _amount);
        uint256 balanceAfter = _token.balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    /// @notice Initiates a deposit transaction within Bridgehub, used by `requestL2TransactionTwoBridges`.
    function bridgehubDeposit(uint256 _chainId, address _prevMsgSender, uint256 _l2Value, bytes calldata _data)
        external
        payable
        override
        onlyBridgehub
        whenNotPaused
        returns (L2TransactionRequestTwoBridgesInner memory request)
    {
        require(_l2Value == 0, "USDC-ShB: l2Value must be 0");
        address l2Bridge = l2BridgeAddress[_chainId];
        require(l2Bridge != address(0), "USDC-ShB l2 bridge not deployed");

        (address _l1Token, uint256 _depositAmount, address _l2Receiver) = abi.decode(_data, (address, uint256, address));
        require(_l1Token == L1_USDC_TOKEN, "USDC-ShB: Only USDC deposits supported");
        require(BRIDGE_HUB.baseToken(_chainId) != _l1Token, "USDC-ShB: baseToken deposit not supported");
        require(msg.value == 0, "USDC-ShB m.v > 0 for BH d.it 2");

        uint256 withdrawAmount = _depositFunds(_prevMsgSender, IERC20(_l1Token), _depositAmount);
        require(withdrawAmount == _depositAmount, "5T"); // The token has non-standard transfer logic
        require(_depositAmount != 0, "6T"); // empty deposit amount

        bytes32 txDataHash = keccak256(abi.encode(_prevMsgSender, _l1Token, _depositAmount));
        if (!hyperbridgingEnabled[_chainId]) {
            chainBalance[_chainId][_l1Token] += _depositAmount;
        }

        // Request the finalization of the deposit on the L2 side
        bytes memory l2TxCalldata = abi.encodeCall(
            IL2Bridge.finalizeDeposit,
            (_prevMsgSender, _l2Receiver, _l1Token, _depositAmount, abi.encode("USD Coin", "USDC", 6))
        );

        request = L2TransactionRequestTwoBridgesInner({
            magicValue: TWO_BRIDGES_MAGIC_VALUE,
            l2Contract: l2Bridge,
            l2Calldata: l2TxCalldata,
            factoryDeps: new bytes[](0),
            txDataHash: txDataHash
        });

        emit BridgehubDepositInitiated({
            chainId: _chainId,
            txDataHash: txDataHash,
            from: _prevMsgSender,
            to: _l2Receiver,
            l1Token: _l1Token,
            amount: _depositAmount
        });
    }

    /// @notice Confirms the acceptance of a transaction by the Mailbox, as part of the L2 transaction process within Bridgehub.
    /// This function is utilized by `requestL2TransactionTwoBridges` to validate the execution of a transaction.
    function bridgehubConfirmL2Transaction(uint256 _chainId, bytes32 _txDataHash, bytes32 _txHash)
        external
        override
        onlyBridgehub
        whenNotPaused
    {
        require(depositHappened[_chainId][_txHash] == 0x00, "USDC-ShB tx hap");
        depositHappened[_chainId][_txHash] = _txDataHash;
        emit BridgehubDepositFinalized(_chainId, _txDataHash, _txHash);
    }

    /// @dev Withdraw funds from the initiated deposit, that failed when finalizing on L2
    /// @param _depositSender The address of the deposit initiator
    /// @param _l1Token The address of the deposited L1 ERC20 token
    /// @param _amount The amount of the deposit that failed.
    /// @param _l2TxHash The L2 transaction hash of the failed deposit finalization
    /// @param _l2BatchNumber The L2 batch number where the deposit finalization was processed
    /// @param _l2MessageIndex The position in the L2 logs Merkle tree of the l2Log that was sent with the message
    /// @param _l2TxNumberInBatch The L2 transaction number in a batch, in which the log was sent
    /// @param _merkleProof The Merkle proof of the processing L1 -> L2 transaction with deposit finalization
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
    ) external override {
        _claimFailedDeposit({
            _chainId: _chainId,
            _depositSender: _depositSender,
            _l1Token: _l1Token,
            _amount: _amount,
            _l2TxHash: _l2TxHash,
            _l2BatchNumber: _l2BatchNumber,
            _l2MessageIndex: _l2MessageIndex,
            _l2TxNumberInBatch: _l2TxNumberInBatch,
            _merkleProof: _merkleProof
        });
    }

    /// @dev Processes claims of failed deposit.
    function _claimFailedDeposit(
        uint256 _chainId,
        address _depositSender,
        address _l1Token,
        uint256 _amount,
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof
    ) internal nonReentrant whenNotPaused {
        bool proofValid = BRIDGE_HUB.proveL1ToL2TransactionStatus({
            _chainId: _chainId,
            _l2TxHash: _l2TxHash,
            _l2BatchNumber: _l2BatchNumber,
            _l2MessageIndex: _l2MessageIndex,
            _l2TxNumberInBatch: _l2TxNumberInBatch,
            _merkleProof: _merkleProof,
            _status: TxStatus.Failure
        });
        require(proofValid, "yn");
        require(_amount > 0, "y1");

        // dataHash == txDataHash
        require(
            depositHappened[_chainId][_l2TxHash] == keccak256(abi.encode(_depositSender, _l1Token, _amount)),
            "USDC-ShB: d.it not hap"
        );
        delete depositHappened[_chainId][_l2TxHash];

        if (!hyperbridgingEnabled[_chainId]) {
            // check that the chain has sufficient balance
            require(chainBalance[_chainId][_l1Token] >= _amount, "USDC-ShB n funds");
            chainBalance[_chainId][_l1Token] -= _amount;
        }

        // Withdraw funds
        IERC20(_l1Token).safeTransfer(_depositSender, _amount);

        emit ClaimedFailedDepositSharedBridge(_chainId, _depositSender, _l1Token, _amount);
    }

    /// @notice Finalize the withdrawal and release funds
    /// @param _chainId The chain ID of the transaction to check
    /// @param _l2BatchNumber The L2 batch number where the withdrawal was processed
    /// @param _l2MessageIndex The position in the L2 logs Merkle tree of the l2Log that was sent with the message
    /// @param _l2TxNumberInBatch The L2 transaction number in the batch, in which the log was sent
    /// @param _message The L2 withdraw data, stored in an L2 -> L1 message
    /// @param _merkleProof The Merkle proof of the inclusion L2 -> L1 message about withdrawal initialization
    function finalizeWithdrawal(
        uint256 _chainId,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external override {
        // Note: new withdraws are all recorded here, so double withdrawing them is not possible.
        _finalizeWithdrawal({
            _chainId: _chainId,
            _l2BatchNumber: _l2BatchNumber,
            _l2MessageIndex: _l2MessageIndex,
            _l2TxNumberInBatch: _l2TxNumberInBatch,
            _message: _message,
            _merkleProof: _merkleProof
        });
    }

    struct MessageParams {
        uint256 l2BatchNumber;
        uint256 l2MessageIndex;
        uint16 l2TxNumberInBatch;
    }

    /// @dev Internal function that handles the logic for finalizing withdrawals,
    /// serving the current bridge system.
    function _finalizeWithdrawal(
        uint256 _chainId,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) internal nonReentrant whenNotPaused returns (address l1Receiver, address l1Token, uint256 amount) {
        require(!isWithdrawalFinalized[_chainId][_l2BatchNumber][_l2MessageIndex], "Withdrawal is already finalized");
        isWithdrawalFinalized[_chainId][_l2BatchNumber][_l2MessageIndex] = true;

        MessageParams memory messageParams = MessageParams({
            l2BatchNumber: _l2BatchNumber,
            l2MessageIndex: _l2MessageIndex,
            l2TxNumberInBatch: _l2TxNumberInBatch
        });
        (l1Receiver, l1Token, amount) = _checkWithdrawal(_chainId, messageParams, _message, _merkleProof);

        if (!hyperbridgingEnabled[_chainId]) {
            // Check that the chain has sufficient balance
            require(chainBalance[_chainId][l1Token] >= amount, "USDC-ShB not enough funds 2"); // not enough funds
            chainBalance[_chainId][l1Token] -= amount;
        }

        // Withdraw funds
        IERC20(l1Token).safeTransfer(l1Receiver, amount);

        emit WithdrawalFinalizedSharedBridge(_chainId, l1Receiver, l1Token, amount);
    }

    /// @dev Verifies the validity of a withdrawal message from L2 and returns details of the withdrawal.
    function _checkWithdrawal(
        uint256 _chainId,
        MessageParams memory _messageParams,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) internal view returns (address l1Receiver, address l1Token, uint256 amount) {
        (l1Receiver, l1Token, amount) = _parseL2WithdrawalMessage(_message);
        L2Message memory l2ToL1Message;
        {
            bool baseTokenWithdrawal = (l1Token == BRIDGE_HUB.baseToken(_chainId));
            address l2Sender = baseTokenWithdrawal ? L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR : l2BridgeAddress[_chainId];

            l2ToL1Message =
                L2Message({txNumberInBatch: _messageParams.l2TxNumberInBatch, sender: l2Sender, data: _message});
        }

        bool success = BRIDGE_HUB.proveL2MessageInclusion({
            _chainId: _chainId,
            _batchNumber: _messageParams.l2BatchNumber,
            _index: _messageParams.l2MessageIndex,
            _message: l2ToL1Message,
            _proof: _merkleProof
        });
        require(success, "USDC-ShB withd w proof"); // withdrawal wrong proof
    }

    function _parseL2WithdrawalMessage(bytes memory _l2ToL1message)
        internal
        pure
        returns (address l1Receiver, address l1Token, uint256 amount)
    {
        // We check that the message is long enough to read the data.
        // Please note that there are two versions of the message:
        // 1. The message that is sent by `withdraw(address _l1Receiver)`
        // It should be equal to the length of the bytes4 function signature + address l1Receiver + uint256 amount = 4 + 20 + 32 = 56 (bytes).
        // 2. The message that is sent by `withdrawWithMessage(address _l1Receiver, bytes calldata _additionalData)`
        // It should be equal to the length of the following:
        // bytes4 function signature + address l1Receiver + uint256 amount + address l2Sender + bytes _additionalData =
        // = 4 + 20 + 32 + 32 + _additionalData.length >= 68 (bytes).
        (uint32 functionSignature, uint256 offset) = UnsafeBytes.readUint32(_l2ToL1message, 0);
        if (bytes4(functionSignature) == IL1ERC20Bridge.finalizeWithdrawal.selector) {
            // We use the IL1ERC20Bridge for backward compatibility with old withdrawals.

            // this message is a token withdrawal

            // Check that the message length is correct.
            // It should be equal to the length of the function signature + address + address + uint256 = 4 + 20 + 20 + 32 =
            // 76 (bytes).
            require(_l2ToL1message.length == 76, "USDC-ShB wrong msg len 2");
            (l1Receiver, offset) = UnsafeBytes.readAddress(_l2ToL1message, offset);
            (l1Token, offset) = UnsafeBytes.readAddress(_l2ToL1message, offset);
            (amount, offset) = UnsafeBytes.readUint256(_l2ToL1message, offset);
        } else {
            revert("USDC-ShB Incorrect message function selector");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all functions marked with the `whenNotPaused` modifier.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing all functions marked with the `whenNotPaused` modifier to be called again.
    function unpause() external onlyOwner {
        _unpause();
    }
}
