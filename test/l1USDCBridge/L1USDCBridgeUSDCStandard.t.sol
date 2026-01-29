// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {L1USDCBridge} from "../../src/L1USDCBridge.sol";
import {IBridgehub} from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";

contract MockUSDC is ERC20 {
    address public owner;
    mapping(address => bool) public minters;

    constructor() ERC20("Mock USDC", "USDC") {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "MockUSDC: not owner");
        _mint(to, amount);
    }

    function configureMinter(address minter, bool allowed) external {
        require(msg.sender == owner, "MockUSDC: not owner");
        minters[minter] = allowed;
    }

    function burn(uint256 amount) external {
        require(minters[msg.sender], "MockUSDC: not minter");
        _burn(msg.sender, amount);
    }
}

contract L1USDCBridgeUSDCStandardTest is Test {
    L1USDCBridge bridge;
    MockUSDC usdc;

    address owner;
    address circle;
    address proxyAdmin;

    function setUp() public {
        owner = makeAddr("owner");
        circle = makeAddr("circle");
        proxyAdmin = makeAddr("proxyAdmin");

        usdc = new MockUSDC();
        L1USDCBridge impl = new L1USDCBridge({_l1UsdcAddress: address(usdc), _bridgehub: IBridgehub(makeAddr("bh"))});
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl), proxyAdmin, abi.encodeWithSelector(L1USDCBridge.initialize.selector, owner)
        );
        bridge = L1USDCBridge(payable(proxy));
    }

    function test_burnLockedUSDC() public {
        uint256 lockedSupply = 100e6;

        usdc.mint(address(bridge), lockedSupply);
        usdc.configureMinter(address(bridge), true);

        vm.prank(owner);
        bridge.setCircleBurnCaller(circle);

        vm.prank(owner);
        bridge.pause();
        vm.prank(owner);
        bridge.finalizeSupplyLock(lockedSupply);

        uint256 totalBefore = usdc.totalSupply();

        vm.prank(circle);
        bridge.burnLockedUSDC();

        assertEq(usdc.balanceOf(address(bridge)), 0);
        assertEq(usdc.totalSupply(), totalBefore - lockedSupply);
    }

    function test_burnLockedUSDC_revertWhenNotPaused() public {
        uint256 lockedSupply = 1e6;
        usdc.mint(address(bridge), lockedSupply);
        usdc.configureMinter(address(bridge), true);

        vm.prank(owner);
        bridge.setCircleBurnCaller(circle);
        vm.prank(owner);
        bridge.pause();
        vm.prank(owner);
        bridge.finalizeSupplyLock(lockedSupply);
        vm.prank(owner);
        bridge.unpause();

        vm.prank(circle);
        vm.expectRevert("Pausable: not paused");
        bridge.burnLockedUSDC();
    }

    function test_finalizeSupplyLock_revertIfAlreadyFinalized() public {
        vm.prank(owner);
        bridge.pause();
        vm.prank(owner);
        bridge.finalizeSupplyLock(1);

        vm.prank(owner);
        vm.expectRevert("USDC-ShB: supply lock finalized");
        bridge.finalizeSupplyLock(1);
    }
}
