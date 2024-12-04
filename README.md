# Elastic Chain Custom USDC Bridge
The USDC bridge is an iteration over the [Shared Bridge](https://docs.zksync.io/zk-stack/components/shared-bridges) code
to adhere to the native USDC standard.

## Custom bridge for Native USDC
[![codecov](https://codecov.io/gh/sophon-org/custom-usdc-bridge/graph/badge.svg?token=9YHYPFSMYH)](https://codecov.io/gh/sophon-org/custom-usdc-bridge)


We want to use the canonical zkSync Bridge with a [custom bridge](https://docs.zksync.io/build/developer-reference/bridging-assets#custom-bridges-on-l1-and-l2) implementation that would work only for USDC (since we want to use the [native USDC](https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md) and not the ERC20 that the zksync bridge deploys by default).

The repo implements the [src/L1USDCBridge.sol](https://github.com/sophon-org/custom-usdc-bridge/pull/1/files#diff-1698a2f52c7225fb2a4d7cf5241c28ce85cb4514ffac8a9ec30ab728c4065f6e) and [src/L2USDCBridge.sol](https://github.com/sophon-org/custom-usdc-bridge/pull/1/files#diff-ad529a25299727c85e9b20798cb94a45aaec2709bc7208400fea76e4c2cdb4be) which are custom bridge contracts based on the ones found on [MatterLabs era-contracts](https://github.com/matter-labs/era-contracts) (we've forked from [this](https://github.com/matter-labs/era-contracts.git#bce4b2d0f34bd87f1aaadd291772935afb1c3bd6) commit)

**Bridge/Withdrawal flow**

The flow to bridge and withdraw using custom bridges is the same as when bridging with any token except for the fact that when `Bridgehub` is called, you need specify the address of the custom L1 bridge.

**To bridge USDC from L1 (Ethereum) -> L2 (Sophon):**
- Call `bridgehub.requestL2TransactionTwoBridges` (same as normally) but you set the `secondBridgeAddress` with the custom shared bridge deployed on L1. This way, the bridgehub contracts knows which contract to ping to.
- `requestL2TransactionTwoBridges` makes a call to the custom shared bridge `customBridgeL1.bridgehubDeposit` function and transfers `USDC` from the user to this contract and emits an event.
- sequencers will pick this event and automatically make a call to `customL2Bridge.finalizeDeposit` on the custom bridge deployed on L2 (on Sophon).
- `finalizeDeposit` is the one that calls `usdc.mint()` to mint `USDC` on L2 (**note** this custom bridge must have `MINTER` role on the `USDC` contract).

**To withdraw USDC from L2 (Sophon) -> L1 (Etheruem):**
- User makes a call to `customBridgeL2.withdraw` (same as normally except for the fact that you're calling the custom bridge contract)
- Once the batch is sealed, user needs to call `customL1Bridge.finalizeWithdrawal` to finalise the withdrawal

## Usage

### Build

```shell
$ forge build

# zkSync build
$ forge build --zksync
```

### Scripts

```shell
# Deploy L1 Shared Bridge
$ source .env && forge script ./script/DeployL1USDCBridge.s.sol --rpc-url sepoliaTestnet --private-key $PRIVATE_KEY --verify --broadcast

# Deploy L2 Shared Bridge
$ source .env && forge script ./script/DeployL2USDCBridge.s.sol --rpc-url sophonTestnet --private-key $PRIVATE_KEY --zksync --broadcast --verify --slow

# Initialise L1 Shared Bridge
$ source .env && forge script ./script/InitialiseL1USDCBridge.s.sol --rpc-url sepoliaTestnet --private-key $PRIVATE_KEY --broadcast

# Bridge from Sophon to Ethereum (L1 -> L2)
$ source .env && forge script ./script/Bridge.s.sol --rpc-url sepoliaTestnet --private-key $PRIVATE_KEY --ffi --broadcast

# Withdraw from Sophon to Ethereum (L2 -> L1)
$ source .env && forge script ./script/Withdraw.s.sol --rpc-url sophonTestnet --private-key $PRIVATE_KEY --zksync --slow -vvvv --broadcast

# Finalise withdrawal on Ethereum
$ source .env && export L2_WITHDRAWAL_HASH="YOUR_TX_HASH" && forge script ./script/FinalizeWithdrawal.s.sol --rpc-url sepoliaTestnet --private-key $PRIVATE_KEY --ffi --broadcast
```

### Test

```shell
$ forge test
```

### Coverage
```shell
$ forge coverage --report lcov --no-match-coverage '^.*(node_modules|test|script)/.*$' && genhtml ./lcov.info --branch-coverage --rc derive_function_end_line=0 --output-directory report
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

## License

The Custom USDC Bridge is distributed under the terms of either

- Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or <https://opensource.org/blog/license/mit/>)

at your option.