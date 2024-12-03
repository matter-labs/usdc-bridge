// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import {Script, console} from "forge-std/Script.sol";
// import {L2USDCBridge} from "../src/L2USDCBridge.sol";

// contract FinalizeDepositScript is Script {
//     L2USDCBridge public bridge;

//     address public constant L1_USDC_TOKEN = 0xBF4FdF7BF4014EA78C0A07259FBc4315Cb10d94E; // MockUSDC on Sepolia testnet
//     address public constant L2_USDC_TOKEN = 0x27553b610304b6AB77855a963f8208443D773E60; // Native USDC on Sophon testnet
//     address public constant SOPHON_CUSTOM_SHARED_BRIDGE_L2 = 0x71b5B0B667F313f79F980dEa1ee564298564Cd7e; // Sophon Sepolia

//     function setUp() public {}

//     function run() public {
//         vm.startBroadcast();

//         uint256 amountToBridge = 1 * 10 ** 6; // 1 USDC

//         bytes memory depositData = abi.encode(
//             L1_USDC_TOKEN,
//             amountToBridge,
//             msg.sender // sender is the recipient of the tokens on L2
//         );

//         L2USDCBridge(SOPHON_CUSTOM_SHARED_BRIDGE_L2).finalizeDeposit(
//             msg.sender, msg.sender, L1_USDC_TOKEN, amountToBridge, depositData
//         );

//         vm.stopBroadcast();
//     }
// }
