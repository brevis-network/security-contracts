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
- ✅ `testGrantRoleUnauthorized`: Ensures only owner can grant roles
- ✅ `testRevokeRole`: Tests role revocation by owner
- ✅ `testRenounceRole`: Tests self-renunciation of roles
- ✅ `testMultiplePausers`: Tests multiple accounts with PAUSER_ROLE

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
3. **Ownership Management**: Direct transfer and two-step ownership (`startOwnershipTransfer` → `acceptOwnership`), plus cancellation
4. **Error Handling**: Clear custom errors for unauthorized/invalid operations
5. **State Management**: Correct transitions, including clearing `pendingOwner` on ownership changes

All 18 tests pass successfully, providing confidence in the contract's security and functionality.
