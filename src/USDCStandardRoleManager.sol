// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

interface IFiatTokenOwner {
    function transferOwnership(address newOwner) external;
}

interface IFiatTokenMasterMinter {
    function updateMasterMinter(address newMasterMinter) external;
    function removeMinter(address minter) external returns (bool);
}

interface IAdminUpgradeabilityProxy {
    function admin() external view returns (address);
    function changeAdmin(address newAdmin) external;
}

/// @notice Role manager for bridged USDC standard upgrades.
contract USDCStandardRoleManager is Initializable, Ownable2StepUpgradeable {
    /// @dev USDC proxy address (FiatToken proxy).
    address public usdcProxy;

    /// @dev Circle-controlled address allowed to call transferUSDCRoles.
    address public circleRoleCaller;

    /// @dev Optional L2 bridge address (typically a minter).
    address public l2USDCBridge;

    /// @dev Managed minter list to be removed before role transfer.
    address[] private managedMinters;
    mapping(address => bool) public isManagedMinter;

    /// @dev Marks whether roles have been transferred.
    bool public rolesTransferred;

    event CircleRoleCallerUpdated(address indexed oldCaller, address indexed newCaller);
    event L2USDCBridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event ManagedMinterAdded(address indexed minter);
    event ManagedMinterRemoved(address indexed minter);
    event RolesTransferred(address indexed caller, address indexed newOwner, address indexed newAdmin);

    modifier onlyCircleRoleCaller() {
        require(msg.sender == circleRoleCaller, "USDC-RoleMgr: not circle caller");
        _;
    }

    function initialize(address _owner, address _usdcProxy, address _circleRoleCaller, address _l2USDCBridge)
        external
        initializer
    {
        require(_owner != address(0), "USDC-RoleMgr: owner 0");
        require(_usdcProxy != address(0), "USDC-RoleMgr: usdc 0");
        require(_circleRoleCaller != address(0), "USDC-RoleMgr: circle caller 0");

        __Ownable2Step_init();
        _transferOwnership(_owner);

        usdcProxy = _usdcProxy;
        circleRoleCaller = _circleRoleCaller;
        l2USDCBridge = _l2USDCBridge;

        if (_l2USDCBridge != address(0)) {
            _addManagedMinter(_l2USDCBridge);
        }
    }

    function setCircleRoleCaller(address _caller) external onlyOwner {
        require(_caller != address(0), "USDC-RoleMgr: circle caller 0");
        address oldCaller = circleRoleCaller;
        circleRoleCaller = _caller;
        emit CircleRoleCallerUpdated(oldCaller, _caller);
    }

    function setL2USDCBridge(address _bridge) external onlyOwner {
        address oldBridge = l2USDCBridge;
        l2USDCBridge = _bridge;
        emit L2USDCBridgeUpdated(oldBridge, _bridge);
    }

    function getManagedMinters() external view returns (address[] memory) {
        return managedMinters;
    }

    function addManagedMinter(address minter) external onlyOwner {
        _addManagedMinter(minter);
    }

    function removeManagedMinter(address minter) external onlyOwner {
        require(isManagedMinter[minter], "USDC-RoleMgr: not managed");
        isManagedMinter[minter] = false;

        uint256 length = managedMinters.length;
        for (uint256 i = 0; i < length; i++) {
            if (managedMinters[i] == minter) {
                managedMinters[i] = managedMinters[length - 1];
                managedMinters.pop();
                break;
            }
        }

        emit ManagedMinterRemoved(minter);
    }

    /// @notice Transfers USDC roles to Circle-controlled addresses.
    /// @param newOwner The new implementation owner address.
    function transferUSDCRoles(address newOwner) external onlyCircleRoleCaller {
        require(!rolesTransferred, "USDC-RoleMgr: roles transferred");
        require(newOwner != address(0), "USDC-RoleMgr: new owner 0");

        _removeManagedMinters();

        address newAdmin = address(0);
        if (IAdminUpgradeabilityProxy(usdcProxy).admin() == address(this)) {
            IAdminUpgradeabilityProxy(usdcProxy).changeAdmin(msg.sender);
            newAdmin = msg.sender;
        }

        IFiatTokenMasterMinter(usdcProxy).updateMasterMinter(newOwner);
        IFiatTokenOwner(usdcProxy).transferOwnership(newOwner);

        rolesTransferred = true;
        emit RolesTransferred(msg.sender, newOwner, newAdmin);
    }

    function _addManagedMinter(address minter) internal {
        require(minter != address(0), "USDC-RoleMgr: minter 0");
        require(!isManagedMinter[minter], "USDC-RoleMgr: already managed");
        isManagedMinter[minter] = true;
        managedMinters.push(minter);
        emit ManagedMinterAdded(minter);
    }

    function _removeManagedMinters() internal {
        uint256 length = managedMinters.length;
        for (uint256 i = 0; i < length; i++) {
            address minter = managedMinters[i];
            if (minter != address(0)) {
                IFiatTokenMasterMinter(usdcProxy).removeMinter(minter);
            }
        }
    }
}
