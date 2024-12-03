// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.24;

// import {console} from "forge-std/Script.sol";
// import {SharedBridgesTest} from "./SharedBridgesTest.sol";
// import {
//     L2TransactionRequestTwoBridgesOuter,
//     IBridgehub
// } from "@era-contracts/l1-contracts/contracts/bridgehub/IBridgehub.sol";
// import {AdressAliasHelper} from "@era-contracts/l1-contracts/contracts/dev-contracts/test/AddressAliasHelperTest.sol";
// import {L2USDCBridge} from "../../src/L2USDCBridge.sol";

// // IERC20 MockUSDC compatible
// interface IERC20 {
//     function approve(address usr, uint256 wad) external;
//     function allowance(address owner, address spender) external view returns (uint256);
//     function balanceOf(address account) external view returns (uint256);
// }

// contract BridgeWithdrawalTest is SharedBridgesTest {
//     event BridgehubDepositInitiated(
//         uint256 indexed chainId,
//         bytes32 indexed txDataHash,
//         address indexed from,
//         address to,
//         address l1Token,
//         uint256 amount
//     );

//     function test_bridgeWithdrawal() public {
//         uint256 amountToBridge = 1 * 10 ** 6; // 1 USDC
//         address usdc = vm.envAddress("L1_USDC_TOKEN");

//         ///// L1 CALLS /////

//         // add SOPH balance
//         deal(vm.envAddress("SOPH_TOKEN"), alice, 100e18);

//         // add USDC balance
//         deal(usdc, alice, amountToBridge);

//         vm.prank(alice);
//         IERC20(vm.envAddress("SOPH_TOKEN")).approve(vm.envAddress("SEPOLIA_SHARED_BRIDGE_L1"), type(uint256).max);

//         vm.prank(alice);
//         IERC20(usdc).approve(l1USDCBridge, amountToBridge);

//         console.log("Allowance: ", IERC20(usdc).allowance(alice, l1USDCBridge));
//         console.log("Allowance: ", IERC20(vm.envAddress("SOPH_TOKEN")).allowance(alice, l1USDCBridge));
//         console.log("Balance: ", IERC20(usdc).balanceOf(alice));
//         console.log("Balance: ", IERC20(vm.envAddress("SOPH_TOKEN")).balanceOf(alice));

//         // prepare data for the bridgehubDeposit call
//         bytes memory depositData = abi.encode(
//             usdc,
//             amountToBridge,
//             alice // sender is the recipient of the tokens on L2
//         );

//         // bridge
//         uint256 L2_GAS_LIMIT = 435293;
//         uint256 TX_GAS_PER_PUBDATA_BYTE_LIMIT = 800;
//         uint256 CHAIN_ID = vm.envUint("SOPHON_SEPOLIA_CHAIN_ID"); // Sophon Sepolia

//         bytes32 txDataHash = keccak256(abi.encode(alice, usdc, amountToBridge));
//         vm.expectEmit(true, true, true, true);
//         emit BridgehubDepositInitiated(CHAIN_ID, txDataHash, alice, alice, usdc, amountToBridge);

//         vm.startPrank(alice);
//         IBridgehub(vm.envAddress("SEPOLIA_L1_BRIDGEHUB")).requestL2TransactionTwoBridges( // No vale needed if base token is not ETH (e.g SOPH)
//             L2TransactionRequestTwoBridgesOuter({
//                 chainId: CHAIN_ID,
//                 mintValue: 2e18, // base tokens (SOPH for Sophon Sepolia, ETH for Sepolia)
//                 // mintValue: baseCost,
//                 l2Value: 0,
//                 l2GasLimit: L2_GAS_LIMIT, // TODO: it should take ~300'000
//                 l2GasPerPubdataByteLimit: TX_GAS_PER_PUBDATA_BYTE_LIMIT, // TODO: how to calculate?
//                 refundRecipient: address(0), // TODO: why is 0?
//                 secondBridgeAddress: l1USDCBridge,
//                 secondBridgeValue: 0,
//                 secondBridgeCalldata: depositData
//             })
//         );
//         vm.stopPrank();

//         ///// L2 CALLS /////

//         vm.selectFork(sophonTestnet);
//         // finalise deposit on L2
//         vm.prank(AdressAliasHelper.undoL1ToL2Alias(l1USDCBridge));
//         L2USDCBridge(l2USDCBridge).finalizeDeposit(alice, alice, usdc, amountToBridge, depositData);

//         // asert balances before and after

//         // withdraw on L2
//         vm.prank(alice);
//         L2USDCBridge(l2USDCBridge).withdraw(alice, address(0), amountToBridge);

//         ///// L1 CALLS /////
//         vm.selectFork(sepoliaTestnet);

//         // finalize withdrawal on L1

//     }
// }
