// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IL1ERC20Bridge} from "./interfaces/IL1ERC20Bridge.sol";
import {IL2SharedBridge} from "./interfaces/IL2SharedBridge.sol";
import {IL2Messenger} from "./interfaces/IL2Messenger.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface MintableToken {
    function mint(address _to, uint256 _amount) external;
    function burn(uint256 _amount) external;
}

/// @author Sophon
/// @notice Forked from ML L1USDCBridge contract
/// @custom:security-contact security@matterlabs.dev
/// @notice The "default" bridge implementation for the ERC20 tokens. Note, that it does not
/// support any custom token logic, i.e. rebase tokens' functionality is not supported.
contract L2USDCBridge is IL2SharedBridge, Initializable {
    using SafeERC20 for IERC20;

    uint160 constant SYSTEM_CONTRACTS_OFFSET = 0x8000; // 2^15
    address constant L2_MESSENGER = address(SYSTEM_CONTRACTS_OFFSET + 0x08);

    /// @dev The address of the L1 shared bridge counterpart.
    address public override l1USDCBridge;

    /// @dev Contract is expected to be used as proxy implementation.
    /// @dev Disable the initialization to prevent Parity hack.

    /// @dev The address of the USDC token on L1.
    address public immutable L1_USDC_TOKEN;

    /// @dev The address of the USDC token on L2.
    address public immutable L2_USDC_TOKEN;

    constructor(address _l1UsdcToken, address _l2UsdcToken) {
        require(_l1UsdcToken != address(0), "USDC-ShB: l1UsdcToken is zero address");
        require(address(_l2UsdcToken) != address(0), "USDC-ShB: l2UsdcToken is zero address");
        L1_USDC_TOKEN = _l1UsdcToken;
        L2_USDC_TOKEN = _l2UsdcToken;
        _disableInitializers();
    }

    /// @notice Initializes the bridge contract for later use. Expected to be used in the proxy.
    /// @param _l1USDCBridge The address of the L1 Bridge contract.
    /// _l1Bridge The address of the legacy L1 Bridge contract.
    function initialize(address _l1USDCBridge) external reinitializer(1) {
        require(_l1USDCBridge != address(0), "bf");
        l1USDCBridge = _l1USDCBridge;
    }

    /// @notice Finalize the deposit and mint funds
    /// @param _l1Sender The account address that initiated the deposit on L1
    /// @param _l2Receiver The account address that would receive minted ether
    /// _l1Token The address of the token that was locked on the L1
    /// @param _amount Total amount of tokens deposited from L1
    /// _data [UNUSED] The additional data that user can pass with the deposit
    function finalizeDeposit(address _l1Sender, address _l2Receiver, address, uint256 _amount, bytes calldata)
        external
        override
    {
        // Only the L1 bridge counterpart can initiate and finalize the deposit.
        require(undoL1ToL2Alias(msg.sender) == l1USDCBridge, "mq");
        MintableToken(L2_USDC_TOKEN).mint(_l2Receiver, _amount);
        emit FinalizeDeposit(_l1Sender, _l2Receiver, L2_USDC_TOKEN, _amount);
    }

    /// @notice Initiates a withdrawal by burning funds on the contract and sending the message to L1
    /// where tokens would be unlocked
    /// @param _l1Receiver The account address that should receive funds on L1
    /// _l2Token The L2 token address which is withdrawn
    /// @param _amount The total amount of tokens to be withdrawn
    function withdraw(address _l1Receiver, address, uint256 _amount) external override {
        require(_amount > 0, "Amount cannot be zero");

        // transfer from msg.sender to here and then burn
        IERC20(L2_USDC_TOKEN).safeTransferFrom(msg.sender, address(this), _amount);
        MintableToken(L2_USDC_TOKEN).burn(_amount);

        // encode the message for l2ToL1log sent with withdraw initialization
        bytes memory message =
            abi.encodePacked(IL1ERC20Bridge.finalizeWithdrawal.selector, _l1Receiver, L1_USDC_TOKEN, _amount);
        IL2Messenger(L2_MESSENGER).sendToL1(message);

        emit WithdrawalInitiated(msg.sender, _l1Receiver, L2_USDC_TOKEN, _amount);
    }

    function l1TokenAddress(address _l2Token) external view returns (address) {
        require(_l2Token == L2_USDC_TOKEN, "Unsupported L2 token");
        return L1_USDC_TOKEN;
    }

    function l2TokenAddress(address _l1Token) public view override returns (address) {
        require(_l1Token == L1_USDC_TOKEN, "Unsupported L1 token");
        return L2_USDC_TOKEN;
    }

    /*//////////////////////////////////////////////////////////////
                            UTILS
    //////////////////////////////////////////////////////////////*/

    /// @notice Utility function that converts the msg.sender viewed on L2 to the
    /// address that submitted a tx to the inbox on L1
    /// @param l2Address L2 address as viewed in msg.sender
    /// @return l1Address the address in the L1 that triggered the tx to L2
    function undoL1ToL2Alias(address l2Address) internal pure returns (address l1Address) {
        uint160 offset = uint160(0x1111000000000000000000000000000000001111);
        unchecked {
            l1Address = address(uint160(l2Address) - offset);
        }
    }
}
