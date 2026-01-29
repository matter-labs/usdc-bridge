# USDC Bridged Standard Update Plan

Source of truth: `external/stablecoin-evm/doc/bridged_USDC_standard.md`.

## Decisions

1. **Supply lock + burn amount**
   - Use a one-time `supplyLockFinalized` flag and `lockedSupply` value on L1.
   - `burnLockedUSDC()` burns exactly `lockedSupply` after the bridge is paused.
   - Rationale: avoids burning stray transfers to the bridge and matches the “finalized supply” requirement.

2. **Role transfer mechanism**
   - Introduce an upgradeable `USDCStandardRoleManager` contract.
   - RoleManager holds USDC roles (Implementation Owner + MasterMinter) and exposes `transferUSDCRoles(address owner)`.
   - RoleManager can optionally be ProxyAdmin; if it is, it will transfer ProxyAdmin to the Circle caller.

3. **L2 pause/unpause authority**
   - Add pause functionality to `L2USDCBridge`, gated by an owner.
   - Ownership is initialized via `initializeV2(address owner)` to avoid storage layout shifts.
   - Default owner: `USDCStandardRoleManager` (can transfer to a guardian later).

## Assumptions

- RoleManager will be assigned as:
  - Implementation Owner on the USDC proxy.
  - MasterMinter on the USDC proxy.
- ProxyAdmin is assumed to remain the existing proxy admin (likely a multisig). If RoleManager is ProxyAdmin, it will transfer admin to the Circle caller.
- All active minters will be registered in RoleManager’s `managedMinters` list so they can be removed before role transfer.
- L2 bridge ownership is set to RoleManager after deployment (using `initializeV2` + ownership transfer).

## Open Questions

- Who currently holds:
  - Implementation Owner role?
  - ProxyAdmin role?
  - MasterMinter role?
- Which accounts are active minters on the L2 USDC proxy today?
- Should L2 bridge ownership move to RoleManager immediately or to a separate guardian multisig first?

## Required Contract Changes (Summary)

- **L1USDCBridge**
  - `setCircleBurnCaller(address)`
  - `finalizeSupplyLock(uint256)` (onlyOwner, whenPaused, one-time)
  - `burnLockedUSDC()` (only Circle caller, whenPaused, burns `lockedSupply`)

- **L2USDCBridge**
  - Owner + pause/unpause
  - `initializeV2(address owner)` reinitializer
  - Gate `finalizeDeposit` and `withdraw` behind `whenNotPaused`

- **USDCStandardRoleManager**
  - Upgradeable contract with:
    - `transferUSDCRoles(address owner)` (Circle caller only)
    - Managed minter list
    - Optional ProxyAdmin transfer if RoleManager currently holds it

## Operational Steps (Non-code)

- Pause bridging on both L1 and L2.
- Reconcile L2 USDC supply and call `finalizeSupplyLock(lockedSupply)` on L1.
- Ensure RoleManager minter list is up to date; remove minters if required.
- Circle caller invokes:
  - `burnLockedUSDC()` on L1 bridge.
  - `transferUSDCRoles(address circleOwner)` on RoleManager.

## Manual Setup Checklist (Initial Wiring)

- Deploy `USDCStandardRoleManager` as an upgradeable proxy.
- Initialize RoleManager with:
  - `owner` (initial admin / multisig)
  - `usdcProxy` (L2 USDC proxy address)
  - `circleRoleCaller` (Circle upgrade caller)
  - `l2USDCBridge` (if you want it auto‑added as a managed minter)
- Transfer USDC roles to RoleManager:
  - Implementation Owner → RoleManager
  - MasterMinter → RoleManager
- If desired, transfer L2 bridge ownership to RoleManager:
  - Call `initializeV2(owner)` on L2 bridge if not done.
  - Call `transferOwnership(RoleManager)` on L2 bridge.
- Populate `managedMinters` in RoleManager to match current USDC minters.
