// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/access/PauserControl.sol";
import "../../src/access/interfaces/IPauserControl.sol";
import "../../src/access/interfaces/IOwnable.sol";

// Simple contract that inherits PauserControl for testing
contract TestPauserContract is PauserControl {
    constructor() {
        // Owner is automatically set to msg.sender in Ownable constructor
    }

    // Simple function that can be paused
    function doSomething() external view whenNotPaused returns (string memory) {
        return "Function executed";
    }
}

contract PauserControlTest is Test {
    TestPauserContract public testContract;
    address public owner;
    address public pauser;
    address public user;

    function setUp() public {
        owner = address(this); // Test contract is the owner
        pauser = makeAddr("pauser");
        user = makeAddr("user");

        testContract = new TestPauserContract();

        // Verify owner is set correctly
        assertEq(testContract.owner(), address(this));
    }

    function testInitialState() public view {
        // Check initial owner
        assertEq(testContract.owner(), owner);

        // Check initial pause state
        assertFalse(testContract.paused());

        // Check pauser role is not assigned initially
        assertFalse(testContract.hasRole(testContract.PAUSER_ROLE(), pauser));
    }

    function testGrantPauserRole() public {
        // Grant pauser role
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser);

        // Check role is granted
        assertTrue(testContract.hasRole(testContract.PAUSER_ROLE(), pauser));

        // Check role member count
        assertEq(testContract.roleMemberCount(testContract.PAUSER_ROLE()), 1);

        // Check role members
        address[] memory members = testContract.roleMembers(testContract.PAUSER_ROLE());
        assertEq(members.length, 1);
        assertEq(members[0], pauser);
    }

    function testPauseUnpause() public {
        // Grant pauser role
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser);

        // Pause as pauser
        vm.prank(pauser);
        testContract.pause();

        // Check paused state
        assertTrue(testContract.paused());

        // Unpause as pauser
        vm.prank(pauser);
        testContract.unpause();

        // Check unpaused state
        assertFalse(testContract.paused());
    }

    function testPauseUnauthorized() public {
        // Try to pause without pauser role
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPauserControl.PauserUnauthorized.selector, user));
        testContract.pause();
    }

    function testUnpauseUnauthorized() public {
        // Grant pauser role and pause
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser);
        vm.prank(pauser);
        testContract.pause();

        // Try to unpause without pauser role
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPauserControl.PauserUnauthorized.selector, user));
        testContract.unpause();
    }

    function testFunctionWhenPaused() public {
        // Grant pauser role and pause
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser);
        vm.prank(pauser);
        testContract.pause();

        // Try to call function when paused
        vm.expectRevert(); // OpenZeppelin's Pausable uses EnforcedPause() error in newer versions
        testContract.doSomething();
    }

    function testFunctionWhenNotPaused() public view {
        // Call function when not paused
        string memory result = testContract.doSomething();
        assertEq(result, "Function executed");
    }

    function testRevokeRole() public {
        // Grant pauser role
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser);
        assertTrue(testContract.hasRole(testContract.PAUSER_ROLE(), pauser));

        // Revoke pauser role
        testContract.revokeRole(testContract.PAUSER_ROLE(), pauser);
        assertFalse(testContract.hasRole(testContract.PAUSER_ROLE(), pauser));

        // Try to pause after role revoked
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPauserControl.PauserUnauthorized.selector, pauser));
        testContract.pause();
    }

    function testRenounceRole() public {
        bytes32 pauserRole = testContract.PAUSER_ROLE();

        // Grant pauser role
        testContract.grantRole(pauserRole, pauser);
        assertTrue(testContract.hasRole(pauserRole, pauser));

        // Renounce role as pauser
        vm.prank(pauser);
        testContract.renounceRole(pauserRole);
        assertFalse(testContract.hasRole(pauserRole, pauser));

        // Try to pause after renouncing role
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IPauserControl.PauserUnauthorized.selector, pauser));
        testContract.pause();
    }

    function testGrantRoleUnauthorized() public {
        bytes32 pauserRole = testContract.PAUSER_ROLE();

        // Try to grant role as non-owner
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOwnable.OwnerUnauthorized.selector, user, address(this)));
        testContract.grantRole(pauserRole, pauser);

        // Verify the role was not granted
        assertFalse(testContract.hasRole(pauserRole, pauser));
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        bytes32 pauserRole = testContract.PAUSER_ROLE();

        // Transfer ownership
        testContract.transferOwnership(newOwner);
        assertEq(testContract.owner(), newOwner);

        // Old owner can't grant roles anymore
        vm.expectRevert(abi.encodeWithSelector(IOwnable.OwnerUnauthorized.selector, address(this), newOwner));
        testContract.grantRole(pauserRole, pauser);

        // New owner can grant roles
        vm.prank(newOwner);
        testContract.grantRole(pauserRole, pauser);
        assertTrue(testContract.hasRole(pauserRole, pauser));
    }

    function testMultiplePausers() public {
        address pauser2 = makeAddr("pauser2");

        // Grant pauser role to multiple accounts
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser);
        testContract.grantRole(testContract.PAUSER_ROLE(), pauser2);

        // Check both have the role
        assertTrue(testContract.hasRole(testContract.PAUSER_ROLE(), pauser));
        assertTrue(testContract.hasRole(testContract.PAUSER_ROLE(), pauser2));
        assertEq(testContract.roleMemberCount(testContract.PAUSER_ROLE()), 2);

        // Both can pause
        vm.prank(pauser);
        testContract.pause();
        assertTrue(testContract.paused());

        vm.prank(pauser2);
        testContract.unpause();
        assertFalse(testContract.paused());
    }
}
