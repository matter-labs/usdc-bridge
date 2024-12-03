// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IL2SharedBridge} from "@era-contracts/l2-contracts/contracts/bridge/interfaces/IL2SharedBridge.sol";
import {DeploymentUtils} from "../utils/DeploymentUtils.sol";

interface Proxy {
    function admin() external view returns (address);
    function changeAdmin(address newAdmin) external;
}

contract WithdrawScript is Script, DeploymentUtils {
    function setUp() public {}

    function run() public {
        IERC20 token = IERC20(getDeployedContract("USDC"));
        address l2USDCBridge = getDeployedContract("L2USDCBridge");
        uint256 amountToWithdraw = 1 * 10 ** 6; // 1 USDC

        vm.startBroadcast();

        // approve shared bridge to spend USDC tokens
        uint256 allowance = token.allowance(msg.sender, l2USDCBridge);
        console.log("USDC allowance:", allowance);
        if (allowance < amountToWithdraw) {
            console.log("Approving tokens for withdrawal");
            token.approve(l2USDCBridge, type(uint256).max);
            console.log("USDC allowance:", token.allowance(msg.sender, l2USDCBridge));
        }

        IL2SharedBridge bridgeL2 = IL2SharedBridge(l2USDCBridge);
        bridgeL2.withdraw(msg.sender, address(0), amountToWithdraw);

        vm.stopBroadcast();
    }
}
