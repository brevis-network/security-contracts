# PauserControl Test Suite

This test suite provides comprehensive coverage for the `PauserControl` contract and its inherited functionality from `AccessControl` and `Ownable`, including the two-step ownership flow.

## Test Contract
- `TestPauserContract`: A simple implementation that inherits from `PauserControl`
- Includes a `doSomething()` function that demonstrates the `whenNotPaused` modifier

## Test Coverage

### Initial State Tests
- ✅ `testInitialState`: Verifies owner setup, initial pause state, and role assignments

### Role Management Tests  
- ✅ `testGrantPauserRole`: Tests granting PAUSER_ROLE and verifies role membership
- ✅ `testGrantRoleUnauthorized`: Ensures only owner or role admin can grant; non-admin rejected
- ✅ `testRevokeRole`: Tests role revocation by owner
- ✅ `testRenounceRole`: Tests self-renunciation of roles
- ✅ `testMultiplePausers`: Tests multiple accounts with PAUSER_ROLE
- ✅ `testSetRoleAdminOnlyOwner`: Only owner can set a role's admin; getter reflects it
- ✅ `testRoleAdminCanGrantAndRevoke`: Role admin can manage its role members
- ✅ `testOwnerCanGrantEvenWithRoleAdminSet`: Owner remains super-admin
- ✅ `testClearingRoleAdminRestrictsToOwner`: Setting admin to zero enforces owner-only management

### Pause/Unpause Functionality
- ✅ `testPauseUnpause`: Tests basic pause and unpause operations
- ✅ `testPauseUnauthorized`: Ensures only PAUSER_ROLE can pause
- ✅ `testUnpauseUnauthorized`: Ensures only PAUSER_ROLE can unpause
- ✅ `testFunctionWhenPaused`: Verifies functions are blocked when paused
- ✅ `testFunctionWhenNotPaused`: Verifies functions work when not paused

### Ownership Tests
- ✅ `testTransferOwnership`: Immediate transfer and access control updates
- ✅ `testStartOwnershipTransferAndAccept`: Two-step start → accept flow clears pending and updates owner
- ✅ `testAcceptOwnership_Unauthorized`: Only the pending owner can accept
- ✅ `testCancelOwnershipTransfer`: Canceling two-step clears pending without changing owner
- ✅ `testDirectTransferVoidsPending`: Direct transfer clears pending and prevents stale accept
- ✅ `testStartOwnershipTransfer_ZeroAddressReverts`: startOwnershipTransfer reverts on zero address
- ✅ `testTransferOwnership_ZeroAddressReverts`: transferOwnership reverts on zero address

## Key Features Tested
1. **Role-based Access Control**: `PAUSER_ROLE` management and enforcement
2. **Pausable Functionality**: Contract pause/unpause with proper access control  
3. **Per-role Admin Model**: Owner is super-admin; optional per-role admin; zero admin = owner-only
4. **Ownership Management**: Direct transfer and two-step ownership (`startOwnershipTransfer` → `acceptOwnership`), plus cancellation
5. **Error Handling**: Clear custom errors for unauthorized/invalid operations
6. **State Management**: Correct transitions, including clearing `pendingOwner` on ownership changes

All tests pass locally, providing confidence in the contract's security and functionality.
